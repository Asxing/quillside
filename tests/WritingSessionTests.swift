import AppKit
import Foundation
import Testing
@testable import Quillside

@MainActor @Suite struct WritingSessionTests {
    func draft(_ text: String = "原文🙂\n事实是30分钟缩短到10分钟。") -> WritingDraft {
        .init(noteIdentity: "test-note", baseline: text, rangeLocation: 0, rangeLength: (text as NSString).length, hasSelection: true, candidate: text)
    }
    @Test func tenAnnotationsSurviveRestartAndStayOnTheirOwnVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WritingDraftStore(directory: directory)
        let text = (0..<10).map { "第\($0)句🙂。" }.joined(separator: "\n")
        var d = draft(text)
        for i in 0..<10 { try d.annotate(range: (text as NSString).range(of: "第\(i)句🙂。"), comment: "保留第\(i)条事实") }
        try store.save(d)
        let recovered = try store.load(note: "test-note")
        var loaded = try #require(recovered)
        #expect(loaded.currentAnnotations.count == 10)
        let originalVersion = loaded.versionID
        let assessments = loaded.pendingAnnotations.map { WritingAssessment(annotationID: $0.id, status: "addressed", explanation: "已保留") }
        loaded.accept(.init(document: text + "\n结论。", assessments: assessments, issues: []), instruction: "统一优化")
        #expect(loaded.currentAnnotations.isEmpty)
        #expect(loaded.requirements.count == 10)
        #expect(loaded.versions.last?.assessments.count == 10)
        loaded.restore(try #require(loaded.versions.first(where: { $0.id == originalVersion })))
        #expect(loaded.currentAnnotations.count == 10)
    }
    @Test func invalidEmojiRangeAndMissingAssessmentAreRejected() throws {
        var d = draft("A🙂B")
        #expect(throws: AIError.self) { try d.annotate(range: .init(location: 2, length: 1), comment: "invalid") }
        try d.annotate(range: .init(location: 1, length: 2), comment: "保留emoji")
        #expect(throws: AIError.self) { try WritingProposal(document: "AB", assessments: [], issues: []).validate(annotations: d.pendingAnnotations) }
        d.changeCandidate("changed")
        #expect(d.currentAnnotations.isEmpty)
        #expect(d.annotations.count == 1)
    }
    @Test func nativeRichTextPreservesUnchangedParagraphAndRefusesObjectsOrStructuralLoss() throws {
        let original = NSMutableAttributedString(string: "原文\n修改句。", attributes: [.font: NSFont.systemFont(ofSize: 13)])
        original.addAttribute(.link, value: "https://example.com", range: NSRange(location: 0, length: 2))
        let changed = try RevisionRichText.replacing(original, with: "原文\n修改后的句子。")
        #expect(changed.string == "原文\n修改后的句子。")
        #expect(changed.attribute(.link, at: 0, effectiveRange: nil) != nil)
        #expect(changed.attribute(.link, at: 3, effectiveRange: nil) == nil)
        #expect(throws: AIError.self) { try RevisionRichText.replacing(original, with: "整段合并") }
        #expect(throws: AIError.self) { try RevisionRichText.replacing(NSAttributedString(string: "\u{FFFC}"), with: "x") }
    }
    @Test func boundedAgentReadsApprovedSkillResourceAndAuditsAllTenComments() async throws {
        var d = draft((0..<10).map { "事实\($0)。" }.joined(separator: "\n"))
        for i in 0..<10 { try d.annotate(range: (d.candidate as NSString).range(of: "事实\(i)。"), comment: "意见\(i)") }
        d.skills = [.init(name: "example", description: "desc", instructions: "保留事实", resources: ["references/style.md":"不编造数字"], fingerprint: "fixed", origin: "test", tools: [], compatibility: "")]
        var stages: [String] = [], loaded = false
        let expectedIDs = Set(d.pendingAnnotations.map(\.id))
        let agent = WritingAgent(generate: { _, _, user, _ in
            let decoded = try JSONSerialization.jsonObject(with: Data(user.utf8))
            let request = try #require(decoded as? [String: Any])
            let stage = try #require(request["stage"] as? String); stages.append(stage)
            let task = try #require(request["task"] as? [String: Any])
            if stage == "plan" { return "{\"plan\":\"统一保留事实\",\"resourceRequests\":[{\"skill\":\"example\",\"path\":\"references/style.md\"}]}" }
            loaded = (task["loadedResources"] as? [String:String])?["example/references/style.md"] == "不编造数字"
            let annotations = try #require(task["annotations"] as? [[String:Any]])
            let assessments = annotations.map { ["annotationID":$0["id"]!,"status":"addressed","explanation":"保留原意"] }
            #expect(Set(annotations.compactMap { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) }) == expectedIDs)
            let output: [String: Any] = stage == "audit" ? ["passed":true,"issues":[],"assessments":assessments] : ["document":"统一后的稿件","assessments":assessments,"issues":[]]
            return String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self)
        })
        let result = try await agent.run(draft: d, connection: .init(model:"fixture"), system:"system", instruction:"统一修改") { _ in }
        #expect(stages == ["plan","revise","audit"])
        #expect(loaded)
        #expect(result.assessments.count == 10)
    }
    @Test func unknownResourceAndMalformedModelReplyNeverBecomeCandidate() async throws {
        let agent = WritingAgent(generate: { _,_,_,_ in "{\"plan\":\"x\",\"resourceRequests\":[{\"skill\":\"bad\",\"path\":\"../../secret\"}]}" })
        await #expect(throws: AIError.self) { try await agent.run(draft: draft(), connection:.init(model:"fixture"), system:"", instruction:"edit") { _ in } }
    }
    @Test func corruptDraftIsPreserved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try WritingDraftStore(directory: dir)
        let path = dir.appendingPathComponent(TextFingerprint.hash("test-note") + ".json")
        let content = Data("broken".utf8);try content.write(to:path)
        #expect(throws: (any Error).self) { try store.load(note:"test-note") }
        #expect(try Data(contentsOf:path)==content)
    }
    @Test func stoppedGenerationCannotReplaceDraftWhenLateResultArrives() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var completion: CheckedContinuation<String, Error>?
        let model = WritingSessionModel(generate: { _,_,_,_ in try await withCheckedThrowingContinuation { completion = $0 } }, store: try WritingDraftStore(directory: dir))
        var config = AIConfiguration(); let connection = ModelConnection(model:"fixture")
        config.connections = [connection];config.selectedConnectionID = connection.id
        var original=draft();original.instruction="优化";model.begin(original,config:config);model.run()
        for _ in 0..<200 where completion == nil { try await Task.sleep(nanoseconds:1_000_000) }
        try #require(completion != nil)
        model.stop();completion?.resume(returning:"{\"plan\":\"late\",\"resourceRequests\":[]}")
        try await Task.sleep(nanoseconds:5_000_000)
        #expect(model.draft?.candidate == original.candidate)
        #expect(model.draft?.versions.isEmpty == true)
        #expect(!model.busy)
    }
    @Test func oldAnnotationRequirementsSurviveHistoryPruning() throws {
        var d=draft();try d.annotate(range:NSRange(location:0,length:2),comment:"始终保留原事实")
        for i in 0..<15 { d.accept(.init(document:"版本\(i)",assessments:[],issues:[]),instruction:"修改") }
        #expect(d.versions.count <= 12)
        #expect(d.requirements.count == 1)
    }
    @Test func nextRoundTransmitsHistoricalCommentsEvenWhenCurrentVersionHasNone() async throws {
        var d=draft();try d.annotate(range:NSRange(location:0,length:2),comment:"保留事实")
        d.accept(.init(document:"上一轮候选",assessments:[],issues:[]),instruction:"前次要求")
        var seen:[Int]=[]
        let agent=WritingAgent(generate:{ _,_,user,_ in
            let decoded=try JSONSerialization.jsonObject(with:Data(user.utf8)) as! [String:Any]
            let task=decoded["task"] as! [String:Any], annotations=task["annotations"] as! [[String:Any]]
            seen.append(annotations.count)
            #expect((task["candidate"] as? String) == "上一轮候选")
            let assessments=annotations.map { ["annotationID":$0["id"]!,"status":"addressed","explanation":"保留事实"] }
            let value:[String:Any]
            switch decoded["stage"] as? String {
            case "plan":value=["plan":"继续按既有意见修改","resourceRequests":[]]
            case "audit":value=["passed":true,"assessments":assessments,"issues":[]]
            default:value=["document":"第二轮候选","assessments":assessments,"issues":[]]
            }
            return String(decoding:try JSONSerialization.data(withJSONObject:value),as:UTF8.self)
        })
        _ = try await agent.run(draft:d,connection:.init(model:"fixture"),system:"",instruction:"再简洁") { _ in }
        #expect(seen == [1,1,1])
    }
}
