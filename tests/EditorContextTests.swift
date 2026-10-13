import Foundation
import Testing
@testable import Quillside

@Suite struct EditorContextTests {
    @Test func markdownOnlyCommitsActualSingleSpaceAfterExistingMarker() {
        for pattern in MarkdownTriggerDefinition.all.map(\.pattern) {
            let before = "前文🙂\n" + pattern.dropLast(), caret = (before as NSString).length
            #expect(MarkdownInputContext.committedTrigger(before: before, selection: .init(location: caret,length: 0), after: before + " ", afterSelection: .init(location: caret + 1,length: 0)) == pattern)
            #expect(MarkdownInputContext.committedTrigger(before: before, selection: .init(location: caret,length: 0), after: before, afterSelection: .init(location: caret,length: 0)) == nil)
        }
        #expect(MarkdownInputContext.committedTrigger(before: "", selection: .init(location: 0,length: 0), after: "## ", afterSelection: .init(location: 3,length: 0)) == nil)
    }
    @Test func markdownUsesCurrentLineRatherThanPreviouslyTypedBuffer() {
        for prefix in ["", "之前输入的长正文\n", "🙂👨‍👩‍👧\n"] {
            for pattern in MarkdownTriggerDefinition.all.map(\.pattern) {
                let body = prefix + pattern
                #expect(MarkdownInputContext.trigger(body: body, selection: NSRange(location: (body as NSString).length, length: 0)) == pattern)
            }
        }
        for body in ["正文## ", "#### ", "  # ", "https://example.com/# ", "\n## 后续文字"] {
            #expect(MarkdownInputContext.trigger(body: body, selection: NSRange(location: (body as NSString).length, length: 0)) == nil)
        }
        #expect(MarkdownInputContext.trigger(body: "## ", selection: NSRange(location: 0, length: 3)) == nil)
        #expect(MarkdownInputContext.trigger(body: "## ", selection: NSRange(location: 99, length: 0)) == nil)
    }
    @Test func identifiesBodyAndDoesNotClaimCellOrDialogAsWholeNote() {
        let bodyAncestor = NotesEditorNode(role: "AXScrollArea", identifier: "Note Body Scroll View")
        #expect(NotesEditorPolicy.scope(role: "AXTextArea", identifier: "Note Body Text View", ancestors: [bodyAncestor]) == .body)
        let cell = NotesEditorPolicy.scope(role: "AXTextArea", identifier: "", ancestors: [.init(role: "AXCell", identifier: ""), bodyAncestor])
        #expect(cell == .cell)
        #expect(!NotesEditorPolicy.canCapture(scope: cell, selectionLength: 0))
        #expect(NotesEditorPolicy.canCapture(scope: cell, selectionLength: 5))
        #expect(NotesEditorPolicy.scope(role: "AXTextField", identifier: "", ancestors: [bodyAncestor]) == .unknown)
        #expect(NotesEditorPolicy.scope(role: "AXTextArea", identifier: "", ancestors: []) == .unknown)
        #expect(NotesEditorPolicy.scope(role: "AXTextArea", identifier: "Note Body Text View", ancestors: [.init(role: "AXSheet", identifier: "")]) == .unknown)
    }
    @Test func compositionAndUnknownInputMethodKeepCandidateKeysNative() {
        #expect(!NotesEditorPolicy.mayConsumeNavigation(inputMethod: true, markedLength: nil))
        #expect(!NotesEditorPolicy.mayConsumeNavigation(inputMethod: false, markedLength: 2))
        #expect(NotesEditorPolicy.mayConsumeNavigation(inputMethod: true, markedLength: 0))
        #expect(NotesEditorPolicy.mayConsumeNavigation(inputMethod: false, markedLength: nil))
    }
    @Test func closingOnePanelDoesNotReleaseAnotherPanelsKeyboardProtection() {
        let gate = InlineInteractionGate()
        gate.setActive(true, owner: .ai); gate.setActive(true, owner: .templates)
        gate.setActive(false, owner: .ai); #expect(gate.isActive)
        gate.setActive(false, owner: .ai); #expect(gate.isActive)
        gate.setActive(false, owner: .templates); #expect(!gate.isActive)
    }
    @Test func perTriggerSwitchPersistsAndCannotInventUnsupportedTriggers() throws {
        let name = "Quillside-trigger-test-\(UUID())", defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(MarkdownTriggerPreferences.enabled(defaults: defaults).count == 9)
        MarkdownTriggerPreferences.set("## ", enabled: false, defaults: defaults)
        #expect(!MarkdownTriggerPreferences.enabled(defaults: defaults).contains("## "))
        #expect(MarkdownTriggerPreferences.enabled(defaults: defaults).contains("# "))
        MarkdownTriggerPreferences.set("made-up", enabled: true, defaults: defaults)
        #expect(!MarkdownTriggerPreferences.enabled(defaults: defaults).contains("made-up"))
        MarkdownTriggerPreferences.set("## ", enabled: true, defaults: defaults)
        #expect(MarkdownTriggerPreferences.enabled(defaults: defaults).count == 9)
    }
    @Test func pastePreservesSurroundingTextAndRejectsObjectsAndBrokenUTF16() throws {
        #expect(try NotesPastePlan.expected(body: "头🙂旧文尾", range: .init(location: 3, length: 2), replacement: "新文") == "头🙂新文尾")
        #expect(try NotesPastePlan.expected(body: "前\u{FFFC}后", range: .init(location: 3, length: 0), replacement: "追加") == "前\u{FFFC}后追加")
        #expect(throws: AIError.self) { try NotesPastePlan.expected(body: "头🙂尾", range: .init(location: 2, length: 1), replacement: "x") }
        #expect(throws: AIError.self) { try NotesPastePlan.expected(body: "前\u{FFFC}后", range: .init(location: 1, length: 1), replacement: "x") }
        #expect(!NotesPastePlan.mayRestoreClipboard(savedChange: 10, currentChange: 11))
        #expect(NotesPastePlan.mayRestoreClipboard(savedChange: 10, currentChange: 10))
    }
}
