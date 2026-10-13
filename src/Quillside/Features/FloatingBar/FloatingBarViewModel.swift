import SwiftUI
import Combine

enum FloatingToolbarAction: String, Hashable {
    case bold
    case italic
    case underline
    case strikethrough
    case bullet
    case dash
    case numbered
    case quote
    case monospaced
    case highlight
    case checklist
    case link
}

final class FloatingBarViewModel: ObservableObject {
    
    @Published var shouldDismiss = false
    @Published private(set) var feedback: String?
    @Published private(set) var selectedActions:
        Set<FloatingToolbarAction> = []

    var onFormatApplied: (() -> Void)?
    var onAskAI: (() -> Void)?
    var onAnnotate: (() -> Void)?
    
    private let formattingService: FormattingServicing

    init(
        formattingService: FormattingServicing =
            FormattingService.shared,
        selectedActions: Set<FloatingToolbarAction> = []
    ) {
        self.formattingService = formattingService
        self.selectedActions = selectedActions
    }
    
    func toggleBold() {
        formattingService.toggleBold()
        finishFormat()
    }
    
    func toggleItalic() {
        formattingService.toggleItalic()
        finishFormat()
    }
    
    func toggleUnderline() {
        formattingService.toggleUnderline()
        finishFormat()
    }
    
    func toggleStrikethrough() {
        formattingService.toggleStrikethrough()
        finishFormat()
    }
    
    func setHeading(_ level: HeadingLevel) {
        formattingService.setHeading(level)
        finishFormat()
    }
    
    func insertList(_ type: ListType) {
        formattingService.insertList(type)
        finishFormat()
    }
    
    func insertBlockQuote() {
        formattingService.insertBlockQuote()
        finishFormat()
    }
    
    func insertMonospaced() {
        formattingService.insertMonospaced()
        finishFormat()
    }

    func insertHighlight() {
        formattingService.insertHighlight()
        finishFormat()
    }
    
    func insertCodeBlock() {
        formattingService.insertCodeBlock()
        finishFormat()
    }
    
    func perform(_ item: ToolbarItemID) {
        switch item {
        case .askAI:
            feedback = nil
            if let onAskAI { onAskAI() } else { feedback = "AI 入口暂时不可用。" }
        case .annotate:
            feedback = nil
            if let onAnnotate { onAnnotate() } else { feedback = "批注入口暂时不可用。" }
        case .font, .alignment: break // These controls open native SwiftUI menus.
        case .bold: toggleBold()
        case .italic: toggleItalic()
        case .underline: toggleUnderline()
        case .strikethrough: toggleStrikethrough()
        case .highlight: insertHighlight()
        case .link: formattingService.insertLink(); finishFormat()
        case .checklist: insertList(.checklist)
        case .bullet: insertList(.bullet)
        case .dash: insertList(.dash)
        case .numbered: insertList(.numbered)
        case .quote: insertBlockQuote()
        case .monospaced: insertMonospaced()
        case .table: formattingService.insertTable(); finishFormat()
        }
    }
    func align(_ value: NoteAlignment) { formattingService.align(value); finishFormat() }
    func changeFontSize(larger: Bool) { formattingService.changeFontSize(larger: larger); finishFormat() }
    func showFonts() { formattingService.showFonts(); finishFormat() }
    func clearFeedback() { feedback = nil }
    func showFeedback(_ message: String) { feedback = message }
    private func finishFormat() {
        feedback = formattingService.lastFailure
        if feedback == nil { onFormatApplied?() }
    }

    func dismiss() {
        shouldDismiss = true
    }

    func resetSelectionState() {
        selectedActions.removeAll()
    }

    func updateSelectionState(
        _ actions: Set<FloatingToolbarAction>
    ) {
        selectedActions = actions
    }
}

enum HeadingLevel: String, CaseIterable {
    case title = "Title"
    case heading = "Heading"
    case subheading = "Subheading"
    case body = "Body"
}

enum ListType: String, CaseIterable {
    case bullet = "Bullet"
    case numbered = "Numbered"
    case checklist = "Checklist"
    case dash = "Dash"
}
