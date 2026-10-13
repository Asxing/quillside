import Foundation
import SQLite3
import Testing
@testable import OpenNotes

@Suite struct KnowledgeFailureTests {
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenNotes-index-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("knowledge.sqlite")
    }
    private func doc(_ id: String, text: String) -> KnowledgeDocument {
        .init(id: id, title: "合同", locator: "file:///synthetic.txt", collection: "全部", text: text, indexedAt: 1, collectionID: "test:all")
    }
    @Test func exclusiveLockThrowsInsteadOfReturningEmptyKnowledge() async throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let index = try KnowledgeIndex(path: url.path)
        try await index.upsert(doc("1", text: "合同仍然存在"))
        #expect(try await index.documents().count == 1)
        var writer: OpaquePointer?
        #expect(sqlite3_open(url.path, &writer) == SQLITE_OK)
        defer { sqlite3_exec(writer, "ROLLBACK", nil, nil, nil); sqlite3_close(writer) }
        #expect(sqlite3_exec(writer, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
        await #expect(throws: AIError.self) { try await index.documents() }
        await #expect(throws: AIError.self) { try await index.search("合同", collectionID: nil) }
        #expect(sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        #expect(try await index.documents().count == 1)
        #expect(try await index.search("合同", collectionID: "test:all").count == 1)
    }
    @Test func failedSnapshotReplacementRestoresEverySourceAndFTSRow() async throws {
        let index = try KnowledgeIndex(path: ":memory:")
        try await index.upsert(doc("1", text: "甲合同"))
        try await index.upsert(doc("2", text: "乙合同"))
        let tooLarge = doc("2", text: String(repeating: "x", count: 5_000_001))
        await #expect(throws: AIError.self) {
            try await index.replaceSnapshot([doc("1", text: "新文本"), tooLarge], replacingIDs: ["1", "2"])
        }
        #expect(Set(try await index.documents().map(\.text)) == ["甲合同", "乙合同"])
        #expect(try await index.search("合同", collectionID: nil).count == 2)
        #expect(try await index.search("新文本", collectionID: nil).isEmpty)
        try await index.replaceSnapshot([doc("1", text: "更新合同")], replacingIDs: ["1", "2"])
        #expect(try await index.documents().map(\.id) == ["1"])
    }
    @Test func newerSchemaIsRejectedWithoutRewritingItsVersion() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil) == SQLITE_OK)
        #expect(throws: AIError.self) { try KnowledgeIndex(path: url.path) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 99)
    }
    @Test func notesSnapshotRejectsMissingBodyInsteadOfDeletingIt() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE ZICCLOUDSYNCINGOBJECT(Z_PK INTEGER PRIMARY KEY,ZIDENTIFIER TEXT,ZTITLE1 TEXT,ZTITLE2 TEXT,ZNOTEDATA INTEGER,ZFOLDER INTEGER,ZISPASSWORDPROTECTED INTEGER,ZMARKEDFORDELETION INTEGER,ZFOLDERTYPE INTEGER);
        CREATE TABLE ZICNOTEDATA(Z_PK INTEGER PRIMARY KEY,ZDATA BLOB);
        INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,ZIDENTIFIER,ZTITLE1,ZNOTEDATA) VALUES(1,'synthetic-note','Fixture',100);
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        let reader = NotesDBReader(databasePath: url.path)
        #expect(throws: AIError.self) { try reader.readKnowledgeDocuments(identifiers: ["synthetic-note"]) }
        #expect(try reader.readKnowledgeDocuments(identifiers: []).isEmpty)
        #expect(sqlite3_exec(db, "UPDATE ZICCLOUDSYNCINGOBJECT SET ZISPASSWORDPROTECTED=1", nil, nil, nil) == SQLITE_OK)
        #expect(try reader.readKnowledgeDocuments(identifiers: ["synthetic-note"]).isEmpty)
    }
}
