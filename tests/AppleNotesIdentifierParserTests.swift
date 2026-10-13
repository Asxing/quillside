import Foundation
import AppKit
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class AppleNotesIdentifierParserTests {
    @Test
    func testParsesCoreDataPrimaryKey() {
        #expect(AppleNotesIdentifierParser.primaryKey(
                from: "x-coredata://01234567-89AB-CDEF-0123-456789ABCDEF/ICNote/p42"
            ) == 42)
    }

    @Test
    func testRejectsMalformedCoreDataIdentifier() {
        #expect(AppleNotesIdentifierParser.primaryKey(from: "") == nil)
        #expect(AppleNotesIdentifierParser.primaryKey(from: "x-coredata://store/ICNote/not-a-pk") == nil)
    }

    @Test
    func testExtractsNativeIdentifiersFromKnownAppleNotesURLs() {
        let identifier = "01234567-89AB-CDEF-0123-456789ABCDEF"
        let text = """
        applenotes:note/\(identifier)
        mobilenotes://showNote?identifier=\(identifier.lowercased())
        """

        #expect(NativeNoteLinkParser.identifiers(in: text) == [identifier])
    }

    @Test
    func testMatchesUniqueSelectedNoteTitle() {
        #expect(SelectedNoteMatcher.identifier(
                textCandidates: ["Project Alpha", "Updated today"],
                notes: [
                    (title: "Project Alpha", identifier: "alpha-id"),
                    (title: "Project Beta", identifier: "beta-id")
                ]
            ) == "alpha-id")
    }

    @Test
    func testRejectsAmbiguousSelectedNoteTitle() {
        #expect(SelectedNoteMatcher.identifier(
                textCandidates: ["Duplicate"],
                notes: [
                    (title: "Duplicate", identifier: "first-id"),
                    (title: "Duplicate", identifier: "second-id")
                ]
            ) == nil)
    }
}
