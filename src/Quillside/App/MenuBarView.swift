import AppKit
import ApplicationServices
import SwiftUI

enum MenuBarAction: Hashable {
    case askAI
    case accessibilitySettings
    case fullDiskAccessSettings
    case copyMarkdown
    case copyNoteLink
    case backlinks
    case diagnostics
    case settings
    case quit
}

enum MenuBarShortcut: Equatable {
    case copyMarkdown
    case copyNoteLink
    case backlinks
    case settings
    case quit

    var key: KeyEquivalent {
        switch self {
        case .copyMarkdown:
            return "m"
        case .copyNoteLink:
            return "l"
        case .backlinks:
            return "b"
        case .settings:
            return ","
        case .quit:
            return "q"
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .copyMarkdown, .copyNoteLink:
            return [.command, .option]
        case .backlinks:
            return [.command, .option, .shift]
        case .settings, .quit:
            return .command
        }
    }

    var label: String {
        switch self {
        case .copyMarkdown:
            return "⌥⌘M"
        case .copyNoteLink:
            return "⌥⌘L"
        case .backlinks:
            return "⌥⇧⌘B"
        case .settings:
            return "⌘,"
        case .quit:
            return "⌘Q"
        }
    }
}

struct MenuBarEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case status
        case action(MenuBarAction)
        case divider
    }

    let id: String
    let kind: Kind
    let title: String
    let symbol: String?
    let shortcut: MenuBarShortcut?
}

enum MenuBarContent {
    static func entries(for appState: AppState) -> [MenuBarEntry] {
        var entries = [
            MenuBarEntry(
                id: "status",
                kind: .status,
                title: appState.statusDescription,
                symbol: statusSymbol(for: appState),
                shortcut: nil
            ),
        ]

        if !appState.hasAccessibilityPermission {
            entries.append(
                MenuBarEntry(
                    id: "accessibility",
                    kind: .action(.accessibilitySettings),
                    title: "打开辅助功能设置",
                    symbol: "accessibility",
                    shortcut: nil
                )
            )
        }

        if !appState.canUseBacklinks {
            entries.append(
                MenuBarEntry(
                    id: "full-disk-access",
                    kind: .action(.fullDiskAccessSettings),
                    title: "打开完全磁盘访问设置",
                    symbol: "externaldrive.fill",
                    shortcut: nil
                )
            )
        }

        entries.append(contentsOf: [
            divider(id: "status-divider"),
            MenuBarEntry(
                id: "copy-markdown",
                kind: .action(.copyMarkdown),
                title: "复制 Markdown",
                symbol: "doc.text",
                shortcut: .copyMarkdown
            ),
            MenuBarEntry(
                id: "copy-note-link",
                kind: .action(.copyNoteLink),
                title: "复制笔记链接",
                symbol: "link",
                shortcut: .copyNoteLink
            ),
            MenuBarEntry(
                id: "backlinks",
                kind: .action(.backlinks),
                title: "反向链接",
                symbol: "arrow.triangle.branch",
                shortcut: .backlinks
            ),
            MenuBarEntry(
                id: "diagnostics",
                kind: .action(.diagnostics),
                title: "运行诊断",
                symbol: "stethoscope",
                shortcut: nil
            ),
            divider(id: "app-divider"),
            MenuBarEntry(
                id: "settings",
                kind: .action(.settings),
                title: "设置…",
                symbol: "gear",
                shortcut: .settings
            ),
            MenuBarEntry(
                id: "quit",
                kind: .action(.quit),
                title: "退出 Quillside",
                symbol: "power",
                shortcut: .quit
            ),
        ])
        return entries
    }

    private static func divider(id: String) -> MenuBarEntry {
        MenuBarEntry(id: id, kind: .divider, title: "", symbol: nil, shortcut: nil)
    }

