import Foundation
import AppKit
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class NoteActionsTests {
    @Test
    func testCatalogEnablesAIWithDedicatedWorkspaceRoute() {
        #expect(NoteActionItem.allCases.map(\.id) == ["copy-markdown", "copy-note-link", "backlinks", "ask-ai"])
        #expect(NoteActionItem.allCases.map(\.isEnabled) == [true, true, true, true])
        #expect(NoteActionItem.askAI.actionKind == nil)
    }

    @Test
    func testPresentationKeepsMenuFailureFeedbackVisible() {
        #expect(NoteActionsPresentationPolicy.shouldShow(
                hasCurrentNote: false,
                hasFeedback: true,
                isNotesFrontmost: false
            ))
        #expect(!(NoteActionsPresentationPolicy.shouldShow(
                hasCurrentNote: false,
                hasFeedback: false,
                isNotesFrontmost: true
            )))
    }

    @Test
    func testCopyNoteLinkWritesStringAndURLPasteboardTypes() {
        let pasteboard = PasteboardWriterSpy()
        let service = makeService(pasteboard: pasteboard)

        let outcome = try? service
            .perform(
                .copyNoteLink,
                expectedNote: ResolvedCurrentNote(
                    identifier: "CURRENT-ID",
                    title: "Current"
                )
            )
            .get()
        #expect(pasteboard.writes.isEmpty)
        #expect(outcome?.pasteboardPayload != nil)
        #expect(service.commitPasteboard(outcome!.pasteboardPayload!))
        #expect(pasteboard.writes == [
                .init(
                    value: "applenotes:note/CURRENT-ID",
                    types: [.string, .URL]
                ),
            ])
    }

    @Test
    func testCopyMarkdownWritesOnlyAfterCompleteConversion() {
        let pasteboard = PasteboardWriterSpy()
        let service = makeService(pasteboard: pasteboard)

        let outcome = try? service
            .perform(
                .copyMarkdown,
                expectedNote: ResolvedCurrentNote(
                    identifier: "CURRENT-ID",
                    title: "Current"
                )
            )
            .get()
        #expect(pasteboard.writes.isEmpty)
        #expect(outcome?.pasteboardPayload != nil)
        #expect(service.commitPasteboard(outcome!.pasteboardPayload!))
        #expect(pasteboard.writes == [
                .init(
                    value: "# Current\n\n**Entire body**",
                    types: [.string]
                ),
            ])
    }

    @Test
    func testCopyMarkdownWorksWithoutDatabaseAccess() {
        let pasteboard = PasteboardWriterSpy()
        let service = makeService(
            accessStatus: .permissionRequired,
            pasteboard: pasteboard
        )

        let outcome = try? service
            .perform(.copyMarkdown, expectedNote: nil)
            .get()
        #expect(pasteboard.writes.isEmpty)
        #expect(service.commitPasteboard(outcome!.pasteboardPayload!))
        #expect(pasteboard.writes.count == 1)
    }

    @Test
    func testCopyNoteLinkExplainsDatabaseRequirement() {
        let pasteboard = PasteboardWriterSpy()
        let service = makeService(
            accessStatus: .permissionRequired,
            pasteboard: pasteboard
        )

        #expect(service.perform(.copyNoteLink, expectedNote: nil) == .failure(.resolution(.databaseUnavailable)))
        #expect(pasteboard.writes.isEmpty)
    }

    @Test
    func testViewModelIgnoresDoubleActivationWhileActionIsRunning() {
        let service = NoteActionsServiceStub()
        let executor = ManualExecutor()
        let viewModel = NoteActionsBarViewModel(
            service: service,
            execute: executor.enqueue,
            deliver: { $0() }
        )
        viewModel.setCurrentNote(
            ResolvedCurrentNote(identifier: "CURRENT-ID", title: "Current")
        )

        viewModel.perform(.copyMarkdown)
        viewModel.perform(.copyMarkdown)

        #expect(executor.pendingCount == 1)
        #expect(viewModel.activeAction == .copyMarkdown)

        executor.runNext()

        #expect(service.performedActions == [.copyMarkdown])
        #expect(viewModel.activeAction == nil)
        #expect(viewModel.feedback?.message == "已复制 Markdown")
        #expect(service.committedPayloads.count == 1)
    }

    @Test
    func testViewModelReportsPasteboardCommitFailure() {
        let service = NoteActionsServiceStub()
        service.shouldCommitPasteboard = false
        let executor = ManualExecutor()
        let viewModel = NoteActionsBarViewModel(
            service: service,
            execute: executor.enqueue,
            deliver: { $0() }
        )
        viewModel.setCurrentNote(
            ResolvedCurrentNote(identifier: "CURRENT-ID", title: "Current")
        )

        viewModel.perform(.copyNoteLink)
        executor.runNext()

        #expect(viewModel.activeAction == nil)
        #expect(viewModel.feedback?.kind == .error)
        #expect(viewModel.feedback?.message == "复制失败，请重试")
        #expect(service.committedPayloads.count == 1)
    }

    @Test
    func testViewModelDiscardsCompletionAfterNoteChanges() {
        let service = NoteActionsServiceStub()
        let executor = ManualExecutor()
        let viewModel = NoteActionsBarViewModel(
            service: service,
            execute: executor.enqueue,
            deliver: { $0() }
        )
        viewModel.setCurrentNote(
            ResolvedCurrentNote(identifier: "FIRST-ID", title: "First")
        )

        viewModel.perform(.copyNoteLink)
        viewModel.setCurrentNote(
            ResolvedCurrentNote(identifier: "SECOND-ID", title: "Second")
        )
        executor.runNext()

        #expect(viewModel.feedback == nil)
        #expect(viewModel.activeAction == nil)
        #expect(viewModel.currentNote?.identifier == "SECOND-ID")
        #expect(service.committedPayloads.isEmpty)
    }

    @Test
    func testViewModelDiscardsCompletionAfterRealContextRefreshPath() {
        let service = NoteActionsServiceStub()
        let executor = ManualExecutor()
        let viewModel = NoteActionsBarViewModel(
            service: service,
            execute: executor.enqueue,
            deliver: { $0() }
        )
        viewModel.setCurrentNote(
            ResolvedCurrentNote(identifier: "FIRST-ID", title: "First")
        )

        viewModel.perform(.copyNoteLink)
        viewModel.noteContextDidChange()
        executor.runNext()

        #expect(service.committedPayloads.isEmpty)
        #expect(viewModel.activeAction == nil)

        executor.runNext()
        #expect(viewModel.currentNote?.identifier == "CURRENT-ID")
    }

    @Test
    func testCopyNoteLinkWaitsForSystemAutomationConsent() {
        let service = NoteActionsServiceStub()
        let executor = ManualExecutor()
        let timeoutScheduler = ManualTimeoutScheduler()
        let viewModel = NoteActionsBarViewModel(
            service: service,
            operationTimeout: 3,
            execute: executor.enqueue,
            deliver: { $0() },
            scheduleTimeout: timeoutScheduler.schedule
        )
        viewModel.setCurrentNote(
            ResolvedCurrentNote(identifier: "CURRENT-ID", title: "Current")
        )

        viewModel.perform(.copyNoteLink)

        #expect(viewModel.activeAction == .copyNoteLink)
        #expect(timeoutScheduler.pendingCount == 0)
    }

    @Test
    func testCopyMarkdownWaitsForSystemAutomationConsent() {
        let service = NoteActionsServiceStub()
        let executor = ManualExecutor()
        let timeoutScheduler = ManualTimeoutScheduler()
        let viewModel = NoteActionsBarViewModel(
            service: service,
            operationTimeout: 3,
            execute: executor.enqueue,
            deliver: { $0() },
            scheduleTimeout: timeoutScheduler.schedule
        )
        viewModel.setCurrentNote(
            ResolvedCurrentNote(identifier: "CURRENT-ID", title: "Current")
        )

        viewModel.perform(.copyMarkdown)

        #expect(viewModel.activeAction == .copyMarkdown)
        #expect(timeoutScheduler.pendingCount == 0)
    }

    @Test
    func testViewModelCancelsPendingActionWhenCurrentNoteDisappears() {
        let service = NoteActionsServiceStub()
        let executor = ManualExecutor()
        let viewModel = NoteActionsBarViewModel(
            service: service,
            execute: executor.enqueue,
            deliver: { $0() }
        )
        viewModel.setCurrentNote(
            ResolvedCurrentNote(identifier: "CURRENT-ID", title: "Current")
        )

        viewModel.perform(.copyNoteLink)
        viewModel.setCurrentNote(nil)
        executor.runNext()

        #expect(viewModel.currentNote == nil)
        #expect(viewModel.activeAction == nil)
        #expect(viewModel.feedback == nil)
        #expect(service.committedPayloads.isEmpty)
    }

    private func makeService(
        accessStatus: NotesDatabaseAccessStatus = .available,
        pasteboard: PasteboardWriting
    ) -> NoteActionsService {
        let notes = [
            NotesDBReader.NoteInfo(
                id: 42,
                identifier: "CURRENT-ID",
                title: "Current",
                snippet: "",
                folderName: "Quillside Demo",
                modificationDate: Date(timeIntervalSince1970: 0),
                isPinned: false
            ),
        ]
        let resolver = CurrentNoteResolver(
            environment: CurrentNoteResolverEnvironment(
                isNotesRunning: { true },
                isNotesFrontmost: { true },
                databaseAccessStatus: { accessStatus },
                selectedTextCandidates: { ["Current"] },
                allNotes: { notes },
                identifierByPrimaryKey: { _ in "CURRENT-ID" },
                noteByIdentifier: { _ in notes[0] }
            ),
            selectionProvider: SelectionProviderForActionsStub()
        )
        return NoteActionsService(
            resolver: resolver,
            converter: AppleNotesMarkdownConverter(),
            pasteboard: pasteboard
        )
    }
}

