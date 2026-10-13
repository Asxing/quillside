import Foundation

struct ModelRequestLimits {
    var idle: TimeInterval = 90
    var total: TimeInterval = 240
}

/// Cancels the transport even while AsyncBytes is waiting for another byte.
/// SSE keepalives do not extend the progress deadline; progress cannot extend
/// the absolute deadline. One URLSession belongs to exactly one request.
final class ModelRequestLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private let session: URLSession
    private let limits: ModelRequestLimits
    private let started = ProcessInfo.processInfo.systemUptime
    private var lastProgress = ProcessInfo.processInfo.systemUptime
    private var ended = false
    private var failure: String?
    private let timer: DispatchSourceTimer

    init(session: URLSession, limits: ModelRequestLimits) {
        self.session = session; self.limits = limits
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let interval = max(0.01, min(1, min(limits.idle, limits.total) / 4))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.checkDeadline() }
        timer.resume()
    }
    func progressed() {
        lock.lock(); defer { lock.unlock() }
        if !ended { lastProgress = ProcessInfo.processInfo.systemUptime }
    }
    var timeoutMessage: String? {
        lock.lock(); defer { lock.unlock() }; return failure
    }
    func check() throws {
        checkDeadline()
        if let message = timeoutMessage { throw AIError.message(message) }
    }
    func cancel() { end() }
    func finish() { end() }
    private func end() {
        lock.lock()
        let wasActive = !ended; ended = true
        lock.unlock()
        if wasActive { timer.cancel(); session.invalidateAndCancel() }
    }
    private func checkDeadline() {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        if !ended {
            if now - started >= limits.total { failure = "本次模型请求超过时限，已断开连接；已有内容保留。" }
            else if now - lastProgress >= limits.idle { failure = "模型长时间没有返回有效进展，已断开连接；已有内容保留。" }
        }
        let expired = !ended && failure != nil
        if expired { ended = true }
        lock.unlock()
        if expired { timer.cancel(); session.invalidateAndCancel() }
    }
}
