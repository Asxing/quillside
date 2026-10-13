import Foundation
import AppKit
import AppKit
import Combine
import SwiftUI
import Testing
@testable import Quillside

@MainActor
final class ReadmeScreenshotTests {
    private var outputDirectory: URL {
        get throws {
            guard let path = ProcessInfo.processInfo.environment["OPENNOTES_SCREENSHOT_DIR"] else {
                throw NSError(domain: "FixtureMissing", code: 1)
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENNOTES_SCREENSHOT_DIR"] != nil))
    func testGenerateReadmeScreenshots() throws {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        try renderOnboarding(filename: "onboarding.png")
        try renderOnboarding(filename: "onboarding-dark.png", appearance: .darkAqua)
        try renderBacklinksPanel(filename: "backlinks-panel.png")
        try renderBacklinksPanel(
            filename: "backlinks-panel-dark.png",
            appearance: .darkAqua
        )
        try renderBacklinksPermission()
        try renderNoteActionsBar(filename: "note-actions-bar.png")
        try renderNoteActionsBar(
            filename: "note-actions-bar-dark.png",
            appearance: .darkAqua
        )
        try renderFloatingFormatBar()
        try renderFloatingFormatBar(
            filename: "floating-format-bar-dark.png",
            appearance: .darkAqua
        )
        try renderFloatingFormatBar(
            reduceTransparency: true,
            filename: "floating-format-bar-reduced-transparency.png"
        )
        try renderMarkdownShortcuts()
        try renderSlashCommands(selectedIndex: 0, filename: "slash-commands-top.png")
        try renderSlashCommands(
            selectedIndex: 0,
            filename: "slash-commands-top-dark.png",
            appearance: .darkAqua
        )
        try renderSlashCommands(selectedIndex: 12, filename: "slash-commands-formatting.png")
        try renderSettings(tab: .general, filename: "settings-general.png")
        try renderSettings(tab: .shortcuts, filename: "settings-shortcuts.png")
        try renderSettings(tab: .about, filename: "settings-about.png")
        try renderMenuBarStatus()
    }

    private func renderOnboarding(
        filename: String,
        appearance: NSAppearance.Name? = nil
    ) throws {
        let appState = previewAppState()
        appState.hasAccessibilityPermission = true
        appState.notesDatabaseAccess = .permissionRequired

        try render(
            FeatureScene(
                title: "第一次打开，就知道下一步",
                detail: "两项权限放在一个窗口里，状态、用途和修复动作都清楚。",
                content: OnboardingView(isPresented: .constant(true))
                    .environmentObject(appState)
            ),
            size: NSSize(width: 920, height: 620),
            filename: filename,
            appearance: appearance
        )
    }

    private func renderBacklinksPanel(
        filename: String,
        appearance: NSAppearance.Name? = nil
    ) throws {
        let appState = previewAppState()
        let viewModel = previewBacklinksViewModel()

        try render(
            FeatureScene(
                title: "原生 Backlinks，就在当前笔记旁边",
                detail: "显示当前笔记、来源摘要和更新时间，点击即可跳转。",
                content: BacklinksPanelView(viewModel: viewModel)
                    .environmentObject(appState)
            ),
            size: NSSize(width: 760, height: 560),
            filename: filename,
            appearance: appearance
        )
    }

    private func renderBacklinksPermission() throws {
        let appState = previewAppState()
        appState.notesDatabaseAccess = .permissionRequired
        let viewModel = BacklinksPanelViewModel()
        viewModel.currentNoteTitle = "Quillside 发布计划"

        try render(
            FeatureScene(
                title: "权限问题不会伪装成“没有链接”",
                detail: "数据库不可读时直接说明原因，并给出修复入口。",
                content: BacklinksPanelView(viewModel: viewModel)
                    .environmentObject(appState)
            ),
            size: NSSize(width: 760, height: 520),
            filename: "backlinks-permission.png"
        )
    }

    private func renderNoteActionsBar(
        filename: String,
        appearance: NSAppearance.Name? = nil
    ) throws {
        try render(
            FeatureScene(
                title: "当前笔记的常用动作，始终在手边",
                detail: "复制 Markdown、复制原生链接、Backlinks 和 AI 写作入口。",
                content: NoteActionsBarView(viewModel: NoteActionsBarViewModel())
            ),
            size: NSSize(width: 720, height: 300),
            filename: filename,
            appearance: appearance
        )
    }

    private func renderFloatingFormatBar(
        reduceTransparency: Bool = false,
        filename: String = "floating-format-bar.png",
        appearance: NSAppearance.Name? = nil
    ) throws {
        try render(
            FeatureScene(
                title: "选中文字，十项格式立即可用",
                detail: "文本、列表和强调三组排列，能力完整但不拥挤。",
                content: FloatingBarView(
                    viewModel: FloatingBarViewModel(
                        selectedActions: [.bold, .bullet]
                    )
                )
                    .environment(
                        \.quillsideReduceTransparencyOverride,
                        reduceTransparency
                    )
            ),
            size: NSSize(width: 760, height: 320),
            filename: filename,
            appearance: appearance
        )
    }

    private func renderMarkdownShortcuts() throws {
        try render(
            FeatureScene(
                title: "熟悉的 Markdown 输入，转换为原生格式",
                detail: "八种触发规则来自运行时同一份定义，不是单独维护的文档样例。",
                content: MarkdownShortcutShowcase()
            ),
            size: NSSize(width: 760, height: 500),
            filename: "markdown-shortcuts.png"
        )
    }

    private func renderSlashCommands(
        selectedIndex: Int,
        filename: String,
        appearance: NSAppearance.Name? = nil
    ) throws {
        let monitor = KeyboardMonitorService()
        let service = SlashCommandService(keyboardMonitor: monitor)

        try render(
            FeatureScene(
                title: "输入 /，直接选择下一步",
                detail: "格式命令与模板分组显示，继续键入即可筛选。",
                content: SlashMenuView(
                    commands: Just(service.filteredCommands).eraseToAnyPublisher(),
                    selectedIndex: Just(selectedIndex).eraseToAnyPublisher(),
                    commandBuffer: Just("").eraseToAnyPublisher(),
                    initialCommands: service.filteredCommands,
                    initialSelectedIndex: selectedIndex,
                    onSelect: { _ in }
                )
                .frame(height: 380)
            ),
            size: NSSize(width: 760, height: 580),
            filename: filename,
            appearance: appearance
        )
    }

    private func renderSettings(
        tab: SettingsTab,
        filename: String
    ) throws {
        let appState = previewAppState()

        try render(
            SettingsView(
                initialTab: tab,
                displayVersionOverride: previewVersion
            )
            .environmentObject(appState),
            size: NSSize(width: 900, height: 690),
            filename: filename
        )
    }

    private var previewVersion: String {
        ProcessInfo.processInfo.environment["OPENNOTES_PREVIEW_VERSION"]
            ?? "Development"
    }

    private func renderMenuBarStatus() throws {
        let appState = previewAppState()

        try render(
            FeatureScene(
                title: "状态和动作回到标准菜单",
                detail: "Backlinks、诊断、设置和退出都保持 macOS 熟悉的层级。",
                content: MenuBarScreenshotView(appState: appState)
            ),
            size: NSSize(width: 680, height: 500),
            filename: "menu-bar-status.png"
        )
    }

    private func previewAppState() -> AppState {
        let appState = AppState()
        appState.hasAccessibilityPermission = true
        appState.notesDatabaseAccess = .available
        appState.automationAccess = .notDetermined
        appState.isNotesRunning = true
        appState.isNotesFrontmost = true
        return appState
    }

    private func previewBacklinksViewModel() -> BacklinksPanelViewModel {
        let viewModel = BacklinksPanelViewModel()
        viewModel.currentNoteTitle = "Quillside 发布计划"
        viewModel.configureForPreview(backlinks: [
            .init(
                id: 1,
                noteTitle: "设计评审记录",
                identifier: "example-1",
                context: "交互细节与改进项，包括权限状态和快捷输入。",
                modificationDate: Date(timeIntervalSince1970: 1_785_096_000)
            ),
            .init(
                id: 2,
                noteTitle: "本周工作复盘",
                identifier: "example-2",
                context: "关联任务、发布检查和后续行动。",
                modificationDate: Date(timeIntervalSince1970: 1_785_009_600)
            ),
            .init(
                id: 3,
                noteTitle: "产品路线与里程碑",
                identifier: "example-3",
                context: "从开源预览到稳定版本的计划。",
                modificationDate: Date(timeIntervalSince1970: 1_784_404_800)
            ),
        ])
        return viewModel
    }

    private func render<Content: View>(
        _ content: Content,
        size: NSSize,
        filename: String,
        appearance: NSAppearance.Name? = nil
    ) throws {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        if let appearance {
            window.appearance = NSAppearance(named: appearance)
        }
        window.contentView = hostingView
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            Issue.record("Failed to create bitmap for \(filename)"); return
        }

        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        window.orderOut(nil)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to encode \(filename)"); return
        }

        try pngData.write(to: outputDirectory.appendingPathComponent(filename))
    }
}

private struct FeatureScene<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .center
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.35)

                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 7)

                Spacer()

                content
                    .frame(maxWidth: .infinity)

                Spacer()
            }
            .padding(42)
        }
    }
}

private struct MarkdownShortcutShowcase: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(MarkdownTriggerDefinition.all) { trigger in
                HStack(spacing: 12) {
                    Text(trigger.pattern)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .frame(width: 48, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(trigger.resultName)
                        .font(.system(size: 12, weight: .medium))

                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(
                    Color(nsColor: .windowBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(QuillsideStyle.border, lineWidth: 0.5)
                }
            }
        }
        .frame(maxWidth: 620)
    }
}

private struct MenuBarScreenshotView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        FloatingSurface(cornerRadius: 9) {
            VStack(spacing: 0) {
                ForEach(MenuBarContent.entries(for: appState)) { entry in
                    switch entry.kind {
                    case .divider:
                        Divider()
                    case .status, .action(_):
                        menuRow(entry)
                    }
                }
            }
            .frame(width: 260)
        }
    }

    private func menuRow(_ entry: MenuBarEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbol ?? "circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(entry.kind == .status ? Color.green : Color.secondary)
                .frame(width: 18)

            Text(entry.title)
                .font(.system(size: 12))

            Spacer()

            if let shortcut = entry.shortcut {
                Text(shortcut.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}
