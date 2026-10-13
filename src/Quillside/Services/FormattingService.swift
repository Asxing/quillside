import AppKit
import Combine

protocol FormattingServicing: AnyObject {
    var lastFailure: String? { get }
    func toggleBold()
    func toggleItalic()
    func toggleUnderline()
    func toggleStrikethrough()
    func setHeading(_ level: HeadingLevel)
    func insertList(_ type: ListType)
    func insertBlockQuote()
    func insertMonospaced()
    func insertHighlight()
    func insertCodeBlock()
    func insertLink()
    func align(_ alignment: NoteAlignment)
    func changeFontSize(larger: Bool)
    func showFonts()
    func insertTable()
}

enum NoteAlignment: String, CaseIterable, Identifiable {
    case left, center, right, justified
    var id: String { rawValue }
    var title: String {
        switch self { case .left: return "左对齐"; case .center: return "居中"; case .right: return "右对齐"; case .justified: return "两端对齐" }
    }
    var command: NativeNotesCommand {
        switch self { case .left: return .alignLeft; case .center: return .alignCenter; case .right: return .alignRight; case .justified: return .alignJustified }
    }
}

final class FormattingService: ObservableObject, FormattingServicing {
    static let shared = FormattingService()
    typealias FormatAction = NativeNotesCommand
    @Published private(set) var lastFailure: String?
    private let perform: (NativeNotesCommand) -> Result<Void, NotesFormatFailure>

    init(perform: @escaping (NativeNotesCommand) -> Result<Void, NotesFormatFailure> = NotesMenuExecutor().perform) {
        self.perform = perform
    }
    @discardableResult func applyFormat(_ action: FormatAction) -> Bool {
        switch perform(action) {
        case .success: lastFailure = nil; return true
        case let .failure(error): lastFailure = error.localizedDescription; return false
        }
    }
    func toggleBold() { applyFormat(.bold) }
    func toggleItalic() { applyFormat(.italic) }
    func toggleUnderline() { applyFormat(.underline) }
    func toggleStrikethrough() { applyFormat(.strikethrough) }
    func setHeading(_ level: HeadingLevel) {
        switch level {
        case .title: applyFormat(.title)
        case .heading: applyFormat(.heading)
        case .subheading: applyFormat(.subheading)
        case .body: applyFormat(.body)
        }
    }
    func insertList(_ type: ListType) {
        switch type {
        case .bullet: applyFormat(.bulletList)
        case .numbered: applyFormat(.numberedList)
        case .checklist: applyFormat(.todoList)
        case .dash: applyFormat(.dashList)
        }
    }
    func insertBlockQuote() { applyFormat(.quote) }
    func insertMonospaced() { applyFormat(.codeBlock) }
    func insertCodeBlock() { applyFormat(.codeBlock) }
    func insertHighlight() { applyFormat(.highlight) }
    func insertLink() { applyFormat(.link) }
    func align(_ alignment: NoteAlignment) { applyFormat(alignment.command) }
    func changeFontSize(larger: Bool) { applyFormat(larger ? .fontLarger : .fontSmaller) }
    func showFonts() { applyFormat(.showFonts) }
    func insertTable() { applyFormat(.table) }
}
