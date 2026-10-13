import AppKit
import Testing
@testable import Quillside

@MainActor @Suite struct AIRunLifecycleTests {
    func config() -> AIConfiguration {
        var value = AIConfiguration()
        let connection = ModelConnection(model: "synthetic")
        value.connections = [connection]; value.selectedConnectionID = connection.id
        return value
    }
    func until(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(condition())
    }
    @Test func leavingNotesStopsRevisionPreservesDraftAndRejectsLateResponse() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try WritingDraftStore(directory: dir), runs = AIRunRegistry(observeSystem: false)
        var completion: CheckedContinuation<String, Error>?, calls = 0
        let model = WritingSessionModel(generate: { _,_,_,_ in
            calls += 1
            return try await withCheckedThrowingContinuation { completion = $0 }
        }, store: store, runs: runs)
        var draft = WritingDraft(noteIdentity: "fixture", baseline: "原文", rangeLocation: 0, rangeLength: 2, hasSelection: true, candidate: "原文")
        try draft.annotate(range: NSRange(location: 0, length: 2), comment: "保留事实")
        model.begin(draft, config: config()); model.run()
        try await until { completion != nil }
        #expect(runs.activeCount == 1)
        model.suspend()
        #expect(!model.busy); #expect(runs.activeCount == 0)
        #expect(model.status.contains("离开原笔记"))
        completion?.resume(returning: "{\"plan\":\"late\",\"resourceRequests\":[]}")
        try await Task.sleep(for: .milliseconds(15))
        #expect(calls == 1); #expect(model.draft?.versions.isEmpty == true)
        #expect(model.draft?.candidate == "原文")
        let saved = try store.load(note: "fixture")
        let recovered = try #require(saved)
        #expect(recovered.annotations == draft.annotations)
        model.begin(recovered, config: config())
        #expect(!model.busy); #expect(runs.activeCount == 0); #expect(calls == 1)
    }
    @Test func wholeRevisionDeadlineStopsEvenAnUncooperativeProvider() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runs = AIRunRegistry(observeSystem: false)
        var completion: CheckedContinuation<String, Error>?
        let model = WritingSessionModel(generate: { _,_,_,_ in try await withCheckedThrowingContinuation { completion = $0 } },
            store: try WritingDraftStore(directory: dir), runs: runs, runTimeout: 0.06)
        var draft = WritingDraft(noteIdentity: "fixture", baseline: "原文", rangeLocation: 0, rangeLength: 2, hasSelection: true, candidate: "原文")
        draft.instruction = "优化"; model.begin(draft, config: config()); model.run()
        try await until { completion != nil && !model.busy }
        #expect(model.status.contains("超时")); #expect(runs.activeCount == 0)
        completion?.resume(returning: "{\"plan\":\"late\",\"resourceRequests\":[]}")
        try await Task.sleep(for: .milliseconds(10))
        #expect(model.draft?.candidate == "原文"); #expect(model.draft?.versions.isEmpty == true)
    }
    @Test func cancelAllStopsConcurrentRequestsAndIgnoresLateCallbacks() async throws {
        let runs = AIRunRegistry(observeSystem: false)
        var callbacks: [(@MainActor (String) -> Void, CheckedContinuation<String, Error>)] = []
        let generate: InlineAssistantModel.Generate = { _,_,_,delta in
            try await withCheckedThrowingContinuation { callbacks.append((delta, $0)) }
        }
        let a = InlineAssistantModel(generate: generate, runs: runs), b = InlineAssistantModel(generate: generate, runs: runs)
        for model in [a, b] {
            model.begin(target: .init(text: "原文", hasSelection: true, validate: {}, apply: {_,_ in Issue.record("No write expected")}), configuration: config())
            model.run(model.prompts[0])
        }
        try await until { callbacks.count == 2 }
        #expect(runs.activeCount == 2)
        runs.cancelAll()
        for (delta, completion) in callbacks { delta("迟到"); completion.resume(returning: "迟到") }
        try await Task.sleep(for: .milliseconds(10))
        #expect(runs.activeCount == 0)
        for model in [a,b] { #expect(!model.busy); #expect(model.result.isEmpty); #expect(!model.canApply) }
    }
    @Test func successfulRunReleasesDeadlineAndDoesNotExpireLater() async throws {
        let runs = AIRunRegistry(observeSystem: false)
        let model = InlineAssistantModel(generate: {_,_,_,_ in "完整结果"}, runs: runs, runTimeout: 0.05)
        model.begin(target: .init(text: "原文", hasSelection: true, validate: {}, apply: {_,_ in}), configuration: config())
        model.run(model.prompts[0]); try await until { model.phase == .ready && runs.activeCount == 0 }
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.phase == .ready); #expect(model.result == "完整结果")
    }
    @Test func replacingTaskAndLateFinishCannotUnregisterNewRun() async throws {
        let runs = AIRunRegistry(observeSystem: false)
        var callbacks: [CheckedContinuation<String, Error>] = []
        let model = InlineAssistantModel(generate: {_,_,_,_ in try await withCheckedThrowingContinuation { callbacks.append($0) }}, runs: runs)
        let target = InlineAssistantModel.Target(text: "原文", hasSelection: true, validate: {}, apply: {_,_ in})
        model.begin(target: target, configuration: config()); model.run(model.prompts[0])
        try await until { callbacks.count == 1 }
        model.begin(target: target, configuration: config()); model.run(model.prompts[0])
        try await until { callbacks.count == 2 }
        callbacks[0].resume(returning: "过期")
        try await Task.sleep(for: .milliseconds(10))
        #expect(runs.activeCount == 1); #expect(model.phase == .generating)
        callbacks[1].resume(returning: "新结果")
        try await until { runs.activeCount == 0 }
        #expect(model.result == "新结果")
    }
    @Test func sleepAndUserSessionDepartureCancelActiveWork() async throws {
        let center = NotificationCenter()
        // Inject a private notification center; do not affect live application work.
        let observed = AIRunRegistry(center: center)
        var stopped = 0
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            _ = observed.begin(timeout: 10) { reason in #expect(reason.message.contains("休眠")); stopped += 1 }
            center.post(name: name, object: nil)
            try await until { observed.activeCount == 0 }
        }
        #expect(stopped == 2)
    }
}
