import Foundation

/// Reuses the source's separator layout only when every nonempty paragraph has
/// a one-to-one counterpart. Never merges/splits prose or edits its characters.
enum RevisionParagraphs {
    struct Result { let text: String; let adjusted: Bool }
    static func align(_ candidate: String, to source: String) -> Result {
        let normalized = candidate.replacingOccurrences(of: "\r\n", with: "\n")
        let original = source.components(separatedBy: "\n")
        let proposed = normalized.components(separatedBy: "\n")
        func blank(_ line: String) -> Bool { line.allSatisfy { $0 == " " || $0 == "\t" } }
        func protected(_ lines: [String]) -> Bool {
            lines.contains { line in
                line.contains("\u{FFFC}") || line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
                    || line.trimmingCharacters(in: .whitespaces).hasPrefix("~~~")
                    || (!blank(line) && (line.hasPrefix("    ") || line.hasPrefix("\t")))
            }
        }
        guard !protected(original), !protected(proposed) else { return .init(text: candidate, adjusted: false) }
        let content = proposed.filter { !blank($0) }
        guard !content.isEmpty, original.filter({ !blank($0) }).count == content.count else {
            return .init(text: candidate, adjusted: false)
        }
        var index = 0
        let result = original.map { line -> String in
            if blank(line) { return line }
            defer { index += 1 }; return content[index]
        }.joined(separator: "\n")
        return .init(text: result, adjusted: result != candidate)
    }
    static func prepare(_ proposal: WritingProposal, source: String) -> WritingProposal {
        let aligned = align(proposal.document, to: source)
        return .init(document: aligned.text, assessments: proposal.assessments, issues: proposal.issues,
                     formattingNote: aligned.adjusted ? "已自动对齐原文段间空行，正文内容未改动。" : proposal.formattingNote)
    }
}