    private static func statusSymbol(for appState: AppState) -> String {
        if !appState.hasAccessibilityPermission || !appState.canUseBacklinks {
            return "exclamationmark.circle"
        }
        if appState.isNotesFrontmost {
            return "checkmark.circle"
        }
        return "circle.dashed"
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("AI 编辑…") { MenuBarCommands.perform(.askAI, appState: appState) }
        Divider()
        ForEach(MenuBarContent.entries(for: appState)) { entry in
            switch entry.kind {
            case .status:
                Label(entry.title, systemImage: entry.symbol ?? "circle.dashed")
            case let .action(action):
                actionView(action, entry: entry)
            case .divider:
                Divider()
            }
        }
    }

    @ViewBuilder
    private func actionView(
        _ action: MenuBarAction,
        entry: MenuBarEntry
    ) -> some View {
        if let shortcut = entry.shortcut {
            actionButton(action, entry: entry)
                .keyboardShortcut(
                    shortcut.key,
                    modifiers: shortcut.modifiers
                )
        } else {
            actionButton(action, entry: entry)
        }
    }

    private func actionButton(
        _ action: MenuBarAction,
        entry: MenuBarEntry
    ) -> some View {
        Button {
            MenuBarCommands.perform(action, appState: appState)
        } label: {
            Label(entry.title, systemImage: entry.symbol ?? "circle")
        }
        .disabled(!MenuBarCommands.isEnabled(action, appState: appState))
    }

}

@MainActor enum MenuBarCommands {
    static func perform(_ action: MenuBarAction, appState: AppState) {
        switch action {
        case .askAI:
            InlineAssistantController.shared.present()
        case .accessibilitySettings:
            AccessibilityBridge.shared.openAccessibilitySettings()
        case .fullDiskAccessSettings:
            AccessibilityBridge.shared.openFullDiskAccessSettings()
        case .copyMarkdown:
            performNoteAction(.copyMarkdown)
        case .copyNoteLink:
            performNoteAction(.copyNoteLink)
        case .backlinks:
            toggleBacklinksPanel()
        case .diagnostics:
            runDiagnostics(appState: appState)
        case .settings:
            openSettings(appState: appState)
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    static func isEnabled(_ action: MenuBarAction, appState: AppState) -> Bool {
        switch action {
        case .copyMarkdown, .copyNoteLink:
            return appState.hasAccessibilityPermission
                && appState.isNotesRunning
                && appState.isNotesFrontmost
        default:
            return true
        }
    }

    private static func runDiagnostics(appState: AppState) {
        let bridge = AccessibilityBridge.shared
        var lines: [String] = []
        lines.append("=== Quillside Diagnostics ===")
        lines.append("Time: \(Date())")
        lines.append("1. AXIsProcessTrusted: \(AXIsProcessTrusted())")
        lines.append("2. Notes running: \(bridge.isNotesRunning())")
        lines.append("3. Notes frontmost: \(bridge.isNotesFrontmost())")
        lines.append("4. Notes PID available: \(bridge.getNotesAppPID() != nil)")
        lines.append("5. Notes windows: \(bridge.getNotesWindows().count)")
        lines.append("6. Focused window available: \(bridge.getFocusedWindow() != nil)")
        lines.append("7. Selection bounds available: \(bridge.getSelectionBounds() != nil)")
        lines.append("8. Selection available: \(bridge.getSelectedText() != nil)")
        lines.append("9. Notes database: \(String(describing: appState.notesDatabaseAccess))")
        lines.append("=== End Diagnostics ===")

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Quillside 诊断"
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "完成")
        alert.runModal()
    }

    private static func toggleBacklinksPanel() {
        (NSApplication.shared.delegate as? AppDelegate)?.toggleBacklinksPanel()
    }

    private static func performNoteAction(_ action: NoteActionKind) {
        (NSApplication.shared.delegate as? AppDelegate)?
            .performNoteAction(action)
    }

    private static func openSettings(appState: AppState) {
        SettingsWindowController.shared.show(appState: appState)
    }
}
