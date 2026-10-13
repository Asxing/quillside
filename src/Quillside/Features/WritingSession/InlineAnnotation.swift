import Foundation

/// A popover keeps the exact text/version it was opened for, independent of focus.
struct InlineAnnotationAnchor: Equatable {
    let versionID: UUID
    let range: NSRange
    let quote: String

    init(annotation: WritingAnnotation) {
        versionID = annotation.versionID; range = annotation.range; quote = annotation.quote
    }

    init?(versionID: UUID, range: NSRange, text: String) {
        guard range.length > 0, UTF16TextRange.valid(range, in: text) else { return nil }
        self.versionID = versionID; self.range = range
        quote = (text as NSString).substring(with: range)
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    }
    func matches(_ draft: WritingDraft) -> Bool {
        versionID == draft.versionID && UTF16TextRange.valid(range, in: draft.candidate)
            && (draft.candidate as NSString).substring(with: range) == quote
    }
}
