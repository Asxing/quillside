import Foundation
import Testing
@testable import Quillside

@MainActor struct PiRuntimeTests {
    nonisolated func operation(timeout: TimeInterval = 5) throws -> PiProcessOperation {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return PiProcessOperation(executable: root.appendingPathComponent("build/pi-runtime/node"),
            worker: root.appendingPathComponent("tests/Fixtures/Pi/worker.mjs"), directory: FileManager.default.temporaryDirectory,
            timeout: timeout, idleTimeout: timeout)
    }
    @Test func processReceivesUnicodeStreamingAndRequiresFinalResult() async throws {
        var text = ""
        let r = try await PiRuntime.call(["method": "echo"], operation: operation()) { text += $0.text ?? "" }
        #expect(text == "中"); #expect(r.text == "中文🙂")
        await #expect(throws: (any Error).self) { try await PiRuntime.call(["method": "exit"], operation: operation()) }
        await #expect(throws: (any Error).self) { try await PiRuntime.call(["method": "bad"], operation: operation()) }
        do { _ = try await PiRuntime.call(["method": "secret"], operation: operation()); Issue.record("Expected error") }
        catch { #expect(error.localizedDescription == "safe error") }
    }
    @Test func cancellationBeforeStartAndDuringReadFinishPromptly() async throws {
        let before = try operation(); before.cancel()
        await #expect(throws: (any Error).self) { try await PiRuntime.call(["method": "wait"], operation: before) }
        let running = try operation()
        let task = Task { try await PiRuntime.call(["method": "wait"], operation: running) }
        try await Task.sleep(nanoseconds: 50_000_000)
        let time = Date(); task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(Date().timeIntervalSince(time) < 2)
    }
    @Test nonisolated func hungWorkerIsTerminatedOnTimeout() async throws {
        let start = Date()
        let worker = try operation(timeout: 0.1)
        defer { worker.cancel() }
        // Measure the worker watchdog, not main-actor scheduling behind UI tests.
        do {
            for try await _ in worker.events(request: Data("{\"method\":\"wait\"}".utf8)) { }
            Issue.record("Expected timeout")
        } catch { #expect(error.localizedDescription.contains("超时")) }
        #expect(Date().timeIntervalSince(start) < 3)
    }
    @Test func oldModelConnectionsDecodeAndPiSelectionRoundTrips() throws {
        let old = ModelConnection(name: "Existing", model: "fixture")
        var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        data.removeValue(forKey: "piProvider")
        let decoded = try JSONDecoder().decode(ModelConnection.self, from: JSONSerialization.data(withJSONObject: data))
        #expect(decoded.piProvider == nil && decoded.id == old.id)
        var current = decoded; current.piProvider = "openai"
        let roundTrip = try JSONDecoder().decode(ModelConnection.self, from: JSONEncoder().encode(current))
        #expect(roundTrip.piProvider == "openai" && roundTrip.id == old.id)
    }
}
