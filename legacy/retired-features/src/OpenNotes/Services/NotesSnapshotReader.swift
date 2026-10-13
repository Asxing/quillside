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
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw NotesSearchReadFailure.schema }
        for (index, value) in arguments.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
                sqlite3_finalize(statement); throw NotesSearchReadFailure.schema
            }
        }
        return statement
    }
    func text(_ row: OpaquePointer, _ column: Int32) -> String { sqlite3_column_text(row, column).map { String(cString: $0) } ?? "" }
    func integer(_ row: OpaquePointer, _ column: Int32) -> Int64? { sqlite3_column_type(row, column) == SQLITE_NULL ? nil : sqlite3_column_int64(row, column) }
    private func storeID() throws -> String {
        if try columns("Z_METADATA").contains("Z_UUID") {
            let row = try prepare("SELECT Z_UUID FROM Z_METADATA LIMIT 1"); defer { sqlite3_finalize(row) }
            if try SQLiteReadStep.next(row), !text(row, 0).isEmpty { return text(row, 0) }
        }
        return fallbackStoreID
    }
    private func entityID(_ name: String) throws -> Int64? {
        let primaryColumns = try columns("Z_PRIMARYKEY")
        guard Set(["Z_ENT", "Z_NAME"]).isSubset(of: primaryColumns) else { return nil }
        let row = try prepare("SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME=?", [name]); defer { sqlite3_finalize(row) }
        return try SQLiteReadStep.next(row) ? integer(row, 0) : nil
    }

    func knowledge(identifiers: Set<String>) throws -> [KnowledgeDocument] {
        guard !identifiers.isEmpty else { return [] }
        let fields = try columns("ZICCLOUDSYNCINGOBJECT")
        guard Set(["Z_PK", "ZIDENTIFIER", "ZTITLE1", "ZTITLE2", "ZFOLDER", "ZNOTEDATA", "ZISPASSWORDPROTECTED", "ZMARKEDFORDELETION", "ZFOLDERTYPE"]).isSubset(of: fields) else { throw NotesSearchReadFailure.schema }
        let owner = fields.contains("ZOWNER") ? "ZOWNER" : "NULL"
        let parent = fields.contains("ZPARENT") ? "ZPARENT" : "NULL"
        let folderEntity = try entityID("ICFolder")
        let folderFilter = fields.contains("Z_ENT") && folderEntity != nil ? "Z_ENT=\(folderEntity!)" : "ZTITLE2 IS NOT NULL OR Z_PK IN (SELECT ZFOLDER FROM ZICCLOUDSYNCINGOBJECT WHERE ZTITLE1 IS NOT NULL)"
        let folderRows = try prepare("SELECT Z_PK,ZIDENTIFIER,COALESCE(ZTITLE2,'Notes'),\(parent),\(owner) FROM ZICCLOUDSYNCINGOBJECT WHERE \(folderFilter)")
        var folders: [Int64: NotesFolderIdentity.Folder] = [:]
        do {
            defer { sqlite3_finalize(folderRows) }
            while try SQLiteReadStep.next(folderRows) {
                let pk = sqlite3_column_int64(folderRows, 0)
                folders[pk] = .init(pk: pk, identifier: text(folderRows, 1), name: text(folderRows, 2), parent: integer(folderRows, 3), owner: integer(folderRows, 4))
            }
        }
        var accounts: [Int64: NotesFolderIdentity.Account] = [:]
        if fields.contains("Z_ENT"), let accountEntity = try entityID("ICAccount") {
            let accountName = fields.contains("ZNAME") ? "COALESCE(ZNAME,'')" : "''"
            let rows = try prepare("SELECT Z_PK,ZIDENTIFIER,\(accountName) FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT=\(accountEntity)")
            defer { sqlite3_finalize(rows) }
            while try SQLiteReadStep.next(rows) {
                let pk = sqlite3_column_int64(rows, 0)
                accounts[pk] = .init(pk: pk, identifier: text(rows, 1), name: text(rows, 2))
            }
        }
        let namespace = try storeID(), accountColumn = fields.contains("ZACCOUNT7") ? "n.ZACCOUNT7" : "NULL"
        let requested = identifiers.sorted(), indexedAt = Date().timeIntervalSince1970
        var result: [KnowledgeDocument] = []
        for start in stride(from: 0, to: requested.count, by: 400) {
            let batch = Array(requested[start..<min(requested.count, start + 400)])
            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            let rows = try prepare("""
                SELECT n.ZIDENTIFIER,n.ZTITLE1,n.ZFOLDER,d.ZDATA,\(accountColumn)
                FROM ZICCLOUDSYNCINGOBJECT n LEFT JOIN ZICNOTEDATA d ON n.ZNOTEDATA=d.Z_PK
                LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER=f.Z_PK
                WHERE n.ZIDENTIFIER IN (\(placeholders)) AND n.ZTITLE1 IS NOT NULL
                AND COALESCE(n.ZISPASSWORDPROTECTED,0)=0 AND COALESCE(n.ZMARKEDFORDELETION,0)!=1 AND COALESCE(f.ZFOLDERTYPE,0)!=1
                """, batch)
            defer { sqlite3_finalize(rows) }
            while try SQLiteReadStep.next(rows) {
                guard let bytes = sqlite3_column_blob(rows, 3), sqlite3_column_bytes(rows, 3) > 0 else { throw AIError.message("所选笔记正文暂不可读，原索引已保留。") }
                let id = text(rows, 0), content = try AppleNotesNoteProtoDecoder().decodeDocument(from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(rows, 3))))
                let scope = NotesFolderIdentity.resolve(noteIdentifier: id, folderPK: integer(rows, 2), noteAccountPK: integer(rows, 4), store: namespace, folders: folders, accounts: accounts)
                result.append(.init(id: "notes:" + id, title: text(rows, 1), locator: "applenotes:note/" + id,
                                    collection: scope.name, text: content.noteText, indexedAt: indexedAt,
                                    collectionID: scope.id, collectionDetail: scope.detail))
            }
        }
        return result
    }

    func backlinks(notes: [NotesDBReader.NoteInfo]) throws -> NotesBacklinksSnapshot {
        let fields = try columns("ZICCLOUDSYNCINGOBJECT")
        guard fields.contains("ZISPASSWORDPROTECTED"), fields.contains("ZNOTEDATA") else { throw NotesSearchReadFailure.schema }
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
                let extracted = try ActiveNoteLinkExtractor.extract(note, sourceID: source, attachments: attachments[source] ?? [:])
                coverage.merge(extracted.coverage)
                if !extracted.identifiers.isEmpty { links.append(.init(noteId: source, linkedIdentifiers: extracted.identifiers)) }
            } catch { coverage.unreadableNotes += 1 }
        }
        coverage.unreadableNotes += known.subtracting(seen).count
        return .init(notes: notes, links: links, coverage: coverage)
    }
}
