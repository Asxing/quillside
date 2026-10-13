import Foundation
import AppKit
import AppKit
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class FeatureCatalogTests {
    @Test
    func testSlashMenuUsesFrontmostWindowOrdering() {
        let panel = RecordingSlashMenuPanel()

        SlashMenuPanelPresenter.show(panel)

        #expect(panel.didOrderFrontRegardless)
        #expect(!(panel.didOrderFront))
    }

    @Test
    func testMarkdownCatalogContainsAllSupportedTriggers() {
        #expect(MarkdownTriggerDefinition.all.map(\.pattern) == ["# ", "## ", "### ", "- ", "* ", "1. ", "[] ", "> ", "``` "])
    }

    @Test
    func testSlashCatalogIncludesNativeTableAndDashedList() {
        let service = SlashCommandService(keyboardMonitor: KeyboardMonitorService())

        #expect(service.filteredCommands.count == 17)
        #expect(Set(service.filteredCommands.map(\.category)) == Set(SlashCommandCategory.allCases))
        #expect(service.filteredCommands.map(\.id) == [
                "h1", "h2", "h3", "body", "bullet", "dash", "number", "todo",
                "quote", "code", "table", "link", "bold", "italic", "underline", "strike", "template",
            ])
    }

    @Test
    func testMenuCatalogUsesStandardActionsWhenFullyAvailable() {
        let appState = AppState()
        appState.hasAccessibilityPermission = true
        appState.notesDatabaseAccess = .available
        appState.isNotesRunning = true
        appState.isNotesFrontmost = true

        #expect(MenuBarContent.entries(for: appState).map(\.id) == [
                "status", "status-divider", "copy-markdown",
                "copy-note-link", "backlinks", "diagnostics", "app-divider",
                "settings", "quit",
            ])
        let shortcuts = Dictionary(
            uniqueKeysWithValues:
                MenuBarContent.entries(for: appState)
                .compactMap { entry in
                    entry.shortcut.map { (entry.id, $0) }
                }
        )
        #expect(shortcuts["copy-markdown"] == .copyMarkdown)
        #expect(shortcuts["copy-note-link"] == .copyNoteLink)
        #expect(shortcuts["backlinks"] == .backlinks)
    }

    @Test
    func testMenuCatalogAddsBothPermissionRepairActions() {
        let appState = AppState()
        appState.hasAccessibilityPermission = false
        appState.notesDatabaseAccess = .permissionRequired

        let entries = MenuBarContent.entries(for: appState)

        #expect(entries.filter {
                if case .action = $0.kind { return true }
                return false
            }.map(\.id) == [
                "accessibility", "full-disk-access", "copy-markdown",
                "copy-note-link", "backlinks", "diagnostics", "settings",
                "quit",
            ])
    }
}

private final class RecordingSlashMenuPanel: NSPanel {
    var didOrderFront = false
    var didOrderFrontRegardless = false

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
    }

    override func orderFront(_ sender: Any?) {
        didOrderFront = true
    }

    override func orderFrontRegardless() {
        didOrderFrontRegardless = true
    }
}
