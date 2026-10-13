import Foundation
import CoreGraphics

/// Positions belong to one immutable Notes body; viewport projection is separate.
enum NotesAnnotationGeometry {
    static func matchesSource(_ draft: WritingDraft, noteIdentity: String?, body: String, sameWindow: Bool, sameEditor: Bool) -> Bool {
        draft.noteIdentity == noteIdentity && draft.baseline == body && sameWindow && sameEditor
    }
    static func bodyRange(_ body: String) -> NSRange {
        let text = body as NSString, firstBreak = text.range(of: "\n")
        let start = firstBreak.location == NSNotFound ? 0 : NSMaxRange(firstBreak)
        return NSRange(location: start, length: text.length - start)
    }
    static func localSelection(_ selection: NSRange, within scope: NSRange) -> NSRange? {
        guard scope.location != NSNotFound, scope.location >= 0, scope.length >= 0,
              scope.length <= Int.max - scope.location,
              selection.location != NSNotFound, selection.length > 0, selection.location >= scope.location,
              selection.location <= NSMaxRange(scope), selection.length <= NSMaxRange(scope) - selection.location else { return nil }
        return NSRange(location: selection.location - scope.location, length: selection.length)
    }
    static func absoluteRange(_ item: WritingAnnotation, draft: WritingDraft) -> NSRange? {
        guard item.versionID == draft.id, UTF16TextRange.valid(item.range, in: draft.source),
              (draft.source as NSString).substring(with: item.range) == item.quote else { return nil }
        return NSRange(location: draft.rangeLocation + item.location, length: item.length)
    }
    static func dockFrame(viewport: CGRect, screen: CGRect, expanded: Bool) -> CGRect {
        let area = viewport.intersection(screen).insetBy(dx: 10, dy: 10)
        guard area.width > 120, area.height > 100 else { return .zero }
        let size = CGSize(width: min(370, area.width), height: min(expanded ? 454 : 240, area.height))
        return CGRect(x: area.maxX - size.width, y: area.minY, width: size.width, height: size.height)
    }
    static func visibleMark(bounds: CGRect, viewport: CGRect) -> CGRect? {
        guard bounds.width > 0, bounds.height > 0, viewport.intersects(bounds) else { return nil }
        let intersection = bounds.intersection(viewport)
        guard intersection.height >= 6 else { return nil }
        // AX can return a multiline bounding box. The marker identifies the
        // passage; no permanent underline is inserted into the native note.
        return CGRect(x: max(viewport.minX + 3, min(bounds.maxX + 5, viewport.maxX - 25)),
                      y: max(viewport.minY, min(intersection.maxY - 21, viewport.maxY - 21)), width: 22, height: 21)
    }
}
