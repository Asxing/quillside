import Foundation
import AppKit
import Testing
@testable import Quillside

@MainActor struct ParagraphRepairTests {
    @Test func previousRealReportWritesWithoutManualRetry() throws {
        let file = try #require(Bundle.module.url(forResource: "report-extra-blank-lines", withExtension: "json", subdirectory: "Fixtures"))
        let input = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: String]
        let source = NSAttributedString(string: input["source"]!, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let written = try RevisionRichText.replacing(source, with: input["candidate"]!)
        #expect(written.string == input["candidate"]!.replacingOccurrences(of: "\n\n", with: "\n"))
        #expect(written.string.components(separatedBy: "\n").count == 4)
    }
    @Test func preservesOriginalEmptyParagraphsAndEveryContentCharacter() throws {
        let source = "第一段\n\n第二段\n"
        let candidate = " 甲🙂  \r\n \t\r\n乙30分钟\r\n\r\n"
        let result = RevisionParagraphs.align(candidate, to: source)
        #expect(result.text == " 甲🙂  \n\n乙30分钟\n")
        #expect(result.adjusted)
        let rich = NSMutableAttributedString(string: "链接\n\n原句", attributes: [.font:NSFont.systemFont(ofSize:14)])
        rich.addAttribute(.link, value:"https://example.com", range:NSRange(location:0,length:2))
        let replacement = try RevisionRichText.replacing(rich, with:"链接\n\n\n改句")
        #expect(replacement.string == "链接\n\n改句")
        #expect(replacement.attribute(.link, at:0, effectiveRange:nil) != nil)
    }
    @Test func neverMergesContentOrReformatsCodeAndObjects() {
        for (source,candidate) in [("甲\n乙","甲乙"),("甲\n乙","甲\n多加内容\n乙"),
                                    ("```\na\n```","```\n\na\n```"),("    code\nline","    code\n\nline"),
                                    ("\u{FFFC}\n甲","\u{FFFC}\n\n乙")] {
            #expect(RevisionParagraphs.align(candidate,to:source).text == candidate)
            #expect(!RevisionParagraphs.align(candidate,to:source).adjusted)
            #expect(throws: AIError.self) { try RevisionRichText.replacing(NSAttributedString(string:source),with:candidate) }
        }
    }
    @Test func agentAuditsNormalizedPreviewAndNeedsNoExtraModelRequest() async throws {
        var stages:[String]=[]
        let agent=WritingAgent(generate:{_,_,user,_ in
            let request=try JSONSerialization.jsonObject(with:Data(user.utf8)) as! [String:Any]
            let stage=request["stage"] as! String;stages.append(stage)
            let task=request["task"] as! [String:Any]
            #expect((task["formatRequirements"] as? String)?.contains("2个原生段落") == true)
            if stage == "plan" {return "{\"plan\":\"改写\",\"resourceRequests\":[]}"}
            if stage == "audit" {
                let proposal=task["proposal"] as! [String:Any]
                #expect(proposal["document"] as? String == "改甲\n改乙")
                return "{\"passed\":true,\"issues\":[],\"assessments\":[]}"
            }
            return "{\"document\":\"改甲\\n\\n改乙\",\"issues\":[],\"assessments\":[]}"
        })
        let draft=WritingDraft(noteIdentity:"test",baseline:"甲\n乙",rangeLocation:0,rangeLength:3,hasSelection:true,candidate:"甲\n乙")
        let proposal=try await agent.run(draft:draft,connection:.init(model:"fixture"),system:"",instruction:"改写") {_ in}
        #expect(proposal.document == "改甲\n改乙");#expect(proposal.formattingNote != nil)
        #expect(stages == ["plan","revise","audit"])
    }
}
