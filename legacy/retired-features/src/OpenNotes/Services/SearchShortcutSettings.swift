import Foundation
import Combine
import CoreGraphics
import Carbon

struct ShortcutChord: Codable, Equatable {
    let keyCode: UInt16
    /// Independent of CGEvent/Carbon bit layouts: Command=1, Option=2, Control=4, Shift=8.
    let modifiers: UInt8
    var keyLabel: String?
    static let notesDefault = Self(keyCode: 35, modifiers: 1, keyLabel: "P")
    static let globalDefault = Self(keyCode: 35, modifiers: 3, keyLabel: "P")
    var display: String {
        let labels: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        return (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") + (modifiers & 8 != 0 ? "⇧" : "") + (modifiers & 1 != 0 ? "⌘" : "") + (labels[keyCode] ?? keyLabel?.uppercased() ?? "Key \(keyCode)")
    }
    var eventFlags: CGEventFlags {
        var result: CGEventFlags = []
        if modifiers & 1 != 0 { result.insert(.maskCommand) }; if modifiers & 2 != 0 { result.insert(.maskAlternate) }
        if modifiers & 4 != 0 { result.insert(.maskControl) }; if modifiers & 8 != 0 { result.insert(.maskShift) }
        return result
    }
    var carbonFlags: UInt32 {
        var result: UInt32 = 0
        if modifiers & 1 != 0 { result |= UInt32(cmdKey) }; if modifiers & 2 != 0 { result |= UInt32(optionKey) }
        if modifiers & 4 != 0 { result |= UInt32(controlKey) }; if modifiers & 8 != 0 { result |= UInt32(shiftKey) }
        return result
    }
    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode && eventFlags == flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
    }
    func sameKeys(as other: Self?) -> Bool { other.map { keyCode == $0.keyCode && modifiers == $0.modifiers } ?? false }
    func validate() throws {
        let functionKeys: Set<UInt16> = [122,120,99,118,96,97,98,100,101,109,103,111]
        guard keyCode < 128, modifiers < 16, modifiers & 7 != 0 || functionKeys.contains(keyCode) else { throw AIError.message("请使用修饰键组合或功能键，避免占用普通输入。") }
        guard AppShortcutMatcher.fixedAction(keyCode: keyCode, modifiers: eventFlags) == nil else { throw AIError.message("该组合已用于 OpenNotes 的其他操作，请选择另一组合。") }
    }
}

struct SearchShortcutConfiguration: Codable, Equatable {
    var version = 1
    var notes: ShortcutChord? = .notesDefault
    var global: ShortcutChord? = .globalDefault
    func validate() throws {
        guard version == 1 else { throw AIError.message("快捷键配置版本不受支持。") }
        try notes?.validate(); try global?.validate()
    }
}

final class SearchShortcutStore: ObservableObject {
    typealias Register = (ShortcutChord, UInt32) throws -> (() -> Void)
    static let shared = SearchShortcutStore()
    @Published private(set) var configuration = SearchShortcutConfiguration()
    @Published private(set) var status = ""
    @Published private(set) var editable = true
    @Published private(set) var recording = false
    private var url: URL?
    private let persist: (SearchShortcutConfiguration, URL) throws -> Void
    private var register: Register?
    private var active: (chord: ShortcutChord, id: UInt32, cancel: () -> Void)?
    private var nextID: UInt32 = 1
    var activeGlobalID: UInt32? { active?.id }
    var notesChordForRouting: ShortcutChord? {
        guard !recording else { return nil }
        if let chord = configuration.notes, chord.sameKeys(as: active?.chord) { return nil }
        return configuration.notes
    }
    init(url: URL? = nil, persist: @escaping (SearchShortcutConfiguration, URL) throws -> Void = { try AppFiles.save($0, to: $1) }) {
        self.persist = persist
        do {
            let file = try url ?? AppFiles.directory().appendingPathComponent("shortcuts.json"); self.url = file
            if FileManager.default.fileExists(atPath: file.path) {
                let decoded = try JSONDecoder().decode(SearchShortcutConfiguration.self, from: Data(contentsOf: file))
                try decoded.validate(); configuration = decoded
            }
        } catch { editable = false; configuration = .init(notes: nil, global: nil); status = "快捷键配置无法读取，原文件保留；可恢复默认。" }
    }
    deinit { active?.cancel() }
    func bind(register: @escaping Register) {
        self.register = register
        guard editable else { return }
        resumeGlobalRegistration()
    }
    func unbind() { active?.cancel(); active = nil; register = nil }
    private func staged(_ chord: ShortcutChord?) throws -> (chord: ShortcutChord, id: UInt32, cancel: () -> Void)? {
        guard let chord, let register else { return nil }
        let id = nextID; nextID &+= 1
        return (chord, id, try register(chord, id))
    }
    func save(_ candidate: SearchShortcutConfiguration) throws {
        guard editable, let url else { throw AIError.message("请先恢复有效的快捷键配置。") }
        guard !recording else { throw AIError.message("请先完成或取消快捷键录入。") }
        try candidate.validate()
        let definitionUnchanged = candidate.global.map { $0.sameKeys(as: configuration.global) } ?? (configuration.global == nil)
        let unchanged = definitionUnchanged || (candidate.global.map { $0.sameKeys(as: active?.chord) } ?? (active == nil))
        let replacement = unchanged ? nil : try staged(candidate.global)
        do { try persist(candidate, url) }
        catch { replacement?.cancel(); throw error }
        if !unchanged { active?.cancel(); active = replacement }
        configuration = candidate
        status = register == nil ? "已保存；应用启动后注册全局快捷键。"
            : configuration.global != nil && active == nil ? "Notes 内设置已保存；全局快捷键尚未注册，请重试或更换组合。" : "已保存并应用快捷键。"
    }
    func setRecording(_ value: Bool) {
        guard recording != value else { return }
        recording = value
        if value { active?.cancel(); active = nil }
        else { resumeGlobalRegistration() }
    }
    func resumeGlobalRegistration() {
        guard editable, !recording, active == nil else { return }
        do { active = try staged(configuration.global); status = active == nil ? "全局快捷键未设置。" : "全局快捷键已注册。" }
        catch { status = error.localizedDescription }
    }
    func reset() throws {
        guard let url else { throw AIError.message("快捷键目录不可用。") }
        if !editable, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("shortcuts-unreadable-\(UUID()).json"))
        }
        let previous = editable; editable = true
        do { try save(.init()) } catch { editable = previous; throw error }
    }
}
