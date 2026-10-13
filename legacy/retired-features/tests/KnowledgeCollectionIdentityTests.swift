import Foundation
import SQLite3
import Testing
@testable import OpenNotes

@Suite struct KnowledgeCollectionIdentityTests {
    @Test func actualAccountFolderMetadataKeepsSameNamesSeparateAndRenameStable() async throws {
        let fixture = try NotesDataFixture()
        try fixture.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,Z_ENT,ZIDENTIFIER,ZTITLE1,ZFOLDER,ZNOTEDATA,ZACCOUNT7) VALUES(1,1,'note-a','A',10,1001,100),(2,1,'note-b','B',20,1002,200);")
        try fixture.blob(NotesDataFixture.body("账户甲的合同"), pk: 1001)
        try fixture.blob(NotesDataFixture.body("账户乙的合同"), pk: 1002)
        let reader = NotesDBReader(databasePath: fixture.url.path)
        let docs = try reader.readKnowledgeDocuments(identifiers: ["note-a", "note-b"])
        #expect(docs.count == 2)
        #expect(docs[0].scopeID != docs[1].scopeID)
        #expect(Set(docs.map(\.collectionDetail)) == ["账户 A", "账户 B"])
        let first = try #require(docs.first(where: { $0.id == "notes:note-a" }))
        let index = try KnowledgeIndex(path: ":memory:")
        for doc in docs { try await index.upsert(doc) }
        #expect(try await index.search("合同", collectionID: first.scopeID).map(\.documentID) == [first.id])
        try fixture.execute("UPDATE ZICCLOUDSYNCINGOBJECT SET ZTITLE2='项目' WHERE Z_PK=10; UPDATE ZICCLOUDSYNCINGOBJECT SET ZNAME='新账户名' WHERE Z_PK=100;")
        let renamed = try #require(reader.readKnowledgeDocuments(identifiers: ["note-a"]).first)
        #expect(renamed.scopeID == first.scopeID)
        #expect(renamed.collection == "项目")
        #expect(renamed.collectionDetail == "新账户名")
    }
    @Test func nestedFoldersAndUnresolvedOwnershipCannotCollapseByName() {
        let folders: [Int64: NotesFolderIdentity.Folder] = [
            1: .init(pk: 1, identifier: "root", name: "资料", parent: nil, owner: 100),
            2: .init(pk: 2, identifier: "DefaultFolder", name: "工作", parent: 1, owner: nil),
            3: .init(pk: 3, identifier: "DefaultFolder", name: "工作", parent: nil, owner: nil)
        ]
        let accounts: [Int64: NotesFolderIdentity.Account] = [100: .init(pk: 100, identifier: "account", name: "iCloud")]
        let a = NotesFolderIdentity.resolve(noteIdentifier: "a", folderPK: 2, noteAccountPK: nil, store: "store", folders: folders, accounts: accounts)
        let b = NotesFolderIdentity.resolve(noteIdentifier: "b", folderPK: 3, noteAccountPK: nil, store: "store", folders: folders, accounts: accounts)
        #expect(a.name == "资料 / 工作")
        #expect(a.detail == "iCloud")
        #expect(a.id != b.id)
        let conflict = NotesFolderIdentity.resolve(noteIdentifier: "a", folderPK: 2, noteAccountPK: 200, store: "store", folders: folders, accounts: accounts)
        #expect(conflict.id == "unresolved-source:a")
    }
    @Test func versionOneMigrationRetainsTextAndIndexWithoutGuessingAccounts() async throws {
        let fixture = try NotesDataFixture(schema: Self.versionOneSchema)
        try fixture.execute("INSERT INTO documents VALUES('notes:a','A','applenotes:note/a','工作','甲合同','hash',1),('notes:b','B','applenotes:note/b','工作','乙合同','hash',2); INSERT INTO chunks VALUES(11,'notes:a','甲合同'),(12,'notes:b','乙合同'); INSERT INTO chunks_fts(rowid,terms) VALUES(11,'甲 合同'),(12,'乙 合同');")
        let index = try KnowledgeIndex(path: fixture.url.path)
        let documents = try await index.documents()
        #expect(documents.count == 2)
        #expect(Set(documents.map(\.scopeID)).count == 2)
        #expect(documents.allSatisfy { $0.scopeID.hasPrefix("legacy-source:") })
        let first = try #require(documents.first)
        #expect(try await index.search("合同", collectionID: first.scopeID).map(\.documentID) == [first.id])
        #expect(try await index.search("合同", collectionID: "工作").isEmpty)
        #expect(try await index.search("合同", collectionID: nil).count == 2)
        #expect(Set(documents.map(\.text)) == ["甲合同", "乙合同"])
    }
    @Test func failedMigrationRollsBackColumnsAndVersion() {
        do {
            let fixture = try NotesDataFixture(schema: Self.versionOneSchema)
            try fixture.execute("ALTER TABLE documents ADD COLUMN collection_detail TEXT; INSERT INTO documents(id,title,locator,collection,body,content_hash,indexed_at) VALUES('notes:a','A','a','工作','keep me','hash',1);")
            #expect(throws: AIError.self) { try KnowledgeIndex(path: fixture.url.path) }
            var statement: OpaquePointer?
            #expect(sqlite3_prepare_v2(fixture.db, "SELECT body FROM documents", -1, &statement, nil) == SQLITE_OK)
            #expect(sqlite3_step(statement) == SQLITE_ROW)
            #expect(String(cString: sqlite3_column_text(statement, 0)) == "keep me")
            sqlite3_finalize(statement)
            #expect(sqlite3_prepare_v2(fixture.db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK)
            #expect(sqlite3_step(statement) == SQLITE_ROW); #expect(sqlite3_column_int(statement, 0) == 1); sqlite3_finalize(statement)
            #expect(sqlite3_prepare_v2(fixture.db, "SELECT collection_id FROM documents", -1, &statement, nil) != SQLITE_OK)
            sqlite3_finalize(statement)
        } catch { Issue.record(error) }
    }
    @Test func identicalLabelsAndFileSourcesHaveDistinctSelectableIDs() {
        let documents: [KnowledgeDocument] = [
            .init(id: "a", title: "A", locator: "", collection: "文件", text: "", indexedAt: 1, collectionID: "notes-a", collectionDetail: "iCloud"),
            .init(id: "b", title: "B", locator: "", collection: "文件", text: "", indexedAt: 1, collectionID: "notes-b", collectionDetail: "iCloud"),
            .init(id: "file:c", title: "C", locator: "", collection: "文件", text: "", indexedAt: 1, collectionID: KnowledgeCollectionIdentity.files, collectionDetail: "导入文件")
        ]
        let options = KnowledgeCollectionOption.options(documents)
        #expect(Set(options.map(\.id)).count == 3)
        #expect(Set(options.map(\.label)).count == 3)
    }
    static let versionOneSchema = """
    PRAGMA user_version=1;
    CREATE TABLE documents(id TEXT PRIMARY KEY,title TEXT NOT NULL,locator TEXT NOT NULL,collection TEXT NOT NULL,body TEXT NOT NULL,content_hash TEXT NOT NULL,indexed_at REAL NOT NULL);
    CREATE TABLE chunks(id INTEGER PRIMARY KEY,document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,body TEXT NOT NULL);
    CREATE VIRTUAL TABLE chunks_fts USING fts5(terms, tokenize='unicode61');
    """
}
