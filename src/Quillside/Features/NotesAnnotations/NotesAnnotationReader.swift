import AppKit
import ApplicationServices

struct NotesAnnotationProjection {
    let viewport: CGRect
    let marks: [(WritingAnnotation, CGRect)]
    var commentBounds: CGRect?
}

enum NotesAnnotationObservation {
    case hidden
    case changed(CGRect)
    case visible(NotesAnnotationProjection)
}

enum NotesAnnotationReader {
    static func viewport(editor: AXUIElement, window: AXUIElement) -> CGRect? {
        let bridge = AccessibilityBridge.shared
        guard let windowFrame = bridge.getElementFrame(window) else { return nil }
        var node = editor
        for _ in 0..<10 {
            if SelectionTransaction.value(kAXIdentifierAttribute, of: node) as? String == "Note Body Scroll View",
               let frame = bridge.getElementFrame(node) { return frame.intersection(windowFrame) }
            guard let parent = SelectionTransaction.value(kAXParentAttribute, of: node), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            node = parent as! AXUIElement
        }
        return bridge.getElementFrame(editor)?.intersection(windowFrame)
    }
    static func bounds(_ range: NSRange, in element: AXUIElement) -> CGRect? {
        var range = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(result as! AXValue, .cgRect, &rect) && rect.width > 0 && rect.height > 0 ? rect : nil
    }
    static func read(target: SelectionTransaction, draft: WritingDraft, verifyContext: Bool,
                     contextVerified: Bool, openCommentRange: NSRange?) -> NotesAnnotationObservation {
        guard AppleNotesTarget.isFrontmost(), let window = AccessibilityBridge.shared.getFocusedWindow() else { return .hidden }
        var sameNote: Bool? = contextVerified ? true : nil
        if verifyContext {
            let identity = try? SystemAppleNotesSelectionProvider().selectedNote(includeBody: false, allowAutomationPrompt: false).get().coreDataIdentifier
            sameNote = identity.map { $0 == draft.noteIdentity }
        }
        let sameWindow = CFEqual(window.element, target.window)
        let visibleWindow = SelectionTransaction.value(kAXMinimizedAttribute, of: window.element) as? Bool != true
        guard NotesAnnotationPresence.context(notesVisible: visibleWindow, sameNote: sameNote, sameWindow: sameWindow, bodyFocused: false) == .keep,
              let viewport = viewport(editor: target.element, window: target.window),
              viewport.width > 100, viewport.height > 100 else { return .hidden }
        if verifyContext {
            guard let body = SelectionTransaction.value(kAXValueAttribute, of: target.element) as? String else { return .hidden }
            guard body == draft.baseline else { return .changed(viewport) }
        }
        var visible: NSRange?
        if let raw = SelectionTransaction.value("AXVisibleCharacterRange", of: target.element), CFGetTypeID(raw) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length > 0 { visible = NSRange(location: range.location, length: range.length) }
        }
        var marks: [(WritingAnnotation, CGRect)] = []
        for item in draft.annotations where item.versionID == draft.id && item.enabled {
            guard marks.count < 32, let range = NotesAnnotationGeometry.absoluteRange(item, draft: draft),
                  visible == nil || NSIntersectionRange(visible!, range).length > 0,
                  let rect = bounds(range, in: target.element), rect.intersects(viewport) else { continue }
            marks.append((item, rect))
        }
        let commentBounds = openCommentRange.flatMap { bounds($0, in: target.element) }
        return .visible(.init(viewport: viewport, marks: marks, commentBounds: commentBounds))
    }
}
