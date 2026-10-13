import AppKit
import Combine
import SwiftUI
import os.log

struct RequestGeneration {
    private(set) var current = 0

    mutating func begin() -> Int {
        current += 1
        return current
    }

    func isCurrent(_ generation: Int) -> Bool {
        generation == current
    }
}

enum BacklinksPanelAccessCoordinator {
    static func apply(
        status: NotesDatabaseAccessStatus,
        isVisible: Bool,
        start: () -> Void,
        stop: () -> Void
    ) {
        guard isVisible else { return }
        if status == .available {
            start()
        } else {
            stop()
        }
    }
}

final class BacklinksPanelWindowController: NSWindowController {
    
    private let viewModel = BacklinksPanelViewModel()
    private let windowTracker: WindowTrackService
    private let appState: AppState
    private let backlinksService = BacklinksService.shared
    private let currentNoteResolver: CurrentNoteResolver
    private let noteActionsFrame: () -> CGRect?
    private let logger = Logger(subsystem: "com.opennotes.app", category: "BacklinksPanel")
    
    private var isResolvingCurrentNote = false
    private var lastResolvedIdentifier: String?
    private var noteChangeHealthTimer: Timer?
    private var requestGeneration = RequestGeneration()
    private var clickMonitor: Any?
    private var permissionCancellable: AnyCancellable?
    private var trackerCancellable: AnyCancellable?
    private var frontmostCancellable: AnyCancellable?
    
