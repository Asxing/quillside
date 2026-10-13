import AppKit
import Combine
import os.log

private func appleNotesProAXObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let service = Unmanaged<WindowTrackService>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    service.handleAXNotification(
        element: element,
        notification: notification as String
    )
}

enum AXObserverLifecycleAction: Equatable {
    case none
    case remove
    case install(pid_t)
    case replace(pid_t)
}

enum AXObserverLifecyclePolicy {
    static func action(
        observedPID: pid_t?,
        observerInstalled: Bool,
        snapshotPID: pid_t?,
        isTrusted: Bool
    ) -> AXObserverLifecycleAction {
        guard isTrusted, let snapshotPID else {
            return observerInstalled ? .remove : .none
        }
        guard observerInstalled, let observedPID else {
            return .install(snapshotPID)
        }
        return observedPID == snapshotPID
            ? .none
            : .replace(snapshotPID)
    }
}

enum WindowHealthCheckPolicy {
    static func requiresFullSnapshot(
        currentIsRunning: Bool,
        currentIsFrontmost: Bool,
        observedIsRunning: Bool,
        observedIsFrontmost: Bool,
        observerAction: AXObserverLifecycleAction
    ) -> Bool {
        currentIsRunning != observedIsRunning
            || currentIsFrontmost != observedIsFrontmost
            || observerAction != .none
    }
}

final class WindowTrackService: ObservableObject {
    enum Event: Equatable {
        case statusChanged
        case focusedWindowChanged
        case windowFrameChanged
        case focusedElementChanged
        case selectionChanged
        case healthCheck
    }

    struct Snapshot {
        let isRunning: Bool
        let isFrontmost: Bool
        let pid: pid_t?
        let focusedWindow: AccessibilityBridge.WindowInfo?
        let windows: [AccessibilityBridge.WindowInfo]
    }

    @Published private(set) var focusedWindow:
        AccessibilityBridge.WindowInfo?
    @Published private(set) var allWindows:
        [AccessibilityBridge.WindowInfo] = []
    @Published private(set) var isNotesRunning = false
    @Published private(set) var isNotesFrontmost = false

    let eventSubject = PassthroughSubject<Event, Never>()
    let documentChangeSubject = PassthroughSubject<AXUIElement, Never>()

    private let bridge: AccessibilityBridge
    private let logger = Logger(
        subsystem: "com.opennotes.app",
        category: "WindowTrack"
    )
    private let queryQueue = DispatchQueue(
        label: "com.opennotes.window-track.query",
        qos: .userInitiated
    )

    private var workspaceObservers: [NSObjectProtocol] = []
    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var observedElements: [AXUIElement] = []
    private var healthTimer: Timer?
    private var recoveryTimer: Timer?
    private var recoveryDeadline: Date?
    private var refreshGeneration = 0
    private var lastFocusedWindowFrame: CGRect?
    private var lastFocusedWindowElement: AXUIElement?
    private let selectionQueue = DispatchQueue(label: "com.opennotes.selection-anchor", qos: .userInteractive)
    private let formattingQueue = DispatchQueue(label: "com.opennotes.selection-style", qos: .userInitiated)
    private lazy var selectionReader = SelectionSnapshotReader<AccessibilityBridge.SelectionGeometry, Set<FloatingToolbarAction>>(
        readGeometry: { [weak self] done in
            guard let self else { done(nil); return }
            self.selectionQueue.async { [bridge = self.bridge] in
                let value = bridge.getSelectionGeometry()
                DispatchQueue.main.async { done(value) }
            }
        }, readStyle: { [weak self] geometry, done in
            guard let self else { done([]); return }
            self.formattingQueue.async { [bridge = self.bridge] in
                let value = bridge.getSelectionFormatting(geometry)
                DispatchQueue.main.async { done(value) }
            }
        })

    init(bridge: AccessibilityBridge = .shared) {
        self.bridge = bridge
    }

    deinit {
        stop()
    }

    func start() {
        logger.info("WindowTrackService started")
        setupWorkspaceObservers()
        refreshSnapshot(event: .statusChanged)
        if bridge.isTrusted {
            installAXObserverIfPossible()
        }
        startHealthCheck()
    }

    func stop() {
        logger.info("WindowTrackService stopped")
        stopHealthCheck()
        stopRecoveryProbe()
        removeAXObserver()
        removeWorkspaceObservers()
        refreshGeneration += 1
        selectionReader.cancel()
    }

    func selectionSnapshot(geometry: @escaping (AccessibilityBridge.SelectionGeometry?) -> Void,
                           formatting: @escaping (Set<FloatingToolbarAction>) -> Void) {
        selectionReader.request(geometry: geometry, style: formatting)
    }
    func cancelSelectionSnapshot() { selectionReader.cancel() }

