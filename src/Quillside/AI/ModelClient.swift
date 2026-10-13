import Foundation

struct ModelRequestBuilder {
    static func request(connection: ModelConnection, key: String, system: String, user: String) throws -> URLRequest {
        var request = URLRequest(url: try connection.endpoint())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["model": connection.model, "stream": true]
        switch connection.api {
        case .chatCompletions:
            payload["messages"] = [["role": "system", "content": system], ["role": "user", "content": user]]
            payload["max_tokens"] = connection.maxOutputTokens
            // Some compatible providers reject OpenAI-specific storage options.
            if request.url?.host?.lowercased() == "api.openai.com" { payload["store"] = false }
        case .responses:
            payload["instructions"] = system
            payload["input"] = user
            payload["store"] = false
            payload["max_output_tokens"] = connection.maxOutputTokens
        case .anthropic:
            payload["system"] = system
            payload["messages"] = [["role": "user", "content": user]]
            payload["max_tokens"] = connection.maxOutputTokens
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .ollama:
            payload["messages"] = [["role": "system", "content": system], ["role": "user", "content": user]]
            payload["options"] = ["num_predict": connection.maxOutputTokens]
        }
        if connection.api != .anthropic && !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if connection.api != .ollama && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIError.message("请先在模型连接中保存 API Key。")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }
}

/// Keeps provider completion semantics separate from text. EOF alone is never success.
struct ModelStreamDecoder {
    let api: ModelProtocol
    private(set) var completed = false
    private var anthropicStop: String?
    private var chatFinished = false
    init(api: ModelProtocol) { self.api = api }

    mutating func consume(_ line: String) throws -> String? {
        if line.isEmpty || line.hasPrefix("event:") || line.hasPrefix(":") { return nil }
        let json: String
        if api == .ollama { json = line }
        else {
            guard line.hasPrefix("data:") else { return nil }
            json = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if json == "[DONE]" { completed = chatFinished; return nil }
        }
        guard let data = json.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.message("模型返回了无法识别的流数据。")
        }
        if object["error"] != nil { throw AIError.message("服务商在生成过程中返回错误。请检查模型、额度和服务状态。") }
        switch api {
        case .chatCompletions:
            guard let choice = (object["choices"] as? [[String: Any]])?.first else { return nil }
            if let reason = choice["finish_reason"] as? String {
                guard reason == "stop" else { throw AIError.message("生成未正常完成（\(reason)），候选内容未写入。") }
                chatFinished = true
                completed = true
            }
            let delta = choice["delta"] as? [String: Any]
            if delta?["refusal"] is String { throw AIError.message("模型拒绝了本次请求，未写入笔记。") }
            return delta?["content"] as? String
        case .responses:
            switch object["type"] as? String {
            case "response.output_text.delta": return object["delta"] as? String
            case "response.completed":
                let response = object["response"] as? [String: Any]
                guard response?["status"] as? String == "completed" else { throw AIError.message("响应没有完整结束。") }
                completed = true
            case "response.failed", "response.incomplete", "error", "response.refusal.delta":
                throw AIError.message("模型返回失败、截断或拒答，未写入笔记。")
            default: break
            }
        case .anthropic:
            let type = object["type"] as? String
            let delta = object["delta"] as? [String: Any]
            if type == "content_block_delta", delta?["type"] as? String == "text_delta" { return delta?["text"] as? String }
            if type == "message_delta" { anthropicStop = delta?["stop_reason"] as? String }
            if type == "message_stop" {
                guard anthropicStop == "end_turn" || anthropicStop == "stop_sequence" else {
                    throw AIError.message("模型未完成正文生成，可能达到输出上限。")
                }
                completed = true
            }
        case .ollama:
            if object["done"] as? Bool == true {
                if let reason = object["done_reason"] as? String, reason != "stop" {
                    throw AIError.message("本地模型输出未完成（\(reason)）。")
                }
                completed = true
            }
            return (object["message"] as? [String: Any])?["content"] as? String
        }
        return nil
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct ModelClient {
    var limits = ModelRequestLimits()
    func generate(connection: ModelConnection, key: String, system: String, user: String,
                  onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
        try Task.checkCancellation()
        let request = try ModelRequestBuilder.request(connection: connection, key: key, system: system, user: user)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = limits.idle
        configuration.timeoutIntervalForResource = limits.total
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        let lifetime = ModelRequestLifetime(session: session, limits: limits)
        defer { lifetime.finish() }
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await consume(request, session: session, lifetime: lifetime, api: connection.api, onDelta: onDelta)
            } onCancel: { lifetime.cancel() }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            try lifetime.check()
            if (error as? URLError)?.code == .timedOut { throw AIError.message("模型请求超时，已断开连接；已有内容保留。") }
            throw error
        }
    }
    private func consume(_ request: URLRequest, session: URLSession, lifetime: ModelRequestLifetime, api: ModelProtocol,
                         onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.message("请求失败（HTTP \(code)）。401/403 请检查密钥；404 检查地址和模型；429 检查额度。")
        }
        var decoder = ModelStreamDecoder(api: api)
        var framer = ModelStreamFramer(api: api)
        var result = ""
        for try await byte in bytes {
            try Task.checkCancellation()
            if let event = try framer.consume(byte) {
                try lifetime.check()
                let delta = try decoder.consume(event)
                lifetime.progressed()
                if let delta {
                    guard result.utf8.count + delta.utf8.count < 2_000_000 else { throw AIError.message("输出过长，生成已停止。") }
                    result += delta
                    await onDelta(delta)
                }
            }
            if decoder.completed { break }
        }
        try lifetime.check()
        if !decoder.completed, let event = try framer.finish(), let delta = try decoder.consume(event) {
            guard result.utf8.count + delta.utf8.count < 2_000_000 else { throw AIError.message("输出过长，生成已停止。") }
            result += delta; await onDelta(delta)
        }
        try Task.checkCancellation()
        try lifetime.check()
        guard decoder.completed, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.message("连接提前结束或没有正文，候选内容未写入。")
        }
        return result
    }
}
