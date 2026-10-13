import Foundation
import AppKit
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class AppleNotesMarkdownConverterTests {
    private let converter = AppleNotesMarkdownConverter()

    @Test func preservesChineseEmojiAndNativeLinkLabels() throws {
        let markdown = try converter.convert(title: "测试笔记", htmlBody: "<div>测试笔记</div><div>保留正文🙂</div><div><a href=\"applenotes:note/11111111-1111-1111-1111-111111111111\">来源 A</a></div>")
        #expect(markdown.contains("保留正文🙂"))
        #expect(markdown.contains("[来源 A](applenotes:note/11111111-1111-1111-1111-111111111111)"))
    }

    @Test
    func testConvertsHeadingsAndInlineFormatting() throws {
        let markdown = try converter.convert(
            title: "Release Plan",
            htmlBody: """
            <div><h2>Milestone</h2></div>
            <p><b>Bold</b> <i>Italic</i> <u>Underline</u> \
            <s>Removed</s> <a href="https://example.com">Link</a></p>
            """
        )

        #expect(markdown == """
            # Release Plan

            ## Milestone

            **Bold** *Italic* <u>Underline</u> ~~Removed~~ [Link](https://example.com)
            """)
    }

    @Test
    func testConvertsNestedListsAndChecklist() throws {
        let markdown = try converter.convert(
            title: "Tasks",
            htmlBody: """
            <ul>
              <li>Parent
                <ol><li>Child</li></ol>
              </li>
              <li data-checked="true">Done</li>
              <li data-checked="false">Todo</li>
            </ul>
            """
        )

        #expect(markdown == """
            # Tasks

            - Parent
              1. Child
            - [x] Done
            - [ ] Todo
            """)
    }

    @Test
    func testConvertsQuotesCodeAndTable() throws {
        let markdown = try converter.convert(
            title: "Reference",
            htmlBody: """
            <blockquote><p>Keep it local.</p></blockquote>
            <p>Run <code>swift test</code>.</p>
            <pre><code>let value = 42
            print(value)</code></pre>
            <table>
              <tr><th>Name</th><th>Status</th></tr>
              <tr><td>Quillside</td><td>Ready</td></tr>
            </table>
            """
        )

        #expect(markdown == """
            # Reference

            > Keep it local.

            Run `swift test`.

            ```
            let value = 42
            print(value)
            ```

            | Name | Status |
            | --- | --- |
            | Quillside | Ready |
            """)
    }

    @Test
    func testUsesExplicitPlaceholdersForImagesAndAttachments() throws {
        let markdown = try converter.convert(
            title: "Assets",
            htmlBody: """
            <p>Preview <img src="cid:image-1" alt="Diagram"/></p>
            <p><object data="report.pdf" title="report.pdf"></object></p>
            """
        )

        #expect(markdown == """
            # Assets

            Preview [图片: Diagram]

            [附件: report.pdf]
            """)
    }

    @Test
    func testDoesNotDuplicateTitleAlreadyPresentInBody() throws {
        #expect(try converter.convert(
                title: "Same Title",
                htmlBody: "<h1>Same Title</h1><p>Body</p>"
            ) == """
            # Same Title

            Body
            """)
    }

    @Test
    func testDoesNotDuplicateEscapedTitleAlreadyPresentInBody() throws {
        #expect(try converter.convert(
                title: "Roadmap [0.3]",
                htmlBody: "<h1>Roadmap [0.3]</h1><p>Body</p>"
            ) == """
            # Roadmap \\[0.3\\]

            Body
            """)
    }

    @Test
    func testDoesNotDuplicateFormattedTitleAlreadyPresentInBody() throws {
        #expect(try converter.convert(
                title: "Formatted Title",
                htmlBody:
                    "<div><h1><b>Formatted Title</b></h1><p>Body</p></div>"
            ) == """
            # **Formatted Title**

            Body
            """)
    }

    @Test
    func testExpandsCodeFencesAroundEmbeddedBackticks() throws {
        #expect(try converter.convert(
                title: "Code",
                htmlBody: """
                <p>Use <code>a``b</code>.</p>
                <pre><code>let fence = ```</code></pre>
                """
            ) == """
            # Code

            Use ```a``b```.

            ````
            let fence = ```
            ````
            """)
    }

    @Test
    func testEscapesRawHTMLAndRejectsUnsafeLinkSchemes() throws {
        #expect(try converter.convert(
                title: "Security & Export",
                htmlBody: """
                <p>&lt;img src=x onerror=alert(1)&gt; &amp; safe
                <a href="javascript:alert(1)">Unsafe</a>
                <a href="https://example.com/a b(c)">Safe</a></p>
                """
            ) == """
            # Security &amp; Export

            &lt;img src=x onerror=alert(1)&gt; &amp; safe Unsafe [Safe](https://example.com/a%20b%28c%29)
            """)
    }
}
