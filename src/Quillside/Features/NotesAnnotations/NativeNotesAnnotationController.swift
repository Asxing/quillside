import AppKit
import SwiftUI
import Combine
import ApplicationServices

@MainActor final class NativeNotesAnnotationController: ObservableObject {
    static let shared = NativeNotesAnnotationController()
    let model: WritingSessionModel
    @Published var showPreview = false
    @Published var showComments = false
    @Published private(set) var stale = false
    @Published private(set) var message = ""
    @Published private(set) var visibleCommentCount = 0
    @Published private(set) var hasOpenComment = false
    private let store: WritingDraftStore?
    private var target: SelectionTransaction?
    private weak var tracker: WindowTrackService?
    private var subscriptions = Set<AnyCancellable>()
    private var modelSubscriptions = Set<AnyCancellable>()
    private var dock: NotesAnnotationInputPanel?
    private var commentPanel: NotesAnnotationInputPanel?
    private var markers: [NSPanel] = []
    private var monitor: Any?
    private var viewport = CGRect.zero
    private var active = false
    private var epoch = 0
    private var refreshTask: DispatchWorkItem?
    private var projectionRunning = false
    private var projectionPending = false
    private var needsContextCheck = true
    private var contextVerified = false
    private var suspended = false
    private var openCommentRange: NSRange?
    private var workspaceObserver: NSObjectProtocol?
    private let queryQueue = DispatchQueue(label: "com.opennotes.original-annotations", qos: .userInitiated)

