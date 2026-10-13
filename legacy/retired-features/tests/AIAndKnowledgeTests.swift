import Foundation
import Testing
@testable import OpenNotes

@Suite struct AIAndKnowledgeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENNOTES_TEST_MODEL_BASEURL"] != nil))
    func realHTTPStreamingAcrossFourProtocols() async throws {
        let baseURL = try #require(ProcessInfo.processInfo.environment["OPENNOTES_TEST_MODEL_BASEURL"])
        for api in ModelProtocol.allCases {
            let connection = ModelConnection(name: "fixture", api: api, baseURL: baseURL, model: "fixture-model", maxOutputTokens: 512)
            let result = try await ModelClient().generate(connection: connection, key: "synthetic-key", system: "test system", user: "synthetic input") { _ in }
            #expect(result == "合成结果🙂")
        }
    }
    @Test func requestRoutesSeparateProtocolsAndNeverStoreCredentialsInBody() throws {
        for api in ModelProtocol.allCases {
            let connection = ModelConnection(name: "fixture", api: api, baseURL: api.defaultURL, model: "fixture-model", maxOutputTokens: 512)
            let request = try ModelRequestBuilder.request(connection: connection, key: "synthetic-test-key", system: "SYS", user: "SOURCE")
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["model"] as? String == "fixture-model")
            #expect(!String(decoding: request.httpBody!, as: UTF8.self).contains("synthetic-test-key"))
            switch api {
            case .responses:
                #expect(request.url?.path == "/v1/responses")
                #expect(body["store"] as? Bool == false)
                #expect(body["messages"] == nil)
            case .anthropic:
                #expect(request.value(forHTTPHeaderField: "x-api-key") == "synthetic-test-key")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(body["system"] as? String == "SYS")
            case .chatCompletions:
                #expect(request.url?.path == "/v1/chat/completions")
            case .ollama:
                #expect(request.url?.path == "/api/chat")
            }
        }
    }
    @Test func rejectsRemoteCleartextCredentialsAndInvalidModels() {
        var connection = ModelConnection(model: "fixture")
        connection.baseURL = "http://example.com/v1"
        #expect(throws: AIError.self) { try connection.endpoint() }
        connection.baseURL = "https://user:secret@example.com/v1"
        #expect(throws: AIError.self) { try connection.endpoint() }
        connection.baseURL = "http://127.0.0.1:11434"; connection.model = ""
        #expect(throws: AIError.self) { try connection.endpoint() }
    }
    @Test func credentialsAreBoundToSchemeHostAndPort() {
        let original = ModelConnection(baseURL: "https://example.com/v1")
        #expect(ModelConnection(baseURL: "https://EXAMPLE.com:443/v2").hasSameCredentialOrigin(as: original))
        #expect(!ModelConnection(baseURL: "https://example.com:8443/v1").hasSameCredentialOrigin(as: original))
        #expect(!ModelConnection(baseURL: "https://other.example/v1").hasSameCredentialOrigin(as: original))
        #expect(!ModelConnection(baseURL: "http://example.com/v1").hasSameCredentialOrigin(as: original))
    }
    @Test func streamRequiresCompletionAndRejectsTruncation() throws {
        var parser = ModelStreamDecoder(api: .chatCompletions)
        #expect(try parser.consume(#"data: {"choices":[{"delta":{"content":"你好"}}]}"#) == "你好")
        #expect(!parser.completed)
        #expect(throws: AIError.self) { try parser.consume(#"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#) }
        #expect(!parser.completed)
        _ = try parser.consume(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
        #expect(parser.completed)
    }
    @Test func supportsResponsesClaudeAndNDJSONCompletion() throws {
        var responses = ModelStreamDecoder(api: .responses)
        #expect(try responses.consume(#"data: {"type":"response.output_text.delta","delta":"OK"}"#) == "OK")
        _ = try responses.consume(#"data: {"type":"response.completed","response":{"status":"completed"}}"#)
        #expect(responses.completed)
        var claude = ModelStreamDecoder(api: .anthropic)
        _ = try claude.consume(#"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#)
        #expect(throws: AIError.self) { try claude.consume(#"data: {"type":"message_stop"}"#) }
        var ollama = ModelStreamDecoder(api: .ollama)
        #expect(try ollama.consume(#"{"message":{"content":"OK"},"done":false}"#) == "OK")
        #expect(!ollama.completed)
        _ = try ollama.consume(#"{"message":{"content":""},"done":true,"done_reason":"stop"}"#)
        #expect(ollama.completed)
    }
    @Test func templatesDoNotRecursivelyInterpretUserText() {
        let rendered = PromptRenderer.render("{text}|{instruction}", values: ["text": "用户原文 {instruction} 🧑‍💻", "instruction": "纠错"])
        #expect(rendered == "用户原文 {instruction} 🧑‍💻|纠错")
    }
    @Test func markdownAndSlashDeletionRequireVisibleExactTrigger() {
        #expect(InlineInputEdit.range(body: "正文## ", caret: 5, trigger: "## ", lineStartOnly: true, trailingNewline: false) == nil)
        #expect(InlineInputEdit.range(body: "🙂\n## ", caret: 6, trigger: "## ", lineStartOnly: true, trailingNewline: false) == NSRange(location: 3, length: 3))
        #expect(InlineInputEdit.range(body: "/h1\n", caret: 4, trigger: "/h1", lineStartOnly: false, trailingNewline: true) == NSRange(location: 0,length: 4))
        #expect(InlineInputEdit.range(body: "https://h1", caret: 10, trigger: "/h1", lineStartOnly: false, trailingNewline: false) == nil)
        #expect(InlineInputEdit.range(body: "/h2", caret: 3, trigger: "/h1", lineStartOnly: false, trailingNewline: false) == nil)
    }
    @Test func staleSelectionAndUTF16BoundariesAreValidated() {
        let text = "头🙂ABC尾"
        #expect(SelectionGuard.allowsWrite(originalBody: text, currentBody: text, range: NSRange(location: 3,length: 3), originalText: "ABC"))
        #expect(!SelectionGuard.allowsWrite(originalBody: text, currentBody: text + "!", range: NSRange(location: 3,length: 3), originalText: "ABC"))
        #expect(!SelectionGuard.allowsWrite(originalBody: text, currentBody: text, range: NSRange(location: 30,length: 3), originalText: "ABC"))
        #expect(!SelectionGuard.allowsWrite(originalBody: text, currentBody: text, range: NSRange(location: 2,length: 3), originalText: "ABC"))
    }
    @Test func chineseKnowledgeScopeReplacementAndDeletion() async throws {
        let index = try KnowledgeIndex(path: ":memory:")
        try await index.upsert(.init(id: "1",title: "项目",locator: "file:///synthetic-a.md",collection: "工作",text: "合同明天到期，预算是五万元。",indexedAt: 1, collectionID: "test:work"))
        try await index.upsert(.init(id: "2",title: "旅行",locator: "file:///synthetic-b.md",collection: "生活",text: "旅行合同已签署。",indexedAt: 1, collectionID: "test:life"))
        #expect(try await index.search("合同", collectionID: "test:work").map(\.documentID) == ["1"])
        #expect(try await index.search("合同", collectionID: nil).count == 2)
        #expect(try await index.search("\" OR *;DROP TABLE documents", collectionID: nil).isEmpty)
        try await index.upsert(.init(id: "1",title: "项目",locator: "file:///synthetic-a.md",collection: "工作",text: "已经完成交付。",indexedAt: 2, collectionID: "test:work"))
        #expect(try await index.search("合同", collectionID: "test:work").isEmpty)
        try await index.remove("2")
        #expect(try await index.search("合同", collectionID: nil).isEmpty)
        #expect(try await index.documents().count == 1)
    }
    @MainActor @Test func rejectsInventedAndMissingSourceReferences() throws {
        try WorkspaceModel.validateCitations("结论 [S1]", sourceCount: 1)
        #expect(throws: AIError.self) { try WorkspaceModel.validateCitations("结论 [S2]", sourceCount: 1) }
        #expect(throws: AIError.self) { try WorkspaceModel.validateCitations("结论", sourceCount: 1) }
        #expect(throws: AIError.self) { try WorkspaceModel.validateCitations("结论 [S1]", sourceCount: 0) }
    }
    @Test func configurationRoundtripAndInvalidReferences() throws {
        var config = AIConfiguration()
        let data = try JSONEncoder().encode(config)
        let loaded = try JSONDecoder().decode(AIConfiguration.self, from: data)
        #expect(loaded.prompts.count == 12)
        #expect(loaded.templates.count == 2)
        config.selectedConnectionID = UUID()
        #expect(throws: AIError.self) { try config.validate() }
    }
}
