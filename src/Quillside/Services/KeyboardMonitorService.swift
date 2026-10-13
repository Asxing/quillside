import AppKit
import Combine
import os.log

enum KeyboardEventRoutingPolicy {
    static func shouldHandle(
        cachedIsNotesFrontmost: Bool,
        liveFrontmostBundleIdentifier: String?,
        inlinePanelActive: Bool = false
    ) -> Bool {
        !inlinePanelActive && cachedIsNotesFrontmost
            && liveFrontmostBundleIdentifier
                == AppleNotesTarget.bundleIdentifier
    }
}

final class KeyboardMonitorService: ObservableObject {
    
    @Published private(set) var isListening: Bool = false
    
    let keyPressSubject = PassthroughSubject<KeyPressEvent, Never>()
    
    struct KeyPressEvent {
        let keyCode: CGKeyCode
        let modifiers: CGEventFlags
        let character: String?
        let timestamp: Date
        var shortcutAction: AppShortcutAction? = nil
        var context: NotesEditorContext? = nil
        var intercepted = false
    }
    
    private let logger = Logger(subsystem: "com.opennotes.app", category: "KeyboardMonitor")
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    
    private var isNotesFrontmost = false
    private var suppressArrowKeys = false
    private var activeSlashToken: String?
    private var observedContext: NotesEditorContext?
    private var observedAt: TimeInterval = 0
    private var navigationAllowed = false
    private var cancellables = Set<AnyCancellable>()
    
    private let lock = NSLock()
    
    init() {}
    
    deinit {
        stop()
    }
    
    func start() {
        guard !isListening else {
            logger.debug("KeyboardMonitorService already listening")
            return
        }
        
        logger.info("KeyboardMonitorService starting")
        
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventCallback,
            userInfo: refcon
        ) else {
            logger.error("Failed to create CGEvent tap - check Accessibility permission")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapRunLoop = CFRunLoopGetMain()
        
        if let source = runLoopSource, let runLoop = tapRunLoop {
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            
            DispatchQueue.main.async { [weak self] in
                self?.isListening = true
            }
            logger.info("CGEvent tap created and enabled")
        }
    }
    
    func stop() {
        logger.info("KeyboardMonitorService stopping")
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        
        if let source = runLoopSource, let runLoop = tapRunLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.isListening = false
        }
    }
    
    func bind(windowTracker: WindowTrackService) {
        windowTracker.$isNotesFrontmost
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isFrontmost in
                self?.lock.lock()
                self?.isNotesFrontmost = isFrontmost
                self?.lock.unlock()
            }
            .store(in: &cancellables)
    }

    func setSlashCommandActive(_ active: Bool) {
        lock.lock()
        suppressArrowKeys = active
        if !active { activeSlashToken = nil }
        lock.unlock()
    }
    func setSlashCommandToken(_ token: String) {
        lock.lock(); activeSlashToken = token; lock.unlock()
    }
    func updateEditorContext(_ context: NotesEditorContext?) {
        let allowed = context?.mayConsumeNavigation() ?? false
        lock.lock()
        observedContext = context; observedAt = ProcessInfo.processInfo.systemUptime; navigationAllowed = allowed
        lock.unlock()
    }
    
    private static let eventCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        guard let refcon = refcon else {
            return Unmanaged.passUnretained(event)
        }
        
        let service = Unmanaged<KeyboardMonitorService>.fromOpaque(refcon).takeUnretainedValue()
        
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = service.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        service.lock.lock()
        let cachedIsNotesFrontmost = service.isNotesFrontmost
        service.lock.unlock()

        guard KeyboardEventRoutingPolicy.shouldHandle(
            cachedIsNotesFrontmost: cachedIsNotesFrontmost,
            liveFrontmostBundleIdentifier:
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            inlinePanelActive: InlineInteractionGate.shared.isActive
        ) else {
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags

        if let shortcutAction = AppShortcutMatcher.action(
            keyCode: keyCode,
            modifiers: modifiers
        ) {
            DispatchQueue.main.async {
                service.handleKeyEvent(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    character: nil,
                    shortcutAction: shortcutAction
                )
            }
            return nil
        }

        service.lock.lock()
        let shouldSuppress = service.suppressArrowKeys
        let expectedToken = service.activeSlashToken
        let cachedContext = service.observedContext
        let navigationAllowed = service.navigationAllowed
        let fresh = ProcessInfo.processInfo.systemUptime - service.observedAt < 0.3
        service.lock.unlock()

        // Validate committed text and editable-body focus before consuming navigation or commit keys.
        // Return/Tab must not be delivered to Notes before deleting the command token.
        if shouldSuppress && [125, 126, 36, 76, 48, 53].contains(keyCode),
           EditorFeaturePreferences.enabled("slash"), let expectedToken,
           fresh, navigationAllowed, let context = cachedContext, context.scope == .body, context.selection.length == 0,
           SlashInputContext.token(body: context.body, caret: context.selection.location) == expectedToken {
            DispatchQueue.main.async {
                service.handleKeyEvent(keyCode: keyCode, modifiers: modifiers, character: nil, context: context, intercepted: true)
            }
            return nil
        }
        
        var actualLength: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(
            maxStringLength: 4,
            actualStringLength: &actualLength,
            unicodeString: &chars
        )
        
        let character: String? = actualLength > 0 ? String(utf16CodeUnits: chars, count: actualLength) : nil
        
        // Never synchronously query Notes from an event tap: it holds delivery
        // of the user's key until this callback returns.
        let context = fresh ? cachedContext : nil
        service.lock.lock(); service.observedAt = 0; service.lock.unlock()
        DispatchQueue.main.async {
            service.handleKeyEvent(keyCode: keyCode, modifiers: modifiers, character: character, context: context)
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleKeyEvent(keyCode: CGKeyCode, modifiers: CGEventFlags, character: String?, shortcutAction: AppShortcutAction? = nil, context: NotesEditorContext? = nil, intercepted: Bool = false) {
        guard !InlineInteractionGate.shared.isActive else { return }
        keyPressSubject.send(KeyPressEvent(keyCode: keyCode, modifiers: modifiers, character: character, timestamp: Date(), shortcutAction: shortcutAction, context: context, intercepted: intercepted))
    }
}

extension KeyboardMonitorService {
    enum KeyCode: CGKeyCode {
        case returnKey = 36
        case tab = 48
        case space = 49
        case delete = 51
        case escape = 53
        case enterKey = 76
        case leftArrow = 123
        case rightArrow = 124
        case downArrow = 125
        case upArrow = 126
    }
}
