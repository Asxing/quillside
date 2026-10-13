import AppKit
import Foundation

struct PiProvider: Codable, Identifiable {
    let id: String
    let name: String
    let oauth: Bool
    let apiKey: Bool
    let credential: String?
}
struct PiModel: Codable, Identifiable {
    let id: String
    let name: String
    let maxTokens: Int
}
struct PiPrompt: Decodable {
    struct Option: Decodable, Identifiable { let id: String; let label: String }
    let type: String
    let message: String
    let options: [Option]?
    let placeholder: String?
}
struct PiAuthEvent: Decodable {
    let type: String
    let url: String?
    let message: String?
    let userCode: String?
    let verificationUri: String?
}
struct PiResult: Decodable {
    var version: String?
    var providers: [PiProvider]?
    var models: [PiModel]?
    var authenticated: Bool?
    var text: String?
}
struct PiEvent: Decodable {
    let type: String
    var text: String?
    var message: String?
    var code: String?
    var result: PiResult?
    var event: PiAuthEvent?
    var prompt: PiPrompt?
}

/// One isolated Pi process per operation. No worker or remote session stays idle.
final class PiProcessOperation: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let queue = DispatchQueue(label: "com.quillside.pi-process")
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var buffer = Data()
    private var cancelled = false
    private var ended = false
    private var timer: DispatchSourceTimer?
    private var lastProgress = ProcessInfo.processInfo.systemUptime
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private let timeout: TimeInterval
    private let idleTimeout: TimeInterval
    private let executable: URL
    private let worker: URL
    private let directory: URL

    init(executable: URL, worker: URL, directory: URL, timeout: TimeInterval, idleTimeout: TimeInterval = 90) {
        self.executable = executable; self.worker = worker; self.directory = directory
        self.timeout = timeout; self.idleTimeout = idleTimeout
    }
    deinit {
        timer?.cancel()
        output.fileHandleForReading.readabilityHandler = nil
        continuation?.finish(throwing: CancellationError())
        if process.isRunning { process.terminate() }
    }
    func events(request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            queue.async { [self] in
                self.continuation = continuation
                guard !cancelled else { continuation.finish(throwing: CancellationError()); self.continuation = nil; return }
                process.executableURL = executable
                process.arguments = [worker.path]
                process.currentDirectoryURL = directory
                process.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                    "PATH": "/usr/bin:/bin", "TMPDIR": NSTemporaryDirectory(),
                    "QUILLSIDE_PI_DIR": directory.path, "PI_OFFLINE": "1", "PI_OAUTH_CALLBACK_HOST": "127.0.0.1",
                    "PI_PACKAGE_DIR": worker.deletingLastPathComponent().path]
                process.standardInput = input; process.standardOutput = output
                process.standardError = FileHandle.nullDevice // Provider exceptions can contain credentials.
                output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    let bytes = handle.availableData
                    self?.queue.async { [weak self] in self?.receive(bytes) }
                }
                do {
                    try process.run()
                    startedAt = ProcessInfo.processInfo.systemUptime; lastProgress = startedAt
                    try input.fileHandleForWriting.write(contentsOf: request + Data([10]))
                    let timer = DispatchSource.makeTimerSource(queue: queue)
                    timer.schedule(deadline: .now() + 1, repeating: 1)
                    timer.setEventHandler { [weak self] in self?.checkTimeout() }
                    self.timer = timer; timer.resume()
                } catch { finish(AIError.message("Pi 运行环境启动失败，请重新安装完整应用。")); stopProcess() }
            }
            continuation.onTermination = { [weak self] _ in self?.cancel() }
        }
    }
    func reply(_ value: String) {
        queue.async { [weak self] in
            guard let self, !ended, process.isRunning,
                  let data = try? JSONSerialization.data(withJSONObject: ["method": "reply", "value": value]) else { return }
            try? input.fileHandleForWriting.write(contentsOf: data + Data([10]))
        }
    }
    func cancel() {
        queue.async { [weak self] in
            guard let self, !ended else { return }
            cancelled = true; finish(CancellationError()); stopProcess()
        }
    }
    private func receive(_ data: Data) {
        guard !ended else { return }
        if data.isEmpty { finish(nil); return }
        lastProgress = ProcessInfo.processInfo.systemUptime
        buffer.append(data)
        guard buffer.count <= 4_000_000 else { finish(AIError.message("Pi 输出超过限制，操作已停止。")); stopProcess(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            if !line.isEmpty { continuation?.yield(line) }
        }
    }
    private func checkTimeout() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - startedAt > timeout || now - lastProgress > idleTimeout {
            finish(AIError.message("Pi 请求超时，已停止连接；原文和批注保留。")); stopProcess()
        }
    }
    private func finish(_ error: Error?) {
        guard !ended else { return }; ended = true
        timer?.cancel(); timer = nil
        output.fileHandleForReading.readabilityHandler = nil
        if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
        continuation = nil
    }
    private func stopProcess() {
        guard process.isRunning else { return }
        try? input.fileHandleForWriting.write(contentsOf: Data("{\"method\":\"cancel\"}\n".utf8))
        let running = process
        queue.asyncAfter(deadline: .now() + 2) {
            guard running.isRunning else { return }
            running.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if running.isRunning { kill(running.processIdentifier, SIGKILL) } }
        }
    }
}

