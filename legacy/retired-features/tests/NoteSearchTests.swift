import Foundation
import SQLite3
import Testing
@testable import OpenNotes

@MainActor @Suite(.serialized) struct NoteSearchTests {
    private func note(_ id: String, _ title: String, snippet: String = "", folder: String = "工作", pinned: Bool = false, time: Double = 0) -> NotesDBReader.NoteInfo {
        .init(id: 1, identifier: id, title: title, snippet: snippet, folderName: folder, modificationDate: Date(timeIntervalSince1970: time), isPinned: pinned)
    }
    @Test func titleMatchesWinOverPinnedRecentSnippetMatches() {
        let notes = [note("2", "Memo", snippet: "合同", pinned: true, time: 99), note("1", "合同", time: 0), note("3", "合同审批", time: 100)]
        #expect(NoteSearchRanking.results(notes, query: "合同").map(\.identifier) == ["1", "3", "2"])
        #expect(NoteSearchRanking.results([note("4", "Résumé")], query: "resume").count == 1)
        #expect(NoteSearchRanking.results([note("5", "会议", snippet: "合同审批")], query: "会议 合同").count == 1)
    }
    @Test func keyboardSelectionOpensOnlyTheCurrentMatchingIdentity() async throws {
        var opened: [String] = []
        let model = NoteSearchModel(load: { [self.note("a", "Alpha"), self.note("b", "Beta")] }, open: { opened.append($0); return true })
        model.reload()
        try await wait { !model.loading }
        #expect(model.selectedID == "a")
        model.move(1); model.submit()
        #expect(opened == ["b"])
        model.query = "not present"; model.submit()
        #expect(opened == ["b"])
        #expect(model.selectedID == nil)
    }
    @Test func readingErrorIsDistinctFromNoMatches() async throws {
        let model = NoteSearchModel(load: { throw NotesSearchReadFailure.schema }, open: { _ in Issue.record("Should not open on read failure"); return false })
        model.reload(); try await wait { !model.loading }
        #expect(model.error != nil)
        #expect(!model.needsPermission)
        #expect(model.results.isEmpty)
        model.submit()
    }
    @Test func cancelledOldLoadCannotReplaceNewResults() async throws {
        var continuations: [CheckedContinuation<[NotesDBReader.NoteInfo], Error>] = []
        let model = NoteSearchModel(load: { try await withCheckedThrowingContinuation { continuations.append($0) } }, open: { _ in true })
        model.reload(); try await wait { continuations.count == 1 }
        model.reload(); try await wait { continuations.count == 2 }
        continuations[1].resume(returning: [note("new", "New")]); try await wait { !model.loading }
        continuations[0].resume(returning: [note("old", "Old")])
        try await Task.sleep(nanoseconds: 5_000_000)
        #expect(model.results.map(\.identifier) == ["new"])
    }
    @Test func databaseSearchHidesLockedSnippetsAndRejectsUnknownSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenNotes-search-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Notes.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TABLE ZICCLOUDSYNCINGOBJECT(Z_PK INTEGER PRIMARY KEY,ZIDENTIFIER TEXT,ZTITLE1 TEXT,ZTITLE2 TEXT,ZFOLDER INTEGER,ZMODIFICATIONDATE1 REAL,ZMARKEDFORDELETION INTEGER,ZFOLDERTYPE INTEGER,ZSNIPPET TEXT,ZISPASSWORDPROTECTED INTEGER); INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,ZIDENTIFIER,ZTITLE1,ZSNIPPET,ZISPASSWORDPROTECTED) VALUES(1,'fixture','Locked','secret fixture',1);", nil, nil, nil) == SQLITE_OK)
        let reader = NotesDBReader(databasePath: file.path)
        #expect(try reader.readAllNotes().first?.snippet == "")
        reader.close()
        #expect(sqlite3_exec(db, "ALTER TABLE ZICCLOUDSYNCINGOBJECT RENAME COLUMN ZIDENTIFIER TO UNKNOWN_COLUMN", nil, nil, nil) == SQLITE_OK)
        #expect(throws: NotesSearchReadFailure.self) { try reader.readAllNotes() }
    }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 { if predicate() { return }; try await Task.sleep(nanoseconds: 1_000_000) }
        #expect(predicate())
    }
}
