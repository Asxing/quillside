import Foundation
import Testing
@testable import Quillside

@Suite struct EditorPerformanceTests {
    @Test func ordinaryLongNoteInputDoesNotRequestWholeBody() {
        let note = String(repeating: "中文🙂 ordinary prose 12345 ", count: 4000)
        for ending in ["", "more text", "https://example.com/h1", "word/h1", " normal space ", "\n"] {
            let prefix = String((note + ending).suffix(EditorInputProbe.limit))
            #expect(!EditorInputProbe.needsSnapshot(prefix: prefix, startsAtDocumentBeginning: false))
        }
        #expect(!EditorInputProbe.needsSnapshot(prefix: "/h1", startsAtDocumentBeginning: false))
    }
    @Test func commandsAndCommittedDelimitersStillRequestValidatedSnapshot() {
        for token in ["/", "/h1", "/block", "/template", "/meeting"] {
            for suffix in ["", " ", "\n", "\t"] {
                #expect(EditorInputProbe.needsSnapshot(prefix: "中文🙂\n" + token + suffix, startsAtDocumentBeginning: false))
            }
        }
        for trigger in MarkdownTriggerDefinition.all {
            #expect(EditorInputProbe.needsSnapshot(prefix: "中文\n" + trigger.pattern, startsAtDocumentBeginning: false))
            #expect(EditorInputProbe.needsSnapshot(prefix: String(trigger.pattern.dropLast()), startsAtDocumentBeginning: true))
        }
    }
    @Test func eventStormKeepsAtMostOneQueryInFlightAndOnePending() throws {
        var scheduled: [() -> Void] = [], completions: [(Int) -> Void] = [], results: [Int] = []
        let pump = CoalescedObservation<Int>(schedule: { scheduled.append($0) }, read: { completions.append($0) }, deliver: { results.append($0) })
        pump.request(); try #require(scheduled.count == 1); scheduled.removeFirst()()
        for _ in 0..<1000 { pump.request() }
        #expect(completions.count == 1); #expect(scheduled.isEmpty)
        completions.removeFirst()(1)
        #expect(results == [1]); #expect(scheduled.count == 1)
        scheduled.removeFirst()(); completions.removeFirst()(2)
        #expect(results == [1, 2]); #expect(scheduled.isEmpty)
        pump.request(); scheduled.removeFirst()(); pump.cancel(); completions.removeFirst()(3)
        #expect(results == [1, 2])
    }
}
