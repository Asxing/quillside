import AppKit
import SwiftUI

enum PickerKeyAction: Equatable { case move(Int), submit, cancel }
enum PickerKeyPolicy {
    static func action(selector: String, hasMarkedText: Bool) -> PickerKeyAction? {
        guard !hasMarkedText else { return nil }
        switch selector {
        case "moveUp:": return .move(-1)
        case "moveDown:": return .move(1)
        case "insertNewline:": return .submit
        case "cancelOperation:": return .cancel
        default: return nil
        }
    }
}

/// Both pickers own their text field, so the field editor can report real IME marked-text state.
struct KeyboardSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusRequest: UUID
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: KeyboardSearchField
        var focusRequest: UUID?
        init(_ parent: KeyboardSearchField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            // Marked text remains the input method's responsibility until it is committed.
            guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let action = PickerKeyPolicy.action(selector: NSStringFromSelector(commandSelector), hasMarkedText: textView.hasMarkedText()) else { return false }
            parent.text = control.stringValue
            switch action {
            case let .move(delta): parent.onMove(delta)
            case .submit: parent.onSubmit()
            case .cancel: parent.onCancel()
            }
            return true
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 17)
        field.controlSize = .large
        field.setAccessibilityLabel(placeholder)
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true, field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window, window.isVisible else { return }
                window.makeFirstResponder(field)
            }
        }
    }
}

enum PickerSelection {
    static func next<ID: Equatable>(_ selected: ID?, among ids: [ID], delta: Int) -> ID? {
        guard !ids.isEmpty else { return nil }
        guard let selected, let index = ids.firstIndex(of: selected) else { return ids[0] }
        return ids[max(0, min(ids.count - 1, index + delta))]
    }
    static func retained<ID: Equatable>(_ selected: ID?, among ids: [ID]) -> ID? {
        selected.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
    }
}
