import Foundation
import CoreGraphics
import Testing
@testable import OpenNotes

@Suite struct SearchShortcutSettingsTests {
    final class Registry {
        var active: [UInt32: ShortcutChord] = [:]
        var cancelled: [UInt32] = []
        var rejectedKey: UInt16?
        func register(_ chord: ShortcutChord, id: UInt32) throws -> () -> Void {
            if chord.keyCode == rejectedKey { throw AIError.message("synthetic shortcut conflict") }
            active[id] = chord
            return { self.active.removeValue(forKey: id); self.cancelled.append(id) }
        }
    }
    private func url() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OpenNotes-shortcut-test-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shortcuts.json")
        try AppFiles.save(SearchShortcutConfiguration(), to: url)
        return url
    }
    @Test func conflictingReplacementPreservesOldLiveBindingAndDisk() throws {
        let file = try url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let before = try Data(contentsOf: file), registry = Registry()
        let store = SearchShortcutStore(url: file); store.bind(register: registry.register)
        let originalID = store.activeGlobalID
        registry.rejectedKey = 12
        var next = store.configuration; next.global = .init(keyCode: 12, modifiers: 3, keyLabel: "Q")
        #expect(throws: AIError.self) { try store.save(next) }
        #expect(store.activeGlobalID == originalID)
        #expect(registry.active.count == 1)
        #expect(try Data(contentsOf: file) == before)
        #expect(store.configuration.global == .globalDefault)
    }
    @Test func failedPersistenceRemovesOnlyStagedRegistration() throws {
        let file = try url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let registry = Registry()
        let store = SearchShortcutStore(url: file, persist: { _, _ in throw AIError.message("synthetic disk full") })
        store.bind(register: registry.register); let originalID = store.activeGlobalID
        var next = store.configuration; next.global = .init(keyCode: 12, modifiers: 3, keyLabel: "Q")
        #expect(throws: AIError.self) { try store.save(next) }
        #expect(store.activeGlobalID == originalID)
        #expect(registry.active.count == 1)
        #expect(!registry.cancelled.contains(originalID!))
        #expect(registry.cancelled.count == 1)
    }
    @Test func successfulChangeAndClearSurviveReload() throws {
        let file = try url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let registry = Registry(), store = SearchShortcutStore(url: file)
        store.bind(register: registry.register); let originalID = store.activeGlobalID
        var next = store.configuration; next.notes = .init(keyCode: 12, modifiers: 1, keyLabel: "Q"); next.global = nil
        try store.save(next)
        #expect(store.activeGlobalID == nil)
        #expect(registry.cancelled.contains(originalID!))
        #expect(SearchShortcutStore(url: file).configuration == next)
        #expect(AppShortcutMatcher.action(keyCode: 12, modifiers: .maskCommand, notesSearch: store.notesChordForRouting) == .search)
        #expect(AppShortcutMatcher.action(keyCode: 35, modifiers: .maskCommand, notesSearch: store.notesChordForRouting) == nil)
    }
    @Test func globalConflictDoesNotPreventChangingNotesOnlyShortcut() throws {
        let file = try url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let registry = Registry(); registry.rejectedKey = 35
        let store = SearchShortcutStore(url: file); store.bind(register: registry.register)
        #expect(store.activeGlobalID == nil)
        var next = store.configuration; next.notes = .init(keyCode: 12, modifiers: 1, keyLabel: "Q")
        try store.save(next)
        #expect(store.configuration.notes == next.notes)
        #expect(store.activeGlobalID == nil)
        #expect(store.status.contains("尚未注册"))
    }
    @Test func identicalLocalGlobalChordHasOneRouteAndRecordingRestoresIt() throws {
        let file = try url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let registry = Registry(), store = SearchShortcutStore(url: file)
        store.bind(register: registry.register)
        var next = store.configuration; next.notes = next.global; try store.save(next)
        #expect(store.notesChordForRouting == nil)
        store.setRecording(true)
        #expect(registry.active.isEmpty)
        #expect(store.notesChordForRouting == nil)
        #expect(throws: AIError.self) { try store.save(store.configuration) }
        store.setRecording(false)
        #expect(registry.active.count == 1)
        #expect(store.notesChordForRouting == nil)
        store.unbind()
        #expect(registry.active.isEmpty)
    }
    @Test func ordinaryTypingAndExistingActionsCannotBeHijacked() {
        #expect(throws: AIError.self) { try ShortcutChord(keyCode: 35, modifiers: 0).validate() }
        #expect(throws: AIError.self) { try ShortcutChord(keyCode: 46, modifiers: 3).validate() }
        #expect(throws: AIError.self) { try ShortcutChord(keyCode: 35, modifiers: 255).validate() }
        let chord = ShortcutChord(keyCode: 12, modifiers: 3, keyLabel: "Q")
        #expect(chord.matches(keyCode: 12, flags: [.maskCommand, .maskAlternate, .maskAlphaShift]))
        #expect(!chord.matches(keyCode: 12, flags: [.maskCommand]))
    }
    @Test func futureConfigurationIsNotOverwrittenDuringOrdinarySave() throws {
        let file = try url(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var future = SearchShortcutConfiguration(); future.version = 99
        try AppFiles.save(future, to: file); let before = try Data(contentsOf: file)
        let store = SearchShortcutStore(url: file)
        #expect(!store.editable)
        #expect(throws: AIError.self) { try store.save(.init()) }
        #expect(try Data(contentsOf: file) == before)
        try store.reset()
        #expect(store.editable)
        #expect(SearchShortcutStore(url: file).configuration == .init())
    }
}