    private func refreshSnapshot(event: Event) {
        refreshGeneration += 1
        let generation = refreshGeneration
        queryQueue.async { [bridge] in
            let isRunning = bridge.isNotesRunning()
            let snapshot = Snapshot(
                isRunning: isRunning,
                isFrontmost:
                    isRunning && bridge.isNotesFrontmost(),
                pid: isRunning ? bridge.getNotesAppPID() : nil,
                focusedWindow:
                    isRunning ? bridge.getFocusedWindow() : nil,
                windows:
                    isRunning ? bridge.getNotesWindows() : []
            )
            DispatchQueue.main.async { [weak self] in
                guard
                    let self,
                    self.refreshGeneration == generation
                else {
                    return
                }
                self.apply(snapshot: snapshot, event: event)
            }
        }
    }

    private func apply(snapshot: Snapshot, event: Event) {
        let statusChanged =
            snapshot.isRunning != isNotesRunning
            || snapshot.isFrontmost != isNotesFrontmost
        isNotesRunning = snapshot.isRunning
        isNotesFrontmost = snapshot.isFrontmost

        let focusedElementChanged = !axElementsEqual(
            snapshot.focusedWindow?.element,
            lastFocusedWindowElement
        )
        if focusedElementChanged
            || snapshot.focusedWindow?.frame != lastFocusedWindowFrame {
            focusedWindow = snapshot.focusedWindow
            lastFocusedWindowFrame = snapshot.focusedWindow?.frame
            lastFocusedWindowElement =
                snapshot.focusedWindow?.element
        }
        allWindows = snapshot.windows

        switch AXObserverLifecyclePolicy.action(
            observedPID: observedPID,
            observerInstalled: axObserver != nil,
            snapshotPID: snapshot.pid,
            isTrusted: bridge.isTrusted
        ) {
        case .none:
            break
        case .remove:
            removeAXObserver()
        case let .install(pid):
            installAXObserverIfPossible(pid: pid)
        case let .replace(pid):
            removeAXObserver()
            installAXObserverIfPossible(pid: pid)
        }

        eventSubject.send(statusChanged ? .statusChanged : event)
    }

    fileprivate func handleAXNotification(
        element: AXUIElement,
        notification: String
    ) {
        switch notification {
        case kAXFocusedWindowChangedNotification:
            registerDynamicNotifications()
            debounceRefresh(event: .focusedWindowChanged)
        case kAXMovedNotification, kAXResizedNotification:
            debounceRefresh(event: .windowFrameChanged)
        case kAXFocusedUIElementChangedNotification:
            registerDynamicNotifications()
            eventSubject.send(.focusedElementChanged)
            debounceRefresh(event: .focusedElementChanged)
        case kAXSelectedTextChangedNotification:
            eventSubject.send(.selectionChanged)
        case kAXValueChangedNotification:
            documentChangeSubject.send(element)
            eventSubject.send(.selectionChanged)
        case kAXWindowCreatedNotification,
             kAXUIElementDestroyedNotification:
            registerDynamicNotifications()
            debounceRefresh(event: .focusedWindowChanged)
        default:
            break
        }
    }

