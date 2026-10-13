import AppKit
import Combine
import SwiftUI
import Testing
@testable import Quillside

/// Opt-in visual fixtures render production views without a model request or a user draft.
@MainActor struct UnifiedThemePreviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["QUILLSIDE_THEME_PREVIEW_DIR"] != nil))
    func renderUnifiedTheme() throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["QUILLSIDE_THEME_PREVIEW_DIR"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let controller = NativeNotesAnnotationController(store: try WritingDraftStore(directory: temporary))
        let text = "项目进展\n整理工单从30分钟缩短到10分钟，仍需人工复核。\n下一步补记复核耗时，负责人和时间暂未确定。"
        let range = NotesAnnotationGeometry.bodyRange(text)
        var draft = WritingDraft(noteIdentity: "theme-fixture", baseline: text, rangeLocation: range.location,
            rangeLength: range.length, hasSelection: false, candidate: (text as NSString).substring(with: range))
        draft.versionID = draft.id
        try draft.annotate(range: (draft.source as NSString).range(of: "仍需人工复核"), comment: "保留人工复核要求，不要写成完全自动。")
        draft.instruction = "让表达更清楚，保留数字与限制。"
        let item = try #require(draft.annotations.first)
        draft.accept(.init(document: "试用中，工单整理耗时从30分钟降至10分钟，结果仍需人工复核。\n下一步记录复核耗时；负责人和完成时间待定。",
            assessments: [.init(annotationID: item.id, status: "addressed", explanation: "保留复核要求与未知事项。")], issues: []), instruction: draft.instruction)
        controller.model.begin(draft, config: AIConfiguration())
        let agents = AgentStore(file: temporary.appendingPathComponent("agents.json"), legacy: AIConfiguration(), enabledSkills: [])
        let skills = WritingSkillStore(file: temporary.appendingPathComponent("skills.json"), bundled: nil)
        controller.model.configureAgents(agents, skills: skills)
        controller.showPreview = true
        let commands = Array(SlashCommandCatalog.builtins.prefix(8))
        let slash = SlashMenuView(commands: Empty().eraseToAnyPublisher(), selectedIndex: Empty().eraseToAnyPublisher(),
            commandBuffer: Empty().eraseToAnyPublisher(), initialCommands: commands, onSelect: { _ in })
        let bubble = InlineAnnotationBubble(anchor: .init(annotation: item), items: [item],
            save: { _, _, _, _ in true }, delete: { _ in }, close: {})
        let state = AppState()
        state.hasAccessibilityPermission = true; state.notesDatabaseAccess = .available
        state.automationAccess = .granted; state.isNotesRunning = true
        for (name, scheme, appearance, reduced) in [
            ("light", ColorScheme.light, NSAppearance.Name.aqua, false),
            ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua, false),
            ("opaque", ColorScheme.light, NSAppearance.Name.aqua, true)
        ] {
            let board = HStack(alignment: .top, spacing: 24) {
                column("Slash", slash.frame(width: 320, height: 390))
                column("批注", bubble)
                column("整体优化", NativeNotesAnnotationView(controller: controller, model: controller.model).frame(width: 370, height: 454))
            }.padding(24).frame(width: 1110, height: 540, alignment: .topLeading)
                .background(scheme == .dark ? Color(white: 0.08) : Color(white: 0.94))
                .environment(\.colorScheme, scheme).environment(\.quillsideReduceTransparencyOverride, reduced)
            try render(board, size: CGSize(width: 1110, height: 540), appearance: appearance, to: output.appendingPathComponent("panels-\(name).png"))
            try render(SettingsView(initialTab: .general, displayVersionOverride: "0.6.7").environmentObject(state)
                .environment(\.colorScheme, scheme),
                size: CGSize(width: 900, height: 690), appearance: appearance, to: output.appendingPathComponent("settings-\(name).png"))
        }
        let longQuote = String(repeating: "这是一段很长的选区文字，保留事实与数字。", count: 12)
        let longAnchor = try #require(InlineAnnotationAnchor(versionID: UUID(), range: NSRange(location: 0, length: (longQuote as NSString).length), text: longQuote))
        let longBubble = InlineAnnotationBubble(anchor: longAnchor, items: [], save: { _, _, _, _ in true }, delete: { _ in }, close: {})
        try render(longBubble, size: CGSize(width: 320, height: 280), appearance: .aqua, to: output.appendingPathComponent("comment-long.png"))
        controller.showPreview = false
        try render(NativeNotesAnnotationView(controller: controller, model: controller.model),
            size: CGSize(width: 370, height: 240), appearance: .aqua, to: output.appendingPathComponent("composer-compact.png"))
    }

    private func column<V: View>(_ title: String, _ view: V) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            view
        }
    }

    private func render<V: View>(_ content: V, size: CGSize, appearance: NSAppearance.Name, to url: URL) throws {
        let view = NSHostingView(rootView: content)
        view.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = view.appearance
        window.contentView = view
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.06))
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        window.contentView = nil
    }
}
