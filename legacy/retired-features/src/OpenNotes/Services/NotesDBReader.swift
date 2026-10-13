import Foundation
import SQLite3
import AppKit
import os.log

enum NotesSearchReadFailure: LocalizedError {
    case permission, unavailable, schema, identity
    var errorDescription: String? {
        switch self {
        case .permission: return "请在系统设置中为 OpenNotes 开启完全磁盘访问。"
        case .unavailable: return "Notes 数据库尚未就绪或暂时不可读，请打开 Notes 后重试。"
        case .schema: return "当前 Notes 数据格式尚不受支持。"
        case .identity: return "笔记定位信息不完整，请稍后重新加载。"
        }
    }
}

enum NotesDatabaseAccessIssue: Equatable {
    case databaseMissing
    case openFailed(Int32)
}

enum NotesDatabaseAccessStatus: Equatable {
    case checking
    case available
    case permissionRequired
    case unavailable(NotesDatabaseAccessIssue)
}

final class NotesDBReader {
    
    static let shared = NotesDBReader()
    
    private let logger = Logger(subsystem: "com.opennotes.app", category: "NotesDB")
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.opennotes.db", qos: .userInitiated)
    
    private let dbPath: String?
    private let permissionProtectedContainerPath: String?
    private let snapshotObserver: (() -> Void)?
    
    struct NoteInfo: Identifiable, Equatable {
        let id: Int64
        let identifier: String
        let title: String
        let snippet: String
        let folderName: String
        let modificationDate: Date
        let isPinned: Bool
        var isPasswordProtected = false
    }
    
    private convenience init() {
        let containerPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes")
        self.init(
            databasePath: containerPath
                .appendingPathComponent("NoteStore.sqlite")
                .path,
            permissionProtectedContainerPath: containerPath.path
        )
    }

    init(
        databasePath: String,
        permissionProtectedContainerPath: String? = nil,
        snapshotObserver: (() -> Void)? = nil
    ) {
        dbPath = databasePath
        self.permissionProtectedContainerPath = permissionProtectedContainerPath
        self.snapshotObserver = snapshotObserver
    }
    
    deinit {
        dbQueue.sync {
            closeUnsafe()
        }
    }
    
    func open() -> Bool {
        return dbQueue.sync {
            openUnsafe()
        }
    }

    func accessStatus() -> NotesDatabaseAccessStatus {
        dbQueue.sync {
            accessStatusUnsafe()
        }
    }
    
    func close() {
        dbQueue.sync {
            closeUnsafe()
        }
    }

    func closeAsync() {
        dbQueue.async { [weak self] in
            self?.closeUnsafe()
        }
    }
    
    func readKnowledgeDocuments(identifiers: Set<String>) throws -> [KnowledgeDocument] {
        try dbQueue.sync {
            guard openUnsafe(), let db else { throw NotesSearchReadFailure.unavailable }
            guard sqlite3_exec(db, "BEGIN DEFERRED", nil, nil, nil) == SQLITE_OK else { throw NotesSearchReadFailure.unavailable }
            defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
            return try NotesSnapshotReader(db: db, fallbackStoreID: KnowledgeText.fingerprint(dbPath ?? "local")).knowledge(identifiers: identifiers)
        }
    }

    func getAllNotes() -> [NoteInfo] {
        return dbQueue.sync {
            getAllNotesUnsafe()
        }
    }

    /// Search requires an authoritative result, not a partial/empty array on read failure.
    func readAllNotes() throws -> [NoteInfo] { try dbQueue.sync { try readAllNotesUnsafe() } }

    func readBacklinksSnapshot() throws -> NotesBacklinksSnapshot {
        try dbQueue.sync {
            guard openUnsafe(), let db else { throw NotesSearchReadFailure.unavailable }
            guard sqlite3_exec(db, "BEGIN DEFERRED", nil, nil, nil) == SQLITE_OK else { throw NotesSearchReadFailure.unavailable }
            defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
            let notes = try readAllNotesUnsafe()
            snapshotObserver?()
            return try NotesSnapshotReader(db: db, fallbackStoreID: KnowledgeText.fingerprint(dbPath ?? "local")).backlinks(notes: notes)
        }
    }

