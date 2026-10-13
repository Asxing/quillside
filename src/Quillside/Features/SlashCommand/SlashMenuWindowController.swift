import AppKit
import SwiftUI
import Combine

enum SlashMenuPanelPresenter {
    static func show(_ panel: NSWindow) {
        panel.orderFrontRegardless()
    }
}

final class SlashMenuWindowController {
    
    private var panel: NSPanel?
    private var slashCommandService: SlashCommandService
    private var windowTracker: WindowTrackService?
    private var cancellables = Set<AnyCancellable>()
    private let bridge = AccessibilityBridge.shared
    private var lastCaretPosition: CGPoint?
    
    init(slashCommandService: SlashCommandService, windowTracker: WindowTrackService? = nil) {
        self.slashCommandService = slashCommandService
        self.windowTracker = windowTracker
        setupSubscriptions()
    }
    
    deinit {
        hide()
        cancellables.removeAll()
    }
    
    private func setupSubscriptions() {
        windowTracker?.eventSubject
            .filter { $0 == .focusedWindowChanged || $0 == .focusedElementChanged }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.slashCommandService.deactivate() }
            .store(in: &cancellables)
        slashCommandService.commandActivatedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.show()
            }
            .store(in: &cancellables)
        
        slashCommandService.commandDeactivatedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.hide()
            }
            .store(in: &cancellables)
        
        slashCommandService.$filteredCommands
            .combineLatest(slashCommandService.$selectedIndex)
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _, _ in
                self?.updateContent()
            }
            .store(in: &cancellables)
        
        windowTracker?.$isNotesFrontmost
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFrontmost in
                if !isFrontmost {
                    self?.slashCommandService.deactivate()
                }
            }
            .store(in: &cancellables)
    }
    
    func show() {
        guard panel == nil else { return }
        
        let cocoaCaret: CGPoint
        if let axCaret = getCaretPosition() {
            cocoaCaret = convertAXToCocoaPoint(axCaret)
        } else {
            cocoaCaret = NSEvent.mouseLocation
        }
        lastCaretPosition = cocoaCaret
        
        let menuSize = currentMenuSize()
        
        let menuOrigin = calculateMenuOrigin(caretPosition: cocoaCaret, menuSize: menuSize)
        
        let newPanel = NSPanel(
            contentRect: NSRect(origin: menuOrigin, size: menuSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let menuView = SlashMenuView(
            commands: slashCommandService.$filteredCommands.eraseToAnyPublisher(),
            selectedIndex: slashCommandService.$selectedIndex.eraseToAnyPublisher(),
            commandBuffer: slashCommandService.$commandBuffer.eraseToAnyPublisher(),
            onSelect: { [weak self] index in
                self?.slashCommandService.selectCommand(at: index)
            }
        )
        
        newPanel.contentView = NSHostingView(rootView: menuView)
        SlashMenuPanelPresenter.show(newPanel)
        
        panel = newPanel
    }
    
    func hide() {
        panel?.orderOut(nil)
        panel = nil
        lastCaretPosition = nil
    }
    
    private func updateContent() {
        guard let panel = panel, let caretPosition = lastCaretPosition else { return }
        
        let menuSize = currentMenuSize()
        
        let newOrigin = calculateMenuOrigin(caretPosition: caretPosition, menuSize: menuSize)
        
        let newFrame = NSRect(origin: newOrigin, size: menuSize)
        panel.setFrame(newFrame, display: true)
    }

    private func currentMenuSize() -> NSSize {
        let commands = slashCommandService.filteredCommands
        let categoryCount = Set(commands.map(\.category)).count
        let contentHeight =
            39
            + CGFloat(commands.count) * 38
            + CGFloat(categoryCount) * 25
            + 6
        return NSSize(
            width: 320,
            height: max(min(contentHeight, 380), 76)
        )
    }
    
    private func getCaretPosition() -> CGPoint? {
        guard let focusedElement = getFocusedUIElement() else { return nil }
        
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let range = rangeValue else {
            return fallbackCaretPosition()
        }
        
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsValue
        ) == .success, let bounds = boundsValue else {
            return fallbackCaretPosition()
        }
        
        guard CFGetTypeID(bounds) == AXValueGetTypeID() else { return fallbackCaretPosition() }
        let axValue = bounds as! AXValue
        
        var rect = CGRect.zero
        AXValueGetValue(axValue, .cgRect, &rect)
        
        return CGPoint(x: rect.origin.x, y: rect.origin.y + rect.height)
    }

    private func fallbackCaretPosition() -> CGPoint? {
        guard let selection = bridge.getSelectionBounds() else { return nil }
        return CGPoint(x: selection.origin.x, y: selection.origin.y + selection.height)
    }
    
    private func getFocusedUIElement() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == AppleNotesTarget.bundleIdentifier
        })?.processIdentifier else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let focused = focusedElement else {
            return nil
        }
        
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }
    
    private func calculateMenuOrigin(caretPosition: CGPoint, menuSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(caretPosition, $0.frame) }) ?? NSScreen.main else {
            return caretPosition
        }
        
        let screenFrame = screen.visibleFrame
        var origin = NSPoint(x: caretPosition.x, y: caretPosition.y - menuSize.height - 4)
        
        if origin.y < screenFrame.minY {
            origin.y = caretPosition.y + 20
        }
        
        if origin.y + menuSize.height > screenFrame.maxY {
            origin.y = screenFrame.maxY - menuSize.height - 8
        }
        
        if origin.x + menuSize.width > screenFrame.maxX {
            origin.x = screenFrame.maxX - menuSize.width - 8
        }
        
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX + 8
        }
        
        return origin
    }

    private func convertAXToCocoaPoint(_ point: CGPoint) -> CGPoint {
        guard let primaryScreen = NSScreen.screens.first else {
            return point
        }
        return WindowGeometry.cocoaPoint(
            fromAX: point,
            primaryScreenFrame: primaryScreen.frame
        )
    }
}
