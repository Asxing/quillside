import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    var value: ShortcutChord?
    var label: String
    var onCapture: (ShortcutChord?) -> Void
    var onRecording: (Bool) -> Void
    final class RecorderButton: NSButton {
        var capture: ((ShortcutChord?) -> Void)?
        var recordingChanged: ((Bool) -> Void)?
        var idleTitle = "未设置"
        private var recording = false
        private var observer: NSObjectProtocol?
        override var acceptsFirstResponder: Bool { true }
        @objc func beginRecording() {
            guard !recording else { return }
            window?.makeFirstResponder(self); recording = true
            title = "请按快捷键…"; recordingChanged?(true)
        }
        func finish() {
            guard recording else { return }
            recording = false; title = idleTitle; recordingChanged?(false)
        }
        override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let window {
                observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.finish() }
            } else { finish() }
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            record(event); return true
        }
        override func keyDown(with event: NSEvent) {
            if recording { record(event) } else { super.keyDown(with: event) }
        }
        private func record(_ event: NSEvent) {
            guard !event.isARepeat else { return }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53 && flags.isEmpty { finish(); return }
            if [51, 117].contains(event.keyCode) && flags.isEmpty { finish(); capture?(nil); return }
            var modifiers: UInt8 = 0
            if flags.contains(.command) { modifiers |= 1 }; if flags.contains(.option) { modifiers |= 2 }
            if flags.contains(.control) { modifiers |= 4 }; if flags.contains(.shift) { modifiers |= 8 }
            let chord = ShortcutChord(keyCode: event.keyCode, modifiers: modifiers, keyLabel: event.charactersIgnoringModifiers.map { String($0.prefix(8)) })
            finish(); capture?(chord)
        }
    }
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(title: value?.display ?? "未设置", target: nil, action: nil)
        button.target = button; button.action = #selector(RecorderButton.beginRecording)
        button.bezelStyle = .rounded; button.setAccessibilityLabel(label)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.idleTitle = value?.display ?? "未设置"
        button.capture = onCapture; button.recordingChanged = onRecording
        if !button.title.hasPrefix("请按") { button.title = button.idleTitle }
    }
    static func dismantleNSView(_ nsView: RecorderButton, coordinator: ()) { nsView.finish() }
}

struct SearchShortcutEditor: View {
    @ObservedObject private var store = SearchShortcutStore.shared
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Notes 内搜索", value: store.configuration.notes) { candidate in
                var config = store.configuration; config.notes = candidate; save(config)
            }
            row("系统全局搜索", value: store.configuration.global) { candidate in
                var config = store.configuration; config.global = candidate; save(config)
            }
            Text("点击录入；Esc 取消，Delete 清除。按物理键位保存。录入期间暂停本应用的全局快捷键，结束后恢复。")
                .font(.caption).foregroundStyle(.secondary)
            Text(error.isEmpty ? store.status : error).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("恢复搜索默认键") { do { try store.reset(); error = "" } catch { self.error = error.localizedDescription } }.disabled(store.recording)
                Button("重试注册全局键") { error = ""; store.resumeGlobalRegistration() }.disabled(store.recording)
            }
        }
    }
    private func row(_ label: String, value: ShortcutChord?, capture: @escaping (ShortcutChord?) -> Void) -> some View {
        HStack {
            Text(label); Spacer()
            ShortcutRecorder(value: value, label: label, onCapture: capture, onRecording: store.setRecording)
                .frame(width: 170, height: 28).disabled(!store.editable)
            Button("清除") { capture(nil) }.disabled(!store.editable || value == nil || store.recording)
        }
    }
    private func save(_ config: SearchShortcutConfiguration) {
        do { try store.save(config); error = "" } catch { self.error = error.localizedDescription }
    }
}