private final class SelectionProviderForActionsStub:
    AppleNotesSelectionProviding
{
    func selectedNote(
        includeBody: Bool,
        allowAutomationPrompt: Bool
    ) -> Result<AppleNotesSelection, CurrentNoteResolutionError> {
        .success(
            AppleNotesSelection(
                coreDataIdentifier: "x-coredata://store/ICNote/p42",
                title: "Current",
                htmlBody: includeBody ? "<p><b>Entire body</b></p>" : nil
            )
        )
    }
}

private final class PasteboardWriterSpy: PasteboardWriting {
    struct Write: Equatable {
        let value: String
        let types: [NSPasteboard.PasteboardType]
    }

    private(set) var writes: [Write] = []

    func write(
        _ value: String,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        writes.append(.init(value: value, types: types))
        return true
    }
}

private final class NoteActionsServiceStub: NoteActionsServicing {
    var shouldCommitPasteboard = true
    private(set) var performedActions: [NoteActionKind] = []
    private(set) var committedPayloads:
        [NoteActionPasteboardPayload] = []

    func resolveCurrentNote()
        -> Result<ResolvedCurrentNote, NoteActionError>
    {
        .success(
            ResolvedCurrentNote(identifier: "CURRENT-ID", title: "Current")
        )
    }

    func perform(
        _ action: NoteActionKind,
        expectedNote: ResolvedCurrentNote?
    ) -> Result<NoteActionOutcome, NoteActionError> {
        performedActions.append(action)
        return .success(
            NoteActionOutcome(
                note: expectedNote
                    ?? ResolvedCurrentNote(
                        identifier: "CURRENT-ID",
                        title: "Current"
                    ),
                feedbackMessage: action.successMessage,
                pasteboardPayload:
                    action == .backlinks
                        ? nil
                        : NoteActionPasteboardPayload(
                            value: action.rawValue,
                            types: [.string]
                        )
            )
        )
    }

    func commitPasteboard(
        _ payload: NoteActionPasteboardPayload
    ) -> Bool {
        committedPayloads.append(payload)
        return shouldCommitPasteboard
    }
}

private final class ManualExecutor {
    private var work: [() -> Void] = []

    var pendingCount: Int { work.count }

    func enqueue(_ operation: @escaping () -> Void) {
        work.append(operation)
    }

    func runNext() {
        work.removeFirst()()
    }
}

private final class ManualTimeoutScheduler {
    private var work: [() -> Void] = []

    var pendingCount: Int { work.count }

    func schedule(
        delay: TimeInterval,
        operation: @escaping () -> Void
    ) {
        work.append(operation)
    }

    func runNext() {
        work.removeFirst()()
    }
}
