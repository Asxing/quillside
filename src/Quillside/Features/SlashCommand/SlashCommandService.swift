import AppKit
import Combine
import os.log

enum SlashCommandCategory: String, CaseIterable {
    case structure
    case formatting
    case templates

    var title: String {
        switch self {
        case .structure:
            return "文本结构"
        case .formatting:
            return "格式"
        case .templates:
            return "模板"
        }
    }
}

final class SlashCommandService: ObservableObject {
    
    @Published private(set) var isActive: Bool = false
    @Published private(set) var commandBuffer: String = ""
    @Published private(set) var filteredCommands: [SlashCommand] = []
    @Published private(set) var selectedIndex: Int = 0
    
    let commandActivatedSubject = PassthroughSubject<Void, Never>()
    let commandDeactivatedSubject = PassthroughSubject<Void, Never>()
    let commandExecutedSubject = PassthroughSubject<SlashCommand, Never>()
    
    private let keyboardMonitor: KeyboardMonitorService
    private let formattingService = FormattingService.shared
    private let bridge = AccessibilityBridge.shared
    
    private let logger = Logger(subsystem: "com.opennotes.app", category: "SlashCommand")
    private var cancellables = Set<AnyCancellable>()
    
    private var previousContext: NotesEditorContext?
    private var dismissedContext: NotesEditorContext?
    private var executing = false
    private let readContext: () -> NotesEditorContext?
    private var templates: [SnippetTemplate] = []
    private var allCommands: [SlashCommand] { SlashCommandCatalog.commands(templates: templates) }
    var onInsertTemplate: ((SnippetTemplate, String) -> Void)?
    var onShowTemplatePicker: ((String) -> Void)?

    func updateTemplates(_ templates: [SnippetTemplate]) {
        guard templates != self.templates else { return }
        if isActive { deactivate() }
        self.templates = templates
        filteredCommands = allCommands
    }

