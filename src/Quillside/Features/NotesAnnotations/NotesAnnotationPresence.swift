import Foundation

/// Whether an existing source-annotation session should remain on screen.
enum NotesAnnotationPresence {
    enum Effect: Equatable { case keep, hide }
    static func click(insideBody: Bool) -> Effect { .keep }
    static func context(notesVisible: Bool, sameNote: Bool?, sameWindow: Bool, bodyFocused: Bool) -> Effect {
        guard notesVisible, sameNote == true, sameWindow else { return .hide }
        return .keep
    }
}
