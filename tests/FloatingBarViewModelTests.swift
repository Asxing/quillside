import Foundation
import AppKit
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class FloatingBarViewModelTests {
    @Test func testAddedToolbarItemsReachTheirIntendedNativeOperations() {
        let service = FormattingServiceSpy()
        let model = FloatingBarViewModel(formattingService: service)
        model.perform(.link)
        model.perform(.checklist)
        model.perform(.table)
        model.setHeading(.heading)
        model.changeFontSize(larger: true)
        model.changeFontSize(larger: false)
        model.showFonts()
        model.align(.justified)
        #expect(service.actions == ["link", "list-Checklist", "table", "heading-Heading", "font-larger", "font-smaller", "fonts", "align-justified"])
    }
    @Test func testAIUsesAssistantCallbackWithoutFormattingText() {
        let service = FormattingServiceSpy()
        let model = FloatingBarViewModel(formattingService: service)
        var opened = 0
        model.onAskAI = { opened += 1 }
        model.perform(.askAI)
        #expect(opened == 1)
        #expect(service.actions.isEmpty)
    }
    @Test func testRejectedOperationShowsFeedbackWithoutReportingAppliedFormat() {
        let service = FormattingServiceSpy()
        service.lastFailure = "菜单操作不可用"
        let model = FloatingBarViewModel(formattingService: service)
        var applied = 0; model.onFormatApplied = { applied += 1 }
        model.perform(.link)
        #expect(model.feedback == "菜单操作不可用")
        #expect(applied == 0)
    }
    @Test
    func testSelectedStateComesFromSelectionSnapshotNotClickHistory() {
        let formatting = FormattingServiceSpy()
        let viewModel = FloatingBarViewModel(
            formattingService: formatting
        )

        viewModel.updateSelectionState([.bold, .highlight])
        viewModel.toggleBold()
        viewModel.insertHighlight()

        #expect(viewModel.selectedActions == [.bold, .highlight])
        #expect(formatting.actions == ["bold", "highlight"])

        viewModel.resetSelectionState()
        #expect(viewModel.selectedActions.isEmpty)
    }

    @Test
    func testFormatActionRequestsASelectionRefresh() {
        let formatting = FormattingServiceSpy()
        let viewModel = FloatingBarViewModel(
            formattingService: formatting
        )
        var refreshCount = 0
        viewModel.onFormatApplied = { refreshCount += 1 }

        viewModel.insertList(.bullet)
        #expect(viewModel.selectedActions.isEmpty)
        #expect(refreshCount == 1)
    }
}

private final class FormattingServiceSpy: FormattingServicing {
    private(set) var actions: [String] = []
    var lastFailure: String? = nil

    func insertLink() { actions.append("link") }
    func align(_ alignment: NoteAlignment) { actions.append("align-" + alignment.rawValue) }
    func changeFontSize(larger: Bool) { actions.append(larger ? "font-larger" : "font-smaller") }
    func showFonts() { actions.append("fonts") }
    func insertTable() { actions.append("table") }
    func toggleBold() { actions.append("bold") }
    func toggleItalic() { actions.append("italic") }
    func toggleUnderline() { actions.append("underline") }
    func toggleStrikethrough() { actions.append("strikethrough") }
    func setHeading(_ level: HeadingLevel) {
        actions.append("heading-\(level.rawValue)")
    }
    func insertList(_ type: ListType) {
        actions.append("list-\(type.rawValue)")
    }
    func insertBlockQuote() { actions.append("quote") }
    func insertMonospaced() { actions.append("monospaced") }
    func insertHighlight() { actions.append("highlight") }
    func insertCodeBlock() { actions.append("code") }
}
