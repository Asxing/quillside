import Foundation
import CoreGraphics
import Testing
@testable import Quillside

@MainActor struct NotesAnnotationTests {
    func draft(_ text: String) -> WritingDraft {
        let range = NotesAnnotationGeometry.bodyRange(text)
        var draft = WritingDraft(noteIdentity: "native-note", baseline: text, rangeLocation: range.location,
            rangeLength: range.length, hasSelection: false, candidate: (text as NSString).substring(with: range))
        draft.versionID = draft.id
        return draft
    }
    @Test func bodyScopePreservesTitleAndUsesUTF16Offsets() {
        let text = "标题🙂\n正文中的🙂和数字30。"
        let scope = NotesAnnotationGeometry.bodyRange(text)
        #expect((text as NSString).substring(with: scope) == "正文中的🙂和数字30。")
        let selected = (text as NSString).range(of: "🙂和数字30")
        let local = NotesAnnotationGeometry.localSelection(selected, within: scope)
        #expect(local == NSRange(location: 4, length: 7))
        #expect(NotesAnnotationGeometry.localSelection(NSRange(location: 0, length: 2), within: scope) == nil)
        #expect(NotesAnnotationGeometry.localSelection(NSRange(location: NSNotFound, length: 2), within: scope) == nil)
    }
    @Test func sourceCommentsCanBeEditedAfterGenerationWithoutUsingCandidateOffsets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = WritingSessionModel(generate: { _,_,_,_ in "" }, store: try WritingDraftStore(directory: directory))
        let source = draft("标题\n处理30分钟。")
        model.begin(source, config: AIConfiguration())
        let anchor = try #require(InlineAnnotationAnchor(versionID: source.id, range: (source.source as NSString).range(of: "30分钟"), text: source.source))
        #expect(model.saveSourceComment(id: nil, anchor: anchor, comment: "保留数字", enabled: true))
        let item = try #require(model.draft?.annotations.first)
        model.draft?.accept(.init(document: "经过调整后的候选：30分钟。", assessments: [], issues: []), instruction: "优化")
        #expect(model.saveSourceComment(id: item.id, anchor: anchor, comment: "保留数字与单位", enabled: true))
        let current = try #require(model.draft)
        #expect(current.candidate == "经过调整后的候选：30分钟。")
        #expect(NotesAnnotationGeometry.absoluteRange(item, draft: current) == (source.baseline as NSString).range(of: "30分钟"))
        #expect(current.requirements.first?.comment == "保留数字与单位")
        #expect(current.currentAnnotations.isEmpty)
    }
    @Test func identicalTextInAnotherNoteDoesNotAuthorizeAnOverlayWrite() {
        let original = draft("标题\n相同正文")
        #expect(NotesAnnotationGeometry.matchesSource(original, noteIdentity: original.noteIdentity, body: original.baseline, sameWindow: true, sameEditor: true))
        #expect(!NotesAnnotationGeometry.matchesSource(original, noteIdentity: "another-note", body: original.baseline, sameWindow: true, sameEditor: true))
        #expect(!NotesAnnotationGeometry.matchesSource(original, noteIdentity: original.noteIdentity, body: original.baseline + "修改", sameWindow: true, sameEditor: true))
        #expect(!NotesAnnotationGeometry.matchesSource(original, noteIdentity: original.noteIdentity, body: original.baseline, sameWindow: false, sameEditor: true))
    }
    @Test(arguments: [false, true])
    func appliedDraftSurvivesReopenAfterNativeUndo(insertAfter: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WritingDraftStore(directory: directory)
        var source = draft("标题🙂\n处理30分钟。")
        try source.annotate(range: (source.source as NSString).range(of: "30分钟"), comment: "保留试用口径")
        source.accept(.init(document: "试用中处理需要30分钟。", assessments: [
            .init(annotationID: source.annotations[0].id, status: "addressed", explanation: "保留数字与单位")
        ], issues: []), instruction: "客观简洁")
        let model = WritingSessionModel(generate: { _, _, _, _ in "" }, store: store)
        model.begin(source, config: AIConfiguration())
        var writes = 0
        model.applyTarget = { submitted, append in
            #expect(submitted.annotations == source.annotations)
            #expect(append == insertAfter)
            writes += 1
        }
        await withCheckedContinuation { continuation in
            model.onApplied = { continuation.resume() }
            model.apply(insertAfter: insertAfter)
        }
        #expect(writes == 1)
        #expect(model.draft == nil) // The active operation ends; its recovery snapshot remains.
        let saved = try store.load(note: source.noteIdentity)
        let restored = try #require(saved)
        let reopened = WritingSessionModel(generate: { _, _, _, _ in "" }, store: store)
        reopened.begin(restored, config: AIConfiguration())
        #expect(reopened.draft?.annotations == source.annotations)
        #expect(reopened.draft?.versions == source.versions)
        #expect(reopened.draft?.candidate == source.candidate)
        #expect(reopened.draft?.instruction == source.instruction)
        #expect(NotesAnnotationGeometry.matchesSource(restored, noteIdentity: source.noteIdentity, body: source.baseline, sameWindow: true, sameEditor: true))
        #expect(!NotesAnnotationGeometry.matchesSource(restored, noteIdentity: source.noteIdentity, body: source.baseline + source.candidate, sameWindow: true, sameEditor: true))
    }
    @Test func dockFollowsEditorViewportIncludingNegativeScreenCoordinates() {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1600, y: 100, width: 1600, height: 900)] {
            let viewport = screen.insetBy(dx: 70, dy: 80)
            for expanded in [false, true] {
                let frame = NotesAnnotationGeometry.dockFrame(viewport: viewport, screen: screen, expanded: expanded)
                #expect(viewport.contains(frame)); #expect(frame.maxX == viewport.maxX - 10); #expect(frame.minY == viewport.minY + 10)
            }
        }
        #expect(NotesAnnotationGeometry.dockFrame(viewport: .zero, screen: CGRect(x: 0, y: 0, width: 800, height: 600), expanded: false) == .zero)
    }
    @Test func offscreenOrZeroBoundsNeverProduceClickableMarkers() {
        let viewport = CGRect(x: 100, y: 100, width: 600, height: 400)
        #expect(NotesAnnotationGeometry.visibleMark(bounds: CGRect(x: 110, y: 650, width: 50, height: 20), viewport: viewport) == nil)
        #expect(NotesAnnotationGeometry.visibleMark(bounds: .zero, viewport: viewport) == nil)
        let visible = NotesAnnotationGeometry.visibleMark(bounds: CGRect(x: 120, y: 200, width: 70, height: 20), viewport: viewport)
        #expect(visible.map(viewport.contains) == true)
    }
}