    init(keyboardMonitor: KeyboardMonitorService, readContext: @escaping () -> NotesEditorContext? = NotesEditorContext.read) {
        self.keyboardMonitor = keyboardMonitor
        self.readContext = readContext
        filteredCommands = allCommands
        setupSubscriptions()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    private func setupSubscriptions() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in if !EditorFeaturePreferences.enabled("slash") { self?.deactivate() } }
            .store(in: &cancellables)
        keyboardMonitor.keyPressSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleKeyPress(event)
            }
            .store(in: &cancellables)
    }
    
    private func handleKeyPress(_ event: KeyboardMonitorService.KeyPressEvent) {
        guard bridge.isNotesFrontmost(), EditorFeaturePreferences.enabled("slash"), !InlineInteractionGate.shared.isActive,
              event.shortcutAction == nil,
              event.modifiers.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { deactivate(); return }
        if event.intercepted {
            guard isActive, let context = event.context, context.stillMatches() else { deactivate(); return }
            switch event.keyCode {
            case 53: dismissedContext = context; deactivate()
            case 36, 76, 48: executeSelectedCommand(expected: context)
            case 125: moveSelection(by: 1)
            case 126: moveSelection(by: -1)
            default: break
            }
            return
        }
        if event.keyCode == 53 { dismissedContext = NotesEditorContext.read(); deactivate(); return }
        if let before = event.context { previousContext = before }
    }

    /// Reads committed Notes content, including text produced by an IME or assistive input.
    /// Raw keyboard events accelerate observation, but are not required to open/filter the menu.
    func observeCommittedInput() {
        observeCommittedInput(readContext())
    }
    func observeCommittedInput(_ current: NotesEditorContext?) {
        guard !executing else { return }
        guard EditorFeaturePreferences.enabled("slash"), !InlineInteractionGate.shared.isActive,
              let current, current.scope == .body,
              current.selection.length == 0, (current.markedLength ?? 0) == 0 else {
            previousContext = nil; dismissedContext = nil; deactivate(); return
        }
        if let dismissedContext, sameEditor(dismissedContext, current), dismissedContext.body == current.body, dismissedContext.selection == current.selection { return }
        dismissedContext = nil
        if let previous = previousContext, sameEditor(previous, current),
           let submission = SlashObservedInput.submission(previousBody: previous.body, previousSelection: previous.selection, body: current.body, selection: current.selection) {
            let query = String(submission.token.dropFirst())
            let exact = SlashCommandCatalog.exact(query, in: allCommands)
            let selected = isActive && commandBuffer == query && filteredCommands.indices.contains(selectedIndex) ? filteredCommands[selectedIndex] : nil
            if let command = submission.suffix == " " ? exact : (exact ?? selected) {
                commandBuffer = query; filteredCommands = [command]; selectedIndex = 0
                previousContext = nil
                executeSelectedCommand(suffix: submission.suffix, expected: current)
                return
            }
        }
        previousContext = current
        guard let token = SlashInputContext.token(body: current.body, caret: current.selection.location) else { deactivate(); return }
        let query = String(token.dropFirst())
        if !isActive { activate() }
        if commandBuffer != query { commandBuffer = query; updateFilteredCommands() }
    }
    private func sameEditor(_ a: NotesEditorContext, _ b: NotesEditorContext) -> Bool {
        a.pid == b.pid && CFEqual(a.element, b.element) && CFEqual(a.window, b.window)
    }

    private func activate() {
        logger.info("Slash command activated")
        keyboardMonitor.setSlashCommandActive(true)
        keyboardMonitor.setSlashCommandToken("/")
        isActive = true
        commandBuffer = ""
        filteredCommands = allCommands
        selectedIndex = 0
        commandActivatedSubject.send()
    }
    
    func deactivate() {
        guard isActive else { return }
        logger.info("Slash command deactivated")
        keyboardMonitor.setSlashCommandActive(false)
        isActive = false
        commandBuffer = ""
        filteredCommands = allCommands
        selectedIndex = 0
        commandDeactivatedSubject.send()
    }
    
    private func updateFilteredCommands() {
        keyboardMonitor.setSlashCommandToken("/" + commandBuffer)
        let selectedID = filteredCommands.indices.contains(selectedIndex) ? filteredCommands[selectedIndex].id : nil
        filteredCommands = SlashCommandCatalog.suggestions(commandBuffer, in: allCommands)
        if let exact = SlashCommandCatalog.exact(commandBuffer, in: allCommands),
           let index = filteredCommands.firstIndex(where: { $0.id == exact.id }) { selectedIndex = index }
        else { selectedIndex = selectedID.flatMap { id in filteredCommands.firstIndex(where: { $0.id == id }) } ?? 0 }
    }
    
    private func moveSelection(by delta: Int) {
        guard !filteredCommands.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + filteredCommands.count) % filteredCommands.count
    }
    
    func selectCommand(at index: Int) {
        guard index >= 0, index < filteredCommands.count else { return }
        selectedIndex = index
        executeSelectedCommand()
    }
    
    private func executeSelectedCommand(suffix: String = "", expected: NotesEditorContext? = nil) {
        guard !filteredCommands.isEmpty else {
            deactivate()
            return
        }
        
        guard let context = expected ?? NotesEditorContext.read(), context.scope == .body, context.selection.length == 0,
              context.stillMatches(), (context.markedLength ?? 0) == 0 else { deactivate(); return }
        let command = filteredCommands[selectedIndex]
        logger.info("Executing slash command")
        
        let trigger = "/" + commandBuffer + suffix
        executing = true
        
        deactivate()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self else { return }
            defer { self.executing = false; self.previousContext = nil }
            guard self.bridge.isNotesFrontmost(), context.stillMatches(), !InlineInteractionGate.shared.isActive else { return }
            switch command.kind {
            case let .template(template): self.onInsertTemplate?(template, trigger); return
            case .templatePicker: self.onShowTemplatePicker?(trigger); return
            case .format: break
            }
            guard let action = command.action else { return }
            if InlineInputEdit.removeThenApply(trigger: trigger, lineStartOnly: false, trailingNewline: false, expected: context, perform: {
                self.formattingService.applyFormat(action)
            }) {
                self.commandExecutedSubject.send(command)
            }
        }
    }
    
}

struct SlashCommand: Identifiable, Equatable {
    enum Kind { case format(NativeNotesCommand), template(SnippetTemplate), templatePicker }
    let id: String
    let name: String
    let description: String
    let icon: String
    let category: SlashCommandCategory
    let kind: Kind
    var aliases: [String] = []
    var action: NativeNotesCommand? { if case let .format(command) = kind { return command }; return nil }
    var tokens: [String] { if case .template = kind { return aliases }; return [id] + aliases }
    var displayToken: String {
        if case let .template(template) = kind { return TemplateShortcutRules.normalized(template.shortcut).map { "/" + $0 } ?? "模板" }
        return "/" + id
    }
    init(id: String, name: String, description: String, icon: String, category: SlashCommandCategory,
         action: NativeNotesCommand, aliases: [String] = []) {
        self.id = id; self.name = name; self.description = description; self.icon = icon
        self.category = category; self.kind = .format(action); self.aliases = aliases
    }
    init(template: SnippetTemplate) {
        id = "template-" + template.id.uuidString.lowercased(); name = template.name
        description = String(template.content.replacingOccurrences(of: "\n", with: " ").prefix(70))
        icon = "doc.on.doc"; category = .templates; kind = .template(template)
        aliases = TemplateShortcutRules.normalized(template.shortcut).map { [$0] } ?? []
    }
    init(templatePicker: Void) {
        id = "template"; name = "搜索模板…"; description = "按中文名称或快捷词查找并插入"
        icon = "doc.text.magnifyingglass"; category = .templates; kind = .templatePicker; aliases = ["templates"]
    }
    
    static func == (lhs: SlashCommand, rhs: SlashCommand) -> Bool {
        lhs.id == rhs.id
    }
}
