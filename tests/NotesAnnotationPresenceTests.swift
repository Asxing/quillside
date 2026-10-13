import Testing
@testable import Quillside

struct NotesAnnotationPresenceTests {
    @Test func clickingOutsideBodyDoesNotEndCurrentNotesSession() {
        #expect(NotesAnnotationPresence.click(insideBody: true) == .keep)
        #expect(NotesAnnotationPresence.click(insideBody: false) == .keep)
    }
    @Test func applicationSwitchHidesAndReturnRestoresWithoutEndingSession() {
        #expect(NotesAnnotationPresence.context(notesVisible: false, sameNote: true, sameWindow: true, bodyFocused: false) == .hide)
        #expect(NotesAnnotationPresence.context(notesVisible: true, sameNote: true, sameWindow: true, bodyFocused: false) == .keep)
    }
    @Test func onlyVerifiedSameNoteCanDisplayMarkersWhenFocusLeavesEditor() {
        #expect(NotesAnnotationPresence.context(notesVisible: true, sameNote: true, sameWindow: true, bodyFocused: false) == .keep)
        #expect(NotesAnnotationPresence.context(notesVisible: true, sameNote: false, sameWindow: true, bodyFocused: true) == .hide)
        #expect(NotesAnnotationPresence.context(notesVisible: true, sameNote: nil, sameWindow: true, bodyFocused: false) == .hide)
        #expect(NotesAnnotationPresence.context(notesVisible: true, sameNote: true, sameWindow: false, bodyFocused: true) == .hide)
    }
}
