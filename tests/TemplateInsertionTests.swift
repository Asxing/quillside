import Foundation
import Testing
@testable import Quillside

@MainActor @Suite(.serialized) struct TemplateInsertionTests {
    @Test func oldTemplateJSONAndNewAliasCatalogRemainCompatible() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"name\":\"会议\",\"content\":\"正文\"}".utf8)
        let old = try JSONDecoder().decode(SnippetTemplate.self, from: data)
        #expect(old.shortcut == nil)
        let template = SnippetTemplate(name: "会议记录", content: "合成会议模板", shortcut: "meeting")
        let catalog = SlashCommandCatalog.commands(templates: [old, template])
        let match = try #require(SlashCommandCatalog.exact("MEETING", in: catalog))
        if case let .template(selected) = match.kind { #expect(selected.id == template.id) } else { Issue.record("Expected a template action") }
        #expect(TemplateCatalog.matching([old, template], query: "记录").map(\.id) == [template.id])
        #expect(TemplateCatalog.matching([old, template], query: "meeting").map(\.id) == [template.id])
        #expect(match.displayToken == "/meeting")
    }
    @Test func privateTemplateIDsAreNotImplicitCommandAliases() throws {
        let first = SnippetTemplate(name: "第一份", content: "first")
        let internalID = SlashCommand(template: first).id
        let second = SnippetTemplate(name: "第二份", content: "second", shortcut: internalID)
        let catalog = SlashCommandCatalog.commands(templates: [first, second])
        if case let .template(selected) = try #require(SlashCommandCatalog.exact(internalID, in: catalog)).kind {
            #expect(selected.id == second.id)
        } else { Issue.record("Expected explicit alias to win") }
    }
    @Test func duplicateAndBuiltinAliasesAreRejectedBeforePersistence() throws {
        for alias in SlashCommandCatalog.builtins.flatMap(\.tokens) {
            #expect(TemplateShortcutRules.reserved.contains(alias))
            #expect(throws: AIError.self) { try TemplateShortcutRules.validate([.init(name: "模板", content: "x", shortcut: alias)]) }
        }
        #expect(throws: AIError.self) { try TemplateShortcutRules.validate([.init(name: "A", content: "a", shortcut: "MEET"), .init(name: "B", content: "b", shortcut: "meet")]) }
        #expect(throws: AIError.self) { try TemplateShortcutRules.validate([.init(name: "A", content: "a", shortcut: "/meet")]) }
    }
    @Test func dateIsRenderedWithoutInterpretingOtherTemplateData() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-08T03:00:00Z"))
        let template = SnippetTemplate(name: "日期", content: "{date}\n{text}🙂")
        #expect(TemplateCatalog.render(template, date: date, timeZone: TimeZone(secondsFromGMT: 0)!) == "2026-10-08\n{text}🙂")
    }
    @Test func inputMethodOwnsCandidateNavigationAndConfirmation() {
        for selector in ["moveUp:", "moveDown:", "insertNewline:", "cancelOperation:"] {
            #expect(PickerKeyPolicy.action(selector: selector, hasMarkedText: true) == nil)
        }
        #expect(PickerKeyPolicy.action(selector: "moveDown:", hasMarkedText: false) == .move(1))
        #expect(PickerKeyPolicy.action(selector: "insertNewline:", hasMarkedText: false) == .submit)
    }
    @Test func failedOrRepeatedSubmissionDoesNotWriteTwice() async throws {
        let model = TemplatePickerModel()
        let template = SnippetTemplate(name: "模板", content: "正文")
        var calls = 0
        model.begin(templates: [template], apply: { _ in calls += 1; throw AIError.message("synthetic conflict") })
        model.submit(); model.submit()
        #expect(!model.cancel())
        for _ in 0..<100 where model.applying { try await Task.sleep(nanoseconds: 1_000_000) }
        #expect(calls == 1)
        #expect(model.status == "synthetic conflict")
        #expect(model.textToCopy == "正文")
        model.submit()
        #expect(calls == 1)
        #expect(!model.canInsert)
        #expect(model.cancel())
    }
    @Test func movedCaretRejectsWriteEvenWhenBodyIsUnchanged() {
        let body = "🙂 /meeting"
        let target = InlineInputEdit.range(body: body, caret: (body as NSString).length, trigger: "/meeting", lineStartOnly: false, trailingNewline: false)!
        let captured = NSRange(location: (body as NSString).length, length: 0)
        #expect(SelectionGuard.allowsWrite(originalBody: body, currentBody: body, range: target, originalText: "/meeting", expectedSelection: captured, currentSelection: captured))
        #expect(!SelectionGuard.allowsWrite(originalBody: body, currentBody: body, range: target, originalText: "/meeting", expectedSelection: captured, currentSelection: NSRange(location: 0, length: 0)))
    }
}
