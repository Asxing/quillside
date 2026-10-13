import Foundation
import SQLite3
import zlib
@testable import Quillside

final class NotesDataFixture {
    let directory: URL
    let url: URL
    var db: OpaquePointer?
    init(schema: String = NotesDataFixture.schema) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Quillside-data-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("fixture.sqlite")
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw AIError.message("fixture open failed") }
        try execute(schema)
    }
    deinit { sqlite3_close(db); try? FileManager.default.removeItem(at: directory) }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw AIError.message("fixture SQL failed") }
    }
    func blob(_ data: Data, pk: Int) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO ZICNOTEDATA(Z_PK,ZDATA) VALUES(?,?)", -1, &statement, nil) == SQLITE_OK else { throw AIError.message("fixture prepare failed") }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(pk))
        _ = data.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AIError.message("fixture bind failed") }
    }
    static let schema = """
    PRAGMA journal_mode=WAL;
    CREATE TABLE Z_METADATA(Z_UUID TEXT); INSERT INTO Z_METADATA VALUES('fixture-store');
    CREATE TABLE Z_PRIMARYKEY(Z_ENT INTEGER,Z_NAME TEXT);
    INSERT INTO Z_PRIMARYKEY VALUES(1,'ICNote'),(2,'ICFolder'),(3,'ICAccount');
    CREATE TABLE ZICCLOUDSYNCINGOBJECT(Z_PK INTEGER PRIMARY KEY,Z_ENT INTEGER,ZIDENTIFIER TEXT,ZTITLE1 TEXT,ZTITLE2 TEXT,ZNAME TEXT,ZFOLDER INTEGER,ZNOTEDATA INTEGER,ZMODIFICATIONDATE1 REAL DEFAULT 0,ZMARKEDFORDELETION INTEGER DEFAULT 0,ZFOLDERTYPE INTEGER DEFAULT 0,ZISPINNED INTEGER DEFAULT 0,ZSNIPPET TEXT,ZISPASSWORDPROTECTED INTEGER DEFAULT 0,ZOWNER INTEGER,ZPARENT INTEGER,ZACCOUNT7 INTEGER,ZNOTE1 INTEGER,ZNOTE INTEGER,ZTYPEUTI1 TEXT,ZTOKENCONTENTIDENTIFIER TEXT,ZURLSTRING TEXT);
    CREATE TABLE ZICNOTEDATA(Z_PK INTEGER PRIMARY KEY,ZDATA BLOB);
    INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,Z_ENT,ZIDENTIFIER,ZNAME) VALUES(100,3,'account-a','账户 A'),(200,3,'account-b','账户 B');
    INSERT INTO ZICCLOUDSYNCINGOBJECT(Z_PK,Z_ENT,ZIDENTIFIER,ZTITLE2,ZOWNER) VALUES(10,2,'folder-a','工作',100),(20,2,'folder-b','工作',200);
    """
    static func field(_ number: UInt8, _ content: Data) -> Data {
        var result = Data([number << 3 | 2]); result.append(varint(content.count)); result.append(content); return result
    }
    static func varint(_ value: Int) -> Data {
        var value = value, bytes: [UInt8] = []
        repeat { let byte = UInt8(value & 127); value >>= 7; bytes.append(byte | (value == 0 ? 0 : 128)) } while value != 0
        return Data(bytes)
    }
    static func compressed(_ data: Data) throws -> Data {
        var count = compressBound(uLong(data.count))
        var buffer = [UInt8](repeating: 0, count: Int(count))
        let result = data.withUnsafeBytes { bytes in compress2(&buffer, &count, bytes.bindMemory(to: UInt8.self).baseAddress, uLong(data.count), Z_DEFAULT_COMPRESSION) }
        guard result == Z_OK else { throw AIError.message("fixture compression failed") }
        return Data(buffer.prefix(Int(count)))
    }
    static func body(_ text: String, link: String? = nil) throws -> Data {
        var note = field(2, Data(text.utf8))
        if let link {
            var run = Data([8]); run.append(varint((text as NSString).length)); run.append(field(9, Data(link.utf8)))
            note.append(field(5, run))
        }
        return try compressed(field(2, field(3, note)))
    }
    static func attachmentBody(_ id: String, type: String = "com.apple.notes.inlinetextattachment.link") throws -> Data {
        var run = Data([8,1])
        run.append(field(12, field(1, Data(id.utf8)) + field(2, Data(type.utf8))))
        return try compressed(field(2, field(3, field(2, Data("\u{FFFC}".utf8)) + field(5, run))))
    }
}
