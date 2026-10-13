import Foundation
import Combine

@MainActor final class WritingSessionModel: ObservableObject {
    @Published var draft: WritingDraft?
    @Published var selection = NSRange(location: 0, length: 0)
    @Published var comment = ""
    @Published var connectionID: UUID?
    @Published private(set) var agents: [AgentProfile] = []
    private var agentStore: AgentStore?
    private var skillStore: WritingSkillStore?
    var selectedAgentID: UUID? { draft?.agent?.profile.id }
    func configureAgents(_ agents: AgentStore = .shared, skills: WritingSkillStore = .shared) {
        agentStore = agents; skillStore = skills; self.agents = agents.catalog.profiles
        do {
            if draft?.agent == nil {
                var snapshot = try agents.snapshot(skills: skills.catalog.skills)
                // Old drafts retain their exact Skill snapshots until the user
                // explicitly chooses another role or refreshes it.
                if let existing = draft?.skills, !existing.isEmpty, snapshot.profile.isLegacy {
                    snapshot = .init(profile: snapshot.profile, skills: existing)
                }
                draft?.agent = snapshot
                draft?.skills = AgentContextBuilder.skills(snapshot, operation: .revision)
            }
            if let saved = draft?.agent?.profile, !self.agents.contains(where: { $0.id == saved.id }) { self.agents.append(saved) }
            persist()
        } catch { self.error = error.localizedDescription }
    }
    func selectAgent(_ id: UUID?) {
        guard !busy, !applying, let id, let agentStore, let skillStore else { return }
        do {
            let snapshot = try agentStore.snapshot(id: id, skills: skillStore.catalog.skills)
            draft?.agent = snapshot; draft?.skills = AgentContextBuilder.skills(snapshot, operation: .revision)
            agentStore.activeID = id; error = ""; persist()
            status = "已切换为\(snapshot.profile.name)，候选稿和批注意见保留。"
        } catch { self.error = error.localizedDescription }
    }
    @Published private(set) var busy = false
    @Published private(set) var applying = false
    @Published private(set) var status = ""
    @Published private(set) var error = ""
    @Published private(set) var connections: [ModelConnection] = []
    @Published var showOriginal = false
    @Published var focusRange: NSRange?
    private var config = AIConfiguration()
    private var store: WritingDraftStore?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private let runs: AIRunRegistry
    private let runTimeout: TimeInterval
    private var runID: UUID?
    private var saveTask: Task<Void, Never>?
    private let agent: WritingAgent
    var validateTarget: (() throws -> Void)?
    var applyTarget: ((WritingDraft, Bool) async throws -> Void)?
    var onApplied: (() -> Void)?
    var canApply: Bool { !busy && !applying && draft != nil && error.isEmpty }
    init(generate: @escaping WritingAgent.Generate = { connection, system, user, delta in
        return try await PiRuntime.generate(connection: connection, system: system, user: user, onDelta: delta)
    }, store: WritingDraftStore? = nil, runs: AIRunRegistry? = nil,
       runTimeout: TimeInterval = AIRunRegistry.revisionLimit) {
        agent = WritingAgent(generate: generate)
        self.store = store ?? (try? WritingDraftStore())
        self.runs = runs ?? .shared; self.runTimeout = runTimeout
    }
    func begin(_ incoming: WritingDraft, config: AIConfiguration) {
        task?.cancel(); task = nil; runs.finish(runID); runID = nil
        saveTask?.cancel(); generation = UUID()
        draft = incoming; self.config = config; connections = config.connections; connectionID = config.selectedConnectionID
        selection = .init(location: 0, length: 0); comment = ""; showOriginal = false; busy = false; applying = false; error = ""
        status = incoming.versions.isEmpty ? "选中文字添加批注，最后统一优化。" : "已恢复本机修订草稿。"
    }
    func report(_ message: String) { error = message }
    func editCandidate(_ text: String) {
        guard !busy, !applying, !showOriginal else { return }
        let had = !(draft?.currentAnnotations.isEmpty ?? true)
        draft?.changeCandidate(text); selection = .init(location: 0, length: 0)
        if had { status = "正文已手动编辑，旧批注继续作为意见保留；划线只标在对应版本。" }
        scheduleSave()
    }
    func updateInstruction(_ text: String) { draft?.instruction = text; scheduleSave() }
    func addComment() {
        guard !busy, !applying, !showOriginal else { return }
        do { try draft?.annotate(range: selection, comment: comment); comment = ""; error = ""; persist(); status = "批注已保存；可以继续选择下一处。" }
        catch { self.error = error.localizedDescription }
    }
    @discardableResult func saveInlineComment(id: UUID?, anchor: InlineAnnotationAnchor, comment: String, enabled: Bool) -> Bool {
        guard !busy, !applying, !showOriginal, var updated = draft, anchor.matches(updated) else {
            error = "这段文字已经变化，请重新选择后添加批注。"; return false
        }
        let value = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 4_000 else { error = "请输入批注意见（不超过4KB）。"; return false }
        do {
            if let id {
                guard let index = updated.annotations.firstIndex(where: { $0.id == id }),
                      updated.annotations[index].versionID == anchor.versionID,
                      updated.annotations[index].range == anchor.range,
                      updated.annotations[index].quote == anchor.quote else {
                    throw AIError.message("原批注已经变化，请重新打开。")
                }
                updated.annotations[index].comment = value; updated.annotations[index].enabled = enabled
            } else { try updated.annotate(range: anchor.range, comment: value) }
            guard let store else { throw AIError.message("无法保存修订草稿。") }
            updated.updatedAt = Date(); try store.save(updated)
            saveTask?.cancel(); draft = updated; self.comment = ""; error = ""
            status = "批注已保存，点击划线或气泡可继续编辑。"
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    /// Notes overlays always refer to the immutable source, even after a new
    /// candidate has been generated. They never reuse candidate offsets.
    @discardableResult func saveSourceComment(id: UUID?, anchor: InlineAnnotationAnchor, comment: String, enabled: Bool) -> Bool {
        guard !busy, !applying, var updated = draft,
              anchor.versionID == updated.id, UTF16TextRange.valid(anchor.range, in: updated.source),
              (updated.source as NSString).substring(with: anchor.range) == anchor.quote else {
            error = "原文批注位置已失效，请重新选择。"; return false
        }
        let value = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 4_000 else { error = "请输入批注意见（不超过4KB）。"; return false }
        do {
            if let id {
                guard let index = updated.annotations.firstIndex(where: { $0.id == id }),
                      updated.annotations[index].versionID == updated.id,
                      updated.annotations[index].range == anchor.range,
                      updated.annotations[index].quote == anchor.quote else { throw AIError.message("原批注已经变化。") }
                updated.annotations[index].comment = value; updated.annotations[index].enabled = enabled
            } else {
                guard updated.annotations.count < 200 else { throw AIError.message("本次修订最多保留200条批注。") }
                updated.annotations.append(.init(id: UUID(), versionID: updated.id, location: anchor.range.location,
                    length: anchor.range.length, quote: anchor.quote, comment: value, enabled: enabled))
            }
            guard let store else { throw AIError.message("无法保存批注。") }
            updated.updatedAt = Date(); try store.save(updated)
            saveTask?.cancel(); draft = updated; error = ""; status = "已保存，可继续在 Notes 选择下一处。"
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func removeComment(_ id: UUID) { draft?.annotations.removeAll { $0.id == id }; persist() }
    func locate(_ item: WritingAnnotation) {
        guard let draft else { return }
        showOriginal = false
        if item.versionID == draft.versionID {
            selection = item.range; focusRange = nil
            DispatchQueue.main.async { [weak self] in self?.focusRange = item.range }
        } else {
            let text = draft.candidate as NSString, found = text.range(of: item.quote)
            if found.location != NSNotFound,
               text.range(of: item.quote, range: .init(location: NSMaxRange(found), length: text.length - NSMaxRange(found))).location == NSNotFound {
                selection = found; focusRange = nil
                DispatchQueue.main.async { [weak self] in self?.focusRange = found }
            } else { status = "该原句已修改或有多个匹配，可在历史版本中查看对应划线。" }
        }
    }
    func toggleComment(_ id: UUID) {
        guard let index = draft?.annotations.firstIndex(where: { $0.id == id }) else { return }
        draft?.annotations[index].enabled.toggle(); persist()
    }
    func changeComment(_ id: UUID, _ value: String) {
        guard let index = draft?.annotations.firstIndex(where: { $0.id == id }) else { return }
        draft?.annotations[index].comment = value; scheduleSave()
    }
    func restore(_ version: WritingVersion) { guard !busy, !applying else { return }; draft?.restore(version); selection = .init(location: 0, length: 0); error = ""; persist() }
    func refreshSkills() {
        guard !busy else { return }
        if let id = selectedAgentID { selectAgent(id); return }
        let skills = WritingSkillStore.shared.enabledSkills
        guard skills.count <= 8 else { error = "每次修订最多启用 8 个 Skill。"; return }
        draft?.skills = skills; persist(); status = "已使用当前启用的 Skill 版本。"
    }
    func run() {
        guard agentStore == nil || (agentStore?.loadFailed == false && draft?.agent != nil) else { error = "Agent配置不可用，请先检查设置。"; return }
        guard !busy, !applying, let draft, let connection = connections.first(where: { $0.id == connectionID }) else { error = "请选择可用模型连接。"; return }
        guard !draft.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.requirements.isEmpty else { error = "请添加批注或填写整体修改要求。"; return }
        do { try draft.validate(); try validateTarget?() }
        catch { self.error = error.localizedDescription; return }
        guard persist() else { return }
        let id = UUID(); generation = id; busy = true; error = ""; showOriginal = false
        let system = draft.agent.map { AgentContextBuilder.system($0, operation: .revision) }
            ?? (config.systemPrompt + "\n写作偏好：" + config.writingPreferences)
        let lease = runs.begin(timeout: runTimeout) { [weak self] reason in self?.stop(reason: reason) }
        runID = lease
        task = Task { [weak self, agent, runs] in
            defer { runs.finish(lease) }
            do {
                let proposal = try await agent.run(draft: draft, connection: connection, system: system, instruction: draft.instruction) { [weak self] stage in
                    guard self?.generation == id else { return }; self?.status = stage
                }
                guard let self, self.generation == id else { return }
                self.task = nil; self.runID = nil
                self.draft?.accept(proposal, instruction: draft.instruction); self.busy = false; self.selection = .init(location: 0, length: 0)
                self.status = proposal.formattingNote.map { $0 + " 请检查修改建议。" } ?? "修订完成，请检查逐条处理说明与候选稿。"; self.persist()
            } catch {
                guard let self, self.generation == id else { return }; self.busy = false
                self.task = nil; self.runID = nil
                self.error = error is CancellationError ? "已停止，上一稿和批注已保留。" : error.localizedDescription
            }
        }
    }
    func stop(reason: AIRunStopReason = .user) {
        guard !applying else { return }
        task?.cancel(); task = nil; runs.finish(runID); runID = nil
        generation = UUID(); busy = false; error = ""; status = reason.message; persist()
    }
    func suspend() { if busy { stop(reason: .leftNote) } }
    @discardableResult func persist() -> Bool {
        saveTask?.cancel()
        guard var draft else { return false }; draft.updatedAt = Date(); self.draft = draft
        do { guard let store else { throw AIError.message("无法保存修订草稿。") }; try store.save(draft); return true }
        catch { self.error = "草稿保存失败：" + error.localizedDescription; return false }
    }
    private func scheduleSave() {
        saveTask?.cancel(); saveTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 400_000_000); try Task.checkCancellation(); self?.persist() } catch { }
        }
    }
    func apply(insertAfter: Bool) {
        guard canApply, let draft, let applyTarget else { return }
        do { try validateTarget?() } catch { self.error = error.localizedDescription; return }
        guard persist() else { return }
        applying = true
        task = Task { [weak self] in
            do {
                try await applyTarget(draft, insertAfter)
                guard let self else { return }; self.applying = false
                // Keep the snapshot saved before writing. Notes owns Undo; after
                // undoing, reopening must recover the same annotations/history.
                // The baseline check still prevents applying it to changed text.
                self.draft = nil
                self.status = "已应用到 Notes，可使用原生撤销。"; self.onApplied?()
            } catch { self?.applying = false; self?.error = error.localizedDescription + " 未自动重试，请检查 Notes。" }
        }
    }
    func addOriginalQuote(_ quote: String) {
        guard !busy, let draft, !quote.isEmpty else { return }
        let text = draft.candidate as NSString, range = text.range(of: quote)
        guard range.location != NSNotFound,
              text.range(of: quote, range: NSRange(location: NSMaxRange(range), length: text.length - NSMaxRange(range))).location == NSNotFound else {
            error = "这段原文在候选稿中无法唯一定位，请直接在候选稿选区批注。"; return
        }
        showOriginal = false; selection = range; focusRange = range; status = "已定位 Notes 选区，请填写批注。"
    }
}
