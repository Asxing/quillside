import Foundation

/// SSE events end at a blank line; multiple data fields join with LF (WHATWG SSE).
/// NDJSON uses one JSON object per line. Both paths bound buffers before allocating a full line.
struct ModelStreamFramer {
    let api: ModelProtocol
    var maximumBytes = 2_000_000
    private var line = Data()
    private var fields: [String] = []
    private var eventBytes = 0
    private var afterCR = false
    private var firstLine = true
    init(api: ModelProtocol, maximumBytes: Int = 2_000_000) { self.api = api; self.maximumBytes = maximumBytes }

    mutating func consume(_ byte: UInt8) throws -> String? {
        if afterCR { afterCR = false; if byte == 10 { return nil } }
        if byte == 13 || byte == 10 {
            afterCR = byte == 13
            return try finishLine()
        }
        guard line.count < maximumBytes else { throw AIError.message("模型流数据超过单帧限制，生成已停止。") }
        line.append(byte)
        return nil
    }
    mutating func finish() throws -> String? {
        // Incomplete SSE events are discarded; EOF never supplies the missing blank line.
        guard api == .ollama, !line.isEmpty else { return nil }
        return try finishLine()
    }
    private mutating func finishLine() throws -> String? {
        guard var text = String(data: line, encoding: .utf8) else { throw AIError.message("模型返回了无效的 UTF-8 数据。") }
        line.removeAll(keepingCapacity: true)
        if firstLine { firstLine = false; if text.first == "\u{FEFF}" { text.removeFirst() } }
        if api == .ollama { return text.isEmpty ? nil : text }
        if text.isEmpty {
            guard !fields.isEmpty else { return nil }
            let data = fields.joined(separator: "\n")
            fields.removeAll(keepingCapacity: true); eventBytes = 0
            return data.isEmpty ? nil : "data: " + data
        }
        guard !text.hasPrefix(":") else { return nil }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.first == "data" else { return nil }
        var value = parts.count == 2 ? String(parts[1]) : ""
        if value.first == " " { value.removeFirst() }
        eventBytes += value.utf8.count + 1
        guard eventBytes <= maximumBytes else { throw AIError.message("模型流事件超过限制，生成已停止。") }
        fields.append(value)
        return nil
    }
}
