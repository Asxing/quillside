import Foundation
import CoreGraphics
import Testing
@testable import Quillside

@Suite struct NativeNotesCommandTests {
    @Test func duplicateQuoteUsesVisiblePrimaryOrMatchingNativeShortcut() {
        let primary = NotesMenuItemDescription(title: "Block Quote", ancestors: ["Format"], enabled: true, commandCharacter: "'", commandModifiers: 0)
        var alternate = primary; alternate.alternate = true
        var hidden = primary; hidden.hidden = true
        #expect(NotesMenuMatcher.resolve(.quote, in: [alternate, primary, hidden]) == .item(1))
        var different = primary; different.commandModifiers = 2
        #expect(NotesMenuMatcher.resolve(.quote, in: [different, primary]) == .item(1))
        #expect(SlashCommandCatalog.exact("block")?.action == .quote)
    }
    @Test func matchingUsesMenuContextRatherThanAnyMatchingText() {
        let items: [NotesMenuItemDescription] = [
            .init(title: "Title", ancestors: ["Help"], enabled: true),
            .init(title: "Title", ancestors: ["Format"], enabled: true),
            .init(title: "Heading", ancestors: ["Format"], enabled: true)
        ]
        #expect(NotesMenuMatcher.resolve(.title, in: items) == .item(1))
        #expect(NotesMenuMatcher.resolve(.heading, in: items) == .item(2))
    }
    @Test func localizedLinkAndAlignmentResolveWithEllipsis() {
        let items: [NotesMenuItemDescription] = [
            .init(title: "添加链接…", ancestors: ["编辑"], enabled: false),
            .init(title: "编辑链接...", ancestors: ["编辑"], enabled: true),
            .init(title: "两端对齐", ancestors: ["格式", "文本"], enabled: true)
        ]
        #expect(NotesMenuMatcher.resolve(.link, in: items) == .item(1))
        #expect(NotesMenuMatcher.resolve(.alignJustified, in: items) == .item(2))
    }
    @Test func disabledKnownCommandDoesNotFallBackToUnrelatedShortcut() {
        let items: [NotesMenuItemDescription] = [
            .init(title: "Highlight", ancestors: ["Format"], enabled: false),
            .init(title: "Unrelated", ancestors: ["Window"], enabled: true, commandCharacter: "E", commandModifiers: 1)
        ]
        #expect(NotesMenuMatcher.resolve(.highlight, in: items) == .disabled)
        #expect(NotesMenuMatcher.resolve(.showFonts, in: items) == .unavailable)
        let linkItems: [NotesMenuItemDescription] = [
            .init(title: "Add Link…", ancestors: ["Edit"], enabled: false),
            .init(title: "Add Link", ancestors: ["Edit", "Find", "Recent Searches"], enabled: true)
        ]
        #expect(NotesMenuMatcher.resolve(.link, in: linkItems) == .disabled)
    }
    @Test func duplicateEnabledCommandsAreRejectedRatherThanChoosingFirst() {
        let item = NotesMenuItemDescription(title: "Add Link…", ancestors: ["Edit"], enabled: true)
        #expect(NotesMenuMatcher.resolve(.link, in: [item, item]) == .ambiguous)
    }
    @Test func actualMenuShortcutDisambiguatesTitleAndFontPanelAcrossLanguages() {
        let items: [NotesMenuItemDescription] = [
            .init(title: "Schriften einblenden", ancestors: ["Formatieren"], enabled: true, commandCharacter: "t", commandModifiers: 0),
            .init(title: "Titel", ancestors: ["Formatieren"], enabled: true, commandCharacter: "T", commandModifiers: 1)
        ]
        #expect(NotesMenuMatcher.resolve(.showFonts, in: items) == .item(0))
        #expect(NotesMenuMatcher.resolve(.title, in: items) == .item(1))
        #expect(NotesMenuMatcher.eventFlags(menuModifiers: 3) == [.maskCommand, .maskShift, .maskAlternate])
        #expect(NotesMenuMatcher.eventFlags(menuModifiers: 8) == [])
    }
    @Test func absentShortcutMetadataCannotTypeAnOrdinaryCharacter() {
        #expect(!NotesMenuMatcher.canPostShortcut(virtualKey: 0, character: "", modifiers: 8))
        #expect(!NotesMenuMatcher.canPostShortcut(virtualKey: nil, character: "b", modifiers: 0))
        #expect(!NotesMenuMatcher.canPostShortcut(virtualKey: 70000, character: "b", modifiers: 0))
        #expect(NotesMenuMatcher.canPostShortcut(virtualKey: 11, character: "b", modifiers: 0))
    }
    @Test func rejectedFormatPreservesFailureAndDoesNotBlindlyRetry() {
        var commands: [NativeNotesCommand] = []
        let service = FormattingService { command in commands.append(command); return .failure(.disabled) }
        #expect(!service.applyFormat(.table))
        #expect(commands == [.table])
        #expect(service.lastFailure == NotesFormatFailure.disabled.localizedDescription)
    }
    @Test func rollbackIsAllowedOnlyBeforeAnyInterveningEditOrCaretMovement() {
        #expect(InlineInputEdit.mayRestoreTrigger(expectedBody: "正文\n", currentBody: "正文\n", caret: NSRange(location: 3, length: 0), insertion: 3))
        #expect(!InlineInputEdit.mayRestoreTrigger(expectedBody: "正文\n", currentBody: "正文\n用户输入", caret: NSRange(location: 3, length: 0), insertion: 3))
        #expect(!InlineInputEdit.mayRestoreTrigger(expectedBody: "正文\n", currentBody: "正文\n", caret: NSRange(location: 1, length: 0), insertion: 3))
    }
}
