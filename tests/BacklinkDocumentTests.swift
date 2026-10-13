import Foundation
import AppKit
import Testing
@testable import Quillside

@Suite struct BacklinkDocumentTests {
    @Test func quillsideRenamePreservesPreviousBrandRegionAndRejectsUnknownMarkers() throws {
        let identifier = "11111111-1111-1111-1111-111111111111"
        let data = Data("{\"entries\":[{\"identifier\":\"\(identifier)\",\"title\":\"已有来源🙂\"}],\"headingText\":\"引用此笔记 · AppleNotesPro\"}".utf8)
        let previous = try JSONDecoder().decode(BacklinkDocumentRegion.self, from: data)
        let body = "保持作者正文🙂\n\n" + previous.text
        let html = "<div>引用此笔记 · AppleNotesPro</div><div><a href=\"applenotes:note/\(identifier)\">已有来源🙂</a></div><div>引用列表结束</div>"
        let plan = try BacklinkDocumentPlan.make(body: body, html: html, known: [previous], entries: [], complete: false)
        let updated = (body as NSString).replacingCharacters(in: plan.range, with: plan.region.text)
        #expect(updated == "保持作者正文🙂\n\n引用此笔记 · Quillside\n已有来源🙂\n引用列表结束")
        #expect(previous.headingText == "引用此笔记 · AppleNotesPro")
        #expect(previous.range(in: body) != nil)
        #expect(plan.region.range(in: updated) != nil)
        #expect(previous.range(in: body + "\n引用此笔记 · Quillside") == nil)
        #expect(throws: AIError.self) {
            try BacklinkDocumentPlan.make(body: body, html: html, known: [], entries: [], complete: true)
        }
        #expect(throws: AIError.self) {
            try BacklinkDocumentRegion.make([.init(identifier: identifier, title: "引用此笔记 · AppleNotesPro")])
        }
    }
    @Test func renamePreservesLegacyOwnershipAndReplacesOnlyGeneratedRegion() throws {
        let identifier = "11111111-1111-1111-1111-111111111111"
        let data = Data("{\"entries\":[{\"identifier\":\"\(identifier)\",\"title\":\"旧来源🙂\"}]}".utf8)
        let legacy = try JSONDecoder().decode(BacklinkDocumentRegion.self, from: data)
        #expect(legacy.text.hasPrefix("引用此笔记 · OpenNotes\n"))
        let body = "用户原文🙂\n\n" + legacy.text
        let html = "<div>引用此笔记 · OpenNotes</div><div><a href=\"applenotes:note/\(identifier)\">旧来源🙂</a></div><div>引用列表结束</div>"
        let plan = try BacklinkDocumentPlan.make(body: body, html: html, known: [legacy], entries: [], complete: false)
        #expect(!plan.unchanged)
        #expect(plan.region.entries == legacy.entries)
        let updated = (body as NSString).replacingCharacters(in: plan.range, with: plan.region.text)
        #expect(updated == "用户原文🙂\n\n引用此笔记 · Quillside\n旧来源🙂\n引用列表结束")
        #expect(legacy.range(in: body) != nil)
        #expect(plan.region.range(in: updated) != nil)
        #expect(try JSONDecoder().decode(BacklinkDocumentRegion.self, from: JSONEncoder().encode(plan.region)) == plan.region)
    }
    let a = BacklinkDocumentEntry(identifier: "11111111-1111-1111-1111-111111111111", title: "来源🙂A")
    let b = BacklinkDocumentEntry(identifier: "22222222-2222-2222-2222-222222222222", title: "来源 B")
    func html(_ region: BacklinkDocumentRegion) -> String {
        "<div>" + BacklinkDocumentRegion.heading + "</div>" + region.entries.map { "<div><a href=\"\($0.url)\">\($0.title)</a></div>" }.joined() + "<div>" + BacklinkDocumentRegion.ending + "</div>"
    }
    @Test func verifiesSplitAndEntityEncodedNativeHTML() throws {
        let region = try BacklinkDocumentRegion.make([a])
        let source = "<div>其他正文<a href=\"\(b.url)\">普通链接</a></div><div><span>引用此笔记</span>&nbsp;·&nbsp;<span>Quillside</span></div><div><a href=\"\(a.url)\">来源🙂</a><a href=\"\(a.url)\">A</a></div><div><span>引用列表</span>结束</div>"
        #expect(region.linksMatch(html: source))
        #expect(!region.linksMatch(html: source.replacingOccurrences(of: a.url, with: b.url)))
        #expect(!region.linksMatch(html: source.replacingOccurrences(of: a.url, with: "https://example.com")))
    }
    @Test func nativeAttributesVerifyWhenNotesHTMLOmitsLinks() throws {
        let region = try BacklinkDocumentRegion.make([a]), text = NSMutableAttributedString(string: region.text)
        let label = (region.text as NSString).range(of: a.title)
        let opaqueAXLink = NSObject()
        text.addAttribute(NotesNativeLinks.accessibilityKey, value: opaqueAXLink, range: label)
        #expect(NotesNativeLinks.identifiers(in: text, resolve: { _ in a.url }) == [a.identifier])
        #expect(NotesNativeLinks.identifiers(in: text, resolve: { _ in "https://example.com" }) == nil)
        #expect(NotesNativeLinks.identifiers(in: text, resolve: { _ in nil }) == nil)
        let body = "正文🙂\n" + region.text
        let plan = try BacklinkDocumentPlan.make(body: body, html: "<div>正文导出不包含链接</div>", known: [region], entries: [a], complete: true,
            validateLinks: { candidate, range in candidate == region && range == region.range(in: body) })
        #expect(plan.unchanged)
        #expect(throws: AIError.self) {
            try BacklinkDocumentPlan.make(body: body, html: html(region), known: [region], entries: [a], complete: true, validateLinks: { _, _ in false })
        }
    }
    @Test func repeatedUpdateIsIdempotentAndPartialReadRetainsOldSources() throws {
        let region = try BacklinkDocumentRegion.make([a, a])
        let body = "用户正文🙂\n\n" + region.text + "\n"
        let repeated = try BacklinkDocumentPlan.make(body: body, html: html(region), known: [region], entries: [a], complete: true)
        #expect(repeated.unchanged)
        let partial = try BacklinkDocumentPlan.make(body: body, html: html(region), known: [region], entries: [b], complete: false)
        #expect(Set(partial.region.entries.map(\.identifier)) == Set([a.identifier, b.identifier]))
        let complete = try BacklinkDocumentPlan.make(body: body, html: html(region), known: [region], entries: [b], complete: true)
        #expect(complete.region.entries == [b])
        #expect((body as NSString).replacingCharacters(in: complete.range, with: complete.region.text).hasPrefix("用户正文🙂\n\n"))
    }
    @Test func rejectsEditedMovedUnknownRegionsAndEditedDestinations() throws {
        let region = try BacklinkDocumentRegion.make([a]), body = "正文\n" + (try BacklinkDocumentRegion.make([a])).text
        for changed in [body.replacingOccurrences(of: a.title, with: "用户改了"), body + "\n用户在区域之后继续写", body + "\n" + region.text] {
            #expect(throws: AIError.self) { try BacklinkDocumentPlan.make(body: changed, html: html(region), known: [region], entries: [b], complete: true) }
        }
        #expect(throws: AIError.self) { try BacklinkDocumentPlan.make(body: body, html: html(region), known: [], entries: [b], complete: true) }
        #expect(throws: AIError.self) { try BacklinkDocumentPlan.make(body: body, html: html(region).replacingOccurrences(of: a.url, with: b.url), known: [region], entries: [b], complete: true) }
    }
    @Test func generatedLinksAreExcludedButOrdinaryIncomingLinksRemain() throws {
        let region = try BacklinkDocumentRegion.make([a]), prefix = "原始引用\n"
        var note = AppleNotesDecodedNote(noteText: "", attributeRuns: [])
        note.noteText = prefix + region.text
        var ordinary = AppleNotesDecodedAttributeRun(length: 0, paragraphStyle: nil, fontWeight: nil, underlined: false, strikethrough: false, superscript: nil, link: nil, attachmentInfo: nil); ordinary.length = (prefix as NSString).length; ordinary.link = b.url
        var heading = AppleNotesDecodedAttributeRun(length: 0, paragraphStyle: nil, fontWeight: nil, underlined: false, strikethrough: false, superscript: nil, link: nil, attachmentInfo: nil); heading.length = (BacklinkDocumentRegion.heading + "\n" as NSString).length
        var link = AppleNotesDecodedAttributeRun(length: 0, paragraphStyle: nil, fontWeight: nil, underlined: false, strikethrough: false, superscript: nil, link: nil, attachmentInfo: nil); link.length = (a.title as NSString).length; link.link = a.url
        var end = AppleNotesDecodedAttributeRun(length: 0, paragraphStyle: nil, fontWeight: nil, underlined: false, strikethrough: false, superscript: nil, link: nil, attachmentInfo: nil); end.length = ("\n" + BacklinkDocumentRegion.ending as NSString).length
        note.attributeRuns = [ordinary, heading, link, end]
        let range = try #require(region.range(in: note.noteText))
        #expect(try ActiveNoteLinkExtractor.extract(note, sourceID: 1, attachments: [:], excluding: [range]).identifiers == [b.identifier])
        #expect(try ActiveNoteLinkExtractor.extract(note, sourceID: 1, attachments: [:], only: range).identifiers == [a.identifier])
    }
    @Test func ownershipSurvivesRestartAndOldVersionsSupportUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("regions.json"), first = try BacklinkDocumentRegion.make([a]), second = try BacklinkDocumentRegion.make([b])
        let store = BacklinkRegionStore(url: file)
        try store.prepare(first, noteID: b.identifier); try store.prepare(second, noteID: b.identifier)
        #expect(try BacklinkRegionStore(url: file).snapshot()[b.identifier] == [second, first])
        let corrupt = Data("not JSON".utf8); try corrupt.write(to: file)
        let broken = BacklinkRegionStore(url: file)
        #expect(throws: AIError.self) { try broken.prepare(first, noteID: b.identifier) }
        #expect(try Data(contentsOf: file) == corrupt)
    }
}
