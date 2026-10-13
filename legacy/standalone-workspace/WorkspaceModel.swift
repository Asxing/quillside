import AppKit
import SwiftUI

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case writing = "写作助手", templates = "模板", connections = "模型连接", prompts = "AI 指令"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .writing: return "sparkles"
        case .templates: return "doc.on.doc"
        case .connections: return "network"
        case .prompts: return "text.bubble"
        }
    }
}

@MainActor final class WorkspaceModel: ObservableObject {
    static let shared = WorkspaceModel()
    let configuration = ConfigurationStore.shared
    @Published var section: WorkspaceSection = .writing
    @Published var input = ""
    @Published var instruction = ""
    @Published var language = "中文"
    @Published var promptID: UUID?
    @Published var result = ""
    @Published var status = ""
    @Published var busy = false
    @Published var complete = false
    @Published private(set) var applying = false
    @Published var writeAvailable = false
    @Published var hasSelectedText = false
    @Published var targetName = "手动输入"
    private var transaction: SelectionTransaction?
    private var task: Task<Void, Never>?
    private var runID = UUID()
    init() { promptID = configuration.committed.prompts.first?.id }
    func capture() {
        guard !busy, !applying else { status = "请等待当前操作结束再切换输入。"; return }
        do {
            let captured = try SelectionTransaction.capture()
            transaction = captured
            input = captured.text.isEmpty ? captured.body : captured.text
            targetName = captured.title
            writeAvailable = captured.noteIdentity != nil
            hasSelectedText = captured.range.length > 0
            result = ""; complete = false
            status = "已捕获。生成前可检查下方输入；应用时会重新验证原笔记。"
        } catch { status = error.localizedDescription }
    }
    func clearTargetIfInputChanged() {
        guard let transaction else { return }
        let original = transaction.text.isEmpty ? transaction.body : transaction.text
        if input != original { writeAvailable = false; self.transaction = nil; targetName = "手动输入" }
    }
    func generate() {
        guard !busy, !applying else { return }
        guard let connection = configuration.selectedConnection else { section = .connections; status = "请先添加并选定一个模型连接。"; return }
        guard let prompt = configuration.committed.prompts.first(where: { $0.id == promptID }) else { status = "请选择一个 AI 指令。"; return }
        let user: String
        do { user = try EditingRequest.render(prompt: prompt, text: input, instruction: instruction, language: language) }
        catch { status = error.localizedDescription; return }
        let id = UUID(); runID = id; busy = true; complete = false; result = ""
        let system = configuration.committed.systemPrompt + "\n写作偏好：" + configuration.committed.writingPreferences
        status = "正在处理本次显示的内容…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try ProviderKeychain.read(connection.keychainID)
                let output = try await ModelClient().generate(connection: connection, key: key, system: system, user: user) { [weak self] delta in
                    guard let self, self.runID == id else { return }
                    self.result += delta
                }
                try Task.checkCancellation()
                guard runID == id else { return }
                result = output
                complete = true; status = "生成完成。请检查内容后复制或应用。"
            } catch is CancellationError { if runID == id { status = "已取消，笔记未改变。" } }
            catch { if runID == id { status = error.localizedDescription; complete = false } }
            if runID == id { busy = false }
        }
    }
    func cancel() { task?.cancel(); runID = UUID(); busy = false; complete = false; status = "已取消，笔记未改变。" }
    func apply(insertAfter: Bool) {
        guard complete, !busy, !applying, writeAvailable, let transaction else { return }
        guard insertAfter || transaction.range.length > 0 else { status = "没有原选区，请选择插入或复制结果。"; return }
        writeAvailable = false; applying = true
        let replacement = result
        Task {
            defer { applying = false }
            do {
                try await transaction.apply(replacement, insertAfter: insertAfter)
                self.transaction = nil; status = "已写入并读回验证。"
            } catch { status = error.localizedDescription }
        }
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); status = "已复制" }
    func useTemplate(_ template: SnippetTemplate) {
        guard !busy, !applying else { return }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        result = PromptRenderer.render(template.content, values: ["date": formatter.string(from: Date())])
        complete = true; section = .writing; status = "模板已进入预览，可复制或应用到捕获的位置。"
    }
}

@MainActor final class WorkspaceController: NSWindowController, NSWindowDelegate {
    static let shared = WorkspaceController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "OpenNotes"; window.minSize = NSSize(width: 880, height: 640)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: WorkspaceView())
        window.center(); window.setFrameAutosaveName("OpenNotesWorkspace")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(capture: Bool = false, section: WorkspaceSection? = nil) {
        if capture { WorkspaceModel.shared.capture() }
        if let section { WorkspaceModel.shared.section = section }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
}
