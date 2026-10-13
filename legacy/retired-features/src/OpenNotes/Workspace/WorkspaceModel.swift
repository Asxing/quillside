import AppKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case writing = "写作助手", search = "笔记搜索", templates = "模板", knowledge = "个人知识库", connections = "模型连接", prompts = "AI 指令"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .writing: return "sparkles"
        case .search: return "magnifyingglass"
        case .templates: return "doc.on.doc"
        case .knowledge: return "books.vertical"
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
    @Published var useKnowledge = false
    @Published var collection: String?
    @Published private(set) var answerSources: [KnowledgeHit] = []
    @Published private(set) var retrievalHits: [KnowledgeHit] = []
    @Published var documents: [KnowledgeDocument] = []
    @Published var notes: [NotesDBReader.NoteInfo] = []
    @Published var noteQuery = ""
    @Published var selectedNotes = Set<String>()
    @Published var indexing = false
    @Published var writeAvailable = false
    @Published var hasSelectedText = false
    @Published var targetName = "手动输入"
    private var transaction: SelectionTransaction?
    private var task: Task<Void, Never>?
    private var runID = UUID()
    private var index: KnowledgeIndex?

    init() {
        promptID = configuration.value.prompts.first?.id
        do { index = try KnowledgeIndex(path: AppFiles.directory().appendingPathComponent("knowledge.sqlite").path) }
        catch { status = error.localizedDescription }
        Task { await refreshDocuments() }
    }
    var collections: [KnowledgeCollectionOption] { KnowledgeCollectionOption.options(documents) }
    var selectedCollectionExists: Bool { collection.map { id in collections.contains { $0.id == id } } ?? true }
    var filteredNotes: [NotesDBReader.NoteInfo] {
        guard !noteQuery.isEmpty else { return notes }
        return notes.filter { ($0.title + " " + $0.snippet + " " + $0.folderName).localizedCaseInsensitiveContains(noteQuery) }
    }
    func capture() {
        guard !busy else { status = "请先取消当前生成再切换输入。"; return }
        do {
            let captured = try SelectionTransaction.capture()
            transaction = captured
            input = captured.text.isEmpty ? captured.body : captured.text
            targetName = captured.title
            writeAvailable = captured.noteIdentity != nil
            hasSelectedText = captured.range.length > 0
            result = ""; complete = false; answerSources = []
            status = "已捕获。生成前可检查下方输入；应用时会重新验证原笔记。"
        } catch { status = error.localizedDescription }
    }
    func clearTargetIfInputChanged() {
        guard let transaction else { return }
        let original = transaction.text.isEmpty ? transaction.body : transaction.text
        if input != original { writeAvailable = false; self.transaction = nil; targetName = "手动输入" }
    }
    func generate() {
        guard !busy else { return }
        guard !useKnowledge || selectedCollectionExists else { status = "选定集合已变化，请重新选择；发送范围没有自动扩大。"; return }
        guard let connection = configuration.selectedConnection else { section = .connections; status = "请先添加并选定一个模型连接。"; return }
        guard let prompt = configuration.committed.prompts.first(where: { $0.id == promptID }) else { status = "请选择一个 AI 指令。"; return }
        guard !input.isEmpty || !instruction.isEmpty else { status = "请先输入材料或问题。"; return }
        guard input.utf8.count < 200_000 else { status = "输入超过 200 KB，请分段处理。"; return }
        let id = UUID(); runID = id; busy = true; complete = false; result = ""; answerSources = []
        let text = input, question = instruction.isEmpty && useKnowledge ? input : instruction, system = configuration.committed.systemPrompt + "\n写作偏好：" + configuration.committed.writingPreferences
        let lang = language, knowledge = useKnowledge, scope = collection
        status = knowledge ? "检索所选知识集合…" : "生成中…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var sources = ""
                if knowledge {
                    guard let index else { throw AIError.message("知识索引不可用。") }
                    let found = try await index.search(question.isEmpty ? text : question, collectionID: scope)
                    try Task.checkCancellation()
                    guard !found.isEmpty else { throw AIError.message("没有检索到相关资料。请补充资料、调整集合或改写问题。") }
                    self.answerSources = found
                    sources = found.enumerated().map { "[S\($0.offset + 1)] \($0.element.title)\n\($0.element.text)" }.joined(separator: "\n\n")
                }
                let variables = ["text": text, "instruction": question, "language": lang, "sources": sources]
                var user = PromptRenderer.render(prompt.instruction, values: variables)
                if !question.isEmpty && !prompt.instruction.contains("{instruction}") { user += "\n补充要求：" + question }
                if knowledge && !prompt.instruction.contains("{sources}") { user += "\n参考资料（引用格式 [S1]）：\n" + sources }
                let key = try ProviderKeychain.read(connection.keychainID)
                let output = try await ModelClient().generate(connection: connection, key: key, system: system, user: user) { [weak self] delta in
                    guard let self, self.runID == id else { return }
                    self.result += delta
                }
                try Task.checkCancellation()
                guard runID == id else { return }
                if knowledge { try Self.validateCitations(output, sourceCount: answerSources.count) }
                complete = true; status = "生成完成。请检查内容后复制或应用。"
            } catch is CancellationError { if runID == id { status = "已取消，笔记未改变。" } }
            catch { if runID == id { status = error.localizedDescription; complete = false } }
            if runID == id { busy = false }
        }
    }
    static func validateCitations(_ text: String, sourceCount: Int) throws {
        let regex = try NSRegularExpression(pattern: #"\[S(\d+)\]"#)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        guard !matches.isEmpty else { throw AIError.message("回答缺少来源引用，请检查材料或重新生成。") }
        for match in matches {
            let n = Int((text as NSString).substring(with: match.range(at: 1))) ?? 0
            guard n >= 1 && n <= sourceCount else { throw AIError.message("回答引用了未提供的来源，未启用应用操作。") }
        }
    }
    func cancel() { task?.cancel(); runID = UUID(); busy = false; complete = false; status = "已取消，笔记未改变。" }
    func apply(insertAfter: Bool) {
        guard complete, !busy, writeAvailable, let transaction else { return }
        guard insertAfter || transaction.range.length > 0 else { status = "没有原选区，请选择插入或复制结果。"; return }
        writeAvailable = false
        Task {
            do {
                try await transaction.apply(result, insertAfter: insertAfter)
                self.transaction = nil; status = "已写入并读回验证。"
            } catch { status = error.localizedDescription }
        }
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); status = "已复制" }
    func openSource(_ locator: String) {
        guard let url = URL(string: locator), ["file", "applenotes", "notes"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }
    func loadNotes() {
        guard !indexing else { return }; indexing = true
        Task {
            do {
                notes = try await Task.detached { try NotesDBReader.shared.readAllNotes() }.value
                status = "已读取 \(notes.count) 篇笔记的标题与摘要。选择后才导入正文。"
            } catch { notes = []; status = error.localizedDescription }
            indexing = false
        }
    }

    func importSelectedNotes() {
        guard !indexing, !selectedNotes.isEmpty else { return }
        let ids = selectedNotes; indexing = true
        Task {
            do {
                guard let index else { throw AIError.message("知识索引不可用。") }
                let imported = try await Task.detached { try NotesDBReader.shared.readKnowledgeDocuments(identifiers: ids) }.value
                for document in imported { try await index.upsert(document) }
                await refreshDocuments()
                status = "已导入 \(imported.count) 篇笔记快照；跳过 \(ids.count - imported.count) 篇锁定或不可读取笔记。"
            } catch { status = error.localizedDescription }
            indexing = false
        }
    }
    func refreshNotesSnapshots() {
        guard !indexing else { return }
        let old = documents.filter { $0.id.hasPrefix("notes:") }
        let ids = Set(old.map { String($0.id.dropFirst(6)) }); guard !ids.isEmpty else { return }
        indexing = true
        Task {
            do {
                guard let index else { throw AIError.message("知识索引不可用。") }
                let new = try await Task.detached { try NotesDBReader.shared.readKnowledgeDocuments(identifiers: ids) }.value
                try await index.replaceSnapshot(new, replacingIDs: Set(old.map(\.id)))
                await refreshDocuments(); status = "Notes 快照已更新，删除或锁定的来源已从索引移除。"
            } catch { status = error.localizedDescription }
            indexing = false
        }
    }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .pdf, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls; guard urls.count <= 50 else { status = "每次最多导入 50 个文件。"; return }
        indexing = true
        Task {
            var imported = 0
            do {
                guard let index else { throw AIError.message("知识索引不可用。") }
                for url in urls {
                    let document = try await Task.detached { () throws -> KnowledgeDocument in
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 50_000_000 else { throw AIError.message("文件超过 50 MB，请拆分后导入。") }
                        let text: String
                        if url.pathExtension.lowercased() == "pdf" {
                            guard let pdf = PDFDocument(url: url), !pdf.isLocked else { throw AIError.message("PDF 无法读取或已经加密。") }
                            text = (0..<pdf.pageCount).compactMap { n in pdf.page(at: n)?.string.map { "第 \(n+1) 页\n" + $0 } }.joined(separator: "\n\n")
                        } else { text = try String(contentsOf: url, encoding: .utf8) }
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.message("资料没有可提取文字；扫描 PDF 需要先做 OCR。") }
                        return .init(id: "file:" + KnowledgeText.fingerprint(url.standardizedFileURL.path), title: url.lastPathComponent, locator: url.absoluteString, collection: "文件", text: text, indexedAt: Date().timeIntervalSince1970, collectionID: KnowledgeCollectionIdentity.files, collectionDetail: "导入文件")
                    }.value
                    try await index.upsert(document); imported += 1
                }
                status = "已导入 \(imported) 个文件快照。文件变化后可重新导入更新。"
            } catch { status = "已导入 \(imported) 个；" + error.localizedDescription }
            await refreshDocuments(); indexing = false
        }
    }
    func removeDocument(_ id: String) {
        Task { do { try await index?.remove(id); await refreshDocuments(); retrievalHits = []; if answerSources.contains(where: { $0.documentID == id }) { cancel(); result = ""; answerSources = [] }; status = "来源与检索索引已移除。" } catch { status = error.localizedDescription } }
    }
    func refreshDocuments() async { do { documents = try await index?.documents() ?? [] } catch { status = error.localizedDescription } }
    func previewRetrieval(_ query: String) {
        guard selectedCollectionExists else { status = "选定集合已变化，请重新选择。"; return }
        Task { do { retrievalHits = try await index?.search(query, collectionID: collection) ?? []; status = "找到 \(retrievalHits.count) 个片段；此操作不调用模型。" } catch { status = error.localizedDescription } }
    }
    func useTemplate(_ template: SnippetTemplate) {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        answerSources = []
        result = PromptRenderer.render(template.content, values: ["date": formatter.string(from: Date())])
        complete = true; section = .writing; status = "模板已进入预览，可复制或应用到捕获的位置。"
    }
}

@MainActor final class WorkspaceController: NSWindowController {
    static let shared = WorkspaceController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "OpenNotes"; window.minSize = NSSize(width: 880, height: 640)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: WorkspaceView())
        window.center(); window.setFrameAutosaveName("OpenNotesWorkspace")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(capture: Bool = false, section: WorkspaceSection? = nil) {
        if capture { WorkspaceModel.shared.capture() }
        if let section { WorkspaceModel.shared.section = section }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
}
