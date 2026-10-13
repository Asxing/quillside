import AppKit
import SwiftUI

@MainActor final class PiConnectionsModel: ObservableObject {
    @Published var providers: [PiProvider] = []
    @Published var models: [PiModel] = []
    @Published var providerID = "openai"
    @Published var modelID = ""
    @Published var filter = ""
    @Published var key = ""
    @Published var message = ""
    @Published var busy = false
    @Published var prompt: PiPrompt?
    @Published var reply = ""
    @Published var authURL: URL?
    @Published var deviceCode = ""
    private var task: Task<Void, Never>?
    private var operation: PiProcessOperation?
    private var generation = UUID()
    private var lease: UUID?
    var provider: PiProvider? { providers.first { $0.id == providerID } }
    var matchingModels: [PiModel] { models.filter { filter.isEmpty || ($0.name + $0.id).localizedCaseInsensitiveContains(filter) } }

    func load() { run { [self] in
        let result = try await PiRuntime.call(["method": "catalog"])
        providers = (result.providers ?? []).sorted { rank($0.id) < rank($1.id) }
        try await loadModels()
        message = "Pi " + (result.version ?? "") + " · 模型目录已就绪"
    } }
    private func rank(_ id: String) -> String {
        let preferred = ["openai", "openai-codex", "anthropic", "github-copilot", "google", "deepseek", "openrouter"]
        return preferred.firstIndex(of: id).map { "0\($0)" } ?? "1" + id
    }
    private func loadModels() async throws {
        let result = try await PiRuntime.call(["method": "models", "provider": providerID])
        models = result.models ?? []
        if !models.contains(where: { $0.id == modelID }) { modelID = "" }
    }
    func selectProvider(_ id: String) {
        guard !busy else { return }; providerID = id; key = ""; filter = ""
        run { [self] in try await loadModels(); message = "" }
    }
    func login() {
        run { [self] in
            let op = try PiRuntime.operation(login: true); operation = op
            message = "请在浏览器完成服务商授权。"
            _ = try await PiRuntime.call(["method": "login", "provider": providerID], operation: op) { [weak self] event in self?.receive(event) }
            authURL = nil; prompt = nil; reply = ""; deviceCode = ""
            let catalog = try await PiRuntime.call(["method": "catalog"])
            providers = (catalog.providers ?? []).sorted { rank($0.id) < rank($1.id) }
            message = "授权已保存。选择模型后点击“使用此模型”。"
        }
    }
    private func receive(_ event: PiEvent) {
        if event.type == "prompt" { prompt = event.prompt; reply = event.prompt?.options?.first?.id ?? "" }
        if event.type == "promptClosed" { prompt = nil; reply = "" }
        if let auth = event.event {
            if let text = auth.message { message = text }
            if auth.type == "auth_url", let raw = auth.url, let url = URL(string: raw), url.scheme == "https" {
                authURL = url; NSWorkspace.shared.open(url)
            }
            if auth.type == "device_code" {
                deviceCode = auth.userCode ?? ""
                if let raw = auth.verificationUri, let url = URL(string: raw), url.scheme == "https" { authURL = url; NSWorkspace.shared.open(url) }
            }
        }
    }
    func submitReply() { operation?.reply(reply); prompt = nil; reply = "" }
    func saveKey() {
        let entered = key
        run { [self] in
            _ = try await PiRuntime.call(["method": "saveKey", "provider": providerID, "key": entered])
            key = ""
            let result = try await PiRuntime.call(["method": "catalog"])
            providers = (result.providers ?? []).sorted { rank($0.id) < rank($1.id) }
            message = "API Key 已由 Pi 保存。"
        }
    }
    func logout() { run { [self] in
        _ = try await PiRuntime.call(["method": "logout", "provider": providerID])
        let result = try await PiRuntime.call(["method": "catalog"])
        providers = (result.providers ?? []).sorted { rank($0.id) < rank($1.id) }
        message = "已移除此应用中的授权，不影响其他客户端。"
    } }
    func useModel(_ store: ConfigurationStore) {
        guard let provider, let model = models.first(where: { $0.id == modelID }) else { return }
        do {
            var next = store.committed
            let saved = next.connections.first { $0.piProvider == providerID && $0.model == modelID }
            let connection = saved ?? ModelConnection(name: provider.name + " · " + model.name,
                model: modelID, maxOutputTokens: min(8192, model.maxTokens), piProvider: providerID)
            if saved == nil { next.connections.append(connection) }
            next.selectedConnectionID = connection.id
            try store.commit(next); message = "已使用 " + connection.name
        } catch { message = error.localizedDescription }
    }
    func test(_ connection: ModelConnection) { run { [self] in
        message = connection.piProvider == nil ? "正在读取旧连接的钥匙串密钥；如系统询问，请在系统窗口确认。测试只发送固定文字。" : "正在通过 Pi 测试所选模型，只发送固定文字。"
        let result = try await PiRuntime.generate(connection: connection, system: "Follow the instruction.", user: "Reply with exactly OK.", allowAuthentication: true) { _ in }
        message = "Pi 生成与流式结束测试成功：" + String(result.prefix(100))
    } }
    func selectSaved(_ connection: ModelConnection, store: ConfigurationStore) {
        do { var next = store.committed; next.selectedConnectionID = connection.id; try store.commit(next) }
        catch { message = error.localizedDescription }
    }
    func removeSaved(_ connection: ModelConnection, store: ConfigurationStore) {
        guard connection.piProvider != nil else { return }
        do {
            var next = store.committed; next.connections.removeAll { $0.id == connection.id }
            if next.selectedConnectionID == connection.id { next.selectedConnectionID = next.connections.first?.id }
            try store.commit(next); message = "模型已移除，服务商授权仍保留。"
        } catch { message = error.localizedDescription }
    }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; message = "处理中…"
        let id = UUID(); generation = id
        let run = AIRunRegistry.shared.begin(timeout: 600) { [weak self] _ in self?.stop() }; lease = run
        task = Task { [weak self] in
            defer { AIRunRegistry.shared.finish(run) }
            do { try await work() } catch {
                if self?.generation == id { self?.message = error is CancellationError ? "操作已停止。" : error.localizedDescription }
            }
            guard let self, generation == id else { return }
            busy = false; task = nil; operation = nil; lease = nil
        }
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil; operation?.cancel(); operation = nil
        AIRunRegistry.shared.finish(lease); lease = nil; busy = false; prompt = nil; reply = ""; authURL = nil; deviceCode = ""; key = ""
        message = "操作已停止，原文与批注保留。"
    }
}