    private func readAllNotesUnsafe(identifier: String? = nil) throws -> [NoteInfo] {

            if accessStatusUnsafe() == .permissionRequired { throw NotesSearchReadFailure.permission }
            guard openUnsafe(), let db else { throw NotesSearchReadFailure.unavailable }
            var metadata: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA table_info(ZICCLOUDSYNCINGOBJECT)", -1, &metadata, nil) == SQLITE_OK else { throw AIError.message("无法读取 Notes 数据库结构。") }
            var columns = Set<String>()
            do {
                defer { sqlite3_finalize(metadata) }
                while try SQLiteReadStep.next(metadata) {
                    if let name = sqlite3_column_text(metadata, 1) { columns.insert(String(cString: name).uppercased()) }
                }
            }
            let required: Set<String> = ["Z_PK", "ZIDENTIFIER", "ZTITLE1", "ZTITLE2", "ZFOLDER", "ZMODIFICATIONDATE1", "ZMARKEDFORDELETION", "ZFOLDERTYPE"]
            guard required.isSubset(of: columns) else { throw NotesSearchReadFailure.schema }
            let snippet = columns.contains("ZSNIPPET") && columns.contains("ZISPASSWORDPROTECTED")
                ? "CASE WHEN COALESCE(n.ZISPASSWORDPROTECTED,0)=1 THEN '' ELSE COALESCE(n.ZSNIPPET,'') END" : "''"
            let pinned = columns.contains("ZISPINNED") ? "COALESCE(n.ZISPINNED,0)" : "0"
            let locked = columns.contains("ZISPASSWORDPROTECTED") ? "COALESCE(n.ZISPASSWORDPROTECTED,0)" : "0"
            let sql = """
                SELECT n.Z_PK, n.ZIDENTIFIER, n.ZTITLE1, \(snippet), COALESCE(f.ZTITLE2,'Notes'), n.ZMODIFICATIONDATE1, \(pinned), \(locked)
                FROM ZICCLOUDSYNCINGOBJECT n LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER=f.Z_PK
                WHERE n.ZTITLE1 IS NOT NULL AND COALESCE(n.ZMARKEDFORDELETION,0)!=1 AND COALESCE(f.ZFOLDERTYPE,0)!=1
                \(identifier == nil ? "" : "AND n.ZIDENTIFIER=?")
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw AIError.message("Notes 搜索查询不可用。") }
            defer { sqlite3_finalize(statement) }
            if let identifier { sqlite3_bind_text(statement, 1, identifier, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            var result: [NoteInfo] = []
            while try SQLiteReadStep.next(statement) {
                guard let note = parseNoteRow(statement), !note.identifier.isEmpty else { throw NotesSearchReadFailure.identity }
                result.append(note)
            }
            return result
    }

    func readIdentifierByPK(_ pk: Int64) throws -> String? {
        try dbQueue.sync {
            guard openUnsafe(), let db else { throw NotesSearchReadFailure.unavailable }
            let reader = NotesSnapshotReader(db: db, fallbackStoreID: "")
            let statement = try reader.prepare("SELECT ZIDENTIFIER FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK=?", [String(pk)])
            defer { sqlite3_finalize(statement) }
            guard try SQLiteReadStep.next(statement) else { return nil }
            let value = reader.text(statement, 0)
            return value.isEmpty ? nil : value
        }
    }
    func readNoteByIdentifier(_ identifier: String) throws -> NoteInfo? {
        try dbQueue.sync { try readAllNotesUnsafe(identifier: identifier).sorted { $0.modificationDate > $1.modificationDate }.first }
    }

    func buildNoteURL(identifier: String) -> String {
        return "applenotes:note/\(identifier)"
    }
    
    struct NoteLinkData {
        let noteId: Int64
        let linkedIdentifiers: [String]
    }
    
    func getAllNoteLinks() -> [NoteLinkData] {
        return dbQueue.sync {
            getAllNoteLinksUnsafe()
        }
    }
    
    func getIdentifierByPK(_ pk: Int64) -> String? {
        return dbQueue.sync {
            getIdentifierByPKUnsafe(pk)
        }
    }
    
    func getNoteByIdentifier(_ identifier: String) -> NoteInfo? {
        return dbQueue.sync {
            getNoteByIdentifierUnsafe(identifier)
        }
    }
    
    private func getIdentifierByPKUnsafe(_ pk: Int64) -> String? {
        guard let db = db else {
            if !openUnsafe() { return nil }
            return getIdentifierByPKUnsafe(pk)
        }
        
        let sql = "SELECT ZIDENTIFIER FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, pk)
        
        if sqlite3_step(stmt) == SQLITE_ROW,
           let identifierPtr = sqlite3_column_text(stmt, 0) {
            return String(cString: identifierPtr)
        }
        return nil
    }
    
    private func getNoteByIdentifierUnsafe(_ identifier: String) -> NoteInfo? {
        guard let db = db else {
            if !openUnsafe() { return nil }
            return getNoteByIdentifierUnsafe(identifier)
        }
        
        let sql = """
            SELECT 
                n.Z_PK as id,
                COALESCE(n.ZIDENTIFIER, '') as identifier,
                n.ZTITLE1 as title,
                COALESCE(n.ZSNIPPET, '') as snippet,
                COALESCE(f.ZTITLE2, 'Notes') as folder,
                n.ZMODIFICATIONDATE1 as modDate,
                COALESCE(n.ZISPINNED, 0) as isPinned
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            WHERE n.ZIDENTIFIER = ?
                AND n.ZTITLE1 IS NOT NULL
                AND COALESCE(n.ZMARKEDFORDELETION, 0) != 1
                AND COALESCE(f.ZFOLDERTYPE, 0) != 1
            LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, identifier, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseNoteRow(stmt)
        }
        return nil
    }
    
    private func getAllNoteLinksUnsafe() -> [NoteLinkData] {
        guard let db = db else {
            if !openUnsafe() { return [] }
            return getAllNoteLinksUnsafe()
        }

        var grouped: [Int64: Set<String>] = [:]
        
        let sql = """
            SELECT att.ZNOTE1 as sourceNoteId, att.ZTOKENCONTENTIDENTIFIER as tokenURL
            FROM ZICCLOUDSYNCINGOBJECT att
            WHERE att.ZNOTE1 IS NOT NULL
                AND att.ZTOKENCONTENTIDENTIFIER IS NOT NULL
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Failed to prepare native note-link query")
            return []
        }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sourceId = sqlite3_column_int64(stmt, 0)
            guard let tokenPtr = sqlite3_column_text(stmt, 1) else { continue }
            let tokenURL = String(cString: tokenPtr)
            for identifier in NativeNoteLinkParser.identifiers(in: tokenURL) {
                grouped[sourceId, default: []].insert(identifier)
            }
        }
        sqlite3_finalize(stmt)

        let compressedLinksSQL = """
            SELECT n.Z_PK, d.ZDATA
            FROM ZICCLOUDSYNCINGOBJECT n
            JOIN ZICNOTEDATA d ON n.ZNOTEDATA = d.Z_PK
            WHERE n.ZNOTEDATA IS NOT NULL
                AND d.ZDATA IS NOT NULL
        """
        stmt = nil
        guard sqlite3_prepare_v2(
            db,
            compressedLinksSQL,
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else {
            logger.error("Failed to prepare compressed note-link query")
            return grouped.compactMap { entry -> NoteLinkData? in
                guard !entry.value.isEmpty else { return nil }
                return NoteLinkData(
                    noteId: entry.key,
                    linkedIdentifiers: entry.value.sorted()
                )
            }
            .sorted { $0.noteId < $1.noteId }
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let sourceId = sqlite3_column_int64(stmt, 0)
            guard let bytes = sqlite3_column_blob(stmt, 1) else { continue }
            let byteCount = Int(sqlite3_column_bytes(stmt, 1))
            let data = Data(bytes: bytes, count: byteCount)
            grouped[sourceId, default: []].formUnion(
                AppleNotesProtobufLinkParser.identifiers(
                    inCompressedNoteData: data
                )
            )
        }
        
        let results = grouped.compactMap { entry -> NoteLinkData? in
            guard !entry.value.isEmpty else { return nil }
            return NoteLinkData(
                noteId: entry.key,
                linkedIdentifiers: entry.value.sorted()
            )
        }
        .sorted { $0.noteId < $1.noteId }
        logger.debug("Native note links found in \(results.count) notes")
        return results
    }
    
    func openNote(identifier: String) {
        let urlString = buildNoteURL(identifier: identifier)
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openUnsafe() -> Bool {
        if db != nil {
            return true
        }
        
        guard let path = dbPath else {
            logger.error("Database path not found")
            return false
        }
        
        let fileExists = FileManager.default.fileExists(atPath: path)
        let isReadable = FileManager.default.isReadableFile(atPath: path)
        logger.info("Database availability: exists=\(fileExists), readable=\(isReadable)")
        
        guard fileExists else {
            logger.error("Database file does not exist")
            return false
        }
        
        guard isReadable else {
            logger.error("Database file not readable - Full Disk Access required")
            return false
        }
        
        var tempDb: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &tempDb, flags, nil)
        
        if result != SQLITE_OK {
            let errorMsg = tempDb != nil ? String(cString: sqlite3_errmsg(tempDb)) : "unknown"
            logger.error("Failed to open database: \(result), error: \(errorMsg)")
            if let tempDb = tempDb {
                sqlite3_close(tempDb)
            }
            return false
        }
        
        sqlite3_busy_timeout(tempDb, 5000)
        
        db = tempDb
        logger.info("Database opened successfully")
        return true
    }

    private func accessStatusUnsafe() -> NotesDatabaseAccessStatus {
        guard let path = dbPath else {
            return .unavailable(.databaseMissing)
        }

        guard FileManager.default.fileExists(atPath: path) else {
            if let containerPath = permissionProtectedContainerPath {
                do {
                    _ = try FileManager.default.contentsOfDirectory(
                        atPath: containerPath
                    )
                } catch let error as CocoaError where
                    error.code == .fileNoSuchFile
                    || error.code == .fileReadNoSuchFile
                {
                    return .unavailable(.databaseMissing)
                } catch {
                    return .permissionRequired
                }
            }
            return .unavailable(.databaseMissing)
        }

        guard FileManager.default.isReadableFile(atPath: path) else {
            return .permissionRequired
        }

        var probeDatabase: OpaquePointer?
        let result = sqlite3_open_v2(
            path,
            &probeDatabase,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        if let probeDatabase {
            sqlite3_close(probeDatabase)
        }

        guard result == SQLITE_OK else {
            return .unavailable(.openFailed(result))
        }

        return .available
    }
    
    private func closeUnsafe() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
            logger.info("Database closed")
        }
    }
    
    private func getAllNotesUnsafe() -> [NoteInfo] {
        guard let db = db else {
            if !openUnsafe() { return [] }
            return getAllNotesUnsafe()
        }
        
        let sql = """
            SELECT 
                n.Z_PK as id,
                COALESCE(n.ZIDENTIFIER, '') as identifier,
                n.ZTITLE1 as title,
                COALESCE(n.ZSNIPPET, '') as snippet,
                COALESCE(f.ZTITLE2, 'Notes') as folder,
                n.ZMODIFICATIONDATE1 as modDate,
                COALESCE(n.ZISPINNED, 0) as isPinned
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            WHERE n.ZTITLE1 IS NOT NULL
                AND COALESCE(n.ZMARKEDFORDELETION, 0) != 1
                AND COALESCE(f.ZFOLDERTYPE, 0) != 1
            ORDER BY n.ZISPINNED DESC, n.ZMODIFICATIONDATE1 DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Failed to prepare getAllNotes query")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        var results: [NoteInfo] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let note = parseNoteRow(stmt) {
                results.append(note)
            }
        }
        
        logger.debug("getAllNotes returned \(results.count) results")
        return results
    }
    
    private func parseNoteRow(_ stmt: OpaquePointer?) -> NoteInfo? {
        guard let stmt = stmt else { return nil }
        
        let id = sqlite3_column_int64(stmt, 0)
        
        let identifier: String
        if let identifierPtr = sqlite3_column_text(stmt, 1) {
            identifier = String(cString: identifierPtr)
        } else {
            identifier = ""
        }
        
        guard let titlePtr = sqlite3_column_text(stmt, 2) else { return nil }
        let title = String(cString: titlePtr)
        
        let snippet: String
        if let snippetPtr = sqlite3_column_text(stmt, 3) {
            snippet = String(cString: snippetPtr)
        } else {
            snippet = ""
        }
        
        let folder: String
        if let folderPtr = sqlite3_column_text(stmt, 4) {
            folder = String(cString: folderPtr)
        } else {
            folder = "Notes"
        }
        
        let modTimestamp = sqlite3_column_double(stmt, 5)
        let isPinned = sqlite3_column_int(stmt, 6) != 0
        
        let modDate = Date(timeIntervalSinceReferenceDate: modTimestamp)
        
        return NoteInfo(
            id: id,
            identifier: identifier,
            title: title.isEmpty ? "Untitled" : title,
            snippet: snippet,
            folderName: folder,
            modificationDate: modDate,
            isPinned: isPinned,
            isPasswordProtected: sqlite3_column_count(stmt) > 7 && sqlite3_column_int(stmt, 7) != 0
        )
    }
}
