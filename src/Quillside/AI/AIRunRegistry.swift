import AppKit
import Combine

enum AIRunStopReason {
    case user, leftNote, timeout, sleep, shutdown
    var message: String {
        switch self {
        case .user: return "已停止 AI 请求，笔记未改变。"
        case .leftNote: return "已离开原笔记，AI 请求已停止；批注和上一稿已保留。"
        case .timeout: return "本轮 AI 已超时并停止；已有内容保留，可主动重新开始。"
        case .sleep: return "电脑休眠或用户会话已离开，AI 请求已停止。"
        case .shutdown: return "应用退出，AI 请求已停止。"
        }
    }
}

/// Tracks active work only, never remote conversation IDs or document contents.
/// Restoring a local draft does not register a run or reconnect to a provider.
@MainActor final class AIRunRegistry: ObservableObject {
    static let shared = AIRunRegistry()
    nonisolated static let quickLimit: TimeInterval = 300
    nonisolated static let revisionLimit: TimeInterval = 600
    @Published private(set) var activeCount = 0
    private struct Entry {
        let cancel: (AIRunStopReason) -> Void
        let deadline: Task<Void, Never>
    }
    private var entries: [UUID: Entry] = [:]
    private var observers: [NSObjectProtocol] = []
    private let center: NotificationCenter

    init(observeSystem: Bool = true, center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.center = center
        if observeSystem {
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.cancelAll(reason: .sleep) }
                })
            }
        }
    }
    deinit {
        for observer in observers { center.removeObserver(observer) }
        for entry in entries.values { entry.deadline.cancel() }
    }

    func begin(timeout: TimeInterval, cancel: @escaping (AIRunStopReason) -> Void) -> UUID {
        let id = UUID()
        let deadline = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeout))
                try Task.checkCancellation()
                self?.cancel(id, reason: .timeout)
            } catch { }
        }
        entries[id] = Entry(cancel: cancel, deadline: deadline)
        activeCount = entries.count
        return id
    }
    func finish(_ id: UUID?) {
        guard let id, let entry = entries.removeValue(forKey: id) else { return }
        entry.deadline.cancel(); activeCount = entries.count
    }
    func cancel(_ id: UUID, reason: AIRunStopReason) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.deadline.cancel(); activeCount = entries.count
        entry.cancel(reason)
    }
    func cancelAll(reason: AIRunStopReason = .user) {
        for id in Array(entries.keys) { cancel(id, reason: reason) }
    }
}
