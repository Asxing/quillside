import Foundation
import Testing
@testable import Quillside

@Suite struct FeatureParityRegressionTests {
    @Test func officialAliasesResolveToTheirExactAction() throws {
        let expected: [(String, FormattingService.FormatAction)] = [
            ("title", .title), ("h1", .title), ("heading", .heading), ("h2", .heading),
            ("subheading", .subheading), ("h3", .subheading), ("body", .body),
            ("monostyled", .codeBlock), ("code", .codeBlock), ("checklist", .todoList),
            ("bulletedlist", .bulletList), ("dashedlist", .dashList), ("numberedlist", .numberedList),
            ("quote", .quote), ("blockquote", .quote), ("table", .table), ("strikethrough", .strikethrough), ("link", .link)
        ]
        for (alias, action) in expected {
            #expect(SlashCommandCatalog.exact(alias)?.action == action)
            #expect(SlashCommandCatalog.suggestions(alias).first?.action == action)
        }
        #expect(SlashCommandCatalog.exact("Heading")?.action == .heading)
        #expect(SlashCommandCatalog.exact("head") == nil)
        #expect(!SlashCommandCatalog.suggestions("head").isEmpty)
    }

    @Test func commandContextUsesCommittedBodyAndUTF16Caret() {
        #expect(SlashInputContext.token(body: "中文🙂 /heading", caret: 13) == "/heading")
        #expect(SlashInputContext.token(body: "https://heading", caret: 15) == nil)
        #expect(SlashInputContext.token(body: "path/heading", caret: 12) == nil)
        #expect(SlashInputContext.token(body: "/heading ", caret: 9) == nil)
        #expect(SlashInputContext.token(body: "/拼音", caret: 3) == nil)
        #expect(SlashInputContext.token(body: "/", caret: -1) == nil)
        #expect(SlashInputContext.token(body: "/", caret: 1) == "/")
    }

    @Test func featureDisablePersistsAndMissingPreferenceDefaultsOn() throws {
        let suite = "Quillside-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(EditorFeaturePreferences.enabled("slash", defaults: defaults))
        defaults.set(false, forKey: "com.opennotes.slash.enabled")
        #expect(!EditorFeaturePreferences.enabled("slash", defaults: defaults))
        #expect(EditorFeaturePreferences.enabled("toolbar", defaults: defaults))
    }
}
