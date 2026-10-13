import Foundation
import Testing
@testable import Quillside

@MainActor @Suite(.serialized) struct AuthorizedCredentialReaderTests {
    @Test func authorizationRunsOffMainAndIsReusedByAllRevisionStages() async throws {
        var reads = 0
        let reader = AuthorizedCredentialReader { _, allowed in
            #expect(!Thread.isMainThread)
            reads += 1
            guard allowed else { throw AIError.message("requires confirmation") }
            return "synthetic-secret"
        }
        let id = UUID()
        #expect(try await reader.read(id, allowAuthentication: true) == "synthetic-secret")
        for _ in 0..<4 {
            #expect(try await reader.read(id, allowAuthentication: false) == "synthetic-secret")
        }
        #expect(reads == 1)
    }

    @Test func invalidationDoesNotReuseAChangedOrDeletedKey() async throws {
        var reads = 0
        let reader = AuthorizedCredentialReader { _, _ in reads += 1; return "key-\(reads)" }
        let id = UUID()
        #expect(try await reader.read(id, allowAuthentication: true) == "key-1")
        reader.invalidate(id)
        #expect(try await reader.read(id, allowAuthentication: false) == "key-2")
        #expect(reads == 2)
    }

    @Test func denialIsNotCachedAndCredentialsNeverCrossConnectionIDs() async throws {
        let permitted = UUID()
        let reader = AuthorizedCredentialReader { id, allowed in
            guard allowed else { throw AIError.message("requires confirmation") }
            return id.uuidString
        }
        await #expect(throws: (any Error).self) { try await reader.read(permitted, allowAuthentication: false) }
        #expect(try await reader.read(permitted, allowAuthentication: true) == permitted.uuidString)
        await #expect(throws: (any Error).self) { try await reader.read(UUID(), allowAuthentication: false) }
    }

    @Test func pendingSystemPromptLeavesMainActorFreeAndCannotRestoreDeletedSecret() async throws {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let reader = AuthorizedCredentialReader { _, _ in
            entered.signal()
            guard release.wait(timeout: .now() + 2) == .success else { throw AIError.message("main actor was blocked") }
            return "stale-secret"
        }
        let id = UUID()
        let pending = Task { try await reader.read(id, allowAuthentication: true) }
        for _ in 0..<100 {
            if entered.wait(timeout: .now()) == .success { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        reader.invalidate(id)
        release.signal()
        await #expect(throws: CancellationError.self) { try await pending.value }
    }

    @Test func cancelledRequestDoesNotContinueToModelAfterAuthorization() async throws {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let reader = AuthorizedCredentialReader { _, _ in
            entered.signal(); _ = release.wait(timeout: .now() + 2)
            return "synthetic-secret"
        }
        var modelRequests = 0
        let pending = Task {
            _ = try await reader.read(UUID(), allowAuthentication: true)
            modelRequests += 1
        }
        for _ in 0..<100 {
            if entered.wait(timeout: .now()) == .success { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        pending.cancel(); release.signal()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(modelRequests == 0)
    }
}
