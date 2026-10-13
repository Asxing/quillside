import AppKit
import SwiftUI
import ApplicationServices

@MainActor final class WritingSessionController: NSWindowController, NSWindowDelegate {
    static let shared = WritingSessionController()
    let model = WritingSessionModel()
    private var captured: SelectionTransaction?
    private var initialCandidate: String?
    private init() {
        let panel = NotesInlinePanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 610), styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        InlinePopoverStyle.configure(panel); panel.title = "批注修订"; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 560, height: 480); panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel); panel.delegate = self
        panel.onCancel = { [weak self] in self?.dismiss() }
        panel.onAppSwitch = { [weak self] in self?.dismiss() }
        panel.contentView = NSHostingView(rootView: WritingSessionView(model: model, close: { [weak self] in self?.dismiss() }, addOriginal: { [weak self] in self?.addNotesSelection() }, startFresh: { [weak self] in self?.startFresh() }))
        model.onApplied = { [weak self] in self?.dismiss(save: false) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(captured: SelectionTransaction, candidate: String?) {
        guard !model.applying else { return }
        self.captured = captured; initialCandidate = candidate
        do {
            guard let identity = captured.noteIdentity else { throw AIError.message("无法识别当前笔记。") }
            let store = try WritingDraftStore()
            let restored = try store.load(note: identity)
            let draft = restored ?? makeDraft(captured, candidate: candidate)
            try draft.validate()
            model.begin(draft, config: ConfigurationStore.shared.committed)
            model.configureAgents()
            model.validateTarget = { [weak self] in
                guard let current = self?.model.draft else { throw AIError.message("修订会话已关闭。") }
                try Self.validate(draft: current)
            }
            model.applyTarget = { draft, after in try await Self.apply(draft: draft, insertAfter: after) }
            if restored != nil, draft.baseline != captured.body { model.report("原笔记已变化，已保留旧草稿。请复制需要的内容，或选择“从当前选区新建”。") }
            if restored == nil { model.persist() }
        } catch { model.report(error.localizedDescription) }
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let size = CGSize(width: min(680, screen.width - 32), height: min(610, screen.height - 40))
        let primary = NSScreen.screens.first?.frame ?? screen
        let notes = AccessibilityBridge.shared.getFocusedWindow().map { WindowGeometry.cocoaRect(fromAX: $0.frame, primaryScreenFrame: primary) } ?? screen
        let origin = CGPoint(x: max(screen.minX + 8, min(notes.maxX - size.width - 12, screen.maxX - size.width - 8)),
                             y: max(screen.minY + 8, min(notes.maxY - size.height - 48, screen.maxY - size.height - 8)))
        window?.setFrame(CGRect(origin: origin, size: size), display: true)
        InlineInteractionGate.shared.setActive(true, owner: .revision)
        window?.makeKeyAndOrderFront(nil)
    }
    private func makeDraft(_ target: SelectionTransaction, candidate: String?) -> WritingDraft {
        let range = target.range.length > 0 ? target.range : NSRange(location: 0, length: (target.body as NSString).length)
        return .init(noteIdentity: target.noteIdentity ?? "", baseline: target.body, rangeLocation: range.location, rangeLength: range.length,
                     hasSelection: target.range.length > 0, candidate: candidate ?? (target.body as NSString).substring(with: range), skills: Array(WritingSkillStore.shared.enabledSkills.prefix(8)))
    }
    private func startFresh() {
        guard !model.busy, !model.applying else { return }
        do {
            let fresh = try SelectionTransaction.capture()
            guard fresh.noteIdentity != nil else { throw AIError.message("请先回到 Notes 正文。") }
            // Explicit new task preserves the prior draft in its own archive.
            if let prior = model.draft {
                let folder = try AppFiles.directory().appendingPathComponent("WritingDrafts")
                try AppFiles.save(prior, to: folder.appendingPathComponent("archive-" + prior.id.uuidString + ".json"))
            }
            captured = fresh; initialCandidate = nil
            model.begin(makeDraft(fresh, candidate: nil), config: ConfigurationStore.shared.committed); model.configureAgents(); model.persist()
        } catch { model.report(error.localizedDescription) }
    }
    private func addNotesSelection() {
        do {
            guard let draft = model.draft else { return }
            let current = try SelectionTransaction.capture()
            guard current.noteIdentity == draft.noteIdentity, current.body == draft.baseline else { throw AIError.message("Notes 正文已变化，请先开始新的修订任务。") }
            model.addOriginalQuote(current.text)
        } catch { model.report(error.localizedDescription) }
    }
    private static func current(draft: WritingDraft) throws -> SelectionTransaction {
        let current = try SelectionTransaction.capture()
        guard current.noteIdentity == draft.noteIdentity, current.body == draft.baseline,
              UTF16TextRange.valid(draft.range, in: current.body) else { throw AIError.message("Notes 文稿已改变，未写入。旧草稿已保留，请检查后新建修订。") }
        return current
    }
    private static func validate(draft: WritingDraft) throws { _ = try current(draft: draft) }
    static func apply(draft: WritingDraft, insertAfter: Bool) async throws {
        try draft.validate()
        let current = try current(draft: draft)
        let target = SelectionTransaction(element: current.element, window: current.window, pid: current.pid, body: current.body,
            range: draft.range, text: draft.source, title: current.title, noteIdentity: current.noteIdentity, capturedSelection: current.capturedSelection)
        if insertAfter { try await target.apply(draft.candidate, insertAfter: true); return }
        guard !draft.source.contains("\u{FFFC}"), !draft.candidate.contains("\u{FFFC}") else { throw AIError.message("选区包含原生对象，未覆盖。请选择纯文字范围。") }
        try await target.activateForWrite()
        // Keep the rest of the note untouched. Reuse exact attributed prefix/suffix
        // and inherit a changed paragraph's style when Notes exports valid RTF.
        var range = CFRange(location: draft.range.location, length: draft.range.length)
        var output: CFTypeRef?
        var content = NotesPasteContent.text(draft.candidate)
        if let parameter = AXValueCreate(.cfRange, &range),
           AXUIElementCopyParameterizedAttributeValue(target.element, kAXRTFForRangeParameterizedAttribute as CFString, parameter, &output) == .success,
           let data = output as? Data,
           let rich = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil), rich.string == draft.source {
            content = .rich(try RevisionRichText.replacing(rich, with: draft.candidate))
        } else {
            // Replacing a range whose formatting cannot be captured could destroy
            // native styles. Insert/copy remains available without that guarantee.
            throw AIError.message("Notes 未提供该范围的完整富文本，未覆盖原格式。可使用“插入后方”或复制候选。")
        }
        try await target.paste(content, at: draft.range)
    }
    func dismiss(save: Bool = true) {
        guard !model.applying else { return }
        if save { model.stop(); model.persist() }
        window?.orderOut(nil); InlineInteractionGate.shared.setActive(false, owner: .revision)
    }
    func persistForTermination() { if model.draft != nil && !model.applying { model.stop() } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(); return false }
}

