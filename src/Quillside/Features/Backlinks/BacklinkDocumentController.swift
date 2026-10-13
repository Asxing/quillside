import AppKit
import SwiftUI
import ApplicationServices

@MainActor final class BacklinkDocumentController: NSWindowController, ObservableObject, NSWindowDelegate {
    static let shared = BacklinkDocumentController()
    @Published private(set) var status = ""
    @Published private(set) var entries: [BacklinkDocumentEntry] = []
    @Published private(set) var busy = false
    @Published private(set) var canApply = false
    private var target: SelectionTransaction?
    private var plan: BacklinkDocumentPlan?
    private var noteID = ""
    private var originalHTML = ""

    private init() {
        let panel = NotesInlinePanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        InlinePopoverStyle.configure(panel)
        panel.title = "正文反向链接"; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self; panel.onCancel = { [weak self] in self?.dismiss() }
        panel.contentView = NSHostingView(rootView: BacklinkDocumentPreview(controller: self, close: { [weak self] in self?.dismiss() }))
        panel.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(identifier: String, items: [BacklinksService.BacklinkInfo], coverage: BacklinksCoverage) {
        guard !busy else { return }
        canApply = false; target = nil; plan = nil; entries = []
        do {
            let captured = try SelectionTransaction.capture()
            let content = try CurrentNoteResolver().resolveContent(expectedNote: nil).get()
            guard content.note.nativeIdentifier?.uppercased() == identifier.uppercased(), captured.noteIdentity == content.note.identity else {
                throw AIError.message("当前笔记已经切换，请重新查看反向链接。")
            }
            let known = try BacklinkRegionStore.shared.snapshot()[identifier.uppercased()] ?? []
            let candidate = try BacklinkDocumentPlan.make(body: captured.body, html: content.htmlBody, known: known,
                entries: items.map { .init(identifier: $0.identifier, title: $0.noteTitle) }, complete: coverage.complete,
                validateLinks: { captured.nativeLinksMatch($0, at: $1) })
            target = captured; plan = candidate; noteID = identifier; originalHTML = content.htmlBody; entries = candidate.region.entries
            canApply = !candidate.unchanged
            status = candidate.unchanged ? "正文反链已经是此版本，无需重复写入。" : coverage.complete
                ? "将更新笔记末尾的生成区域。其他正文保留；Notes 中可撤销。"
                : "来源读取不完整：仅补充已找到的链接，保留生成区域已有来源。\n" + coverage.summary
        } catch { status = error.localizedDescription }
        let primary = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let ax = AccessibilityBridge.shared.getSelectionBounds() ?? AccessibilityBridge.shared.getFocusedWindow()?.frame
        let anchor = ax.map { WindowGeometry.cocoaRect(fromAX: $0, primaryScreenFrame: primary) } ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? primary
        let statusHeight = (status as NSString).boundingRect(with: CGSize(width: 376, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: [.font: NSFont.systemFont(ofSize: 11)]).height
        let height = 104 + min(120, ceil(statusHeight)) + CGFloat(min(entries.count, 4)) * 30
        window?.setFrame(InlinePanelPlacement.frame(anchor: anchor, size: CGSize(width: 400, height: height), screen: screen), display: true)
        InlineInteractionGate.shared.setActive(true, owner: .backlinks)
        window?.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        guard !busy else { return }
        window?.orderOut(nil); InlineInteractionGate.shared.setActive(false, owner: .backlinks)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(); return false }

    func apply() {
        guard !busy, canApply, let target, let plan else { return }
        canApply = false; busy = true
        Task {
            defer { busy = false }
            do {
                try await target.activateForWrite()
                let current = try SystemAppleNotesSelectionProvider().selectedNote(includeBody: true, allowAutomationPrompt: false).get()
                guard current.coreDataIdentifier == target.noteIdentity, current.htmlBody == originalHTML else {
                    throw AIError.message("预览后笔记的格式或链接已改变，请重新预览。")
                }
                if let previous = plan.previous, !target.nativeLinksMatch(previous, at: plan.range) {
                    throw AIError.message("预览后反链目标已改变或无法核实，请重新预览。")
                }
                // Record ownership before any mutation. Failed/pending writes are recognized only if the exact region is present.
                try BacklinkRegionStore.shared.prepare(plan.region, noteID: noteID)
                try await target.pasteBacklinkRegion(plan)
                status = "正文反链已写入并核对文字与链接，可以直接在 Notes 中使用。"
                BacklinksService.shared.invalidateCache()
                BacklinksService.shared.buildLinkGraph()
                window?.orderOut(nil); InlineInteractionGate.shared.setActive(false, owner: .backlinks)
            } catch { status = error.localizedDescription + " 请检查笔记；本次操作不会自动重试。" }
        }
    }
}

private struct BacklinkDocumentPreview: View {
    @ObservedObject var controller: BacklinkDocumentController
    let close: () -> Void
    var body: some View {
        InlinePopoverSurface {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("引用此笔记", systemImage: "link").font(.system(size: 12, weight: .medium))
                Spacer()
                InlineCloseButton(action: close).disabled(controller.busy)
            }
            Text(controller.status).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !controller.entries.isEmpty {
                List(controller.entries, id: \.identifier) { item in Text(item.title).font(.system(size: 12)) }
                    .listStyle(.plain).scrollContentBackground(.hidden)
            }
            HStack {
                Spacer()
                if controller.busy { ProgressView().controlSize(.small) }
                Button("写入当前笔记") { controller.apply() }.buttonStyle(.borderedProminent).controlSize(.small).disabled(!controller.canApply || controller.busy)
            }
        }.padding(12).frame(width: 400).frame(maxHeight: .infinity)
        }
    }
}

extension SelectionTransaction {
    @MainActor func pasteBacklinkRegion(_ plan: BacklinkDocumentPlan) async throws {
        try await paste(.rich(plan.region.attributed(prefix: plan.prefix)), at: plan.range)
        let selection = try SystemAppleNotesSelectionProvider().selectedNote(includeBody: false, allowAutomationPrompt: false).get()
        let range = NSRange(location: plan.range.location + (plan.prefix as NSString).length, length: (plan.region.text as NSString).length)
        guard selection.coreDataIdentifier == noteIdentity, nativeLinksMatch(plan.region, at: range) else {
            throw AIError.message("文字已写入，但链接核对未通过。可在 Notes 撤销后重试。")
        }
    }
}
