import AppKit
import Combine
import ApplicationServices

/// All input features share one bounded query. Ordinary prose never needs the
/// whole note; full snapshots are reserved for a possible command and writing.
enum EditorInputProbe {
    static let limit = 192
    static func needsSnapshot(prefix: String, startsAtDocumentBeginning: Bool) -> Bool {
        let text = prefix as NSString
        let caret = text.length
        // Do not mistake a truncated word for the start of a slash token.
        let candidates = [prefix, prefix.last.map { "\n\t ".contains($0) } == true ? String(prefix.dropLast()) : prefix]
        for candidate in candidates {
            if let token = SlashInputContext.token(body: candidate, caret: (candidate as NSString).length),
               startsAtDocumentBeginning || (candidate as NSString).length > (token as NSString).length { return true }
        }
        let line = prefix.components(separatedBy: "\n").last ?? ""
        guard !line.isEmpty, startsAtDocumentBeginning || prefix.contains("\n") else { return false }
        return caret > 0 && MarkdownTriggerDefinition.all.contains { $0.pattern.hasPrefix(line) || $0.pattern == line }
    }
}

/// A slow AX call may finish after more keystrokes arrive. Keep one pending
/// refresh, not one queued whole-note read per keystroke.
final class CoalescedObservation<Value> {
    private var running = false
    private var pending = false
    private var epoch = 0
    private let schedule: (@escaping () -> Void) -> Void
    private let read: (@escaping (Value) -> Void) -> Void
    private let deliver: (Value) -> Void
    init(schedule: @escaping (@escaping () -> Void) -> Void,
         read: @escaping (@escaping (Value) -> Void) -> Void, deliver: @escaping (Value) -> Void) {
        self.schedule = schedule; self.read = read; self.deliver = deliver
    }
    func request() {
        if running { pending = true; return }
        running = true
        let captured = epoch
        schedule { [weak self] in
            guard let self, self.epoch == captured else { return }
            self.read { [weak self] value in
                guard let self, self.epoch == captured else { return }
                self.deliver(value)
                self.running = false
                if self.pending { self.pending = false; self.request() }
            }
        }
    }
    func cancel() { epoch += 1; running = false; pending = false }
}

final class EditorInputObserver {
    let changes = PassthroughSubject<NotesEditorContext?, Never>()
    private let queue = DispatchQueue(label: "com.opennotes.editor-input", qos: .userInitiated)
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var lastElement: AXUIElement?
    private var lastRange: NSRange?
    private var lastPrefix: String?
    private var lastContext: NotesEditorContext?
    private var foreground = false
    private var revision = 0
    private var loadedRevision = -1
    private lazy var pump = CoalescedObservation<NotesEditorContext?>(
        schedule: { DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: $0) },
        read: { [weak self] done in
            guard let self else { done(nil); return }
            let revision = self.revision
            self.queue.async {
                if self.loadedRevision != revision { self.lastPrefix = nil; self.loadedRevision = revision }
                let context = self.readCandidate()
                DispatchQueue.main.async { done(context) }
            }
        }, deliver: { [weak self] in self?.changes.send($0) })

    init(tracker: WindowTrackService, keyboard: KeyboardMonitorService) {
        tracker.$isNotesFrontmost.removeDuplicates().sink { [weak self] active in
            self?.foreground = active
            if active { self?.request(changed: true) } else { self?.pump.cancel(); self?.changes.send(nil) }
        }.store(in: &subscriptions)
        tracker.eventSubject.filter { [.selectionChanged, .focusedElementChanged, .focusedWindowChanged].contains($0) }
            .sink { [weak self] _ in self?.request(changed: true) }.store(in: &subscriptions)
        keyboard.keyPressSubject.sink { [weak self] _ in self?.request(changed: true) }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: InlineInteractionGate.changed)
            .sink { [weak self] _ in self?.request(changed: true) }.store(in: &subscriptions)
        // Recovery for apps/assistive input that miss AX notifications. This
        // reads at most 192 characters off the main thread, never an idle body.
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.request() }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    deinit { timer?.invalidate() }
    func request(changed: Bool = false) {
        if changed { revision += 1 }
        guard foreground, !InlineInteractionGate.shared.isActive,
              EditorFeaturePreferences.enabled("slash") || EditorFeaturePreferences.enabled("markdown") else {
            pump.cancel(); changes.send(nil); return
        }
        pump.request()
    }
    private func readCandidate() -> NotesEditorContext? {
        guard let focus = NotesEditorFocus.read(), focus.scope == .body,
              focus.selection.length == 0 else { lastContext = nil; lastPrefix = nil; return nil }
        let caret = focus.selection.location, start = max(0, caret - EditorInputProbe.limit)
        var range = CFRange(location: start, length: caret - start)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(focus.element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
              let prefix = value as? String else { return nil }
        if let previous = lastElement, CFEqual(previous, focus.element), lastRange == focus.selection, lastPrefix == prefix { return lastContext }
        lastElement = focus.element; lastRange = focus.selection; lastPrefix = prefix
        guard EditorInputProbe.needsSnapshot(prefix: prefix, startsAtDocumentBeginning: start == 0) else { lastContext = nil; return nil }
        lastContext = NotesEditorContext.read()
        return lastContext
    }
}
