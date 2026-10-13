import AppKit
import SwiftUI
import Combine
import os.log

final class FloatingBarWindowController: NSWindowController {
    
    private var viewModel: FloatingBarViewModel
    private var cancellables = Set<AnyCancellable>()
    private let windowTracker: WindowTrackService
    private let logger = Logger(subsystem: "com.opennotes.app", category: "FloatingBar")
    private var selectionGeneration = 0
    private let toolbarSettings = ToolbarSettingsStore.shared
    private var mouseMonitor: Any?
    private var selectingWithMouse = false
    private var releaseGeneration = 0
    
    init(windowTracker: WindowTrackService) {
        self.windowTracker = windowTracker
        self.viewModel = FloatingBarViewModel()
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 34),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
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
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        
        super.init(window: panel)

        viewModel.onAskAI = {
            Task { @MainActor in InlineAssistantController.shared.present() }
        }
        viewModel.onAnnotate = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                NativeNotesAnnotationController.shared.configure(tracker: self.windowTracker)
                if let error = NativeNotesAnnotationController.shared.addSelection() { self.viewModel.showFeedback(error) }
            }
        }

        viewModel.onFormatApplied = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self?.checkSelection()
            }
        }
        
        let hostingView = NSHostingView(rootView: 
            FloatingBarView(viewModel: viewModel)
        )
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)
        
        setupBindings()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self, AppleNotesTarget.isFrontmost() else { return }
            self.releaseGeneration += 1
            if event.type == .leftMouseDown {
                self.selectingWithMouse = true
                self.selectionGeneration += 1
                self.windowTracker.cancelSelectionSnapshot()
                self.hide()
            } else {
                self.selectingWithMouse = false
                self.checkSelection()
                // Notes can commit its selection just after mouse-up. Retry only
                // while hidden; this is a bounded gesture recovery, not polling.
                let released = self.releaseGeneration
                for delay in [0.035, 0.09] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self, self.releaseGeneration == released, !self.selectingWithMouse,
                              self.window?.isVisible != true else { return }
                        self.checkSelection()
                    }
                }
            }
        }
        
        logger.info("FloatingBarWindowController initialized")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    deinit { if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) } }
    
    // MARK: - Bindings
    
    private func setupBindings() {
        NotificationCenter.default.publisher(for: InlineInteractionGate.changed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.checkSelection() }
            .store(in: &cancellables)
        toolbarSettings.$configuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resizePanel()
                self?.checkSelection()
            }
            .store(in: &cancellables)
        viewModel.$feedback.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resizePanel() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.checkSelection() }
            .store(in: &cancellables)
        windowTracker.$isNotesFrontmost
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFrontmost in
                if isFrontmost {
                    self?.checkSelection()
                } else {
                    self?.selectingWithMouse = false
                    self?.releaseGeneration += 1
                    self?.windowTracker.cancelSelectionSnapshot()
                    self?.selectionGeneration += 1
                    self?.viewModel.resetSelectionState()
                    self?.hide()
                }
            }
            .store(in: &cancellables)

        windowTracker.eventSubject
            .filter { event in
                switch event {
                case .selectionChanged,
                     .focusedElementChanged,
                     .focusedWindowChanged,
                     .windowFrameChanged:
                    return true
                case .statusChanged, .healthCheck:
                    return false
                }
            }
            .throttle(
                for: .milliseconds(16),
                scheduler: DispatchQueue.main,
                latest: true
            )
            .sink { [weak self] _ in
                self?.checkSelection()
            }
            .store(in: &cancellables)
    }
    
    private var lastSelectionBounds: CGRect?
    
    private func checkSelection() {
        guard !selectingWithMouse else { return }
        selectionGeneration += 1
        guard !InlineInteractionGate.shared.isActive, windowTracker.isNotesFrontmost, EditorFeaturePreferences.enabled("toolbar"),
              !toolbarSettings.configuration.visibleItems.isEmpty else {
            windowTracker.cancelSelectionSnapshot()
            if window?.isVisible == true {
                hide()
            }
            return
        }
        
        let generation = selectionGeneration
        windowTracker.selectionSnapshot(geometry: { [weak self] snapshot in
            guard
                let self,
                self.selectionGeneration == generation,
                !InlineInteractionGate.shared.isActive,
                self.windowTracker.isNotesFrontmost,
                EditorFeaturePreferences.enabled("toolbar")
            else {
                return
            }

            if let snapshot {
                let bounds = snapshot.bounds
                if bounds != self.lastSelectionBounds { self.viewModel.clearFeedback() }
                if bounds != self.lastSelectionBounds
                    || self.window?.isVisible != true {
                    self.viewModel.resetSelectionState()
                    self.lastSelectionBounds = bounds
                    self.positionNearSelection(bounds)
                    self.show()
                }
            } else if self.lastSelectionBounds != nil {
                self.lastSelectionBounds = nil
                self.viewModel.resetSelectionState()
                self.hide()
            }
        }, formatting: { [weak self] actions in
            guard let self, self.selectionGeneration == generation, self.window?.isVisible == true,
                  !InlineInteractionGate.shared.isActive, self.windowTracker.isNotesFrontmost else { return }
            self.viewModel.updateSelectionState(actions)
        })
    }
    
    // MARK: - Positioning

    private func resizePanel() {
        guard let panel = window else { return }
        let count = toolbarSettings.configuration.visibleItems.count
        guard count > 0 else { hide(); return }
        let maximumWidth = max(44, (NSScreen.main?.visibleFrame.width ?? 800) - 16)
        panel.setContentSize(ToolbarLayout.size(itemCount: count, feedbackVisible: viewModel.feedback != nil, maximumWidth: maximumWidth))
        if let bounds = lastSelectionBounds { positionNearSelection(bounds) }
    }
    
    private func positionNearSelection(_ selectionBounds: CGRect) {
        guard let panel = window else { return }
        
        let toolbarSize = panel.frame.size
        let margin: CGFloat = 6
        
        let cocoaRect = convertAXToCocoaCoordinates(selectionBounds)
        
        var origin = CGPoint(
            x: cocoaRect.midX - toolbarSize.width / 2,
            y: cocoaRect.maxY + margin
        )
        
        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(CGPoint(x: cocoaRect.midX, y: cocoaRect.midY))
        } ?? NSScreen.main
        
        guard let screenFrame = targetScreen?.visibleFrame else { return }
        
        origin.x = max(screenFrame.minX + margin, 
                      min(origin.x, screenFrame.maxX - toolbarSize.width - margin))
        
        if origin.y + toolbarSize.height > screenFrame.maxY - margin {
            origin.y = cocoaRect.minY - toolbarSize.height - margin
        }
        
        origin.y = max(screenFrame.minY + margin, 
                      min(origin.y, screenFrame.maxY - toolbarSize.height - margin))
        
        panel.setFrameOrigin(origin)
    }
    
    private func convertAXToCocoaCoordinates(_ axRect: CGRect) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else {
            return axRect
        }
        return WindowGeometry.cocoaRect(
            fromAX: axRect,
            primaryScreenFrame: primaryScreen.frame
        )
    }
    
    // MARK: - Show/Hide
    
    func show() {
        guard EditorFeaturePreferences.enabled("toolbar"), !toolbarSettings.configuration.visibleItems.isEmpty,
              let panel = window, !panel.isVisible else { return }
        panel.orderFrontRegardless()
        logger.debug("Floating bar shown")
    }
    
    func hide() {
        guard window?.isVisible == true else { return }
        window?.orderOut(nil)
        logger.debug("Floating bar hidden")
    }
    
    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            checkSelection()
        }
    }
}
