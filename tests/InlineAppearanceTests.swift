import AppKit
import SwiftUI
import Testing
@testable import Quillside

@MainActor struct InlineAppearanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENNOTES_INLINE_SCREENSHOT_DIR"] != nil))
    func renderChooserResultAndSettings() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OPENNOTES_INLINE_SCREENSHOT_DIR"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var config = AIConfiguration()
        let connection = ModelConnection(name: "本机测试", api: .ollama, baseURL: "http://127.0.0.1:11434", model: "fixture")
        config.connections = [connection]; config.selectedConnectionID = connection.id
        let model = InlineAssistantModel(generate: { _, _, _, _ in "计划在周五完成交付。请先确认负责人和验收标准。" })
        model.begin(target: .init(text: "我们计划在本周五交付这个项目，但目前还需要确认负责人和验收标准。", hasSelection: true, validate: {}, apply: { _, _ in }), configuration: config)
        try render(InlineAssistantView(model: model, close: {}, configure: {}).environment(\.colorScheme, .light), size: InlineAssistantLayout.size(model: model), to: folder.appendingPathComponent("inline-chooser.png"))
        try render(InlineAssistantView(model: model, close: {}, configure: {}).environment(\.colorScheme, .dark), size: InlineAssistantLayout.size(model: model), to: folder.appendingPathComponent("inline-chooser-dark.png"))
        model.run(model.prompts[0])
        for _ in 0..<100 where model.phase != .ready { try await Task.sleep(nanoseconds: 1_000_000) }
        try #require(model.phase == .ready)
        try render(InlineAssistantView(model: model, close: {}, configure: {}).environment(\.colorScheme, .light), size: InlineAssistantLayout.size(model: model), to: folder.appendingPathComponent("inline-result.png"))
        try render(InlineAssistantView(model: model, close: {}, configure: {}).environment(\.colorScheme, .dark), size: InlineAssistantLayout.size(model: model), to: folder.appendingPathComponent("inline-result-dark.png"))
        model.result = String(repeating: "这是一段较长的候选结果，用来核对滚动与操作按钮是否完整保留。\n", count: 30)
        try render(InlineAssistantView(model: model, close: {}, configure: {}), size: InlineAssistantLayout.size(model: model), to: folder.appendingPathComponent("inline-result-long.png"))
        model.targetChanged("笔记或选区已改变。")
        try render(InlineAssistantView(model: model, close: {}, configure: {}), size: InlineAssistantLayout.size(model: model), to: folder.appendingPathComponent("inline-result-stale.png"))
        let template = TemplatePickerModel()
        template.begin(templates: config.templates, apply: { _ in })
        try render(TemplatePickerView(model: template, close: {}), size: CGSize(width: 380, height: 248), to: folder.appendingPathComponent("inline-templates.png"))
        try render(SettingsView(initialTab: .general).environmentObject(AppState()), size: CGSize(width: 900, height: 690), to: folder.appendingPathComponent("settings.png"))
        let revision = WritingSessionModel(generate: { _,_,_,_ in "" })
        let body = "项目方案\n原文中的效率提升需要更准确地说明。\n目前处理时间从30分钟缩短到10分钟，仍需人工复核。"
        var draft = WritingDraft(noteIdentity: "render-fixture", baseline: body, rangeLocation: 0, rangeLength: (body as NSString).length, hasSelection: true, candidate: body)
        try draft.annotate(range: (body as NSString).range(of: "效率提升"), comment: "避免空泛表达，和后面的数字对应。")
        revision.begin(draft, config: config)
        for (name, scheme) in [("revision", ColorScheme.light), ("revision-dark", ColorScheme.dark)] {
            try render(WritingSessionView(model: revision, close: {}, addOriginal: {}, startFresh: {}).environment(\.colorScheme, scheme), size: CGSize(width: 680, height: 610), to: folder.appendingPathComponent(name + ".png"))
            let item = try #require(draft.annotations.first)
            try render(InlineAnnotationBubble(anchor: .init(annotation: item), items: [item], save: { _,_,_,_ in true }, delete: { _ in }, close: {}).environment(\.colorScheme, scheme), size: CGSize(width: 330, height: 270), to: folder.appendingPathComponent(name + "-bubble.png"))
        }
    }
    @Test func compactLayoutGrowsWithinBoundsAndLeavesRoomForErrors() {
        let model = InlineAssistantModel(generate: { _, _, _, _ in "" })
        var config = AIConfiguration(); let connection = ModelConnection(model: "fixture")
        config.connections = [connection]; config.selectedConnectionID = connection.id
        model.begin(target: .init(text: "选区", hasSelection: true, validate: {}, apply: { _, _ in }), configuration: config)
        #expect(InlineAssistantLayout.size(model: model).height < 300)
        #expect(InlineAssistantLayout.resultHeight(String(repeating: "长文本\n", count: 5000)) <= 240)
        #expect(InlineAssistantLayout.size(model: model, options: true, original: true).height > InlineAssistantLayout.size(model: model).height)
    }
    private func render<V: View>(_ content: V, size: CGSize, to file: URL) throws {
        let view = NSHostingView(rootView: content)
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: file)
    }
}
