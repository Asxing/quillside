import Foundation
import Testing
@testable import Quillside

@Suite struct ModelLifecycleTests {
    @Test func openAIRequestsDoNotCreateStoredConversations() throws {
        for api in [ModelProtocol.responses, .chatCompletions] {
            let request = try ModelRequestBuilder.request(connection: .init(api: api, model: "fixture"), key: "synthetic-key", system: "test", user: "synthetic input")
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect(body["store"] as? Bool == false)
            #expect(body["background"] as? Bool != true)
            #expect(body["conversation"] == nil)
            #expect(body["previous_response_id"] == nil)
        }
    }
    func serverState(_ base: String) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: URL(string: base)!)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["state"] as? String ?? "missing"
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENNOTES_TEST_MODEL_BASEURL"] != nil))
    @MainActor func cancellationClosesQuietHTTPStreamPromptly() async throws {
        let root = try #require(ProcessInfo.processInfo.environment["OPENNOTES_TEST_MODEL_BASEURL"])
        let base = root + "/lifecycle/quiet/" + UUID().uuidString
        var received = false
        let task = Task {
            try await ModelClient().generate(connection: .init(api: .responses, baseURL: base, model: "fixture-model"), key: "synthetic-key", system: "test system", user: "synthetic input") { _ in received = true }
        }
        for _ in 0..<200 where !received { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(received)
        task.cancel()
        for _ in 0..<40 {
            if try await serverState(base) == "closed" { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(try await serverState(base) == "closed")
        if case .success = await task.result { Issue.record("Cancelled stream returned success") }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENNOTES_TEST_MODEL_BASEURL"] != nil),
          arguments: ["quiet", "heartbeat", "progress"])
    func deadlinesCloseIdleHeartbeatAndEndlessProgressStreams(_ mode: String) async throws {
        let root = try #require(ProcessInfo.processInfo.environment["OPENNOTES_TEST_MODEL_BASEURL"])
        let base = root + "/lifecycle/" + mode + "/" + UUID().uuidString
        do {
            _ = try await ModelClient(limits: .init(idle: 0.2, total: 0.7)).generate(
                connection: .init(api: .responses, baseURL: base, model: "fixture-model"), key: "synthetic-key",
                system: "test system", user: "synthetic input") { _ in }
            Issue.record("Unfinished stream must never succeed")
        } catch {
            #expect(error.localizedDescription.contains(mode == "progress" ? "时限" : "进展") || error.localizedDescription.contains("超时"), "Unexpected error: \(error.localizedDescription)")
        }
        for _ in 0..<40 {
            if try await serverState(base) == "closed" { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(try await serverState(base) == "closed")
        // Rendering tests can occupy MainActor and delay callbacks. Measure the
        // actual transport close at the peer, not when the UI continuation runs.
        let (data, _) = try await URLSession.shared.data(from: URL(string: base)!)
        let response = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let elapsed = try #require(response["elapsed"] as? Double)
        #expect(elapsed < 2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENNOTES_TEST_MODEL_BASEURL"] != nil))
    @MainActor func alreadyCancelledTaskSendsNoHTTPRequest() async throws {
        let root = try #require(ProcessInfo.processInfo.environment["OPENNOTES_TEST_MODEL_BASEURL"])
        let base = root + "/lifecycle/quiet/" + UUID().uuidString
        let task = Task { @MainActor in
            _ = try await ModelClient().generate(connection: .init(api: .responses, baseURL: base, model: "fixture-model"), key: "synthetic-key", system: "test system", user: "synthetic input") { _ in }
        }
        task.cancel()
        if case .success = await task.result { Issue.record("Expected cancellation") }
        #expect(try await serverState(base) == "missing")
    }
}
