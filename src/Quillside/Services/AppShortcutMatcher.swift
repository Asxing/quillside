import CoreGraphics

enum AppShortcutAction: Equatable {
    case copyMarkdown
    case copyNoteLink
    case backlinks
    case askAI
}

enum AppShortcutMatcher {
    private static let bKeyCode: CGKeyCode = 11
    private static let lKeyCode: CGKeyCode = 37
    private static let mKeyCode: CGKeyCode = 46

    static func action(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags
    ) -> AppShortcutAction? {
        return fixedAction(keyCode: keyCode, modifiers: modifiers)
    }

    static func fixedAction(keyCode: CGKeyCode, modifiers: CGEventFlags) -> AppShortcutAction? {
        if keyCode == 0, modifiers.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == [.maskCommand, .maskAlternate] { return .askAI }
        if isShortcut(
            keyCode: keyCode,
            expectedKeyCode: mKeyCode,
            required: [.maskCommand, .maskAlternate],
            disallowed: [.maskShift, .maskControl],
            modifiers: modifiers
        ) {
            return .copyMarkdown
        }
        if isShortcut(
            keyCode: keyCode,
            expectedKeyCode: lKeyCode,
            required: [.maskCommand, .maskAlternate],
            disallowed: [.maskShift, .maskControl],
            modifiers: modifiers
        ) {
            return .copyNoteLink
        }
        if isBacklinksShortcut(
            keyCode: keyCode,
            modifiers: modifiers
        ) {
            return .backlinks
        }
        return nil
    }

    static func isBacklinksShortcut(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags
    ) -> Bool {
        isShortcut(
            keyCode: keyCode,
            expectedKeyCode: bKeyCode,
            required: [.maskCommand, .maskShift, .maskAlternate],
            disallowed: [.maskControl],
            modifiers: modifiers
        )
    }

    private static func isShortcut(
        keyCode: CGKeyCode,
        expectedKeyCode: CGKeyCode,
        required: CGEventFlags,
        disallowed: CGEventFlags,
        modifiers: CGEventFlags
    ) -> Bool {
        keyCode == expectedKeyCode
            && modifiers.intersection(required) == required
            && modifiers.intersection(disallowed).isEmpty
    }
}
