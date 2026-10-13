import Foundation
import AppKit
import SQLite3
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class NotesDatabaseAccessTests {
    @Test
    func testOnboardingDatabaseActionsMatchObservedStatus() {
        #expect(OnboardingDatabaseAction(status: .checking) == .checking)
        #expect(OnboardingDatabaseAction(status: .permissionRequired) == .openFullDiskAccess)
        #expect(OnboardingDatabaseAction(
                status: .unavailable(.databaseMissing)
            ) == .openNotes)
        #expect(OnboardingDatabaseAction(
                status: .unavailable(.openFailed(SQLITE_CANTOPEN))
            ) == .retry)
        #expect(OnboardingDatabaseAction(status: .available) == .ready)
    }

    @Test
    func testReadableSQLiteDatabaseIsAvailable() throws {
        let databaseURL = try makeSQLiteDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let status = NotesDBReader(databasePath: databaseURL.path).accessStatus()

        #expect(status == .available)
    }

    @Test
    func testMissingDatabaseIsReportedAsUnavailable() {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        let status = NotesDBReader(databasePath: databaseURL.path).accessStatus()

        #expect(status == .unavailable(.databaseMissing))
    }

    @Test
    func testProtectedDatabaseHiddenByTCCRequiresPermission() throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: containerURL.path
            )
            try? FileManager.default.removeItem(at: containerURL)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: containerURL.path
        )
        let databaseURL = containerURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        let status = NotesDBReader(
            databasePath: databaseURL.path,
            permissionProtectedContainerPath: containerURL.path
        ).accessStatus()

        #expect(status == .permissionRequired)
    }

    @Test
    func testReadableProtectedContainerWithoutDatabaseReportsMissing() throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let status = NotesDBReader(
            databasePath: containerURL.appendingPathComponent("NoteStore.sqlite").path,
            permissionProtectedContainerPath: containerURL.path
        ).accessStatus()

        #expect(status == .unavailable(.databaseMissing))
    }

    @Test
    func testMissingProtectedContainerReportsDatabaseMissing() {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let status = NotesDBReader(
            databasePath: containerURL.appendingPathComponent("NoteStore.sqlite").path,
            permissionProtectedContainerPath: containerURL.path
        ).accessStatus()

        #expect(status == .unavailable(.databaseMissing))
    }

    @Test
    func testUnreadableDatabaseRequiresPermission() throws {
        let databaseURL = try makeSQLiteDatabase()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: databaseURL.path
            )
            try? FileManager.default.removeItem(at: databaseURL)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: databaseURL.path
        )

        let status = NotesDBReader(databasePath: databaseURL.path).accessStatus()

        #expect(status == .permissionRequired)
    }

    @Test
    func testDatabaseOpenFailureIsReportedAsUnavailable() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let status = NotesDBReader(databasePath: directoryURL.path).accessStatus()

        guard case .unavailable(.openFailed) = status else {
            Issue.record("Expected an open failure, got \(status)"); return
        }
    }

    @Test
    func testAccessStatusRechecksPermissionsAfterDatabaseWasOpened() throws {
        let databaseURL = try makeSQLiteDatabase()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: databaseURL.path
            )
            try? FileManager.default.removeItem(at: databaseURL)
        }
        let reader = NotesDBReader(databasePath: databaseURL.path)
        #expect(reader.open())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: databaseURL.path
        )

        #expect(reader.accessStatus() == .permissionRequired)
    }

    private func makeSQLiteDatabase() throws -> URL {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        guard let database else {
            throw NSError(domain: "NotesDatabaseAccessTests", code: 1)
        }
        sqlite3_close(database)
        return databaseURL
    }
}

@MainActor
final class AppStatePermissionTests {
    @Test
    func testStatusPrioritizesAccessibilityPermission() {
        let appState = AppState()
        appState.hasAccessibilityPermission = false
        appState.notesDatabaseAccess = .permissionRequired

        #expect(appState.statusDescription == "需要辅助功能权限")
    }

    @Test
    func testStatusExplainsBacklinksPermissionWhenAccessibilityIsReady() {
        let appState = AppState()
        appState.hasAccessibilityPermission = true
        appState.notesDatabaseAccess = .permissionRequired

        #expect(appState.statusDescription == "笔记链接与 Backlinks 需要完全磁盘访问")
        #expect(!(appState.canUseBacklinks))
    }

    @Test
    func testBacklinksBecomeAvailableWhenDatabaseCanBeRead() {
        let appState = AppState()
        appState.hasAccessibilityPermission = true
        appState.notesDatabaseAccess = .available

        #expect(appState.canUseBacklinks)
    }

    @Test
    func testDatabaseTransitionDetectsPermissionBecomingAvailable() {
        #expect(NotesDatabaseAccessTransition(
                from: .permissionRequired,
                to: .available
            ) == .becameAvailable)
    }

    @Test
    func testDatabaseTransitionDetectsPermissionBeingRevoked() {
        #expect(NotesDatabaseAccessTransition(
                from: .available,
                to: .permissionRequired
            ) == .becameUnavailable)
    }

    @Test
    func testDatabaseTransitionIgnoresUnchangedStatus() {
        #expect(NotesDatabaseAccessTransition(from: .available, to: .available) == .unchanged)
    }
}