@MainActor enum PiRuntime {
    static func directory() throws -> URL {
        let url = try AppFiles.directory().appendingPathComponent("Pi", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }
    static func operation(login: Bool = false) throws -> PiProcessOperation {
        guard let resources = Bundle.main.resourceURL else { throw AIError.message("Pi 运行环境缺失。") }
        let folder = resources.appendingPathComponent("PiRuntime")
        let node = folder.appendingPathComponent("node"), worker = folder.appendingPathComponent("worker.mjs")
        guard FileManager.default.isExecutableFile(atPath: node.path), FileManager.default.fileExists(atPath: worker.path) else {
            throw AIError.message("此构建没有包含 Pi，请安装完整 Quillside.app。")
        }
        return PiProcessOperation(executable: node, worker: worker, directory: try directory(), timeout: login ? 600 : 240, idleTimeout: login ? 600 : 90)
    }
    static func call(_ request: [String: Any], operation supplied: PiProcessOperation? = nil,
                     onEvent: @escaping @MainActor (PiEvent) -> Void = { _ in }) async throws -> PiResult {
        let operation = try supplied ?? self.operation()
        let data = try JSONSerialization.data(withJSONObject: request)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            var result: PiResult?
            for try await line in operation.events(request: data) {
                try Task.checkCancellation()
                let event = try JSONDecoder().decode(PiEvent.self, from: line)
                if event.type == "error" { throw AIError.message(event.message ?? "Pi 未完成操作。") }
                if event.type == "result" { result = event.result }
                onEvent(event)
            }
            try Task.checkCancellation()
            guard let result else { throw AIError.message("Pi 进程提前退出，未取得完整结果。") }
            return result
        } onCancel: { operation.cancel() }
    }
    static func generate(connection: ModelConnection, system: String, user: String,
                         keyOverride: String? = nil, allowAuthentication: Bool = false,
                         onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
        var request: [String: Any] = ["method": "generate", "system": system, "user": user, "maxOutputTokens": connection.maxOutputTokens]
        if let provider = connection.piProvider {
            request["provider"] = provider; request["model"] = connection.model
        } else {
            _ = try connection.endpoint()
            let secret: String
            if let keyOverride { secret = keyOverride }
            else { secret = try await ProviderKeychain.readAuthorized(connection.keychainID, allowAuthentication: allowAuthentication) }
            try Task.checkCancellation()
            request["connection"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(connection))
            request["key"] = secret
        }
        let result = try await call(request) { if $0.type == "delta", let text = $0.text { onDelta(text) } }
        guard let text = result.text else { throw AIError.message("Pi 没有返回候选正文。") }
        return text
    }
}