    private func debounceRefresh(event: Event) {
        refreshGeneration += 1
        let generation = refreshGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
            [weak self] in
            guard
                let self,
                self.refreshGeneration == generation
            else {
                return
            }
            self.refreshSnapshot(event: event)
        }
    }

    private func installAXObserverIfPossible(pid requestedPID: pid_t? = nil) {
        guard
            axObserver == nil,
            let pid = requestedPID ?? bridge.getNotesAppPID()
        else {
            return
        }

        var observer: AXObserver?
        let result = AXObserverCreate(
            pid,
            appleNotesProAXObserverCallback,
            &observer
        )
        guard result == .success, let observer else {
            logger.warning(
                "AXObserver unavailable: code=\(result.rawValue)"
            )
            startRecoveryProbe()
            return
        }

        axObserver = observer
        observedPID = pid
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            source,
            .commonModes
        )

        let appElement = AXUIElementCreateApplication(pid)
        observedElements = [appElement]
        register(
            notifications: [
                kAXFocusedWindowChangedNotification,
                kAXFocusedUIElementChangedNotification,
                kAXWindowCreatedNotification,
            ],
            on: appElement
        )
        registerDynamicNotifications()
        stopRecoveryProbe()
        logger.info("AXObserver installed")
    }

    private func registerDynamicNotifications() {
        guard axObserver != nil else { return }
        queryQueue.async { [weak self, bridge] in
            let window = bridge.getFocusedWindow()?.element
            let focusedElement = bridge.getFocusedUIElement()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.axObserver != nil else {
                    return
                }
                if let window {
                    self.keepObserved(window)
                    self.register(
                        notifications: [
                            kAXMovedNotification,
                            kAXResizedNotification,
                            kAXUIElementDestroyedNotification,
                        ],
                        on: window
                    )
                }
                if let focusedElement {
                    self.keepObserved(focusedElement)
                    self.register(
                        notifications: [
                            kAXSelectedTextChangedNotification,
                            kAXValueChangedNotification,
                            kAXUIElementDestroyedNotification,
                        ],
                        on: focusedElement
                    )
                }
            }
        }
    }

    private func register(
        notifications: [String],
        on element: AXUIElement
    ) {
        guard let observer = axObserver else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in notifications {
            let result = AXObserverAddNotification(
                observer,
                element,
                notification as CFString,
                refcon
            )
            if result != .success
                && result != .notificationAlreadyRegistered
                && result != .notificationUnsupported {
                logger.debug(
                    "AX notification registration failed: code=\(result.rawValue)"
                )
            }
        }
    }

    private func keepObserved(_ element: AXUIElement) {
        if !observedElements.contains(where: {
            CFEqual($0, element)
        }) {
            observedElements.append(element)
        }
        if observedElements.count > 12 {
            let oldestDynamicIndex =
                observedElements.count > 1 ? 1 : 0
            let oldElement = observedElements.remove(
                at: oldestDynamicIndex
            )
            unregisterDynamicNotifications(on: oldElement)
        }
    }

    private func unregisterDynamicNotifications(
        on element: AXUIElement
    ) {
        guard let observer = axObserver else { return }
        for notification in [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXSelectedTextChangedNotification,
            kAXValueChangedNotification,
            kAXUIElementDestroyedNotification,
        ] {
            AXObserverRemoveNotification(
                observer,
                element,
                notification as CFString
            )
        }
    }

    private func axElementsEqual(
        _ lhs: AXUIElement?,
        _ rhs: AXUIElement?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return CFEqual(lhs, rhs)
        default:
            return false
        }
    }

    private func removeAXObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        axObserver = nil
        observedPID = nil
        observedElements.removeAll()
        lastFocusedWindowElement = nil
        lastFocusedWindowFrame = nil
    }

    private func startHealthCheck() {
        guard healthTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) {
            [weak self] _ in
            self?.performHealthCheck()
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func performHealthCheck() {
        queryQueue.async { [weak self, bridge] in
            let isRunning = bridge.isNotesRunning()
            let isFrontmost = isRunning && bridge.isNotesFrontmost()
            let pid = isRunning ? bridge.getNotesAppPID() : nil
            DispatchQueue.main.async { [weak self] in
                guard let self, self.healthTimer != nil else { return }
                let observerAction = AXObserverLifecyclePolicy.action(
                    observedPID: self.observedPID,
                    observerInstalled: self.axObserver != nil,
                    snapshotPID: pid,
                    isTrusted: bridge.isTrusted
                )
                if WindowHealthCheckPolicy.requiresFullSnapshot(
                    currentIsRunning: self.isNotesRunning,
                    currentIsFrontmost: self.isNotesFrontmost,
                    observedIsRunning: isRunning,
                    observedIsFrontmost: isFrontmost,
                    observerAction: observerAction
                ) {
                    self.refreshSnapshot(event: .healthCheck)
                } else {
                    self.eventSubject.send(.healthCheck)
                }
            }
        }
    }

    private func stopHealthCheck() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func startRecoveryProbe() {
        guard recoveryTimer == nil else { return }
        recoveryDeadline = Date().addingTimeInterval(3)
        let timer = Timer(timeInterval: 0.1, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            guard
                let deadline = self.recoveryDeadline,
                Date() < deadline
            else {
                self.stopRecoveryProbe()
                return
            }
            self.refreshSnapshot(event: .healthCheck)
        }
        RunLoop.main.add(timer, forMode: .common)
        recoveryTimer = timer
    }

    private func stopRecoveryProbe() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        recoveryDeadline = nil
    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleWorkspaceChange(notification)
            },
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleWorkspaceChange(notification)
            },
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleWorkspaceChange(notification)
            },
        ]
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
    }

    private func handleWorkspaceChange(_ notification: Notification) {
        guard
            let app = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication
        else {
            return
        }

        if notification.name
            == NSWorkspace.didActivateApplicationNotification {
            let notesIsFrontmost =
                app.bundleIdentifier
                    == AppleNotesTarget.bundleIdentifier
            if isNotesFrontmost != notesIsFrontmost {
                isNotesFrontmost = notesIsFrontmost
                eventSubject.send(.statusChanged)
            }
            refreshSnapshot(event: .statusChanged)
            return
        }

        guard
            app.bundleIdentifier
                == AppleNotesTarget.bundleIdentifier
        else {
            return
        }

        if notification.name
            == NSWorkspace.didTerminateApplicationNotification {
            removeAXObserver()
        }
        refreshSnapshot(event: .statusChanged)
    }
}
