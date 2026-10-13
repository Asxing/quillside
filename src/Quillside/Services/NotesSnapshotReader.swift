import Foundation
import SQLite3

/// Runs inside a NotesDBReader read transaction. All statements here are SELECT/PRAGMA reads.
struct NotesSnapshotReader {
    let db: OpaquePointer
    let fallbackStoreID: String
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    func columns(_ table: String) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\"\(table.replacingOccurrences(of: "\"", with: "\"\""))\")")
        defer { sqlite3_finalize(statement) }
        var result = Set<String>()
        while try SQLiteReadStep.next(statement) { result.insert(text(statement, 1).uppercased()) }
        return result
    }
    func prepare(_ sql: String, _ arguments: [String] = []) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw NotesReadFailure.schema }
        for (index, value) in arguments.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
                sqlite3_finalize(statement); throw NotesReadFailure.schema
            }
        }
        return statement
    }
    func text(_ row: OpaquePointer, _ column: Int32) -> String { sqlite3_column_text(row, column).map { String(cString: $0) } ?? "" }
    func integer(_ row: OpaquePointer, _ column: Int32) -> Int64? { sqlite3_column_type(row, column) == SQLITE_NULL ? nil : sqlite3_column_int64(row, column) }
    func backlinks(notes: [NotesDBReader.NoteInfo], generatedRegions: [String: [BacklinkDocumentRegion]] = [:]) throws -> NotesBacklinksSnapshot {
        let fields = try columns("ZICCLOUDSYNCINGOBJECT")
        guard fields.contains("ZISPASSWORDPROTECTED"), fields.contains("ZNOTEDATA") else { throw NotesReadFailure.schema }
        var attachments: [Int64: [String: NativeLinkAttachment]] = [:]
        let noteReference = ["ZNOTE1", "ZNOTE"].filter(fields.contains)
        let urlFields = ["ZTOKENCONTENTIDENTIFIER", "ZURLSTRING"].filter(fields.contains)
        if !noteReference.isEmpty, !urlFields.isEmpty {
            let reference = "COALESCE(" + noteReference.map { "NULLIF(\($0),0)" }.joined(separator: ",") + ",NULL)"
            let urls = urlFields.map { "COALESCE(\($0),'')" }.joined(separator: ",")
            let type = fields.contains("ZTYPEUTI1") ? "COALESCE(ZTYPEUTI1,'')" : "''"
            let rows = try prepare("SELECT \(reference),ZIDENTIFIER,\(type),\(urls) FROM ZICCLOUDSYNCINGOBJECT WHERE COALESCE(ZMARKEDFORDELETION,0)!=1 AND (\(reference)) IS NOT NULL")
            defer { sqlite3_finalize(rows) }
            var ambiguous = Set<String>()
            while try SQLiteReadStep.next(rows) {
                let source = sqlite3_column_int64(rows, 0), id = text(rows, 1).uppercased()
                guard !id.isEmpty else { continue }
                let key = "\(source):\(id)"
                let targets = (0..<urlFields.count).map { text(rows, Int32($0 + 3)) }.filter { !$0.isEmpty }
                if let old = attachments[source]?[id], Set(old.urls) != Set(targets) {
                    ambiguous.insert(key); attachments[source]?[id] = nil
                } else if !ambiguous.contains(key) {
                    attachments[source, default: [:]][id] = .init(sourceNoteID: source, identifier: id, type: text(rows, 2), urls: targets)
                }
            }
        }
        let known = Set(notes.filter { !$0.isPasswordProtected }.map(\.id))
        let noteIdentifiers = Dictionary(notes.map { ($0.id, $0.identifier.uppercased()) }, uniquingKeysWith: { first, _ in first })
        let rows = try prepare("SELECT n.Z_PK,d.ZDATA FROM ZICCLOUDSYNCINGOBJECT n LEFT JOIN ZICNOTEDATA d ON n.ZNOTEDATA=d.Z_PK WHERE n.ZTITLE1 IS NOT NULL AND COALESCE(n.ZISPASSWORDPROTECTED,0)=0")
        defer { sqlite3_finalize(rows) }
        var links: [NotesDBReader.NoteLinkData] = [], seen = Set<Int64>()
        var coverage = BacklinksCoverage(lockedNotes: notes.filter(\.isPasswordProtected).count)
        while try SQLiteReadStep.next(rows) {
            let source = sqlite3_column_int64(rows, 0)
            guard known.contains(source) else { continue }; seen.insert(source)
            guard let bytes = sqlite3_column_blob(rows, 1), sqlite3_column_bytes(rows, 1) > 0 else { coverage.unreadableNotes += 1; continue }
            do {
                let note = try AppleNotesNoteProtoDecoder().decodeDocument(from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(rows, 1))))
                let regions = generatedRegions[noteIdentifiers[source] ?? ""] ?? []
                let excluded = try regions.compactMap { region -> NSRange? in
                    guard let range = region.range(in: note.noteText) else { return nil }
                    let actual = try ActiveNoteLinkExtractor.extract(note, sourceID: source, attachments: attachments[source] ?? [:], only: range)
                    return actual.coverage.complete && Set(actual.identifiers) == Set(region.entries.map(\.identifier)) ? range : nil
                }
                let extracted = try ActiveNoteLinkExtractor.extract(note, sourceID: source, attachments: attachments[source] ?? [:], excluding: excluded)
                coverage.merge(extracted.coverage)
                if !extracted.identifiers.isEmpty { links.append(.init(noteId: source, linkedIdentifiers: extracted.identifiers)) }
            } catch { coverage.unreadableNotes += 1 }
        }
        coverage.unreadableNotes += known.subtracting(seen).count
        return .init(notes: notes, links: links, coverage: coverage)
    }
}
