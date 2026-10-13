import AppKit
import SwiftUI

enum NoteSearchRanking {
    static func results(_ notes: [NotesDBReader.NoteInfo], query: String) -> [NotesDBReader.NoteInfo] {
        func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        let query = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        var seen = Set<String>()
        return notes.compactMap { note -> (NotesDBReader.NoteInfo, Int)? in
            let title = fold(note.title), snippet = fold(note.snippet), folder = fold(note.folderName)
            guard words.allSatisfy({ (title + " " + snippet + " " + folder).contains($0) }) else { return nil }
            let score = query.isEmpty || title == query ? 0 : title.hasPrefix(query) ? 1 : words.allSatisfy(title.contains) ? 2 : words.allSatisfy(snippet.contains) ? 3 : 4
            return (note, score)
        }.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if a.0.isPinned != b.0.isPinned { return a.0.isPinned }
            if a.0.modificationDate != b.0.modificationDate { return a.0.modificationDate > b.0.modificationDate }
            return a.0.identifier < b.0.identifier
        }.map(\.0).filter { seen.insert($0.identifier).inserted }
    }
}

@MainActor final class NoteSearchModel: ObservableObject {
    @Published var query = "" { didSet { refilter() } }
    @Published var selectedID: String?
    @Published private(set) var notes: [NotesDBReader.NoteInfo] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var needsPermission = false
    @Published var focusRequest = UUID()
    @Published private(set) var results: [NotesDBReader.NoteInfo] = []
    var onOpened: (() -> Void)?
    private let load: () async throws -> [NotesDBReader.NoteInfo]
    private let open: (String) -> Bool
    private var task: Task<Void, Never>?
    private var generation = UUID()
    init(load: (() async throws -> [NotesDBReader.NoteInfo])? = nil, open: ((String) -> Bool)? = nil) {
        self.load = load ?? { try await Task.detached { try NotesDBReader.shared.readAllNotes() }.value }
        self.open = open ?? { id in
            guard let url = URL(string: NotesDBReader.shared.buildNoteURL(identifier: id)) else { return false }
            return NSWorkspace.shared.open(url)
        }
    }
    func reload(resetQuery: Bool = false) {
        task?.cancel(); generation = UUID(); let current = generation
        if resetQuery { query = "" }
        notes = []; results = []; selectedID = nil; loading = true; error = nil; needsPermission = false; focusRequest = UUID()
        task = Task {
            do {
                let result = try await load()
                guard !Task.isCancelled, current == generation else { return }
                notes = result; refilter()
            } catch {
                guard !Task.isCancelled, current == generation else { return }
                self.error = error.localizedDescription
                if case NotesSearchReadFailure.permission = error { needsPermission = true }
            }
            if current == generation { loading = false }
        }
    }
    func cancel() { task?.cancel(); generation = UUID(); loading = false }
    private func refilter() {
        results = NoteSearchRanking.results(notes, query: query)
        selectedID = PickerSelection.retained(selectedID, among: results.map(\.identifier))
    }
    func move(_ delta: Int) { selectedID = PickerSelection.next(selectedID, among: results.map(\.identifier), delta: delta) }
    func submit() {
        guard !loading, error == nil, let id = selectedID, results.contains(where: { $0.identifier == id }) else { return }
        if open(id) { onOpened?() } else { error = "系统未接受笔记链接，请刷新后重试。" }
    }
}

struct NoteSearchPanelView: View {
    @ObservedObject var model: NoteSearchModel
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                KeyboardSearchField(text: $model.query, placeholder: "搜索标题、摘要或文件夹", focusRequest: model.focusRequest,
                                    onMove: model.move, onSubmit: model.submit, onCancel: close).frame(height: 32)
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新笔记")
            }
            if model.loading {
                Spacer(); HStack { Spacer(); ProgressView("正在读取笔记…"); Spacer() }; Spacer()
            } else if let error = model.error {
                ContentUnavailableView("无法读取或打开笔记", systemImage: "exclamationmark.triangle", description: Text(error))
                if model.needsPermission { Button("打开完全磁盘访问设置") { AccessibilityBridge.shared.openFullDiskAccessSettings() } }
            } else {
                ScrollViewReader { proxy in
                    List(selection: $model.selectedID) {
                        ForEach(model.results, id: \.identifier) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title).font(.headline)
                                Text(note.folderName + " · " + note.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 4).tag(note.identifier).id(note.identifier)
                                .onTapGesture(count: 2) { model.selectedID = note.identifier; model.submit() }
                        }
                    }.onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
                if model.results.isEmpty { Text("没有匹配的笔记").foregroundStyle(.secondary) }
            }
            HStack {
                Text("↑ ↓ 选择   Return 打开   Esc 关闭").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.results.count) 项").font(.caption).foregroundStyle(.secondary)
                Button("打开") { model.submit() }.disabled(model.selectedID == nil || model.loading || model.error != nil)
            }
        }.padding(18).frame(minWidth: 500, minHeight: 340)
    }
}

@MainActor final class NoteSearchPanelController: NSWindowController, NSWindowDelegate {
    static let shared = NoteSearchPanelController()
    private let model = NoteSearchModel()
    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "搜索笔记"; panel.level = .floating; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel); panel.delegate = self
        panel.contentView = NSHostingView(rootView: NoteSearchPanelView(model: model, close: { [weak self] in self?.close() }))
        model.onOpened = { [weak self] in self?.close() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() {
        model.reload(resetQuery: true); window?.center()
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { model.cancel() }
}
