import Foundation
import Testing
@testable import Quillside

@MainActor struct InlineAnnotationTests {
    @Test func capturedQuoteSurvivesFocusChangeAndSavedCommentCanBeEdited() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WritingDraftStore(directory: directory)
        let body = "第一句🙂。\n第二句需要修改。"
        let draft = WritingDraft(noteIdentity: "inline-test", baseline: body, rangeLocation: 0, rangeLength: (body as NSString).length, hasSelection: true, candidate: body)
        let model = WritingSessionModel(generate: { _,_,_,_ in "" }, store: store)
        model.begin(draft, config: AIConfiguration())
        let anchor = try #require(InlineAnnotationAnchor(versionID: draft.versionID, range: (body as NSString).range(of: "第一句🙂"), text: body))
        model.selection = (body as NSString).range(of: "第二句")
        #expect(model.saveInlineComment(id: nil, anchor: anchor, comment: "保留这一句", enabled: true))
        let item = try #require(model.draft?.annotations.first)
        #expect(item.range == anchor.range)
        #expect(item.quote == "第一句🙂")
        #expect(model.saveInlineComment(id: item.id, anchor: anchor, comment: "保留emoji，缩短文字", enabled: false))
        let loaded = try store.load(note: "inline-test")
        let saved = try #require(loaded)
        #expect(saved.annotations.count == 1)
        #expect(saved.annotations[0].comment == "保留emoji，缩短文字")
        #expect(!saved.annotations[0].enabled)
    }
    @Test func oldBubbleCannotAnnotateNewVersionOrResurrectDeletedComment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = "相同句子。"
        var draft = WritingDraft(noteIdentity: "stale-test", baseline: body, rangeLocation: 0, rangeLength: (body as NSString).length, hasSelection: true, candidate: body)
        try draft.annotate(range: NSRange(location: 0, length: 4), comment: "原意见")
        let item = try #require(draft.annotations.first), anchor = InlineAnnotationAnchor(annotation: item)
        let model = WritingSessionModel(generate: { _,_,_,_ in "" }, store: try WritingDraftStore(directory: directory))
        model.begin(draft, config: AIConfiguration()); model.removeComment(item.id)
        #expect(!model.saveInlineComment(id: item.id, anchor: anchor, comment: "迟到编辑", enabled: true))
        #expect(model.draft?.annotations.isEmpty == true)
        model.draft?.versionID = UUID()
        #expect(!model.saveInlineComment(id: nil, anchor: anchor, comment: "旧位置", enabled: true))
        #expect(model.draft?.annotations.isEmpty == true)
    }
    @Test func invalidUnicodeAndWhitespaceSelectionDoNotOfferComments() {
        let id = UUID()
        #expect(InlineAnnotationAnchor(versionID: id, range: NSRange(location: 1, length: 1), text: "🙂") == nil)
        #expect(InlineAnnotationAnchor(versionID: id, range: NSRange(location: 0, length: 2), text: " \n") == nil)
        #expect(InlineAnnotationAnchor(versionID: id, range: NSRange(location: 0, length: 0), text: "原文") == nil)
        #expect(InlineAnnotationAnchor(versionID: id, range: NSRange(location: NSNotFound, length: 1), text: "原文") == nil)
    }
}
