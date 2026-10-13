import Foundation
import Testing
@testable import Quillside

@Suite struct ModelStreamFramerTests {
    func events(_ input: String, api: ModelProtocol = .responses) throws -> [String] {
        var framer = ModelStreamFramer(api: api), result: [String] = []
        for byte in input.utf8 { if let event = try framer.consume(byte) { result.append(event) } }
        if let event = try framer.finish() { result.append(event) }
        return result
    }
    @Test func reconstructsMultilineSSEWithCRLFCommentsAndUTF8() throws {
        let stream = "\u{FEFF}:keepalive\r\nevent: response.output_text.delta\r\ndata: {\r\ndata: \"type\":\"response.output_text.delta\",\r\ndata: \"delta\":\"你好🙂\"}\r\n\r\n"
        let payloads = try events(stream)
        #expect(payloads.count == 1)
        var decoder = ModelStreamDecoder(api: .responses)
        #expect(try decoder.consume(payloads[0]) == "你好🙂")
        #expect(!decoder.completed)
    }
    @Test func incompleteSSEIsNotDispatchedButNDJSONFinalLineIs() throws {
        let payload = #"{"message":{"content":"尾句"},"done":true,"done_reason":"stop"}"#
        #expect(try events("data: " + payload + "\n").isEmpty)
        #expect(try events(payload, api: .ollama) == [payload])
        #expect(try events("data: one\r\rdata: two\n\n") == ["data: one", "data: two"])
    }
    @Test func boundsBothIndividualLinesAndAccumulatedEvents() {
        var line = ModelStreamFramer(api: .responses, maximumBytes: 12)
        #expect(throws: AIError.self) { for byte in String(repeating: "x", count: 13).utf8 { _ = try line.consume(byte) } }
        var event = ModelStreamFramer(api: .responses, maximumBytes: 12)
        #expect(throws: AIError.self) { for byte in String(repeating: "data: x\n", count: 8).utf8 { _ = try event.consume(byte) } }
    }
    @Test func refusesInvalidUTF8AndDoesNotDispatchCommentOrEmptyData() throws {
        var parser = ModelStreamFramer(api: .responses)
        _ = try parser.consume(255)
        #expect(throws: AIError.self) { _ = try parser.consume(10) }
        #expect(try events(": keepalive\n\nevent: ping\n\ndata:\n\n").isEmpty)
    }
}
