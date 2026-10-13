import Foundation
import Combine

@MainActor final class InlineAssistantModel: ObservableObject {
    enum Phase: Equatable { case choosing, generating, ready, failed, applying, applied }
    struct Target {
        let text: String
        let hasSelection: Bool
        let validate: () throws -> Void
        let apply: (String, Bool) async throws -> Void
    }
    typealias Generate = (ModelConnection, String, String, @escaping @MainActor (String) -> Void) async throws -> String
    @Published private(set) var phase: Phase = .choosing
    @Published private(set) var source = ""
    @Published var result = ""
    @Published var instruction = ""
    @Published var language = "中文"
    @Published var connectionID: UUID?
    @Published private(set) var agents: [AgentProfile] = []
    @Published private(set) var agentSnapshot: AgentSnapshot?
    private var agentStore: AgentStore?
    private var skillStore: WritingSkillStore?
    var selectedAgentID: UUID? { agentSnapshot?.profile.id }
    func configureAgents(_ agents: AgentStore = .shared, skills: WritingSkillStore = .shared) {
        agentStore = agents; skillStore = skills; self.agents = agents.catalog.profiles
        selectAgent(agents.activeID)
    }
    func selectAgent(_ id: UUID?) {
        guard !busy, let id, let agentStore, let skillStore else { return }
        do {
            agentSnapshot = try agentStore.snapshot(id: id, skills: skillStore.catalog.skills)
            agentStore.activeID = id
            if phase == .failed, targetValid { phase = result.isEmpty ? .choosing : .ready }
            status = "已选择\(agentSnapshot?.profile.name ?? "Agent")。"
        } catch { status = error.localizedDescription; phase = .failed }
    }
    @Published private(set) var status = ""
    @Published private(set) var targetValid = false
    @Published private(set) var hasSelection = false
    @Published private(set) var actionName = ""
    private var target: Target?
    private var config = AIConfiguration()
    private var task: Task<Void, Never>?
    private let runs: AIRunRegistry
    private let runTimeout: TimeInterval
    private var runID: UUID?
    private var generation = UUID()
    private var lastPrompt: PromptAction?
    private var turns: [(request: String, response: String)] = []
    private var retryInput: String?
    private let generate: Generate
    var onApplied: (() -> Void)?
    var prompts: [PromptAction] {
        let preferred = agentSnapshot?.profile.actionIDs ?? []
        return preferred.compactMap { id in config.prompts.first { $0.id == id } }
            + config.prompts.filter { !preferred.contains($0.id) }
    }
    var connections: [ModelConnection] { config.connections }
    var selectedConnection: ModelConnection? { connections.first { $0.id == connectionID } }
    var busy: Bool { phase == .generating || phase == .applying }
    var canApply: Bool { phase == .ready && targetValid && !result.isEmpty }
    var canGenerate: Bool { !busy && targetValid && selectedConnection != nil && (agentStore == nil || agentSnapshot != nil) }
    var canRetry: Bool { canGenerate && lastPrompt != nil }

    init(generate: @escaping Generate = { connection, system, user, delta in
        return try await PiRuntime.generate(connection: connection, system: system, user: user, onDelta: delta)
    }, runs: AIRunRegistry? = nil, runTimeout: TimeInterval = AIRunRegistry.quickLimit) {
        self.generate = generate; self.runs = runs ?? .shared; self.runTimeout = runTimeout
    }