/// Preserve matching paragraph runs exactly; replace changed paragraphs with
/// their original base attributes. Complex attachments are not accepted.
enum RevisionRichText {
    static func replacing(_ source: NSAttributedString, with candidate: String) throws -> NSAttributedString {
        guard !source.string.contains("\u{FFFC}"), !candidate.contains("\u{FFFC}") else { throw AIError.message("范围包含原生对象。") }
        let aligned = RevisionParagraphs.align(candidate, to: source.string).text
        let old = source.string.components(separatedBy: "\n"), new = aligned.components(separatedBy: "\n")
        let output = NSMutableAttributedString(string: "")
        var offset = 0
        if old.count == new.count {
            for i in old.indices {
                let paragraph = old[i] + (i < old.count - 1 ? "\n" : "")
                let replacement = new[i] + (i < new.count - 1 ? "\n" : "")
                let range = NSRange(location: offset, length: (paragraph as NSString).length)
                if paragraph == replacement { output.append(source.attributedSubstring(from: range)) }
                else {
                    var attrs = source.length > 0 ? source.attributes(at: min(offset, source.length - 1), effectiveRange: nil) : [:]
                    attrs.removeValue(forKey: .link); attrs.removeValue(forKey: .attachment)
                    output.append(NSAttributedString(string: replacement, attributes: attrs))
                }
                offset += range.length
            }
        } else {
            throw AIError.message("修订改变了段落结构，无法确认原生格式保真。请使用“插入后方”，或保持段落结构后重试。")
        }
        return output
    }
}
