import AppKit
import SwiftUI
import Combine

enum NoteActionsPresentationPolicy {
    static func shouldShow(
        hasCurrentNote: Bool,
        hasFeedback: Bool,
        isNotesFrontmost: Bool
    ) -> Bool {
        hasFeedback || (hasCurrentNote && isNotesFrontmost)
    }
}

enum NoteActionsRefreshPolicy {
    static func shouldRefresh(
        for event: WindowTrackService.Event
    ) -> Bool {
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
}

final class NoteActionsBarWindowController: NSWindowController {
    
    private let viewModel: NoteActionsBarViewModel
    private var cancellables = Set<AnyCancellable>()
    private let windowTracker: WindowTrackService
    
    var onShowBacklinks: ((ResolvedCurrentNote) -> Void)? {
        didSet { viewModel.onShowBacklinks = onShowBacklinks }
    }
    
    init(
        windowTracker: WindowTrackService,
        viewModel: NoteActionsBarViewModel = NoteActionsBarViewModel()
    ) {
        self.windowTracker = windowTracker
        self.viewModel = viewModel
        
        let panel = NSPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NoteActionsLayout.panelSize
            ),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        
        super.init(window: panel)
        
        let barView = NoteActionsBarView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: barView)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NoteActionsLayout.panelSize
        )
        panel.contentView = hostingView
        
        setupBindings()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBindings() {
        NotificationCenter.default.publisher(for: InlineInteractionGate.changed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if InlineInteractionGate.shared.isActive { self?.hide() } else { self?.show() }
            }.store(in: &cancellables)
        windowTracker.$focusedWindow
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windowInfo in
                self?.handleWindowChange(windowInfo)
            }
            .store(in: &cancellables)
        
        windowTracker.$isNotesFrontmost
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (isActive: Bool) in
                if isActive {
                    self?.viewModel.refreshCurrentNote()
                } else {
                    self?.viewModel.setCurrentNote(nil)
                    self?.hide()
                }
            }
            .store(in: &cancellables)

        windowTracker.eventSubject
            .filter {
                NoteActionsRefreshPolicy.shouldRefresh(for: $0)
            }
            .debounce(
                for: .milliseconds(400),
                scheduler: DispatchQueue.main
            )
            .sink { [weak self] _ in
                guard self?.windowTracker.isNotesFrontmost == true else {
                    return
                }
                self?.viewModel.noteContextDidChange()
            }
            .store(in: &cancellables)

        viewModel.$currentNote
            .combineLatest(viewModel.$feedback)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note, feedback in
                guard let self else { return }
                if NoteActionsPresentationPolicy.shouldShow(
                    hasCurrentNote: note != nil,
                    hasFeedback: feedback != nil,
                    isNotesFrontmost:
                        self.windowTracker.isNotesFrontmost
                ) {
                    self.show()
                } else {
                    self.hide()
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleWindowChange(_ windowInfo: AccessibilityBridge.WindowInfo?) {
        guard let windowInfo = windowInfo else {
            hide()
            return
        }
        
        positionBar(relativeTo: windowInfo.frame)
        viewModel.noteContextDidChange()
    }
    
    private func positionBar(relativeTo notesFrame: CGRect) {
        guard
            let panel = window,
            let primaryScreen = NSScreen.screens.first
        else {
            return
        }
        let origin = WindowGeometry.noteActionsOrigin(
            axNotesFrame: notesFrame,
            panelSize: panel.frame.size,
            primaryScreenFrame: primaryScreen.frame,
            visibleScreenFrames:
                NSScreen.screens.map(\.visibleFrame)
        )
        panel.setFrameOrigin(origin)
    }
    
    func show() {
        guard
            !InlineInteractionGate.shared.isActive,
            let panel = window,
            NoteActionsPresentationPolicy.shouldShow(
                hasCurrentNote: viewModel.currentNote != nil,
                hasFeedback: viewModel.feedback != nil,
                isNotesFrontmost: windowTracker.isNotesFrontmost
            )
        else {
            return
        }
        
        if let windowInfo = windowTracker.focusedWindow {
            positionBar(relativeTo: windowInfo.frame)
        }
        
        panel.orderFrontRegardless()
    }
    
    func hide() {
        window?.orderOut(nil)
    }

    func performFromMenu(_ action: NoteActionKind) {
        viewModel.perform(action, resolveIfNeeded: true)
    }

    func actionBarFrame() -> CGRect? {
        guard let panel = window, panel.isVisible else { return nil }
        return CGRect(
            x: panel.frame.maxX - NoteActionsLayout.barSize.width,
            y: panel.frame.minY,
            width: NoteActionsLayout.barSize.width,
            height: NoteActionsLayout.barSize.height
        )
    }

}
