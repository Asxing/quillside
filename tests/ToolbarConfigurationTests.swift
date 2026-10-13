import Foundation
import Testing
@testable import Quillside

@Suite struct ToolbarConfigurationTests {
    @Test func defaultToolbarContainsTheObservedProNotesControls() {
        #expect(ToolbarConfiguration.defaults.visibleItems == [.askAI, .annotate, .font, .bold, .italic, .underline, .strikethrough, .highlight, .link, .alignment, .checklist])
    }
    @Test func oldPreferencesKeepOrderAndVisibilityWhileAddingNewItems() {
        let old = ToolbarConfiguration(items: [.init(id: "link", visible: true), .init(id: "bold", visible: false),
                                             .init(id: "link", visible: false), .init(id: "unknown", visible: true)])
        let normalized = old.normalized()
        #expect(Array(normalized.items.prefix(2)) == [.init(id: "link", visible: true), .init(id: "bold", visible: false)])
        #expect(normalized.items.count == ToolbarItemID.allCases.count)
        #expect(Set(normalized.items.map(\.id)).count == normalized.items.count)
        #expect(!normalized.visibleItems.contains(.bold))
    }
    @Test func reorderHideAllAndReloadUsePersistedData() throws {
        let suite = "Quillside-toolbar-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let store = ToolbarSettingsStore(defaults: defaults)
        let last = store.configuration.items.count - 1
        store.setVisible("table", true)
        store.move(from: [last], to: 0)
        #expect(store.configuration.visibleItems.first == .table)
        let reloaded = ToolbarSettingsStore(defaults: defaults)
        #expect(reloaded.configuration == store.configuration)
        for item in store.configuration.items { store.setVisible(item.id, false) }
        #expect(ToolbarSettingsStore(defaults: defaults).configuration.visibleItems.isEmpty)
        #expect(ToolbarLayout.size(itemCount: 0, feedbackVisible: true, maximumWidth: 800) == .zero)
        store.reset()
        #expect(ToolbarSettingsStore(defaults: defaults).configuration == .defaults)
    }
    @Test func invalidMoveCannotLoseCommands() {
        let original = ToolbarConfiguration.defaults
        #expect(original.moving(from: [999], to: 0) == original)
        #expect(original.moving(from: [0], to: -1) == original)
        let moved = original.moving(from: [0, 2], to: original.items.count)
        #expect(Array(moved.items.suffix(2)).map(\.id) == ["askAI", "font"])
        #expect(Set(moved.items.map(\.id)) == Set(original.items.map(\.id)))
    }
    @Test func corruptOrFutureSettingsArePreservedUntilExplicitReset() throws {
        let suite = "Quillside-toolbar-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        for data in [Data("corrupt".utf8), try JSONEncoder().encode(ToolbarConfiguration(version: 99, items: []))] {
            defaults.set(data, forKey: ToolbarSettingsStore.key)
            let store = ToolbarSettingsStore(defaults: defaults)
            #expect(!store.editable)
            store.setVisible("bold", false)
            #expect(defaults.data(forKey: ToolbarSettingsStore.key) == data)
            store.reset()
            #expect(store.editable)
            #expect(defaults.data(forKey: ToolbarSettingsStore.key + ".beforeReset") == data)
        }
    }
    @Test func panelFitsScreenAndExpandsForFailureFeedback() {
        let narrow = ToolbarLayout.size(itemCount: 16, feedbackVisible: false, maximumWidth: 240)
        #expect(narrow.width == 240)
        let short = ToolbarLayout.size(itemCount: 2, feedbackVisible: false, maximumWidth: 800)
        let feedback = ToolbarLayout.size(itemCount: 2, feedbackVisible: true, maximumWidth: 800)
        #expect(short.width < feedback.width)
        #expect(short.height < feedback.height)
        #expect(feedback.width <= 800)
    }
}