    init(store suppliedStore: WritingDraftStore? = nil) {
        store = suppliedStore ?? (try? WritingDraftStore(directory: AppFiles.directory().appendingPathComponent("NotesAnnotationDrafts")))
        model = WritingSessionModel(store: store)
        model.onApplied = { [weak self] in self?.close() }
        model.$draft.dropFirst().sink { [weak self] _ in self?.scheduleProjection() }.store(in: &modelSubscriptions)
        model.$busy.removeDuplicates().dropFirst().sink { [weak self] busy in
            DispatchQueue.main.async {
                guard let self, self.active else { return }
                if busy { self.hideComment() }
                else if let draft = self.model.draft, draft.candidate != draft.source {
                    self.showPreview = true; self.showComments = false
                }
                self.resize()
            }
        }.store(in: &modelSubscriptions)
    }
    func configure(tracker: WindowTrackService?) {
        if self.tracker !== tracker { close(); self.tracker = tracker }
    }
    /// Called only by an explicit user action, never by a typing observer.
    @discardableResult func addSelection() -> String? {
        do {
            guard NotesEditorFocus.read()?.scope == .body else { throw AIError.message("请在 Notes 正文中选择文字，表格单元格暂不支持整篇批注。") }
            let current = try SelectionTransaction.capture()
            if !active || model.draft?.noteIdentity != current.noteIdentity { try begin(current) }
            try validateCurrent()
            guard let draft = model.draft,
                  let range = NotesAnnotationGeometry.localSelection(current.range, within: draft.range),
                  let anchor = InlineAnnotationAnchor(versionID: draft.id, range: range, text: draft.source) else {
                message = "在 Notes 正文选一句话，再点击工具条的“添加批注”。"; return nil
            }
            guard let rect = NotesAnnotationReader.bounds(current.range, in: current.element) else { throw AIError.message("暂时无法定位这段文字，请滚动到可见位置再试。") }
            showComment(anchor: anchor, items: [], axRect: rect)
            return nil
        } catch {
            if active { message = error.localizedDescription }
            return error.localizedDescription
        }
    }
    func present(captured: SelectionTransaction, agentID: UUID? = nil) {
        do {
            try begin(captured)
            if let agentID { model.selectAgent(agentID) }
            if captured.range.length > 0 { _ = addSelection() }
        } catch { message = error.localizedDescription }
    }
    private func begin(_ current: SelectionTransaction, reset: Bool = false) throws {
        guard let noteID = current.noteIdentity, let store else { throw AIError.message("无法识别或保存当前笔记批注。") }
        if active { close() }
        let scope = NotesAnnotationGeometry.bodyRange(current.body)
        guard scope.length > 0, current.body.utf8.count <= 200_000 else { throw AIError.message("请在有正文的笔记中添加批注，当前支持200KB以内的文字。") }
        var restored = try store.load(note: noteID)
        if reset, let old = restored {
            try AppFiles.save(old, to: store.directory.appendingPathComponent("archive-\(old.id.uuidString).json"))
            restored = nil
        }
        var initial = WritingDraft(noteIdentity: noteID, baseline: current.body, rangeLocation: scope.location, rangeLength: scope.length,
            hasSelection: false, candidate: (current.body as NSString).substring(with: scope), skills: Array(WritingSkillStore.shared.enabledSkills.prefix(8)))
        initial.versionID = initial.id
        target = current; active = true; epoch += 1; stale = false; suspended = false; contextVerified = true; needsContextCheck = true
        model.begin(restored ?? initial, config: ConfigurationStore.shared.committed)
        model.configureAgents()
        model.validateTarget = { [weak self] in guard let self else { throw AIError.message("批注会话已关闭。") }; try self.validateCurrent() }
        model.applyTarget = { [weak self] draft, after in
            guard let self else { throw AIError.message("批注会话已关闭。") }
            try self.validateCurrent()
            if let target = self.target { AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) }
            try await WritingSessionController.apply(draft: draft, insertAfter: after)
        }
        showPreview = false; showComments = false
        message = "直接在 Notes 选句批注，最后在这里统一优化。"
        if let restored, restored.baseline != current.body { stale = true; message = "原文已变化，旧批注已保留。请从菜单选择“从当前正文重新开始”。" }
        else { model.persist() }
        if let frame = NotesAnnotationReader.viewport(editor: current.element, window: current.window) { viewport = cocoa(frame) }
        setupDock(); attachTracking(); resize(); scheduleProjection()
    }
    func restart() {
        do { let current = try SelectionTransaction.capture(); try begin(current, reset: true) }
        catch { message = error.localizedDescription }
    }
    private func validateCurrent() throws {
        guard active, !stale, let target, let draft = model.draft else { throw AIError.message("原文批注需要重新定位。") }
        let identity = try? SystemAppleNotesSelectionProvider().selectedNote(includeBody: false, allowAutomationPrompt: false).get().coreDataIdentifier
        guard AppleNotesTarget.isFrontmost(), identity == draft.noteIdentity,
              let window = AccessibilityBridge.shared.getFocusedWindow(), CFEqual(window.element, target.window) else {
            suspend(); throw AIError.message("请先返回原笔记，批注已保留。")
        }
        guard SelectionTransaction.value(kAXValueAttribute, of: target.element) as? String == draft.baseline else {
            invalidate(); throw AIError.message("原文已变化，未写入。请从当前正文重新开始。")
        }
    }

    private func setupDock() {
        if dock == nil {
            let panel = NotesAnnotationInputPanel(owner: .notesComposer, size: CGSize(width: 370, height: 206))
            panel.title = "Notes 整体意见"
            panel.onCancel = { [weak self] in self?.close() }
            panel.onAppSwitch = { [weak self] in self?.suspend() }
            panel.contentView = NSHostingView(rootView: NativeNotesAnnotationView(controller: self, model: model))
            dock = panel
        }
        dock?.orderFront(nil)
    }
    func resize() {
        guard active, !suspended, let dock else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(viewport) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? viewport
        let frame = NotesAnnotationGeometry.dockFrame(viewport: viewport, screen: screen, expanded: showPreview || showComments)
        guard frame.width > 0 else { dock.orderOut(nil); return }
        dock.setFrame(frame, display: true)
        if !dock.isVisible { dock.orderFront(nil) }
    }
    func optimize() {
        do { try validateCurrent(); message = ""; hideComment(); model.run() }
        catch { message = error.localizedDescription }
    }
    func openModelSettings() { close(); SettingsWindowController.shared.show(tab: .ai) }
    func openComment(_ item: WritingAnnotation) {
        do {
            try validateCurrent()
            guard let draft = model.draft, let target,
                  let range = NotesAnnotationGeometry.absoluteRange(item, draft: draft),
                  let rect = NotesAnnotationReader.bounds(range, in: target.element), cocoa(rect).intersects(viewport) else {
                message = "请先在 Notes 滚动到该原句，再打开气泡。"; return
            }
            showComment(anchor: .init(annotation: item), items: [item], axRect: rect)
        } catch { message = error.localizedDescription }
    }
    private func showComment(anchor: InlineAnnotationAnchor, items: [WritingAnnotation], axRect: CGRect) {
        hideComment()
        let panel = NotesAnnotationInputPanel(owner: .notesComment, size: CGSize(width: EditorPanelStyle.width, height: 248))
        panel.title = "Notes 原文批注"
        panel.onCancel = { [weak self] in self?.hideComment() }
        panel.onAppSwitch = { [weak self] in self?.suspend() }
        let root = InlineAnnotationBubble(anchor: anchor, items: items, save: { [weak self] id, anchor, text, enabled in
            guard let self else { return false }
            do { try self.validateCurrent() } catch { self.message = error.localizedDescription; return false }
            guard self.model.saveSourceComment(id: id, anchor: anchor, comment: text, enabled: enabled) else { return false }
            self.message = ""; self.hideComment(); self.scheduleProjection(); return true
        }, delete: { [weak self] id in self?.model.removeComment(id); self?.hideComment(); self?.scheduleProjection() }, close: { [weak self] in self?.hideComment() })
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: EditorPanelStyle.width, height: 250); host.layoutSubtreeIfNeeded()
        panel.contentView = host
        let anchorRect = cocoa(axRect)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? viewport
        panel.setFrame(InlinePanelPlacement.frame(anchor: anchorRect, size: CGSize(width: EditorPanelStyle.width, height: max(220, min(320, host.fittingSize.height))), screen: screen), display: true)
        if let draft = model.draft { openCommentRange = NSRange(location: draft.rangeLocation + anchor.range.location, length: anchor.range.length) }
        commentPanel = panel; hasOpenComment = true; panel.makeKeyAndOrderFront(nil)
        if items.isEmpty {
            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self, let panel, self.commentPanel === panel,
                      let field = Self.editableControl(in: host) else { return }
                panel.makeFirstResponder(field)
            }
        }
    }
    private static func editableControl(in view: NSView) -> NSView? {
        if let field = view as? NSTextField, field.isEditable { return field }
        if let field = view as? NSTextView, field.isEditable { return field }
        for child in view.subviews { if let found = editableControl(in: child) { return found } }
        return nil
    }
    private func hideComment() {
        commentPanel?.orderOut(nil); commentPanel = nil; openCommentRange = nil; hasOpenComment = false
        InlineInteractionGate.shared.setActive(false, owner: .notesComment)
    }
    func resumeComment() {
        guard active, !suspended, !stale, let panel = commentPanel else { return }
        panel.makeKeyAndOrderFront(nil)
        if let content = panel.contentView, let field = Self.editableControl(in: content) { panel.makeFirstResponder(field) }
    }
    private func attachTracking() {
        subscriptions.removeAll()
        tracker?.eventSubject.sink { [weak self] event in
            guard let self, self.active else { return }
            if event == .windowFrameChanged { self.hideMarkers(); self.commentPanel?.orderOut(nil) }
            if [.focusedElementChanged, .focusedWindowChanged, .statusChanged].contains(event) {
                self.needsContextCheck = true
            }
            if event == .selectionChanged, self.commentPanel?.isKeyWindow != true {
                InlineInteractionGate.shared.setActive(false, owner: .notesComposer)
            }
            self.scheduleProjection()
        }.store(in: &subscriptions)
        tracker?.documentChangeSubject.sink { [weak self] element in
            guard let self, self.active, !self.model.applying, let target = self.target, CFEqual(element, target.element) else { return }
            // Identity first: switching notes also produces a value-change event.
            self.needsContextCheck = true; self.contextVerified = false
            self.hideMarkers(); self.commentPanel?.orderOut(nil); self.scheduleProjection(delay: 0.08)
        }.store(in: &subscriptions)
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] event in
            guard let self, self.active,
                  let app = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier == AppleNotesTarget.bundleIdentifier {
                self.needsContextCheck = true; self.scheduleProjection(delay: 0.1)
            } else if app.bundleIdentifier != Bundle.main.bundleIdentifier { self.suspend() }
        }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .scrollWheel]) { [weak self] event in
            guard let self, self.active, AppleNotesTarget.isFrontmost() else { return }
            if event.type == .leftMouseDown {
                let inside = self.viewport.contains(NSEvent.mouseLocation)
                guard NotesAnnotationPresence.click(insideBody: inside) == .keep else { return }
                InlineInteractionGate.shared.setActive(false, owner: .notesComposer)
                InlineInteractionGate.shared.setActive(false, owner: .notesComment)
                if !inside { self.needsContextCheck = true }
            }
            if event.type == .scrollWheel {
                self.commentPanel?.orderOut(nil); self.hideMarkers()
            }
            if event.type != .leftMouseDown { self.scheduleProjection(delay: event.type == .scrollWheel ? 0.1 : 0.03) }
        }
    }
    private func suspend() {
        guard active else { return }
        model.suspend()
        suspended = true; needsContextCheck = true; contextVerified = false; epoch += 1
        refreshTask?.cancel(); refreshTask = nil
        hideMarkers(); commentPanel?.orderOut(nil); dock?.orderOut(nil)
        InlineInteractionGate.shared.setActive(false, owner: .notesComment)
        InlineInteractionGate.shared.setActive(false, owner: .notesComposer)
        // Keep panels, drafts and unfinished comments; remote work ends here.
    }
    private func invalidate() {
        guard active, !stale else { return }
        stale = true; epoch += 1; hideComment(); hideMarkers(); model.stop()
        message = "原文已修改，批注已保留并暂停定位。可从菜单重新开始。"
    }
    private func scheduleProjection(delay: TimeInterval = 0.06) {
        guard active else { return }
        refreshTask?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.project() }
        refreshTask = work; DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func project() {
        guard active, let target, let draft = model.draft else { return }
        if projectionRunning { projectionPending = true; return }
        projectionRunning = true; let generation = epoch
        let verify = needsContextCheck || !contextVerified
        let verified = contextVerified, commentRange = openCommentRange
        needsContextCheck = false
        queryQueue.async { [weak self] in
            let observation = NotesAnnotationReader.read(target: target, draft: draft, verifyContext: verify,
                contextVerified: verified, openCommentRange: commentRange)
            DispatchQueue.main.async {
                guard let self else { return }
                self.projectionRunning = false
                if self.active, self.epoch == generation {
                    switch observation {
                    case .hidden:
                        self.suspend()
                    case let .changed(frame):
                        self.suspended = false; self.contextVerified = true; self.viewport = self.cocoa(frame)
                        self.invalidate(); self.resize()
                    case let .visible(projection):
                        self.suspended = false; self.contextVerified = true
                        if self.stale { self.viewport = self.cocoa(projection.viewport); self.resize() }
                        else { self.render(projection) }
                    }
                }
                if self.projectionPending { self.projectionPending = false; self.scheduleProjection() }
            }
        }
    }
    private func render(_ projection: NotesAnnotationProjection) {
        guard active, !stale else { return }
        viewport = cocoa(projection.viewport); resize(); hideMarkers()
        if let commentPanel {
            if let rect = projection.commentBounds, cocoa(rect).intersects(viewport) {
                let anchor = cocoa(rect)
                let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame ?? viewport
                commentPanel.setFrame(InlinePanelPlacement.frame(anchor: anchor, size: commentPanel.frame.size, screen: screen), display: true)
                if !commentPanel.isVisible { commentPanel.orderFront(nil) }
            } else { commentPanel.orderOut(nil) }
        }
        var groups: [(CGRect, [WritingAnnotation], CGRect)] = []
        for (item, bounds) in projection.marks {
            guard var mark = NotesAnnotationGeometry.visibleMark(bounds: cocoa(bounds), viewport: viewport) else { continue }
            mark.origin.x = viewport.minX + 3
            if let index = groups.firstIndex(where: { abs($0.0.minY - mark.minY) < 7 }) { groups[index].1.append(item) }
            else { groups.append((mark, [item], bounds)) }
        }
        for (frame, items, bounds) in groups {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
            panel.title = "Notes 批注标记"
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: Button { [weak self] in
                guard let self else { return }
                do { try self.validateCurrent(); self.showComment(anchor: .init(annotation: items[0]), items: items, axRect: bounds) }
                catch { self.message = error.localizedDescription }
            } label: {
                Image(systemName: items.count > 1 ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 13)).foregroundStyle(.orange)
                    .frame(width: 22, height: 21)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(alignment: .topTrailing) { if items.count > 1 { Text("\(items.count)").font(.system(size: 8, weight: .bold)) } }
            }.buttonStyle(.plain).accessibilityLabel("Notes 批注：" + String(items[0].quote.prefix(32))).help(items.map(\.comment).joined(separator: "\n")))
            markers.append(panel); panel.orderFront(nil)
        }
        visibleCommentCount = projection.marks.count
    }
    private func hideMarkers() { markers.forEach { $0.orderOut(nil) }; markers = []; visibleCommentCount = 0 }
    private func cocoa(_ rect: CGRect) -> CGRect { WindowGeometry.cocoaRect(fromAX: rect, primaryScreenFrame: NSScreen.screens.first?.frame ?? rect) }
    func close() {
        guard !model.applying else { return }
        if active { model.stop() }
        active = false; epoch += 1; refreshTask?.cancel(); refreshTask = nil; projectionPending = false
        hideComment(); hideMarkers(); dock?.orderOut(nil)
        InlineInteractionGate.shared.setActive(false, owner: .notesComposer)
        subscriptions.removeAll()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver); self.workspaceObserver = nil }
        suspended = false; contextVerified = false; needsContextCheck = true
        target = nil
    }
}
