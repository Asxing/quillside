import AppKit
import ApplicationServices

struct SelectionGuard {
    static func allowsWrite(originalBody: String, currentBody: String, range: NSRange, originalText: String,
                            expectedSelection: NSRange? = nil, currentSelection: NSRange? = nil) -> Bool {
        guard originalBody == currentBody, UTF16TextRange.valid(range, in: currentBody),
              expectedSelection == nil || expectedSelection == currentSelection,
              range.location <= (currentBody as NSString).length,
              range.length <= (currentBody as NSString).length - range.location else { return false }
        return (currentBody as NSString).substring(with: range) == originalText
    }
}

/// Captured before showing an activating AI window. Holds no authority to edit a different window.
struct SelectionTransaction {
    let element: AXUIElement
    let window: AXUIElement
    let pid: pid_t
    let body: String
    let range: NSRange
    let text: String
    let title: String
    let noteIdentity: String?
    let capturedSelection: NSRange

    static func value(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    static func capture() throws -> Self {
        let bridge = AccessibilityBridge.shared
        guard let context = NotesEditorContext.read(), NotesEditorPolicy.canCapture(scope: context.scope, selectionLength: context.selection.length) else {
            throw AIError.message("请在笔记正文中放置光标，或明确选择要处理的文字。表格单元格不能作为整篇笔记读取。")
        }
        guard bridge.isTrusted, bridge.isNotesFrontmost(), let pid = bridge.getNotesAppPID(),
              let window = bridge.getFocusedWindow(), let element = bridge.getFocusedUIElement(),
              value(kAXRoleAttribute, of: element) as? String == kAXTextAreaRole,
              let body = value(kAXValueAttribute, of: element) as? String,
              let raw = value(kAXSelectedTextRangeAttribute, of: element), CFGetTypeID(raw) == AXValueGetTypeID() else {
            throw AIError.message("请先在 Apple Notes 正文中放置光标或选择文字，再从菜单栏捕获选区。")
        }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0,
              range.location <= (body as NSString).length, range.length <= (body as NSString).length - range.location else {
            throw AIError.message("无法读取文字范围。")
        }
        let identity = try? SystemAppleNotesSelectionProvider().selectedNote(includeBody: false, allowAutomationPrompt: true).get().coreDataIdentifier
        guard bridge.isNotesFrontmost(), let currentEditor = bridge.getFocusedUIElement(), CFEqual(currentEditor, element),
              let currentWindow = bridge.getFocusedWindow(), CFEqual(currentWindow.element, window.element),
              value(kAXValueAttribute, of: element) as? String == body,
              selectionRange(of: element) == NSRange(location: range.location, length: range.length) else {
            throw AIError.message("授权或读取期间笔记发生变化，请重新捕获。")
        }
        let nsrange = NSRange(location: range.location, length: range.length)
        return Self(element: element, window: window.element, pid: pid, body: body, range: nsrange,
                    text: (body as NSString).substring(with: nsrange), title: window.title ?? "当前笔记", noteIdentity: identity, capturedSelection: nsrange)
    }

    func replacingTrigger(_ trigger: String) throws -> Self {
        guard range.length == 0,
              let target = InlineInputEdit.range(body: body, caret: range.location, trigger: trigger, lineStartOnly: false, trailingNewline: false) else {
            throw AIError.message("模板触发词已经变化，请重新输入命令。")
        }
        return Self(element: element, window: window, pid: pid, body: body, range: target,
                    text: (body as NSString).substring(with: target), title: title, noteIdentity: noteIdentity, capturedSelection: capturedSelection)
    }
    static func selectionRange(of element: AXUIElement) -> NSRange? {
        guard let raw = value(kAXSelectedTextRangeAttribute, of: element), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    @MainActor func validateEditor() throws {
        guard AccessibilityBridge.shared.isTrusted,
              AccessibilityBridge.shared.getNotesAppPID() == pid,
              let editor = AccessibilityBridge.shared.getFocusedUIElement(), CFEqual(editor, element),
              let focusedWindow = AccessibilityBridge.shared.getFocusedWindow(), CFEqual(window, focusedWindow.element),
              let current = Self.value(kAXValueAttribute, of: element) as? String,
              SelectionGuard.allowsWrite(originalBody: body, currentBody: current, range: range, originalText: text,
                expectedSelection: capturedSelection, currentSelection: Self.selectionRange(of: element)) else {
            throw AIError.message("笔记、窗口或选区已改变。")
        }
    }
    @MainActor func validateForWrite() throws {
        try validateEditor()
        guard let noteIdentity,
              let currentIdentity = try? SystemAppleNotesSelectionProvider().selectedNote(includeBody: false, allowAutomationPrompt: false).get().coreDataIdentifier,
              currentIdentity == noteIdentity,
              AccessibilityBridge.shared.getNotesAppPID() == pid,
              let focusedEditor = AccessibilityBridge.shared.getFocusedUIElement(), CFEqual(focusedEditor, element),
              let focusedWindow = AccessibilityBridge.shared.getFocusedWindow(), CFEqual(window, focusedWindow.element),
              let current = Self.value(kAXValueAttribute, of: element) as? String,
              SelectionGuard.allowsWrite(originalBody: body, currentBody: current, range: range, originalText: text,
                                        expectedSelection: capturedSelection, currentSelection: Self.selectionRange(of: element)) else {
            throw AIError.message("笔记、窗口或正文已改变。请重新捕获选区；候选结果仍在。")
        }
        guard !text.contains("\u{FFFC}") else { throw AIError.message("选区包含原生对象，请只选择文字。") }
    }

    @MainActor func activateForWrite() async throws {
        try validateForWrite()
        guard let app = NSRunningApplication(processIdentifier: pid) else { throw AIError.message("Notes 已关闭。") }
        app.activate(options: [])
        for _ in 0..<10 {
            if AccessibilityBridge.shared.isNotesFrontmost() { try validateForWrite(); return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw AIError.message("无法返回原 Notes 窗口，请重新捕获。")
    }

    @MainActor func apply(_ replacement: String, insertAfter: Bool) async throws {
        try await activateForWrite()
        let target = insertAfter ? NSRange(location: range.location + range.length, length: 0) : range
        let inserted = insertAfter ? "\n" + replacement : replacement
        try await paste(.text(inserted), at: target)
    }
}