struct ConnectionsView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @ObservedObject private var runs = AIRunRegistry.shared
    @StateObject private var model = PiConnectionsModel()
    @State private var showLegacy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("模型与授权").font(.headline)
                    Spacer()
                    Text("Pi Agent").foregroundStyle(.secondary)
                    Button("刷新") { model.load() }.disabled(model.busy)
                }
                Text("选择服务商并授权，模型调用由 Pi 管理。Agent 角色和 Skill 仍在 Notes 中使用。")
                    .font(.caption).foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("服务商", selection: Binding(get: { model.providerID }, set: model.selectProvider)) {
                            if model.providers.isEmpty { Text("正在载入…").tag("openai") }
                            ForEach(model.providers) { Text($0.name).tag($0.id) }
                        }.disabled(model.busy)
                        if let provider = model.provider {
                            HStack {
                                Text(provider.credential == "oauth" ? "已授权订阅" : provider.credential == "api_key" ? "已保存 API Key" : "尚未授权").foregroundStyle(.secondary)
                                Spacer()
                                if provider.oauth {
                                    Button(model.providerID == "openai" ? "使用 ChatGPT 登录" : "登录订阅") { model.login() }.disabled(model.busy)
                                }
                                if provider.credential != nil { Button("退出授权") { model.logout() }.disabled(model.busy) }
                            }
                            if model.providerID == "openai" {
                                Text("ChatGPT 登录使用授权的订阅额度；API Key 使用 API 账户额度。具体模型与额度由服务商决定。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if provider.apiKey {
                                HStack {
                                    SecureField("API Key", text: $model.key).textFieldStyle(.roundedBorder)
                                    Button("保存密钥") { model.saveKey() }.disabled(model.key.isEmpty || model.busy)
                                }.disabled(model.busy)
                            }
                        }
                        if let url = model.authURL { Button("重新打开授权网页") { NSWorkspace.shared.open(url) } }
                        if !model.deviceCode.isEmpty { Text(model.deviceCode).font(.title3.monospaced()).textSelection(.enabled) }
                        if let prompt = model.prompt {
                            Text(prompt.type == "manual_code" ? "浏览器未自动返回时，可粘贴完整回调地址：" : prompt.message).font(.caption)
                            HStack {
                                if let options = prompt.options {
                                    Picker("选择", selection: $model.reply) { ForEach(options) { Text($0.label).tag($0.id) } }.labelsHidden()
                                } else { SecureField(prompt.placeholder ?? "授权信息", text: $model.reply).textFieldStyle(.roundedBorder) }
                                Button("继续") { model.submitReply() }.disabled(model.reply.isEmpty)
                            }
                        }
                        if model.busy { Button("停止") { model.stop() } }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                HStack {
                    TextField("筛选模型", text: $model.filter).textFieldStyle(.roundedBorder)
                    Picker("模型", selection: $model.modelID) {
                        Text("选择模型").tag("")
                        ForEach(model.matchingModels) { Text($0.name + " · " + $0.id).tag($0.id) }
                    }
                    Button("使用此模型") { model.useModel(store) }.disabled(model.busy || model.modelID.isEmpty)
                }.disabled(model.busy)
                Text(model.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                Text("Notes 中可选的模型").font(.headline)
                ForEach(store.committed.connections) { connection in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(connection.name)
                            Text(connection.piProvider.map { "Pi · " + $0 + " / " + connection.model } ?? "兼容连接 · Pi 执行")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.committed.selectedConnectionID == connection.id { Image(systemName: "checkmark.circle") }
                        Button("默认") { model.selectSaved(connection, store: store) }.disabled(model.busy)
                        Button("测试") { model.test(connection) }.disabled(model.busy)
                        if connection.piProvider != nil { Button("移除") { model.removeSaved(connection, store: store) }.disabled(model.busy) }
                    }
                }
                Text(runs.activeCount == 0 ? "当前没有运行中的 AI 任务" : "正在运行 \(runs.activeCount) 个任务")
                    .font(.caption).foregroundStyle(.secondary)
                if runs.activeCount > 0 { Button("停止全部任务") { runs.cancelAll() } }
                DisclosureGroup("自定义服务与旧配置", isExpanded: $showLegacy) {
                    LegacyConnectionsView().frame(minHeight: 590)
                }
                Text("Pi 授权只保存在本机此应用的独立目录，不读取 Codex 或 Magpie 登录。结束或停止任务会关闭运行进程。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.task { model.load() }.onDisappear { model.stop() }
            .onChange(of: model.filter) { _, _ in
                if !model.matchingModels.contains(where: { $0.id == model.modelID }) { model.modelID = "" }
            }
    }
}
