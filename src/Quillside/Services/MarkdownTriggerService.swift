import AppKit
import Combine
import os.log

struct MarkdownTriggerDefinition: Identifiable {
    let pattern: String
    let resultName: String
    let action: FormattingService.FormatAction
    let deleteCount: Int

    var id: String { pattern }

    static let all: [MarkdownTriggerDefinition] = [
        .init(pattern: "# ", resultName: "Title", action: .title, deleteCount: 2),
        .init(pattern: "## ", resultName: "Heading", action: .heading, deleteCount: 3),
        .init(pattern: "### ", resultName: "Subheading", action: .subheading, deleteCount: 4),
        .init(pattern: "- ", resultName: "Dashed List", action: .dashList, deleteCount: 2),
        .init(pattern: "* ", resultName: "Bullet List", action: .bulletList, deleteCount: 2),
        .init(pattern: "1. ", resultName: "Numbered List", action: .numberedList, deleteCount: 3),
        .init(pattern: "[] ", resultName: "Checklist", action: .todoList, deleteCount: 3),
        .init(pattern: "> ", resultName: "Block Quote", action: .quote, deleteCount: 2),
        .init(pattern: "``` ", resultName: "Monostyled", action: .codeBlock, deleteCount: 4),
    ]
}

final class MarkdownTriggerService: ObservableObject {
    
    @Published private(set) var isEnabled: Bool = true
    @Published private(set) var lastTriggeredPattern: String?
    
    private let keyboardMonitor: KeyboardMonitorService
    private let formattingService = FormattingService.shared
    private let bridge = AccessibilityBridge.shared
    
    private let logger = Logger(subsystem: "com.opennotes.app", category: "MarkdownTrigger")
    private var cancellables = Set<AnyCancellable>()
    
    private let triggers = MarkdownTriggerDefinition.all
    
    private var enabledTriggers = Set(MarkdownTriggerDefinition.all.map(\.pattern))
    private var previous: NotesEditorContext?
    
    init(keyboardMonitor: KeyboardMonitorService) {
        self.keyboardMonitor = keyboardMonitor
        loadPreferences()
        setupSubscriptions()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        savePreferences()
    }
    
    func setTriggerEnabled(_ pattern: String, enabled: Bool) {
        if enabled {
            enabledTriggers.insert(pattern)
        } else {
            enabledTriggers.remove(pattern)
        }
        savePreferences()
    }
    
    func isTriggerEnabled(_ pattern: String) -> Bool {
        enabledTriggers.contains(pattern)
    }
    
    private func setupSubscriptions() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadPreferences() }
            .store(in: &cancellables)
        keyboardMonitor.keyPressSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleKeyPress(event)
            }
            .store(in: &cancellables)
    }
    
    private func handleKeyPress(_ event: KeyboardMonitorService.KeyPressEvent) {
        guard isEnabled, event.character == " ", !event.intercepted,
              event.modifiers.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
              let before = event.context, before.scope == .body, before.selection.length == 0 else { return }
        previous = before
    }
    func observeCommittedInput(_ current: NotesEditorContext?) {
        guard isEnabled, !InlineInteractionGate.shared.isActive, let current,
              current.scope == .body, current.selection.length == 0, (current.markedLength ?? 0) == 0 else { previous = nil; return }
        let before = previous; previous = current
        guard let before, before.pid == current.pid, CFEqual(before.element, current.element), CFEqual(before.window, current.window),
              let pattern = MarkdownInputContext.committedTrigger(before: before.body, selection: before.selection, after: current.body, afterSelection: current.selection),
              enabledTriggers.contains(pattern), let config = triggers.first(where: { $0.pattern == pattern }) else { return }
        previous = nil
        if InlineInputEdit.removeThenApply(trigger: pattern, lineStartOnly: true, trailingNewline: false, expected: current, perform: {
            self.formattingService.applyFormat(config.action)
        }) {
            lastTriggeredPattern = pattern
            logger.info("Markdown format applied")
        }
    }

    private let prefsKey = "com.opennotes.markdown.enabled"
    private let triggersKey = "com.opennotes.markdown.triggers"
    
    private func loadPreferences() {
        let defaults = UserDefaults.standard
        
        if defaults.object(forKey: prefsKey) != nil {
            isEnabled = defaults.bool(forKey: prefsKey)
        }
        
        if let savedTriggers = defaults.stringArray(forKey: triggersKey) {
            enabledTriggers = Set(savedTriggers)
        }
    }
    
    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: prefsKey)
        defaults.set(Array(enabledTriggers), forKey: triggersKey)
    }
}
