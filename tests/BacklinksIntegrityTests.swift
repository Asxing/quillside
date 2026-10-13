import Foundation
import Testing
@testable import Quillside

@MainActor @Suite(.serialized) struct BacklinksIntegrityTests {
    let targetA = "11111111-2222-3333-4444-555555555555"
    let targetB = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    private func seed(_ fixture: NotesDataFixture) throws {
        try fixture.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,Z_ENT,ZIDENTIFIER,ZTITLE1,ZFOLDER,ZNOTEDATA) VALUES(1,1,'source','Before',10,1001),(2,1,'\(targetA)','Target A',10,1002);")
        try fixture.blob(NotesDataFixture.body("source", link: "notes://showNote?identifier=" + targetA), pk: 1001)
        try fixture.blob(NotesDataFixture.body("target"), pk: 1002)
    }
    @Test func metadataAndBodyComeFromOneWALSnapshot() throws {
        let fixture = try NotesDataFixture(); try seed(fixture)
        var changed = false, writerError: Error?
        let reader = NotesDBReader(databasePath: fixture.url.path, snapshotObserver: {
            guard !changed else { return }; changed = true
            do {
                try fixture.execute("UPDATE ZICCLOUDSYNCINGOBJECT SET ZTITLE1='After' WHERE Z_PK=1; INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,Z_ENT,ZIDENTIFIER,ZTITLE1,ZFOLDER,ZNOTEDATA) VALUES(3,1,'\(targetB)','Target B',10,1003);")
                try fixture.blob(NotesDataFixture.body("new source", link: "applenotes:note/" + targetB), pk: 1001)
                try fixture.blob(NotesDataFixture.body("target b"), pk: 1003)
            } catch { writerError = error }
        })
        let before = try reader.readBacklinksSnapshot()
        #expect(writerError == nil)
        #expect(before.notes.first(where: { $0.id == 1 })?.title == "Before")
        #expect(before.links.first(where: { $0.noteId == 1 })?.linkedIdentifiers == [targetA])
        #expect(!before.notes.contains(where: { $0.id == 3 }))
        let after = try reader.readBacklinksSnapshot()
        #expect(after.notes.first(where: { $0.id == 1 })?.title == "After")
        #expect(after.links.first(where: { $0.noteId == 1 })?.linkedIdentifiers == [targetB])
    }
    @Test func orphanedAttachmentRowsDoNotCreatePhantomBacklinks() throws {
        let fixture = try NotesDataFixture(); try seed(fixture)
        try fixture.blob(NotesDataFixture.body("no links"), pk: 1001)
        try fixture.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,ZIDENTIFIER,ZNOTE1,ZTYPEUTI1,ZTOKENCONTENTIDENTIFIER) VALUES(50,'link-marker',1,'com.apple.notes.inlinetextattachment.link','applenotes:note/\(targetA)');")
        let reader = NotesDBReader(databasePath: fixture.url.path)
        #expect(try reader.readBacklinksSnapshot().links.isEmpty)
        try fixture.blob(NotesDataFixture.attachmentBody("link-marker"), pk: 1001)
        #expect(try reader.readBacklinksSnapshot().links.first?.linkedIdentifiers == [targetA])
        try fixture.execute("UPDATE ZICCLOUDSYNCINGOBJECT SET ZMARKEDFORDELETION=1 WHERE Z_PK=50")
        let deleted = try reader.readBacklinksSnapshot()
        #expect(deleted.links.isEmpty)
        #expect(deleted.coverage.unresolvedLinks == 1)
    }
    @Test func unreadableLockedAndComplexBodiesAreExplicitlyPartial() throws {
        let fixture = try NotesDataFixture(); try seed(fixture)
        try fixture.execute("INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,Z_ENT,ZIDENTIFIER,ZTITLE1,ZFOLDER,ZNOTEDATA,ZISPASSWORDPROTECTED) VALUES(3,1,'bad','Bad',10,1003,0),(4,1,'locked','Locked',10,1004,1),(5,1,'table','Table',10,1005,0);")
        try fixture.blob(Data([0x1f,0x8b,0x08]), pk: 1003)
        try fixture.blob(NotesDataFixture.attachmentBody("table-marker", type: "com.apple.notes.table"), pk: 1005)
        let snapshot = try NotesDBReader(databasePath: fixture.url.path).readBacklinksSnapshot()
        #expect(!snapshot.coverage.complete)
        #expect(snapshot.coverage.unreadableNotes == 1)
        #expect(snapshot.coverage.lockedNotes == 1)
        #expect(snapshot.coverage.complexContainers == 1)
        #expect(snapshot.links.first?.linkedIdentifiers == [targetA])
    }
    @Test func schemaFailureCannotMasqueradeAsEmptySnapshot() throws {
        let fixture = try NotesDataFixture(); try seed(fixture)
        try fixture.execute("DROP TABLE ZICNOTEDATA")
        #expect(throws: NotesReadFailure.self) { try NotesDBReader(databasePath: fixture.url.path).readBacklinksSnapshot() }
    }
    @Test func realNativeSchemesAreParsedButWebRedirectsAreNotBacklinks() {
        #expect(NativeNoteLinkParser.identifiers(in: "notes://showNote?owner=fixture&identifier=" + targetA) == [targetA])
        #expect(NativeNoteLinkParser.identifiers(in: "https://example.invalid/?next=notes://showNote?identifier=" + targetA).isEmpty)
        #expect(NativeNoteLinkParser.identifiers(in: "notes://showNote?identifier=bad&identifier=" + targetA).isEmpty)
    }
    @Test func unknownNoteFormatIsNotAcceptedAsAnEmptyNote() throws {
        let unknown = try NotesDataFixture.compressed(Data([8,1]))
        #expect(throws: AppleNotesNoteDecodingError.self) { try AppleNotesNoteProtoDecoder().decodeDocument(from: unknown) }
        #expect(try AppleNotesNoteProtoDecoder().decodeDocument(from: NotesDataFixture.body("")).noteText.isEmpty)
    }
}