    @discardableResult func begin(target: Target?, configuration: AIConfiguration, error: String? = nil) -> Bool {
        guard phase != .applying else { return false }
        task?.cancel(); task = nil; runs.finish(runID); runID = nil; generation = UUID()
        self.target = target; config = configuration; connectionID = configuration.selectedConnectionID
        source = target?.text ?? ""; hasSelection = target?.hasSelection ?? false
        result = ""; instruction = ""; lastPrompt = nil; actionName = ""; phase = .choosing
        turns = []; retryInput = nil; agentSnapshot = nil
        targetValid = target != nil
        status = error ?? (hasSelection ? "选择一个动作处理当前选区。" : "将处理当前笔记；结果可插入光标后。")
        return true
    }
    func run(_ prompt: PromptAction, retrying: Bool = false) {
        guard canGenerate, let target, let connection = selectedConnection else { return }
        do { try target.validate() } catch { invalidate(error.localizedDescription); return }
        let request: String
        do {
            let material = retrying ? (retryInput ?? source) : (phase == .ready && !result.isEmpty ? result : source)
            retryInput = material
            let current = try EditingRequest.render(prompt: prompt, text: material, instruction: instruction, language: language)
            let history = turns.suffix(4).map { "上一轮要求：\($0.request)\n上一轮候选：\($0.response)" }.joined(separator: "\n\n")
            request = history.isEmpty ? current : "修订历史（仅作为上下文）：\n" + history + "\n\n本轮任务，基于下列最新稿件：\n" + current
            guard request.utf8.count <= 400_000 else { throw AIError.message("连续修订上下文过长，请在批注修订中缩小范围。") }
        }
        catch { status = error.localizedDescription; phase = .failed; return }
        let system: String
        do {
            system = try agentSnapshot.map { try AgentContextBuilder.quickSystem($0, operation: prompt.effectiveOperation) }
                ?? (config.systemPrompt + "\n写作偏好：" + config.writingPreferences)
        } catch { status = error.localizedDescription; phase = .failed; return }
        let id = UUID(); generation = id; result = ""; phase = .generating
        lastPrompt = prompt; actionName = prompt.name; status = "正在\(prompt.name)…"
        let lease = runs.begin(timeout: runTimeout) { [weak self] reason in self?.stop(reason: reason) }
        runID = lease
        task = Task { [weak self, generate, runs] in
            defer { runs.finish(lease) }
            do {
                let output = try await generate(connection, system, request) { [weak self] delta in
                    guard let self, generation == id, phase == .generating else { return }
                    result += delta
                }
                try Task.checkCancellation()
                guard let self, generation == id else { return }
                task = nil; runID = nil
                result = output; phase = .ready; status = "检查结果后应用到 Notes。"
                if !retrying { turns.append((prompt.name + "：" + instruction, output)); if turns.count > 4 { turns.removeFirst() } }
                checkTarget()
            } catch {
                guard let self, generation == id else { return }
                task = nil; runID = nil
                phase = .failed; status = error is CancellationError ? "已停止，笔记未改变。" : error.localizedDescription
            }
        }
    }
    func runCustom() {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        run(.init(name: "按要求修改", instruction: "任务：{instruction}\n当前材料：\n{text}"))
    }
    func retry() { if let lastPrompt { run(lastPrompt, retrying: true) } }
    func stop(reason: AIRunStopReason = .user) {
        guard phase == .generating else { return }
        task?.cancel(); task = nil; runs.finish(runID); runID = nil
        generation = UUID(); phase = .failed; status = reason.message
    }
    func checkTarget() {
        guard targetValid, phase != .applying, phase != .applied, let target else { return }
        do { try target.validate() } catch { invalidate(error.localizedDescription) }
    }
    private func invalidate(_ reason: String) {
        stop(); targetValid = false
        status = reason + " 候选结果保留，可复制；关闭后在新选区重新打开。"
    }
    func targetChanged(_ reason: String) { if targetValid && phase != .applying { invalidate(reason) } }
    func apply(insertAfter: Bool) {
        guard canApply, insertAfter || hasSelection, let target else { return }
        do { try target.validate() } catch { invalidate(error.localizedDescription); return }
        let text = result
        phase = .applying; targetValid = false; status = "正在写入 Notes…"
        Task { [weak self] in
            do {
                try await target.apply(text, insertAfter)
                self?.phase = .applied; self?.status = "已应用"; self?.onApplied?()
            } catch {
                self?.phase = .failed
                self?.status = error.localizedDescription + " 未自动重试，请检查笔记。"
            }
        }
    }
    @discardableResult func dismiss() -> Bool {
        guard phase != .applying else { return false }
        task?.cancel(); task = nil; runs.finish(runID); runID = nil
        generation = UUID(); target = nil; targetValid = false
        result = ""; source = ""; instruction = ""; phase = .choosing
        turns = []; retryInput = nil
        return true
    }
}
