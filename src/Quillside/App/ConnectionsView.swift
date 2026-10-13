import SwiftUI
import AppKit

struct LegacyConnectionsView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @ObservedObject private var runs = AIRunRegistry.shared
    @State private var editor = ConnectionEditorState()
    @State private var key = ""
    @State private var message = ""
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    @State private var testID = UUID()
    @State private var testRunID: UUID?
    private var draft: ModelConnection { editor.draft }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(runs.activeCount == 0 ? "当前没有运行中的 AI 任务" : "正在运行 \(runs.activeCount) 个 AI 任务")
                        Spacer()
                        if runs.activeCount > 0 { Button("停止全部 AI 任务") { runs.cancelAll() } }
                    }
                    Text("离开原笔记或休眠会停止生成，批注草稿保留。请求无有效进展90秒、单次请求4分钟或整轮修订10分钟后自动停止；恢复草稿不会自动连接模型。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Text("配置自己的模型服务").font(.headline)
                    Spacer()
                    Button("新连接") { editor.create(); key = ""; message = "" }.disabled(testing)
                }
                ForEach(store.value.connections.filter { $0.piProvider == nil }) { connection in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(connection.name).fontWeight(.medium)
                            Text(connection.model).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(editor.editingID == connection.id ? "正在编辑" : "编辑") {
                            editor.edit(connection); key = ""; message = "已载入连接。API Key 留空即可保留已保存的密钥。"
                        }.disabled(testing).accessibilityLabel("编辑连接：" + connection.name)
                        if store.value.selectedConnectionID == connection.id { Label("默认", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                        Button("设为默认") { store.value.selectedConnectionID = connection.id; saveConfig() }
                        Button("删除") {
                            do {
                                try store.deleteConnection(connection.id)
                                if editor.editingID == connection.id { editor.reconcile(store.committed); key = "" }
                            } catch { message = error.localizedDescription }
                        }
                    }.padding(10)
                        .background(editor.editingID == connection.id ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                Divider()
                Text(editor.editingID == nil ? "新建模型连接" : "编辑已有连接：" + draft.name).font(.headline)
                Form {
                    TextField("名称", text: $editor.draft.name)
                    Picker("协议", selection: Binding(get: { editor.draft.api }, set: { editor.selectProtocol($0) })) { ForEach(ModelProtocol.allCases) { api in Text(api.title).tag(api) } }
                    TextField("Base URL", text: $editor.draft.baseURL)
                    TextField("模型 ID", text: $editor.draft.model)
                    SecureField("API Key（Ollama 可留空）", text: $key)
                    TextField("最大输出 token", value: $editor.draft.maxOutputTokens, format: .number)
                }.textFieldStyle(.roundedBorder).disabled(testing)
                if editor.editingID != nil { Text("API Key 留空会保留已保存的密钥；修改后点击“保存修改”。").font(.caption).foregroundStyle(.secondary) }
                Text(verbatim: "地址填写 API 根路径：OpenAI 为 https://api.openai.com/v1；DeepSeek 为 https://api.deepseek.com；Anthropic 为 https://api.anthropic.com/v1；Ollama 为 http://127.0.0.1:11434。")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button(editor.editingID == nil ? "保存新连接" : "保存修改") {
                        do {
                            editor.edit(try store.saveConnection(draft, newKey: key))
                            key = ""
                            message = store.status
                        } catch { message = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).disabled(testing)
                    Button(testing ? "测试中…" : "用合成文本测试") { testConnection() }.disabled(testing)
                    if testing { Button("停止测试") { stopTest() } }
                    Button("清除该连接密钥") { do { try store.clearCredential(draft.id); key = ""; if let saved = store.value.connections.first(where: { $0.id == draft.id }) { editor.edit(saved) }; message = store.status } catch { message = error.localizedDescription } }.disabled(testing || editor.editingID == nil)
                }
                Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                HStack {
                    Button("导出 AI 与模板配置（不含密钥）") { exportConfiguration() }
                    Button("导入 AI 与模板配置") { importConfiguration() }
                }
                Text(store.status).font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }
        .onAppear {
            var legacy = store.committed
            legacy.connections = legacy.connections.filter { $0.piProvider == nil }
            if !legacy.connections.contains(where: { $0.id == legacy.selectedConnectionID }) { legacy.selectedConnectionID = legacy.connections.first?.id }
            editor.open(legacy)
        }
        .onDisappear { if testing { stopTest() } }
    }
    private func saveConfig() { do { try store.save() } catch { message = error.localizedDescription } }
    private func testConnection() {
        testing = true; message = "正在读取钥匙串；如系统弹窗询问，请在系统窗口允许。测试仅发送固定文字。"
        let connection = draft, enteredKey = key
        let id = UUID(); testID = id
        let lease = runs.begin(timeout: AIRunRegistry.quickLimit) { reason in stopTest(reason: reason) }
        testRunID = lease
        testTask = Task {
            defer { runs.finish(lease) }
            do {
                if enteredKey.isEmpty, let old = store.value.connections.first(where: { $0.id == connection.id }),
                   !connection.hasSameCredentialOrigin(as: old) {
                    throw AIError.message("测试地址与已保存服务不同，请输入该服务的密钥。")
                }
                let secret = try await enteredKey.isEmpty ? ProviderKeychain.readAuthorized(connection.keychainID, allowAuthentication: true) : enteredKey
                try Task.checkCancellation()
                guard testID == id else { return }
                message = "正在用固定文字测试模型，不发送笔记。"
                let result = try await PiRuntime.generate(connection: connection, system: "Follow the instruction.", user: "Reply with exactly OK.", keyOverride: secret) { _ in }
                try Task.checkCancellation()
                guard testID == id else { return }
                message = "生成与流式结束测试成功：" + String(result.prefix(120))
            } catch {
                guard testID == id else { return }
                message = error is CancellationError ? "测试已停止。" : error.localizedDescription
            }
            testing = false
            testTask = nil; testRunID = nil
        }
    }
    private func stopTest(reason: AIRunStopReason = .user) {
        testTask?.cancel(); testTask = nil; testID = UUID(); testing = false
        runs.finish(testRunID); testRunID = nil
        message = reason.message + " 若系统验证窗口仍在等待，可以在该窗口取消。"
    }
    private func exportConfiguration() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Quillside-settings.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try AppFiles.save(store.value, to: url); message = "配置已导出，不含密钥。" } catch { message = error.localizedDescription }
    }
    private func importConfiguration() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url); guard data.count < 5_000_000 else { throw AIError.message("配置文件过大。") }
            let config = try JSONDecoder().decode(AIConfiguration.self, from: data); try config.validate()
            try store.importConfiguration(config)
            editor = ConnectionEditorState(); editor.open(store.committed); key = ""
            message = "配置已导入，请为导入的连接单独保存密钥。"
        } catch { message = error.localizedDescription }
    }
}
