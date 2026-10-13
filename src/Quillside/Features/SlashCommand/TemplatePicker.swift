import AppKit
import SwiftUI

enum TemplateCatalog {
    static func matching(_ templates: [SnippetTemplate], query: String) -> [SnippetTemplate] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return templates }
        return templates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || TemplateShortcutRules.normalized($0.shortcut)?.localizedCaseInsensitiveContains(query) == true
        }
    }
    static func render(_ template: SnippetTemplate, date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"
        return PromptRenderer.render(template.content, values: ["date": formatter.string(from: date)])
    }
}

@MainActor final class TemplatePickerModel: ObservableObject {
    @Published var query = "" { didSet { selectedID = PickerSelection.retained(selectedID, among: matches.map(\.id)) } }
    @Published var selectedID: UUID?
    @Published private(set) var templates: [SnippetTemplate] = []
    @Published private(set) var status = ""
    @Published private(set) var applying = false
    @Published private(set) var attempted = false
    @Published private(set) var copyText = ""
    @Published var focusRequest = UUID()
    var onComplete: (() -> Void)?
    var onFailure: (() -> Void)?
    private var applyText: ((String) async throws -> Void)?
    private var sessionID = UUID()
    var matches: [SnippetTemplate] { TemplateCatalog.matching(templates, query: query) }
    var textToCopy: String { attempted ? copyText : matches.first(where: { $0.id == selectedID }).map { TemplateCatalog.render($0) } ?? "" }
    var canInsert: Bool { !attempted && !applying && applyText != nil && matches.contains { $0.id == selectedID } }
    func begin(templates: [SnippetTemplate], status: String = "选择模板后按 Return 插入，Esc 取消。", apply: ((String) async throws -> Void)?) {
        guard !applying else { return }
        sessionID = UUID(); self.templates = templates; query = ""; selectedID = templates.first?.id
        self.status = status; applyText = apply; attempted = false; copyText = ""; focusRequest = UUID()
    }
    func move(_ delta: Int) { selectedID = PickerSelection.next(selectedID, among: matches.map(\.id), delta: delta) }
    func submit() {
        guard canInsert, let template = matches.first(where: { $0.id == selectedID }), let applyText else { return }
        attempted = true; applying = true
        let id = sessionID, text = TemplateCatalog.render(template)
        copyText = text; status = "正在插入并验证…"
        Task {
            do {
                try await applyText(text)
                guard id == sessionID else { return }
                applying = false; status = "已插入并读回验证。"; onComplete?()
            } catch {
                guard id == sessionID else { return }
                applying = false; status = error.localizedDescription; onFailure?()
            }
        }
    }
    @discardableResult func cancel() -> Bool {
        guard !applying else { return false }
        sessionID = UUID(); applyText = nil; return true
    }
}

struct TemplatePickerView: View {
    @ObservedObject var model: TemplatePickerModel
    let close: () -> Void
    var body: some View {
        InlinePopoverSurface {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("插入模板", systemImage: "doc.on.doc").font(.system(size: 12, weight: .medium))
                Spacer()
                InlineCloseButton(action: close).disabled(model.applying)
            }
            KeyboardSearchField(text: $model.query, placeholder: "搜索模板名称或快捷词", focusRequest: model.focusRequest,
                                onMove: model.move, onSubmit: model.submit, onCancel: close)
                .frame(height: 28).disabled(model.applying)
            List(model.matches, selection: $model.selectedID) { template in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(template.name).font(.system(size: 12, weight: .medium))
                        Spacer()
                        if let shortcut = TemplateShortcutRules.normalized(template.shortcut) { Text("/" + shortcut).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                    Text(template.content).lineLimit(2).font(.caption).foregroundStyle(.secondary)
                }.tag(template.id).padding(.vertical, 4)
                    .onTapGesture(count: 2) { model.selectedID = template.id; model.submit() }
            }.listStyle(.plain).scrollContentBackground(.hidden).disabled(model.applying)
            if model.matches.isEmpty { Text("没有匹配模板，可在 Quillside 模板页添加。").foregroundStyle(.secondary) }
            if model.attempted || !model.canInsert && !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.textToCopy, forType: .string) }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.textToCopy.isEmpty)
                Spacer()
                if model.applying { ProgressView().controlSize(.small) }
                Button("插入模板") { model.submit() }.buttonStyle(.borderedProminent).controlSize(.small).disabled(!model.canInsert)
            }.font(.system(size: 11))
        }.padding(12).frame(width: 380).frame(maxHeight: .infinity)
        }
    }
}

@MainActor final class TemplatePickerController: NSWindowController, NSWindowDelegate {
    static let shared = TemplatePickerController()
    private let model = TemplatePickerModel()
    private init() {
        let panel = NotesInlinePanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        InlinePopoverStyle.configure(panel)
        panel.title = "插入模板"; panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.contentView = NSHostingView(rootView: TemplatePickerView(model: model, close: { [weak self] in self?.cancel() }))
        model.onComplete = { [weak self] in
            self?.close()
            InlineInteractionGate.shared.setActive(false, owner: .templates)
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == AppleNotesTarget.bundleIdentifier }?.activate(options: [])
        }
        model.onFailure = { [weak self] in self?.showPanel() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(trigger: String, direct: SnippetTemplate? = nil) {
        guard !model.applying else { return }
        let templates = direct.map { [$0] } ?? ConfigurationStore.shared.committed.templates
        do {
            let target = try SelectionTransaction.capture().replacingTrigger(trigger)
            guard target.noteIdentity != nil else { throw AIError.message("请允许 Quillside 访问 Notes 自动化后重新打开模板。") }
            model.begin(templates: templates, apply: { text in try await target.apply(text, insertAfter: false) })
            if direct != nil { model.submit() } else { showPanel() }
        } catch {
            model.begin(templates: templates, status: error.localizedDescription, apply: nil)
            showPanel()
        }
    }
    private func showPanel() {
        model.focusRequest = UUID()
        let primary = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let ax = AccessibilityBridge.shared.getSelectionBounds() ?? AccessibilityBridge.shared.getFocusedWindow()?.frame
        let anchor = ax.map { WindowGeometry.cocoaRect(fromAX: $0, primaryScreenFrame: primary) } ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? primary
        let height = 152 + CGFloat(max(2, min(5, model.templates.count))) * 48
        window?.setFrame(InlinePanelPlacement.frame(anchor: anchor, size: CGSize(width: 380, height: height), screen: screen), display: true)
        InlineInteractionGate.shared.setActive(true, owner: .templates)
        window?.makeKeyAndOrderFront(nil)
    }
    func cancel() { if model.cancel() { close(); InlineInteractionGate.shared.setActive(false, owner: .templates) } }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.cancel() else { return false }
        InlineInteractionGate.shared.setActive(false, owner: .templates); return true
    }
}
