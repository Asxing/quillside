import Foundation
import Testing
@testable import Quillside

@MainActor @Suite(.serialized) struct InlineAssistantTests {
    @Test func followupUsesEditedCandidateAndPriorInstructions() async throws {
        var inputs: [String] = []
        let model = InlineAssistantModel(generate: { _, _, user, _ in inputs.append(user); return "上一轮候选" })
        model.begin(target: .init(text:"初稿", hasSelection:true, validate:{}, apply:{_,_ in}), configuration:config())
        model.instruction="保留数字";model.runCustom();try await until { model.phase == .ready }
        model.result="人工校对后的稿件";model.instruction="再短一点";model.runCustom();try await until { inputs.count == 2 && model.phase == .ready }
        #expect(inputs[1].contains("人工校对后的稿件"))
        #expect(inputs[1].contains("保留数字"))
        #expect(inputs[1].contains("再短一点"))
    }
    @Test func delayedOutsideClicksCannotDismissANewerPresentation() {
        let first = UUID(), next = UUID()
        #expect(!InlineEventOrder.belongsToPresentation(eventTime: 11, openedAt: 10, eventSession: first, currentSession: next))
        #expect(!InlineEventOrder.belongsToPresentation(eventTime: 9, openedAt: 10, eventSession: next, currentSession: next))
        #expect(InlineEventOrder.belongsToPresentation(eventTime: 11, openedAt: 10, eventSession: next, currentSession: next))
    }
    final class Provider {
        struct Call {
            let connection: ModelConnection
            let system: String
            let user: String
            let delta: @MainActor (String) -> Void
            let completion: CheckedContinuation<String, Error>
        }
        var calls: [Call] = []
        func generate(_ c: ModelConnection, _ system: String, _ user: String, _ delta: @escaping @MainActor (String) -> Void) async throws -> String {
            try await withCheckedThrowingContinuation { calls.append(.init(connection: c, system: system, user: user, delta: delta, completion: $0)) }
        }
    }
    func config() -> AIConfiguration {
        var result = AIConfiguration()
        let c = ModelConnection(name: "Test", api: .ollama, baseURL: "http://127.0.0.1:1", model: "synthetic")
        result.connections = [c]; result.selectedConnectionID = c.id
        return result
    }
    func until(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        try #require(condition())
    }
    @Test func opensWithoutRequestThenStreamsOnlyCapturedContentAndAppliesEditedPreview() async throws {
        let provider = Provider(), model = InlineAssistantModel(generate: provider.generate)
        var writes: [(String, Bool)] = []
        model.begin(target: .init(text: "仅选区🙂", hasSelection: true, validate: {}, apply: { writes.append(($0, $1)) }), configuration: config())
        #expect(provider.calls.isEmpty)
        model.instruction = "保留数字"; model.run(model.prompts[0])
        try await until { provider.calls.count == 1 }
        let call = provider.calls[0]
        #expect(call.user.contains("仅选区🙂")); #expect(call.user.contains("保留数字"))
        #expect(writes.isEmpty)
        call.delta("部分"); #expect(model.result == "部分"); #expect(!model.canApply)
        call.completion.resume(returning: "完整结果")
        try await until { model.phase == .ready }
        model.result = "用户检查后的结果"
        model.apply(insertAfter: false); model.apply(insertAfter: true)
        try await until { model.phase == .applied }
        #expect(writes.count == 1); #expect(writes.first?.0 == "用户检查后的结果"); #expect(writes.first?.1 == false)
    }
    @Test func cancelledAndLateResponsesCannotOverwriteNewSelection() async throws {
        let provider = Provider(), model = InlineAssistantModel(generate: provider.generate)
        let noWrite: (String, Bool) async throws -> Void = { _, _ in Issue.record("No apply expected") }
        model.begin(target: .init(text: "A", hasSelection: true, validate: {}, apply: noWrite), configuration: config())
        model.run(model.prompts[0]); try await until { provider.calls.count == 1 }
        provider.calls[0].delta("半句")
        model.stop(); #expect(model.result == "半句"); #expect(!model.canApply)
        model.dismiss()
        model.begin(target: .init(text: "B", hasSelection: true, validate: {}, apply: noWrite), configuration: config())
        provider.calls[0].delta("迟到数据"); provider.calls[0].completion.resume(returning: "过期结果")
        model.run(model.prompts[0]); try await until { provider.calls.count == 2 }
        provider.calls[1].completion.resume(returning: "B 的结果")
        try await until { model.phase == .ready }
        #expect(model.source == "B"); #expect(model.result == "B 的结果")
    }
    @Test func changingTargetRetainsCandidateButDisablesWriteAndRetry() async throws {
        let model = InlineAssistantModel(generate: { _, _, _, _ in "结果" })
        var valid = true, writes = 0
        model.begin(target: .init(text: "A", hasSelection: true, validate: { if !valid { throw AIError.message("目标已改变") } }, apply: { _, _ in writes += 1 }), configuration: config())
        model.run(model.prompts[0]); try await until { model.phase == .ready }
        valid = false; model.checkTarget(); model.apply(insertAfter: false); model.retry()
        #expect(model.result == "结果"); #expect(!model.canApply); #expect(!model.canRetry); #expect(writes == 0)
    }
    @Test func applyFailureCannotBeRetriedAndBlocksDismissDuringWrite() async throws {
        let model = InlineAssistantModel(generate: { _, _, _, _ in "结果" })
        var continuation: CheckedContinuation<Void, Error>?, writes = 0
        model.begin(target: .init(text: "当前全文", hasSelection: false, validate: {}, apply: { _, after in
            writes += 1; #expect(after)
            try await withCheckedThrowingContinuation { continuation = $0 }
        }), configuration: config())
        model.run(model.prompts[0]); try await until { model.phase == .ready }
        model.apply(insertAfter: false); #expect(model.phase == .ready)
        model.apply(insertAfter: true); try await until { continuation != nil }
        #expect(!model.dismiss()); #expect(!model.begin(target: nil, configuration: config()))
        continuation?.resume(throwing: AIError.message("读回失败"))
        try await until { model.phase == .failed }
        model.apply(insertAfter: true); #expect(writes == 1); #expect(model.result == "结果"); #expect(!model.canApply)
    }
    @Test func unconfiguredOrFailedCaptureDoesNotSendAnything() {
        let provider = Provider(), model = InlineAssistantModel(generate: provider.generate)
        model.begin(target: .init(text: "正文", hasSelection: true, validate: {}, apply: { _, _ in }), configuration: AIConfiguration())
        model.run(model.prompts[0]); #expect(!model.canGenerate); #expect(provider.calls.isEmpty)
        model.begin(target: nil, configuration: config(), error: "缺少权限")
        model.run(model.prompts[0]); #expect(!model.canGenerate); #expect(model.status == "缺少权限")
    }
    @Test func nonactivatingPanelInputIsNotConsumedByNoteShortcuts() {
        #expect(!KeyboardEventRoutingPolicy.shouldHandle(cachedIsNotesFrontmost: true, liveFrontmostBundleIdentifier: AppleNotesTarget.bundleIdentifier, inlinePanelActive: true))
        #expect(KeyboardEventRoutingPolicy.shouldHandle(cachedIsNotesFrontmost: true, liveFrontmostBundleIdentifier: AppleNotesTarget.bundleIdentifier, inlinePanelActive: false))
    }
    @Test func panelStaysVisibleAcrossScreenEdgesAndNegativeCoordinates() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1200, y: 200, width: 1200, height: 800)]
        for screen in screens {
            for point in [screen.origin, CGPoint(x: screen.maxX - 1, y: screen.maxY - 1)] {
                let frame = InlinePanelPlacement.frame(anchor: CGRect(origin: point, size: CGSize(width: 1, height: 10)), size: CGSize(width: 440, height: 510), screen: screen)
                #expect(screen.contains(frame))
            }
        }
    }
}