    init(
        windowTracker: WindowTrackService,
        appState: AppState,
        currentNoteResolver: CurrentNoteResolver = CurrentNoteResolver(),
        noteActionsFrame: @escaping () -> CGRect? = { nil }
    ) {
        self.windowTracker = windowTracker
        self.appState = appState
        self.currentNoteResolver = currentNoteResolver
        self.noteActionsFrame = noteActionsFrame
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        
        super.init(window: panel)
        
        let panelView = BacklinksPanelView(viewModel: viewModel, onClose: { [weak self] in self?.hide() })
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: panelView)
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        permissionCancellable = appState.$notesDatabaseAccess
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleDatabaseAccess(status)
            }

        trackerCancellable = windowTracker.eventSubject
            .filter { event in
                switch event {
                case .focusedWindowChanged,
                     .focusedElementChanged,
                     .selectionChanged:
                    return true
                case .windowFrameChanged,
                     .statusChanged,
                     .healthCheck:
                    return false
                }
            }
            .debounce(
                for: .milliseconds(400),
                scheduler: DispatchQueue.main
            )
            .sink { [weak self] _ in
                guard
                    let self,
                    self.window?.isVisible == true
                else {
                    return
                }
                self.checkForNoteChange(
                    generation: self.requestGeneration.current
                )
            }

        frontmostCancellable = windowTracker.$isNotesFrontmost
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFrontmost in
                guard let self, !isFrontmost else { return }
                self.hide()
                self.stopBacklinksResolution()
            }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopNoteChangeHealthCheck()
        removeClickMonitor()
    }

    private func startNoteChangeHealthCheck(generation: Int) {
        stopNoteChangeHealthCheck()
        noteChangeHealthTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            self?.checkForNoteChange(generation: generation)
        }
    }

    private func stopNoteChangeHealthCheck() {
        noteChangeHealthTimer?.invalidate()
        noteChangeHealthTimer = nil
    }

    private func handleDatabaseAccess(_ status: NotesDatabaseAccessStatus) {
        BacklinksPanelAccessCoordinator.apply(
            status: status,
            isVisible: window?.isVisible == true,
            start: { [weak self] in
                self?.beginBacklinksResolution()
            },
            stop: { [weak self] in
                self?.stopBacklinksResolution()
            }
        )
    }

    private func stopBacklinksResolution() {
        _ = requestGeneration.begin()
        isResolvingCurrentNote = false
        lastResolvedIdentifier = nil
        stopNoteChangeHealthCheck()
        viewModel.reset()
    }

    private func beginBacklinksResolution() {
        guard appState.canUseBacklinks, window?.isVisible == true else {
            return
        }

        let generation = requestGeneration.begin()
        isResolvingCurrentNote = false
        lastResolvedIdentifier = nil
        viewModel.reset()
        startNoteChangeHealthCheck(generation: generation)
        resolveCurrentNoteIdentifier(
            generation: generation,
            allowAutomationPrompt: true
        )
    }
    
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.window, panel.isVisible else { return }
            let screenPoint = event.locationInWindow
            if !panel.frame.contains(screenPoint) {
                self.hide()
            }
        }
    }
    
    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
    
    private func resolveCurrentNoteIdentifier(
        generation: Int,
        allowAutomationPrompt: Bool
    ) {
        guard !isResolvingCurrentNote else { return }
        isResolvingCurrentNote = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let note = try? self.currentNoteResolver
                .resolve(
                    allowAutomationPrompt: allowAutomationPrompt,
                    requiresNativeIdentifier: true
                )
                .get()
            DispatchQueue.main.async {
                guard
                    self.requestGeneration.isCurrent(generation),
                    self.window?.isVisible == true
                else {
                    return
                }
                self.isResolvingCurrentNote = false
                guard let note else {
                    self.viewModel.markCurrentNoteUnavailable()
                    return
                }
                self.lastResolvedIdentifier = note.identifier
                self.viewModel.setCurrentNote(
                    identifier: note.identifier,
                    title: note.title
                )
                self.viewModel.forceRefresh()
            }
        }
    }

    private func checkForNoteChange(generation: Int) {
        guard
            requestGeneration.isCurrent(generation),
            window?.isVisible == true,
            !isResolvingCurrentNote
        else {
            return
        }

        isResolvingCurrentNote = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let note = try? self.currentNoteResolver
                .resolve(
                    allowAutomationPrompt: false,
                    requiresNativeIdentifier: true
                )
                .get()
            DispatchQueue.main.async {
                guard
                    self.requestGeneration.isCurrent(generation),
                    self.window?.isVisible == true
                else {
                    return
                }
                self.isResolvingCurrentNote = false
                guard let note else {
                    self.lastResolvedIdentifier = nil
                    self.viewModel.markCurrentNoteUnavailable()
                    return
                }
                let identifierChanged =
                    note.identifier != self.lastResolvedIdentifier
                self.lastResolvedIdentifier = note.identifier
                self.viewModel.setCurrentNote(
                    identifier: note.identifier,
                    title: note.title
                )
                if identifierChanged {
                    self.viewModel.forceRefresh()
                }
            }
        }
    }
    
    private func positionAboveAnchor(_ anchorFrame: CGRect) {
        guard let panel = window else { return }
        let contentSize = panel.contentView?.fittingSize ?? NSSize(width: 320, height: 220)
        let panelWidth = max(contentSize.width, 320)
        let panelHeight = min(contentSize.height, 420)
        
        let arrowHeight: CGFloat = 8
        let gap: CGFloat = 10
        
        let x = anchorFrame.midX - panelWidth / 2
        let y = anchorFrame.maxY + gap
        
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight + arrowHeight), display: true)
    }
    
    func show() {
        show(initialNote: nil)
    }

    func show(note: ResolvedCurrentNote) {
        show(initialNote: note)
    }

    private func show(initialNote: ResolvedCurrentNote?) {
        guard let panel = window else { return }

        _ = requestGeneration.begin()
        isResolvingCurrentNote = false
        lastResolvedIdentifier = nil
        viewModel.reset()

        if let actionsBar = noteActionsFrame() {
            positionAboveAnchor(actionsBar)
        } else if let windowInfo = windowTracker.focusedWindow {
            positionFallback(relativeTo: windowInfo.frame)
        }

        let reduceMotion =
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()

        if !reduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            })
        }

        installClickMonitor()
        if appState.canUseBacklinks {
            if let initialNote {
                let generation = requestGeneration.begin()
                lastResolvedIdentifier = initialNote.identifier
                viewModel.setCurrentNote(
                    identifier: initialNote.identifier,
                    title: initialNote.title
                )
                viewModel.forceRefresh()
                startNoteChangeHealthCheck(generation: generation)
            } else {
                beginBacklinksResolution()
            }
        } else {
            stopNoteChangeHealthCheck()
        }
    }
    
    private func positionFallback(relativeTo notesFrame: CGRect) {
        guard
            let panel = window,
            let primaryScreen = NSScreen.screens.first
        else {
            return
        }
        let contentSize = panel.contentView?.fittingSize ?? NSSize(
            width: BacklinksPanelLayout.width,
            height: BacklinksPanelLayout.fallbackHeight
        )
        let panelWidth = max(
            contentSize.width,
            BacklinksPanelLayout.width
        )
        let panelHeight = min(
            max(contentSize.height, BacklinksPanelLayout.fallbackHeight),
            420
        )
        let origin = WindowGeometry.backlinksOrigin(
            axNotesFrame: notesFrame,
            panelSize: CGSize(
                width: panelWidth,
                height: panelHeight
            ),
            primaryScreenFrame: primaryScreen.frame,
            visibleScreenFrames:
                NSScreen.screens.map(\.visibleFrame)
        )
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: panelWidth, height: panelHeight), display: true)
    }
    
    func hide() {
        let generation = requestGeneration.begin()
        isResolvingCurrentNote = false
        stopNoteChangeHealthCheck()
        removeClickMonitor()
        guard let panel = window, panel.isVisible else { return }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard self?.requestGeneration.isCurrent(generation) == true else {
                return
            }
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }
    
    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }
}
