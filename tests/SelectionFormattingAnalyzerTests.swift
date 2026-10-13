import Foundation
import AppKit
import AppKit
import ApplicationServices
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class SelectionFormattingAnalyzerTests {
    @Test
    func testReadsRealAccessibilityTextAttributes() {
        let attributes: [NSAttributedString.Key: Any] = [
            key(kAXFontTextAttribute): [
                raw(kAXFontNameKey): "Helvetica-BoldItalic",
                raw(kAXFontFamilyKey): "Helvetica",
            ],
            key(kAXUnderlineTextAttribute): NSNumber(value: 1),
            key(kAXStrikethroughTextAttribute): NSNumber(value: true),
            key(kAXBackgroundColorTextAttribute):
                NSColor.yellow.cgColor,
            key(kAXListItemPrefixTextAttribute):
                NSAttributedString(string: "•"),
        ]
        let value = NSAttributedString(
            string: "Selected",
            attributes: attributes
        )

        #expect(SelectionFormattingAnalyzer.actions(in: value) == [
                .bold,
                .italic,
                .underline,
                .strikethrough,
                .highlight,
                .bullet,
            ])
    }

    @Test
    func testMixedSelectionKeepsOnlyCommonFormatting() {
        let value = NSMutableAttributedString(string: "AB")
        value.addAttributes(
            [
                key(kAXFontTextAttribute): [
                    raw(kAXFontNameKey): "Helvetica-Bold",
                ],
            ],
            range: NSRange(location: 0, length: 1)
        )
        value.addAttributes(
            [
                key(kAXFontTextAttribute): [
                    raw(kAXFontNameKey): "Helvetica",
                ],
            ],
            range: NSRange(location: 1, length: 1)
        )

        #expect(SelectionFormattingAnalyzer.actions(in: value).isEmpty)
    }

    private func key(
        _ value: Unmanaged<CFString>
    ) -> NSAttributedString.Key {
        NSAttributedString.Key(rawValue: raw(value))
    }

    private func raw(
        _ value: Unmanaged<CFString>
    ) -> String {
        value.takeUnretainedValue() as String
    }
}
