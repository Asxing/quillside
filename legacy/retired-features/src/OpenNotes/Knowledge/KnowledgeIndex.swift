import Foundation
import SQLite3
import NaturalLanguage
import CryptoKit

struct KnowledgeDocument: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let locator: String
    let collection: String
    let text: String
    let indexedAt: Double
    var collectionID: String? = nil
    var collectionDetail: String = ""
    var scopeID: String { collectionID ?? KnowledgeCollectionIdentity.legacy(id) }
}

enum KnowledgeCollectionIdentity {
    static let files = "imported-files"
    static func legacy(_ sourceID: String) -> String { "legacy-source:" + sourceID }
    static func notes(store: String, account: String, folder: String) -> String {
        let encoded = (try? JSONEncoder().encode([store, account, folder])) ?? Data()
        return "notes-folder:" + KnowledgeText.fingerprint(String(decoding: encoded, as: UTF8.self))
    }
}

struct KnowledgeCollectionOption: Identifiable, Equatable {
    let id: String
    let label: String
    static func options(_ documents: [KnowledgeDocument]) -> [Self] {
        let grouped = Dictionary(grouping: documents, by: \.scopeID)
        let labels = grouped.mapValues { values in
            let recent = values.max { $0.indexedAt < $1.indexedAt }!
            if recent.scopeID.hasPrefix("legacy-source:") { return recent.collection + " · " + recent.title + "（旧快照，待刷新）" }
            if recent.scopeID.hasPrefix("unresolved-source:") { return recent.collection + " · " + recent.title + "（来源待确认）" }
            return recent.collectionDetail.isEmpty ? recent.collection : recent.collectionDetail + " / " + recent.collection
        }
        let counts = Dictionary(grouping: labels.values, by: { $0 }).mapValues(\.count)
        return labels.map { id, label in
            .init(id: id, label: (counts[label] ?? 0) > 1 ? label + " · " + KnowledgeText.fingerprint(id).prefix(6) : label)
        }.sorted { $0.label == $1.label ? $0.id < $1.id : $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}

struct KnowledgeHit: Identifiable, Equatable, Sendable {
    let id: Int64
    let documentID: String
    let title: String
    let locator: String
    let text: String
}

enum KnowledgeText {
    static func tokens(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            words.append(String(text[range]).lowercased()); return words.count < 100_000
        }
        return words
    }
    static func chunks(_ text: String, size: Int = 800, overlap: Int = 100) -> [String] {
        guard size > overlap, overlap >= 0 else { return [] }
        var result: [String] = [], start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            result.append(String(text[start..<end]))
            if end == text.endIndex { break }
            start = text.index(end, offsetBy: -overlap)
        }
        return result
    }
    static func fingerprint(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}

/// Writes only to OpenNotes' own derived index; never opens the Notes database.
actor KnowledgeIndex {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw AIError.message("无法创建本地知识索引。")
        }
        var versionStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &versionStatement, nil) == SQLITE_OK,
              sqlite3_step(versionStatement) == SQLITE_ROW else {
            sqlite3_finalize(versionStatement); sqlite3_close(db); db = nil
            throw AIError.message("无法读取知识库版本，未修改索引。")
        }
        let version = sqlite3_column_int(versionStatement, 0)
        sqlite3_finalize(versionStatement)
        guard (0...2).contains(version) else {
            sqlite3_close(db); db = nil
            throw AIError.message("此知识库由更新版本创建，请使用对应版本打开。")
        }
        if path != ":memory:" {
            do { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
            catch { sqlite3_close(db); db = nil; throw AIError.message("无法设置本地知识索引的访问权限。") }
        }
        if version > 0 {
            let extra = version == 2 ? ",d.collection_id,d.collection_detail" : ""
            var validation: OpaquePointer?
            let sql = "SELECT d.id,d.title,d.locator,d.collection,d.body,d.content_hash,d.indexed_at,c.id,c.document_id,c.body,f.rowid,f.terms\(extra) FROM documents d LEFT JOIN chunks c ON c.document_id=d.id LEFT JOIN chunks_fts f ON f.rowid=c.id LIMIT 0"
            let status = sqlite3_prepare_v2(db, sql, -1, &validation, nil)
            sqlite3_finalize(validation)
            guard status == SQLITE_OK else { sqlite3_close(db); db = nil; throw AIError.message("本地索引结构不完整，原文件已保留。") }
        }
        let schema: String
        if version == 0 {
            schema = """
            BEGIN IMMEDIATE;
            CREATE TABLE documents(id TEXT PRIMARY KEY,title TEXT NOT NULL,locator TEXT NOT NULL,collection TEXT NOT NULL,body TEXT NOT NULL,content_hash TEXT NOT NULL,indexed_at REAL NOT NULL,collection_id TEXT NOT NULL,collection_detail TEXT NOT NULL);
            CREATE TABLE chunks(id INTEGER PRIMARY KEY,document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,body TEXT NOT NULL);
            CREATE VIRTUAL TABLE chunks_fts USING fts5(terms, tokenize='unicode61');
            PRAGMA user_version=2;
            COMMIT;
            """
        } else if version == 1 {
            schema = """
            BEGIN IMMEDIATE;
            ALTER TABLE documents ADD COLUMN collection_id TEXT NOT NULL DEFAULT '';
            ALTER TABLE documents ADD COLUMN collection_detail TEXT NOT NULL DEFAULT '';
            UPDATE documents SET collection_id=CASE WHEN id LIKE 'file:%' THEN 'imported-files' ELSE 'legacy-source:'||id END,
                collection_detail=CASE WHEN id LIKE 'file:%' THEN '导入文件' ELSE '旧快照，刷新后识别来源' END;
            PRAGMA user_version=2;
            COMMIT;
            """
        } else { schema = "SELECT collection_id,collection_detail FROM documents LIMIT 0;" }
        guard sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            sqlite3_close(db); db = nil
            throw AIError.message("知识库初始化或迁移失败，原有数据未删除。")
        }
    }
    deinit { sqlite3_close(db) }

    private func execute(_ sql: String, strings: [String] = []) throws {
        let statement = try prepare(sql, strings: strings); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AIError.message("索引写入失败，原始资料未改变。") }
    }
    private func prepare(_ sql: String, strings: [String] = []) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw AIError.message("本地索引查询失败。") }
        for (i, value) in strings.enumerated() { sqlite3_bind_text(statement, Int32(i + 1), value, -1, transient) }
        return statement
    }
    private func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }
    func upsert(_ document: KnowledgeDocument) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try upsertRows(document)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    private func upsertRows(_ document: KnowledgeDocument) throws {
        guard document.text.utf8.count <= 5_000_000 else { throw AIError.message("单份资料最多支持 5 MB 文本，请拆分后导入。") }
        try removeRows(document.id)
        try execute("INSERT INTO documents(id,title,locator,collection,body,content_hash,indexed_at,collection_id,collection_detail) VALUES(?,?,?,?,?,?,?,?,?)", strings: [document.id, document.title, document.locator, document.collection, document.text, KnowledgeText.fingerprint(document.text), String(document.indexedAt), document.scopeID, document.collectionDetail])
        for chunk in KnowledgeText.chunks(document.text) {
            try execute("INSERT INTO chunks(document_id,body) VALUES(?,?)", strings: [document.id, chunk])
            let row = sqlite3_last_insert_rowid(db)
            try execute("INSERT INTO chunks_fts(rowid,terms) VALUES(?,?)", strings: [String(row), KnowledgeText.tokens(document.title + " " + chunk).joined(separator: " ")])
        }
    }
    /// Called only with a fully completed source read. Failure restores all prior sources and FTS rows.
    func replaceSnapshot(_ documents: [KnowledgeDocument], replacingIDs: Set<String>) throws {
        guard Set(documents.map(\.id)).isSubset(of: replacingIDs) else { throw AIError.message("快照包含未选择的来源。") }
        try execute("BEGIN IMMEDIATE")
        do {
            for id in replacingIDs { try removeRows(id) }
            for document in documents { try upsertRows(document) }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    private func removeRows(_ id: String) throws {
        try execute("DELETE FROM chunks_fts WHERE rowid IN (SELECT id FROM chunks WHERE document_id=?)", strings: [id])
        try execute("DELETE FROM documents WHERE id=?", strings: [id])
    }
    func remove(_ id: String) throws {
        try execute("BEGIN IMMEDIATE")
        do { try removeRows(id); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func documents() throws -> [KnowledgeDocument] {
        let statement = try prepare("SELECT id,title,locator,collection,body,indexed_at,collection_id,collection_detail FROM documents ORDER BY indexed_at DESC")
        defer { sqlite3_finalize(statement) }
        var result: [KnowledgeDocument] = []
        while try SQLiteReadStep.next(statement) {
            result.append(.init(id: string(statement, 0), title: string(statement, 1), locator: string(statement, 2), collection: string(statement, 3), text: string(statement, 4), indexedAt: sqlite3_column_double(statement, 5), collectionID: string(statement, 6), collectionDetail: string(statement, 7)))
        }
        return result
    }
    func search(_ query: String, collectionID: String?, limit: Int = 8) throws -> [KnowledgeHit] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }
        let tokens = Array(Set(KnowledgeText.tokens(query))).sorted().prefix(32)
        var result: [KnowledgeHit] = []
        let columns = "SELECT c.id,c.document_id,d.title,d.locator,c.body FROM chunks c JOIN documents d ON d.id=c.document_id "
        let scope = collectionID == nil ? "" : " AND d.collection_id=? "
        var scopeArgs: [String] { collectionID.map { [$0] } ?? [] }
        func read(_ sql: String, _ args: [String]) throws {
            let statement = try prepare(sql, strings: args); defer { sqlite3_finalize(statement) }
            while result.count < limit, try SQLiteReadStep.next(statement) {
                let id = sqlite3_column_int64(statement, 0)
                if result.contains(where: { $0.id == id }) { continue }
                result.append(.init(id: id, documentID: string(statement, 1), title: string(statement, 2), locator: string(statement, 3), text: string(statement, 4)))
            }
        }
        // Literal substring path makes short Chinese terms work even without word segmentation.
        try read(columns + "WHERE (instr(lower(c.body),lower(?))>0 OR instr(lower(d.title),lower(?))>0)" + scope + " ORDER BY d.indexed_at DESC LIMIT ?", [query, query] + scopeArgs + [String(limit)])
        if !tokens.isEmpty, result.count < limit {
            let expression = tokens.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
            try read(columns + "JOIN chunks_fts ON chunks_fts.rowid=c.id WHERE chunks_fts MATCH ? " + scope + " ORDER BY bm25(chunks_fts) LIMIT ?", [expression] + scopeArgs + [String(limit * 2)])
        }
        return result
    }
}
