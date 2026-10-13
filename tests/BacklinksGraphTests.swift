import Foundation
import AppKit
import Testing
import SQLite3
@testable import Quillside

@MainActor
@Suite(.serialized)
final class BacklinksGraphTests {
    @Test
    func testUnknownIdentifierRequestsExactlyOneGraphRefresh() {
        #expect(BacklinksIdentifierRefreshPolicy.shouldRequestBuild(
                identifierFound: false,
                alreadyRequested: false
            ))
        #expect(!(BacklinksIdentifierRefreshPolicy.shouldRequestBuild(
                identifierFound: false,
                alreadyRequested: true
            )))
        #expect(!(BacklinksIdentifierRefreshPolicy.shouldRequestBuild(
                identifierFound: true,
                alreadyRequested: false
            )))
    }

    @Test
    func testStaleBacklinksBuildCannotCommitAfterInvalidation() {
        #expect(BacklinksBuildCommitPolicy.canCommit(
                buildGeneration: 3,
                currentGeneration: 3
            ))
        #expect(!(BacklinksBuildCommitPolicy.canCommit(
                buildGeneration: 3,
                currentGeneration: 4
            )))
    }

    @Test
    func testCurrentNoteTitleUpdatesWhenIdentifierDoesNotChange() {
        let viewModel = BacklinksPanelViewModel(service: BacklinksService(load: { .init(notes: [], links: []) }))
        viewModel.setCurrentNote(identifier: "same", title: "Old")
        viewModel.setCurrentNote(identifier: "same", title: "New")

        #expect(viewModel.currentNoteTitle == "New")
    }

    @Test
    func testVisiblePanelStartsResolutionWhenDatabaseBecomesAvailable() {
        var starts = 0
        var stops = 0

        BacklinksPanelAccessCoordinator.apply(
            status: .available,
            isVisible: true,
            start: { starts += 1 },
            stop: { stops += 1 }
        )

        #expect(starts == 1)
        #expect(stops == 0)
    }

    @Test
    func testVisiblePanelStopsResolutionWhenDatabaseAccessIsRevoked() {
        var starts = 0
        var stops = 0

        BacklinksPanelAccessCoordinator.apply(
            status: .permissionRequired,
            isVisible: true,
            start: { starts += 1 },
            stop: { stops += 1 }
        )

        #expect(starts == 0)
        #expect(stops == 1)
    }

    @Test
    func testHiddenPanelDoesNotStartOrStopResolution() {
        var effects = 0

        BacklinksPanelAccessCoordinator.apply(
            status: .available,
            isVisible: false,
            start: { effects += 1 },
            stop: { effects += 1 }
        )

        #expect(effects == 0)
    }

    @Test
    func testRequestGenerationRejectsStaleWork() {
        var generation = RequestGeneration()
        let first = generation.begin()
        let second = generation.begin()

        #expect(!(generation.isCurrent(first)))
        #expect(generation.isCurrent(second))
    }

    @Test
    func testReadsNativeLinkFromCompressedAppleNotesData() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        guard let database else {
            Issue.record("Could not create fixture database"); return
        }

        #expect(sqlite3_exec(
                database,
                """
                CREATE TABLE ZICCLOUDSYNCINGOBJECT (
                    Z_PK INTEGER PRIMARY KEY,
                    ZNOTE1 INTEGER,
                    ZTOKENCONTENTIDENTIFIER TEXT,
                    ZNOTEDATA INTEGER
                );
                CREATE TABLE ZICNOTEDATA (
                    Z_PK INTEGER PRIMARY KEY,
                    ZDATA BLOB
                );
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZNOTEDATA)
                VALUES (42, 7);
                INSERT INTO ZICCLOUDSYNCINGOBJECT (
                    Z_PK,
                    ZNOTE1,
                    ZTOKENCONTENTIDENTIFIER
                )
                VALUES (
                    43,
                    42,
                    'applenotes:note/11111111-2222-3333-4444-555555555555'
                );
                """,
                nil,
                nil,
                nil
            ) == SQLITE_OK)

        let compressedFixture = Data(
            base64Encoded:
                "H4sIAAAAAAAC/xNyE2CUchJiC0ksSk8t0bLgYPMySSwoyEnNyy9JLbYCkfoGhkbGJqZm5roWlo5Ous4urm66ICFdkBhICCQCAK385tlIAAAA"
        )!
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(
                database,
                "INSERT INTO ZICNOTEDATA (Z_PK, ZDATA) VALUES (7, ?)",
                -1,
                &statement,
                nil
            ) == SQLITE_OK)
        guard let statement else {
            Issue.record("Could not prepare fixture insert"); return
        }
        _ = compressedFixture.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), nil)
        }
        #expect(sqlite3_step(statement) == SQLITE_DONE)
        sqlite3_finalize(statement)
        sqlite3_close(database)

        let links = NotesDBReader(databasePath: databaseURL.path).getAllNoteLinks()

        #expect(links.count == 1)
        #expect(links.first?.noteId == 42)
        #expect(links.first?.linkedIdentifiers == [
                "01234567-89AB-CDEF-0123-456789ABCDEF",
                "11111111-2222-3333-4444-555555555555"
            ])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENNOTES_TEST_DB_PATH"] != nil))
    func testReadsBacklinksFromRealDatabaseSnapshotWhenProvided() throws {
        guard
            let databasePath = ProcessInfo.processInfo.environment[
                "OPENNOTES_TEST_DB_PATH"
            ]
        else {
            throw NSError(domain: "FixtureMissing", code: 1)
        }

        let reader = NotesDBReader(databasePath: databasePath)
        let snapshot = try reader.readBacklinksSnapshot()
        let notes = snapshot.notes
        let links = snapshot.links
        let graph = BacklinkGraphBuilder.build(notes: notes, links: links)
        let noteIDs = Set(notes.map(\.id))

        if let expected = ProcessInfo.processInfo.environment["OPENNOTES_EXPECT_EDGE"]?.split(separator: ","), expected.count == 2 {
            let source = try #require(notes.first { $0.identifier.uppercased() == expected[0].uppercased() })
            let target = try #require(notes.first { $0.identifier.uppercased() == expected[1].uppercased() })
            #expect(graph[source.id]?.contains(target.id) == true)
        }

        #expect(!(notes.isEmpty))
        #expect(snapshot.coverage.unreadableNotes == 0)
        #expect(links.allSatisfy {
                noteIDs.contains($0.noteId) && !$0.linkedIdentifiers.isEmpty
            })
        #expect(graph.keys.allSatisfy(noteIDs.contains))
        #expect(graph.allSatisfy { sourceID, targetIDs in
                targetIDs.allSatisfy {
                    noteIDs.contains($0) && $0 != sourceID
                }
            })

        if ProcessInfo.processInfo.environment[
            "OPENNOTES_REQUIRE_REAL_LINKS"
        ] == "1" {
            #expect(links.count >= 2)
            #expect(graph.count >= 2)
        }
    }

    @Test
    func testOmitsNotesWithoutNativeLinks() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        guard let database else {
            Issue.record("Could not create fixture database"); return
        }
        defer { sqlite3_close(database) }

        #expect(sqlite3_exec(
                database,
                """
                CREATE TABLE ZICCLOUDSYNCINGOBJECT (
                    Z_PK INTEGER PRIMARY KEY,
                    ZNOTE1 INTEGER,
                    ZTOKENCONTENTIDENTIFIER TEXT,
                    ZNOTEDATA INTEGER
                );
                CREATE TABLE ZICNOTEDATA (
                    Z_PK INTEGER PRIMARY KEY,
                    ZDATA BLOB
                );
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZNOTEDATA)
                VALUES (42, 7);
                INSERT INTO ZICNOTEDATA (Z_PK, ZDATA)
                VALUES (7, X'1F8B08');
                """,
                nil,
                nil,
                nil
            ) == SQLITE_OK)

        #expect(NotesDBReader(databasePath: databaseURL.path)
                .getAllNoteLinks()
                .isEmpty)
    }

    @Test
    func testOmitsNotesInRecentlyDeletedFolder() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        guard let database else {
            Issue.record("Could not create fixture database"); return
        }
        defer { sqlite3_close(database) }

        #expect(sqlite3_exec(
                database,
                """
                CREATE TABLE ZICCLOUDSYNCINGOBJECT (
                    Z_PK INTEGER PRIMARY KEY,
                    ZIDENTIFIER TEXT,
                    ZTITLE1 TEXT,
                    ZSNIPPET TEXT,
                    ZFOLDER INTEGER,
                    ZMODIFICATIONDATE1 REAL,
                    ZISPINNED INTEGER,
                    ZMARKEDFORDELETION INTEGER,
                    ZTITLE2 TEXT,
                    ZFOLDERTYPE INTEGER
                );
                INSERT INTO ZICCLOUDSYNCINGOBJECT (
                    Z_PK, ZTITLE2, ZFOLDERTYPE
                ) VALUES
                    (10, 'Notes', 0),
                    (11, 'Recently Deleted', 1);
                INSERT INTO ZICCLOUDSYNCINGOBJECT (
                    Z_PK, ZIDENTIFIER, ZTITLE1, ZSNIPPET, ZFOLDER,
                    ZMODIFICATIONDATE1, ZISPINNED, ZMARKEDFORDELETION
                ) VALUES
                    (20, 'active-id', 'Active', '', 10, 1, 0, 0),
                    (21, 'trash-id', 'Trash', '', 11, 2, 0, 0),
                    (22, 'deleted-id', 'Deleted', '', 10, 3, 0, 1);
                """,
                nil,
                nil,
                nil
            ) == SQLITE_OK)

        let notes = NotesDBReader(
            databasePath: databaseURL.path
        ).getAllNotes()

        #expect(notes.map(\.identifier) == ["active-id"])
    }

    @Test
    func testBuildsBacklinkFromSourceToTarget() {
        let source = note(id: 1, identifier: "source-id", title: "Source")
        let target = note(id: 2, identifier: "target-id", title: "Target")

        let graph = BacklinkGraphBuilder.build(
            notes: [source, target],
            links: [
                NotesDBReader.NoteLinkData(
                    noteId: source.id,
                    linkedIdentifiers: ["TARGET-ID"]
                )
            ]
        )

        #expect(graph[source.id] == [target.id])
        #expect(BacklinkGraphBuilder.sourceNoteIDs(linkingTo: target.id, in: graph) == [source.id])
    }

    @Test
    func testIgnoresSelfLinksAndUnknownTargets() {
        let source = note(id: 1, identifier: "source-id", title: "Source")

        let graph = BacklinkGraphBuilder.build(
            notes: [source],
            links: [
                NotesDBReader.NoteLinkData(
                    noteId: source.id,
                    linkedIdentifiers: ["SOURCE-ID", "missing-id"]
                )
            ]
        )

        #expect(graph.isEmpty)
    }

    @Test
    func testDuplicateIdentifiersDoNotCrashGraphBuild() {
        let first = note(id: 1, identifier: "duplicate-id", title: "First")
        let second = note(id: 2, identifier: "DUPLICATE-ID", title: "Second")
        let source = note(id: 3, identifier: "source-id", title: "Source")

        let graph = BacklinkGraphBuilder.build(
            notes: [first, second, source],
            links: [
                NotesDBReader.NoteLinkData(
                    noteId: source.id,
                    linkedIdentifiers: ["duplicate-id"]
                )
            ]
        )

        #expect(graph[source.id]?.count == 1)
    }

    @Test
    func testBuildsMultipleSourcesAndIgnoresMissingSource() {
        let firstSource = note(id: 1, identifier: "source-1", title: "First")
        let secondSource = note(id: 2, identifier: "source-2", title: "Second")
        let target = note(id: 3, identifier: "target-id", title: "Target")

        let graph = BacklinkGraphBuilder.build(
            notes: [firstSource, secondSource, target],
            links: [
                .init(noteId: firstSource.id, linkedIdentifiers: ["target-id"]),
                .init(noteId: secondSource.id, linkedIdentifiers: ["TARGET-ID"]),
                .init(noteId: 999, linkedIdentifiers: ["target-id"])
            ]
        )

        #expect(BacklinkGraphBuilder.sourceNoteIDs(linkingTo: target.id, in: graph) == [firstSource.id, secondSource.id])
        #expect(graph[999] == nil)
    }

    @Test
    func testMalformedCompressedDataProducesNoLinks() {
        #expect(AppleNotesProtobufLinkParser.identifiers(
                inCompressedNoteData: Data([0x1f, 0x8b, 0x08])
            ) == [])
    }

    @Test
    func testBuildsAppleNotesJumpURL() {
        #expect(NotesDBReader.shared.buildNoteURL(identifier: "target-id") == "applenotes:note/target-id")
    }

    private func note(
        id: Int64,
        identifier: String,
        title: String
    ) -> NotesDBReader.NoteInfo {
        NotesDBReader.NoteInfo(
            id: id,
            identifier: identifier,
            title: title,
            snippet: "",
            folderName: "Notes",
            modificationDate: .distantPast,
            isPinned: false
        )
    }
}
