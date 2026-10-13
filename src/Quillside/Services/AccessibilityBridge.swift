import ApplicationServices
import AppKit
import os.log

enum AppleNotesTarget {
    static let bundleIdentifier = "com.apple.Notes"

    static func isFrontmost(
        bundleIdentifier: String? =
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    ) -> Bool {
        bundleIdentifier == self.bundleIdentifier
    }
}

final class AccessibilityBridge {

    static let shared = AccessibilityBridge()

    private let logger = Logger(subsystem: "com.opennotes.app", category: "Accessibility")

    private init() {}
    
    // MARK: - Permission
    
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }
    
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            logger.error("Failed to create Accessibility settings URL")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            logger.error("Failed to create Full Disk Access settings URL")
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Notes App Detection
    
    func getNotesAppPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first {
                $0.bundleIdentifier == AppleNotesTarget.bundleIdentifier
            }?
            .processIdentifier
    }
    
    func getNotesAppElement() -> AXUIElement? {
        guard let pid = getNotesAppPID() else { return nil }
        return AXUIElementCreateApplication(pid)
    }
    
    func isNotesRunning() -> Bool {
        getNotesAppPID() != nil
    }
    
    func isNotesFrontmost() -> Bool {
        AppleNotesTarget.isFrontmost()
    }
    
    // MARK: - Window Info
    
    struct WindowInfo {
        let element: AXUIElement
        let frame: CGRect
        let title: String?
        let isFocused: Bool
    }
    
    func getNotesWindows() -> [WindowInfo] {
        guard let appElement = getNotesAppElement() else { return [] }
        
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        
        guard result == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return []
        }
        
        return windows.compactMap { window -> WindowInfo? in
            guard let frame = getElementFrame(window) else { return nil }
            return WindowInfo(
                element: window,
                frame: frame,
                title: getElementTitle(window),
                isFocused: isElementFocused(window)
            )
        }
    }
    
    func getFocusedWindow() -> WindowInfo? {
        guard let appElement = getNotesAppElement() else { return nil }
        
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        
        guard result == .success, focusedWindow != nil else {
            if result != .success {
                logger.debug("getFocusedWindow AXError: \(result.rawValue)")
            }
            return nil
        }
        
        let window = (focusedWindow as! AXUIElement)
        guard let frame = getElementFrame(window) else { return nil }
        
        return WindowInfo(
            element: window,
            frame: frame,
            title: getElementTitle(window),
            isFocused: true
        )
    }

    // MARK: - Selection Detection

    struct SelectionGeometry {
        let element: AXUIElement
        let range: NSRange
        let bounds: CGRect
    }

    /// Only read the anchor needed to show the toolbar. Format inspection is separate.
    func getSelectionGeometry() -> SelectionGeometry? {
        guard let focus = NotesEditorFocus.read(), focus.scope == .body, focus.selection.length > 0 else { return nil }
        var range = CFRange(location: focus.selection.location, length: focus.selection.length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var output: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(focus.element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &output) == .success,
              let output, CFGetTypeID(output) == AXValueGetTypeID() else { return nil }
        var bounds = CGRect.zero
        guard AXValueGetValue(output as! AXValue, .cgRect, &bounds), bounds.width > 0, bounds.height > 0,
              SelectionTransaction.selectionRange(of: focus.element) == focus.selection else { return nil }
        return .init(element: focus.element, range: focus.selection, bounds: bounds)
    }

    func getSelectionFormatting(_ geometry: SelectionGeometry) -> Set<FloatingToolbarAction> {
        // Very large selections must not make Notes serialize an unbounded rich
        // document just to paint checkmarks. Native actions still use the real selection.
        guard geometry.range.length <= 16_384,
              SelectionTransaction.selectionRange(of: geometry.element) == geometry.range else { return [] }
        var range = CFRange(location: geometry.range.location, length: geometry.range.length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return [] }
        var output: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(geometry.element, kAXAttributedStringForRangeParameterizedAttribute as CFString, parameter, &output) == .success,
              SelectionTransaction.selectionRange(of: geometry.element) == geometry.range else { return [] }
        return SelectionFormattingAnalyzer.actions(in: output as? NSAttributedString)
    }

    func getSelectionBounds() -> CGRect? { getSelectionGeometry()?.bounds }

    func getSelectedText() -> String? {
        guard let focusedElement = getFocusedUIElement() else { return nil }
        
        var selectedTextValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        ) == .success else {
            return nil
        }
        
        return selectedTextValue as? String
    }

    func getSelectedNoteTextCandidates() -> Set<String> {
        guard let root = getFocusedWindow()?.element else { return [] }

        var selectedNodes: [AXUIElement] = []
        collectSelectedNodes(root, depth: 0, nodes: &selectedNodes)

        return selectedNodes
            .map { textValues(in: $0, depth: 0) }
            .max { $0.count < $1.count } ?? []
    }

    func getFocusedUIElement() -> AXUIElement? {
        guard let appElement = getNotesAppElement() else { return nil }
        
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success, focusedElement != nil else {
            return nil
        }
        
        return (focusedElement as! AXUIElement)
    }

    private func elementChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func collectSelectedNodes(
        _ element: AXUIElement,
        depth: Int,
        nodes: inout [AXUIElement]
    ) {
        guard depth <= 10 else { return }
        if boolAttribute(kAXSelectedAttribute, from: element) {
            nodes.append(element)
        }
        for child in elementChildren(element) {
            collectSelectedNodes(child, depth: depth + 1, nodes: &nodes)
        }
    }

    private func textValues(in element: AXUIElement, depth: Int) -> Set<String> {
        guard depth <= 5 else { return [] }

        var values = Set<String>()
        let role = stringAttribute(kAXRoleAttribute, from: element)
        if role == kAXStaticTextRole,
           let value = stringAttribute(kAXValueAttribute, from: element),
           !value.isEmpty {
            values.insert(value)
        }
        for child in elementChildren(element) {
            values.formUnion(textValues(in: child, depth: depth + 1))
        }
        return values
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return false
        }
        return value as? Bool ?? false
    }
    
    // MARK: - Private Helpers
    
    func getElementFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        
        let posAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        
        AXValueGetValue(posAXValue, .cgPoint, &position)
        AXValueGetValue(sizeAXValue, .cgSize, &size)
        
        return CGRect(origin: position, size: size)
    }
    
    private func getElementTitle(_ element: AXUIElement) -> String? {
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue) == .success else {
            return nil
        }
        return titleValue as? String
    }
    
    private func isElementFocused(_ element: AXUIElement) -> Bool {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focusedValue) == .success else {
            return false
        }
        return focusedValue as? Bool ?? false
    }
}
