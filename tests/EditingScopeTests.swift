import Foundation
import CoreGraphics
import Testing
@testable import Quillside

@Suite struct EditingScopeTests {
    @Test func requestContainsOnlyExplicitMaterialAndDoesNotReinterpretIt() throws {
        let prompt = PromptAction(name: "任务", instruction: "处理：{instruction}")
        let rendered = try EditingRequest.render(prompt: prompt, text: "当前笔记🙂 {sources}", instruction: "解释", language: "中文")
        #expect(rendered == "处理：解释\n当前材料：\n当前笔记🙂 {sources}")
        #expect(throws: AIError.self) { try EditingRequest.render(prompt: .init(name: "旧自定义", instruction: "{sources}"), text: "正文", instruction: "", language: "中文") }
        #expect(throws: AIError.self) { try EditingRequest.render(prompt: prompt, text: "", instruction: String(repeating: "甲", count: 100_000), language: "中文") }
    }
    @MainActor @Test func oldDefaultMigratesButCustomPromptsCredentialsAndFilesRemain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = directory.appendingPathComponent("settings.json"), oldIndex = directory.appendingPathComponent("knowledge.sqlite")
        let bytes = Data("untouched old database".utf8); try bytes.write(to: oldIndex)
        let builtin = PromptAction(name: "知识库问答", instruction: PromptAction.legacyKnowledgeInstruction)
        let custom = PromptAction(name: "我的资料", instruction: "自定义 {sources}")
        var configuration = AIConfiguration(); configuration.prompts = [builtin, custom]
        let connection = ModelConnection(model: "fixture", credentialID: UUID())
        configuration.connections = [connection]; configuration.selectedConnectionID = connection.id
        try AppFiles.save(configuration, to: settings)
        let before = try Data(contentsOf: settings)
        let store = ConfigurationStore(url: settings)
        #expect(try Data(contentsOf: settings) == before)
        #expect(store.committed.prompts[0].id == builtin.id)
        #expect(store.committed.prompts[0].instruction == PromptAction.currentContentQuestion)
        #expect(store.committed.prompts[1] == custom)
        try store.save()
        let reopened = ConfigurationStore(url: settings)
        #expect(reopened.committed.connections == [connection])
        #expect(reopened.committed.prompts[1] == custom)
        #expect(try Data(contentsOf: oldIndex) == bytes)
    }
    @Test func nativeSearchAndPrintKeysRemainUnconsumed() {
        for flags in [CGEventFlags.maskCommand, [.maskCommand, .maskAlternate]] {
            #expect(AppShortcutMatcher.action(keyCode: 35, modifiers: flags) == nil)
        }
        #expect(AppShortcutMatcher.action(keyCode: 3, modifiers: .maskCommand) == nil)
    }
}
