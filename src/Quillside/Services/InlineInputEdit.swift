import AppKit
import ApplicationServices

enum InlineInputEdit {
    static func mayRestoreTrigger(expectedBody: String, currentBody: String, caret: NSRange, insertion: Int) -> Bool {
        expectedBody == currentBody && caret.location == insertion && caret.length == 0
    }
    static func currentSlashToken() -> String? {
        guard let context = NotesEditorContext.read(), context.scope == .body, context.selection.length == 0 else { return nil }
        return SlashInputContext.token(body: context.body, caret: context.selection.location)
    }
    /// Never infer the deletion range from keyboard-event counts.
    static func range(body: String, caret: Int, trigger: String, lineStartOnly: Bool, trailingNewline: Bool) -> NSRange? {
        let value = body as NSString
        guard caret >= 0, caret <= value.length, !trigger.isEmpty else { return nil }
        let prefix = value.substring(to: caret) as NSString
        var suffix = trigger
        if trailingNewline, prefix.hasSuffix(trigger + "\n") { suffix += "\n" }
        guard prefix.hasSuffix(suffix) else { return nil }
        let start = caret - (suffix as NSString).length
        if start > 0 {
            let preceding = value.substring(with: NSRange(location: start - 1, length: 1))
            if lineStartOnly && preceding != "\n" { return nil }
            if !lineStartOnly && preceding.rangeOfCharacter(from: .whitespacesAndNewlines) == nil { return nil }
        }
        return NSRange(location: start, length: (suffix as NSString).length)
    }

    static func removeThenApply(trigger: String, lineStartOnly: Bool, trailingNewline: Bool, expected: NotesEditorContext? = nil, perform: () -> Bool) -> Bool {
        let bridge = AccessibilityBridge.shared
        guard let context = NotesEditorContext.read(), context.scope == .body, (context.markedLength ?? 0) == 0,
              expected?.stillMatches() != false, bridge.isNotesFrontmost(), let element = bridge.getFocusedUIElement(), let window = bridge.getFocusedWindow()?.element,
              SelectionTransaction.value(kAXRoleAttribute, of: element) as? String == kAXTextAreaRole,
              let body = SelectionTransaction.value(kAXValueAttribute, of: element) as? String,
              let raw = SelectionTransaction.value(kAXSelectedTextRangeAttribute, of: element),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return false }
        var selected = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &selected), selected.length == 0,
              let target = range(body: body, caret: selected.location, trigger: trigger, lineStartOnly: lineStartOnly, trailingNewline: trailingNewline) else { return false }
        var cfRange = CFRange(location: target.location, length: target.length)
        guard let value = AXValueCreate(.cfRange, &cfRange),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, "" as CFString) == .success else { return false }
        let expectedBody = (body as NSString).replacingCharacters(in: target, with: "")
        guard SelectionTransaction.value(kAXValueAttribute, of: element) as? String == expectedBody else { return false }
        if perform() { return true }
        // Restore only our removed prefix, and only if no intervening edit/focus change has occurred.
        if bridge.isNotesFrontmost(), let current = bridge.getFocusedUIElement(), CFEqual(current, element),
           let currentWindow = bridge.getFocusedWindow()?.element, CFEqual(currentWindow, window),
           let currentBody = SelectionTransaction.value(kAXValueAttribute, of: element) as? String,
           let rawRange = SelectionTransaction.value(kAXSelectedTextRangeAttribute, of: element), CFGetTypeID(rawRange) == AXValueGetTypeID() {
            var caret = CFRange()
            if AXValueGetValue(rawRange as! AXValue, .cfRange, &caret),
               mayRestoreTrigger(expectedBody: expectedBody, currentBody: currentBody,
                                 caret: NSRange(location: caret.location, length: caret.length), insertion: target.location) {
                _ = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                    (body as NSString).substring(with: target) as CFString)
            }
        }
        return false
    }
}
