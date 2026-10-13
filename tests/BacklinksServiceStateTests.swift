import Foundation
import Testing
@testable import Quillside

@MainActor @Suite(.serialized) struct BacklinksServiceStateTests {
    final class Queue {
        var work: [() -> Void] = []
        func enqueue(_ action: @escaping () -> Void) { work.append(action) }
        func run() { work.removeFirst()() }
    }
    private func snapshot(title: String = "Source", coverage: BacklinksCoverage = .init()) -> NotesBacklinksSnapshot {
        let source = NotesDBReader.NoteInfo(id: 1, identifier: "SOURCE", title: title, snippet: "", folderName: "Notes", modificationDate: .distantPast, isPinned: false)
        let target = NotesDBReader.NoteInfo(id: 2, identifier: "TARGET", title: "Target", snippet: "", folderName: "Notes", modificationDate: .distantPast, isPinned: false)
        return .init(notes: [source, target], links: [.init(noteId: 1, linkedIdentifiers: ["TARGET"])], coverage: coverage)
    }
    @Test func queryFailureDoesNotBecomeNoLinksOrAdvanceSuccessTimestamp() {
        let queue = Queue(); var failure = false; var time = Date(timeIntervalSince1970: 10)
        let service = BacklinksService(load: { if failure { throw AIError.message("synthetic read failure") }; return snapshot() }, execute: queue.enqueue, deliver: { $0() }, now: { time })
        #expect(service.lookup("TARGET").phase == .loading)
        queue.run()
        #expect(service.lookup("TARGET").items.count == 1)
        let successTime = service.lastBuildTime
        time = Date(timeIntervalSince1970: 20); failure = true
        service.buildLinkGraph(force: true); queue.run()
        #expect(service.lookup("TARGET").phase == .failed("synthetic read failure"))
        #expect(service.lastBuildTime == successTime)
        #expect(queue.work.isEmpty)
        _ = service.lookup("TARGET")
        #expect(queue.work.isEmpty)
        failure = false; service.buildLinkGraph(force: true); queue.run()
        #expect(service.lookup("TARGET").items.count == 1)
        #expect(service.lastBuildTime == time)
    }
    @Test func invalidatedBuildIsDiscardedAndWaitersFinishAfterFreshBuild() {
        let background = Queue(), delivery = Queue(); var title = "Old"; var completions = 0
        let service = BacklinksService(load: { snapshot(title: title) }, execute: background.enqueue, deliver: delivery.enqueue)
        service.buildLinkGraph { completions += 1 }
        background.run()
        service.invalidateCache(); title = "New"
        service.buildLinkGraph { completions += 1 }
        delivery.run()
        #expect(completions == 0)
        #expect(service.state == .loading)
        #expect(background.work.count == 1)
        background.run(); delivery.run()
        #expect(completions == 2)
        #expect(service.lookup("TARGET").items.first?.noteTitle == "New")
    }
    @Test func forcedRefreshDuringBuildQueuesOneFollowup() {
        let queue = Queue(); var calls = 0
        let service = BacklinksService(load: { calls += 1; return snapshot() }, execute: queue.enqueue, deliver: { $0() })
        service.buildLinkGraph(); service.buildLinkGraph(force: true); service.buildLinkGraph(force: true)
        #expect(queue.work.count == 1)
        queue.run(); #expect(queue.work.count == 1)
        queue.run(); #expect(queue.work.isEmpty)
        #expect(calls == 2)
    }
    @Test func partialCoverageAndMissingTargetAreNotDefinitiveEmptyResults() {
        let queue = Queue()
        let service = BacklinksService(load: { snapshot(coverage: .init(unreadableNotes: 1)) }, execute: queue.enqueue, deliver: { $0() })
        service.buildLinkGraph(); queue.run()
        #expect(!service.lookup("TARGET").coverage.complete)
        #expect(service.lookup("unknown").phase == .loading)
        queue.run()
        #expect(service.lookup("unknown").phase == .targetMissing)
        #expect(queue.work.isEmpty)
    }
    @Test func duplicateMetadataUsesTheSameTargetForIndexAndGraph() {
        let queue = Queue()
        var value = snapshot()
        value = .init(notes: value.notes + [.init(id: 3, identifier: "TARGET", title: "Newest", snippet: "", folderName: "Notes", modificationDate: Date(), isPinned: false)], links: value.links)
        let service = BacklinksService(load: { value }, execute: queue.enqueue, deliver: { $0() })
        service.buildLinkGraph(); queue.run()
        #expect(service.lookup("TARGET").items.count == 1)
    }
}
