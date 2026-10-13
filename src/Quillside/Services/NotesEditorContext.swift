import AppKit
import ApplicationServices
import Carbon

enum NotesEditorScope: Equatable { case body, cell, unknown }
struct NotesEditorNode {
    let role: String
    let identifier: String
}
enum NotesEditorPolicy {
    static func scope(role: String, identifier: String, ancestors: [NotesEditorNode]) -> NotesEditorScope {
        guard role == kAXTextAreaRole,
              !ancestors.contains(where: { [kAXSheetRole, kAXSearchFieldSubrole].contains($0.role) }) else { return .unknown }
        let hasBody = identifier == "Note Body Text View" || ancestors.contains { $0.identifier == "Note Body Scroll View" || $0.identifier == "Note Body Text View" }
        guard hasBody else { return .unknown }
        if ancestors.contains(where: { [kAXCellRole, kAXTableRole, kAXRowRole].contains($0.role) }) { return .cell }
        return .body
    }
    static func canCapture(scope: NotesEditorScope, selectionLength: Int) -> Bool {
        scope == .body || (scope == .cell && selectionLength > 0)
    }
    static func mayConsumeNavigation(inputMethod: Bool, markedLength: Int?) -> Bool {
        if let markedLength { return markedLength == 0 }
        return !inputMethod
    }
}

struct NotesEditorContext {
    let element: AXUIElement
    let window: AXUIElement
    let pid: pid_t
    let body: String
    let selection: NSRange
    let scope: NotesEditorScope

    static func read() -> Self? {
        let bridge = AccessibilityBridge.shared
        guard bridge.isTrusted, bridge.isNotesFrontmost(), let pid = bridge.getNotesAppPID(),
              let element = bridge.getFocusedUIElement(), let window = bridge.getFocusedWindow()?.element,
              let role = SelectionTransaction.value(kAXRoleAttribute, of: element) as? String,
              let body = SelectionTransaction.value(kAXValueAttribute, of: element) as? String,
              let range = SelectionTransaction.selectionRange(of: element), UTF16TextRange.valid(range, in: body) else { return nil }
        let id = SelectionTransaction.value(kAXIdentifierAttribute, of: element) as? String ?? ""
        var nodes: [NotesEditorNode] = [], parent = element
        for _ in 0..<12 {
            guard let value = SelectionTransaction.value(kAXParentAttribute, of: parent), CFGetTypeID(value) == AXUIElementGetTypeID() else { break }
            parent = value as! AXUIElement
            let role = SelectionTransaction.value(kAXRoleAttribute, of: parent) as? String ?? ""
            nodes.append(.init(role: role, identifier: SelectionTransaction.value(kAXIdentifierAttribute, of: parent) as? String ?? ""))
            if role == kAXWindowRole { break }
        }
        let scope = NotesEditorPolicy.scope(role: role, identifier: id, ancestors: nodes)
        guard scope != .unknown else { return nil }
        return .init(element: element, window: window, pid: pid, body: body, selection: range, scope: scope)
    }
    func stillMatches() -> Bool {
        guard let now = Self.read() else { return false }
        return now.pid == pid && CFEqual(now.element, element) && CFEqual(now.window, window)
            && now.body == body && now.selection == selection && now.scope == scope
    }
    static func inputMethodActive() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return true }
        let type = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        return type != (kTISTypeKeyboardLayout as String)
    }
    /// Only consult a marked-range attribute when the editor actually advertises it.
    var markedLength: Int? {
        var names: CFArray?
        let status = AXUIElementCopyAttributeNames(element, &names)
        let attributes = status == .success ? (names as? [String] ?? []) : []
        var markedLength: Int?
        if attributes.contains("AXMarkedTextRange"), let raw = SelectionTransaction.value("AXMarkedTextRange", of: element), CFGetTypeID(raw) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(raw as! AXValue, .cfRange, &range) { markedLength = max(0, range.length) }
        }
        return markedLength
    }
    func mayConsumeNavigation() -> Bool {
        NotesEditorPolicy.mayConsumeNavigation(inputMethod: Self.inputMethodActive(), markedLength: markedLength)
    }
}

/// Focus/selection checks for typing and the toolbar must not materialize the
/// complete AXValue. The full context remains mandatory before any mutation.
struct NotesEditorFocus {
    let element: AXUIElement
    let selection: NSRange
    let scope: NotesEditorScope
    static func read() -> Self? {
        let bridge = AccessibilityBridge.shared
        guard bridge.isTrusted, bridge.isNotesFrontmost(),
              let element = bridge.getFocusedUIElement(),
              let selection = SelectionTransaction.selectionRange(of: element),
              let role = SelectionTransaction.value(kAXRoleAttribute, of: element) as? String else { return nil }
        let id = SelectionTransaction.value(kAXIdentifierAttribute, of: element) as? String ?? ""
        guard role == kAXTextAreaRole else { return nil }
        // Notes' main editor has a stable identifier; cells are checked through ancestors.
        if id == "Note Body Text View" { return .init(element: element, selection: selection, scope: .body) }
        var nodes: [NotesEditorNode] = [], parent = element
        for _ in 0..<12 {
            guard let value = SelectionTransaction.value(kAXParentAttribute, of: parent), CFGetTypeID(value) == AXUIElementGetTypeID() else { break }
            parent = value as! AXUIElement
            let role = SelectionTransaction.value(kAXRoleAttribute, of: parent) as? String ?? ""
            nodes.append(.init(role: role, identifier: SelectionTransaction.value(kAXIdentifierAttribute, of: parent) as? String ?? ""))
            if role == kAXWindowRole { break }
        }
        let scope = NotesEditorPolicy.scope(role: role, identifier: id, ancestors: nodes)
        return scope == .unknown ? nil : .init(element: element, selection: selection, scope: scope)
    }
}

enum MarkdownInputContext {
    static func committedTrigger(before: String, selection: NSRange, after: String, afterSelection: NSRange) -> String? {
        guard selection.length == 0, UTF16TextRange.valid(selection, in: before),
              afterSelection == NSRange(location: selection.location + 1, length: 0),
              after == (before as NSString).replacingCharacters(in: selection, with: " ") else { return nil }
        return trigger(body: after, selection: afterSelection)
    }
    static func trigger(body: String, selection: NSRange) -> String? {
        guard selection.length == 0 else { return nil }
        return MarkdownTriggerDefinition.all.first {
            InlineInputEdit.range(body: body, caret: selection.location, trigger: $0.pattern, lineStartOnly: true, trailingNewline: false) != nil
        }?.pattern
    }
}
