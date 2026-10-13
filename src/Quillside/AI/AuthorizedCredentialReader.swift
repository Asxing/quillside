import Foundation

/// Owns credentials authorized for this process only. No disk cache or ACL changes.
final class AuthorizedCredentialReader: @unchecked Sendable {
    private let load: (UUID, Bool) throws -> String
    private let queue = DispatchQueue(label: "com.opennotes.credentials", qos: .userInitiated)
    private let lock = NSLock()
    private var cached: [UUID: String] = [:]
    private var revisions: [UUID: Int] = [:]
    init(load: @escaping (UUID, Bool) throws -> String) { self.load = load }

    @MainActor func read(_ id: UUID, allowAuthentication: Bool) async throws -> String {
        try Task.checkCancellation()
        let revision = withLock { revisions[id, default: 0] }
        let value: String = try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                continuation.resume(with: Result {
                    let existing = try withLock {
                        guard revisions[id, default: 0] == revision else { throw CancellationError() }
                        return cached[id]
                    }
                    if let existing { return existing }
                    let value = try load(id, allowAuthentication)
                    try withLock {
                        // A deleted or replaced credential must not be resurrected by
                        // a delayed system authentication response.
                        guard revisions[id, default: 0] == revision else { throw CancellationError() }
                        if !value.isEmpty { cached[id] = value }
                    }
                    return value
                })
            }
        }
        try Task.checkCancellation()
        return value
    }
    func invalidate(_ id: UUID) {
        withLock { cached.removeValue(forKey: id); revisions[id, default: 0] += 1 }
    }
    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try operation()
    }
}
