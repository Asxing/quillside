import Foundation
import Testing
import ApplicationServices
@testable import Quillside

@Suite struct SlashObservedInputTests {
    @Test func idleAIButtonNeverAppearsAsAnOngoingOperation() {
        #expect(!NoteActionItem.askAI.isBusy(activeAction: nil))
        #expect(!NoteActionItem.copyMarkdown.isBusy(activeAction: nil))
        #expect(NoteActionItem.copyMarkdown.isBusy(activeAction: .copyMarkdown))
    }
    @MainActor @Test func actualServiceOpensAndFiltersFromCommittedTextWithoutAnyKeyEvent() {
        let element = AXUIElementCreateApplication(0)
        var current: NotesEditorContext? = .init(element: element, window: element, pid: 0, body: "测试\n/h1", selection: .init(location: 6, length: 0), scope: .body)
        let service = SlashCommandService(keyboardMonitor: KeyboardMonitorService(), readContext: { current })
        // The old event-only service never activated in this scenario.
        service.observeCommittedInput()
        #expect(service.isActive)
        #expect(service.filteredCommands.first?.id == "h1")
        current = .init(element: element, window: element, pid: 0, body: "测试\n/heading", selection: .init(location: 11, length: 0), scope: .body)
        service.observeCommittedInput()
        #expect(service.filteredCommands.first?.id == "h2")
        current = nil; service.observeCommittedInput()
        #expect(!service.isActive)
    }
    @Test func confirmsActualInsertedDelimiterWithoutConsumingInputMethodKeys() throws {
        for suffix in ["\n", "\t", " "] {
            let before = "中文🙂\n/h1", selection = NSRange(location: ("中文🙂\n/h1" as NSString).length, length: 0)
            let commit = try #require(SlashObservedInput.submission(previousBody: before, previousSelection: selection, body: before + suffix, selection: .init(location: selection.location + 1, length: 0)))
            #expect(commit.token == "/h1"); #expect(commit.suffix == suffix)
        }
    }
    @Test func candidateConfirmationWithoutDelimiterDoesNotExecute() {
        let before = "/heading", caret = NSRange(location: 8, length: 0)
        #expect(SlashObservedInput.submission(previousBody: before, previousSelection: caret, body: before, selection: caret) == nil)
        #expect(SlashObservedInput.submission(previousBody: before, previousSelection: caret, body: "/标题", selection: .init(location: 3, length: 0)) == nil)
        #expect(SlashObservedInput.submission(previousBody: before, previousSelection: caret, body: "/heading\n别的修改", selection: .init(location: 9, length: 0)) == nil)
        #expect(SlashObservedInput.submission(previousBody: "https://h1", previousSelection: .init(location: 10,length: 0), body: "https://h1\n", selection: .init(location: 11,length: 0)) == nil)
    }
}
