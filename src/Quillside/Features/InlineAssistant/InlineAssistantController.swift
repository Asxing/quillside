import AppKit
import SwiftUI
import ApplicationServices
import Combine

/// A nonactivating panel can own keyboard focus while Notes stays the frontmost app.
/// The event tap must not interpret typing in that panel as note-editing commands.
enum InlinePanelOwner: Hashable { case ai, templates, backlinks, revision, notesComment, notesComposer }
enum InlineEventOrder {
    static func belongsToPresentation(eventTime: TimeInterval, openedAt: TimeInterval,
                                      eventSession: UUID, currentSession: UUID) -> Bool {
        eventSession == currentSession && eventTime >= openedAt
    }
}
final class InlineInteractionGate {
    static let shared = InlineInteractionGate()
    static let changed = Notification.Name("Quillside.inlineInteractionChanged")
    private let lock = NSLock()
    private var owners = Set<InlinePanelOwner>()
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return !owners.isEmpty }
    func setActive(_ value: Bool, owner: InlinePanelOwner) {
        lock.lock(); if value { owners.insert(owner) } else { owners.remove(owner) }; lock.unlock()
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

class NotesInlinePanel: NSPanel {
    var onCancel: (() -> Void)?
    var onAppSwitch: (() -> Void)?
    private var appObserver: NSObjectProtocol?
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.isVisible,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != AppleNotesTarget.bundleIdentifier, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            if let onAppSwitch = self.onAppSwitch { onAppSwitch() } else { self.onCancel?() }
        }
    }
    deinit { if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) } }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) {
        if let editor = firstResponder as? NSTextView, editor.hasMarkedText() { return }
        onCancel?()
    }
}

enum InlinePanelPlacement {
    static func frame(anchor: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let width = min(size.width, screen.width - 16), height = min(size.height, screen.height - 16)
        let x = max(screen.minX + 8, min(anchor.minX, screen.maxX - width - 8))
        let below = anchor.minY - height - 10
        let y = below >= screen.minY + 8 ? below : min(anchor.maxY + 10, screen.maxY - height - 8)
        return CGRect(x: x, y: max(screen.minY + 8, y), width: width, height: height)
    }
}

@MainActor final class InlineAssistantController: NSWindowController, NSWindowDelegate {
    static let shared = InlineAssistantController()
    private let model = InlineAssistantModel()
    private var target: SelectionTransaction?
    private var healthTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var presentationAnchor = CGRect.zero
    private var presentationScreen = CGRect.zero
    private var presentationSession = UUID()
    private var openedAt: TimeInterval = 0
    private init() {
        let panel = NotesInlinePanel(contentRect: NSRect(x: 0, y: 0, width: 392, height: 246),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        InlinePopoverStyle.configure(panel)
        panel.title = "AI 编辑"; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self; panel.onCancel = { [weak self] in self?.dismiss() }
        panel.onAppSwitch = { [weak self] in self?.dismiss(returnToNotes: false) }
        panel.contentView = NSHostingView(rootView: InlineAssistantView(model: model, close: { [weak self] in self?.dismiss() }, configure: { [weak self] in
            self?.dismiss()
            SettingsWindowController.shared.show(tab: .ai)
        }, layoutChanged: { [weak self] size in self?.resize(to: size) }, revise: { [weak self] in self?.openRevision() }))
        model.onApplied = { [weak self] in self?.dismiss() }

    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func openRevision() {
        guard !model.busy, let target else { return }
        dismiss()
        NativeNotesAnnotationController.shared.present(captured: target, agentID: model.selectedAgentID)
    }
    func present() {
        guard model.phase != .applying else { return }
        if window?.isVisible == true { window?.makeKeyAndOrderFront(nil); return }
        presentationSession = UUID()
        openedAt = ProcessInfo.processInfo.systemUptime
        let bridge = AccessibilityBridge.shared
        let bounds = bridge.getSelectionBounds() ?? bridge.getFocusedWindow().map { CGRect(x: $0.frame.maxX - 450, y: $0.frame.minY + 100, width: 0, height: 24) }
        do {
            let captured = try SelectionTransaction.capture()
            guard captured.noteIdentity != nil else { throw AIError.message("请在设置中检查 Notes 自动化权限，再重新打开 AI 编辑。") }
            target = captured
            model.begin(target: .init(text: captured.text.isEmpty ? captured.body : captured.text, hasSelection: captured.range.length > 0,
                validate: { try captured.validateForWrite() },
                apply: { text, after in try await captured.apply(text, insertAfter: after) }), configuration: ConfigurationStore.shared.committed)
            model.configureAgents()
        } catch { target = nil; model.begin(target: nil, configuration: ConfigurationStore.shared.committed, error: error.localizedDescription) }
        let primary = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let anchor = bounds.map { WindowGeometry.cocoaRect(fromAX: $0, primaryScreenFrame: primary) }
            ?? CGRect(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y, width: 0, height: 20)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? primary
        presentationAnchor = anchor
        let noteFrame = bridge.getFocusedWindow().map { WindowGeometry.cocoaRect(fromAX: $0.frame, primaryScreenFrame: primary) }
        let noteArea = noteFrame?.intersection(screen).insetBy(dx: 8, dy: 8)
        presentationScreen = noteArea.map { $0.width >= InlineAssistantLayout.width && $0.height > 420 ? $0 : screen } ?? screen
        window?.setFrame(InlinePanelPlacement.frame(anchor: anchor, size: InlineAssistantLayout.size(model: model), screen: presentationScreen), display: true)
        InlineInteractionGate.shared.setActive(true, owner: .ai)
        window?.makeKeyAndOrderFront(nil) // No activation of Quillside or settings/workspace window.
        startMonitoring()
    }
    private func resize(to size: CGSize) {
        guard let panel = window, panel.isVisible, !presentationScreen.isEmpty else { return }
        let frame = InlinePanelPlacement.frame(anchor: presentationAnchor, size: size, screen: presentationScreen)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }
    private func startMonitoring() {
        stopMonitoring()
        let session = presentationSession
        healthTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.model.phase != .applying, let target = self.target else { return }
                do { try target.validateEditor() } catch { self.model.targetChanged(error.localizedDescription) }
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != AppleNotesTarget.bundleIdentifier, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in
                guard self?.presentationSession == session else { return }
                self?.dismiss(returnToNotes: false)
            }
        }
        // A click back in Notes closes a chooser; generated work remains available until explicitly dismissed.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let timestamp = event.timestamp
            Task { @MainActor in self?.clickedOutside(eventTime: timestamp, session: session) }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let timestamp = event.timestamp
            if event.window !== self?.window { Task { @MainActor in self?.clickedOutside(eventTime: timestamp, session: session) } }
            return event
        }
    }
    private func clickedOutside(eventTime: TimeInterval, session: UUID) {
        guard window?.isVisible == true,
              InlineEventOrder.belongsToPresentation(eventTime: eventTime, openedAt: openedAt,
                  eventSession: session, currentSession: presentationSession) else { return }
        if model.phase == .choosing { dismiss(returnToNotes: false) } else { model.checkTarget() }
    }
    private func stopMonitoring() {
        healthTimer?.invalidate(); healthTimer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }; activationObserver = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }; localMouseMonitor = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }; globalMouseMonitor = nil
    }
    func dismiss(returnToNotes: Bool = true) {
        guard model.dismiss() else { return }
        presentationSession = UUID()
        stopMonitoring(); target = nil; window?.orderOut(nil)
        InlineInteractionGate.shared.setActive(false, owner: .ai)
        if returnToNotes { NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == AppleNotesTarget.bundleIdentifier }?.activate(options: []) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(); return false }
}
