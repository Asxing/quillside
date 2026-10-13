import SwiftUI
import AppKit
import ServiceManagement

struct WorkspaceView: View {
    @ObservedObject private var model = WorkspaceModel.shared
    @ObservedObject private var store = ConfigurationStore.shared
    var body: some View {
        NavigationSplitView {
            List(WorkspaceSection.allCases, selection: $model.section) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationTitle("OpenNotes")
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            VStack(alignment: .leading, spacing: 7) {
                Text("Apple Notes · 原生增强").font(.caption)
                Text("模型自选 · 密钥留在 Keychain").font(.caption2).foregroundStyle(.secondary)
                Button("权限与快捷键…") {
                    let appState = (NSApp.delegate as? AppDelegate)?.appState ?? AppState()
                    SettingsWindowController.shared.show(appState: appState)
                }.buttonStyle(.link)
            }.padding()
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Label(model.section.rawValue, systemImage: model.section.symbol).font(.title2.bold())
                    Spacer()
                    if model.busy || model.indexing { ProgressView().controlSize(.small) }
                }.padding(22)
                Divider()
                Group {
                    switch model.section {
                    case .writing: writing
                    case .search: notesSearch
                    case .knowledge: knowledge
                    case .connections: ConnectionsView()
                    case .prompts: PromptLibraryView()
                    case .templates: TemplateLibraryView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                Text(model.status.isEmpty ? "OpenNotes 0.1 · 本地开发版本" : model.status)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .textSelection(.enabled)
            }
        }
    }
    private var writing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("模型", selection: $store.value.selectedConnectionID) {
                        Text("选择连接").tag(nil as UUID?)
                        ForEach(store.value.connections) { item in Text(item.name + " · " + item.model).tag(Optional(item.id)) }
                    }.disabled(model.busy)
                    Button("配置…") { model.section = .connections }
                }
                HStack {
                    Picker("指令", selection: $model.promptID) {
                        ForEach(store.value.prompts) { action in Text(action.name).tag(Optional(action.id)) }
                    }.disabled(model.busy)
                    TextField("目标语言", text: $model.language).frame(width: 100)
                }
                TextField("补充要求或知识库问题", text: $model.instruction, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4).disabled(model.busy)
                HStack {
                    Toggle("使用知识库", isOn: $model.useKnowledge).disabled(model.busy)
                    if model.useKnowledge { Picker("集合", selection: $model.collection) { Text("全部").tag(nil as String?); if let selected = model.collection, !model.selectedCollectionExists { Text("原集合已变化，请重新选择").tag(Optional(selected)) }; ForEach(model.collections) { Text($0.label).tag(Optional($0.id)) } }.frame(maxWidth: 270).disabled(model.busy) }
                    Spacer()
                }
                GroupBox {
                    TextEditor(text: $model.input).font(.body).frame(minHeight: 140)
                        .disabled(model.busy).accessibilityLabel("输入材料")
                } label: { Label(model.targetName, systemImage: "doc.text") }
                Text("在 Notes 中选中文字后，从菜单栏选择“捕获选区并写作”。也可以直接在这里输入材料。")
                    .font(.caption).foregroundStyle(.secondary)
                if let connection = store.selectedConnection {
                    Text("生成将向 \(URL(string: connection.baseURL)?.host ?? connection.baseURL) 发送上方材料、指令及选定的知识片段。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("生成", systemImage: "sparkles") { model.generate() }.buttonStyle(.borderedProminent).disabled(model.busy)
                    if model.busy { Button("取消") { model.cancel() } }
                    Spacer()
                    Text(model.complete ? "已完整生成" : "候选结果").font(.caption).foregroundStyle(.secondary)
                }
                GroupBox("结果预览") {
                    TextEditor(text: $model.result).frame(minHeight: 180).disabled(model.busy).accessibilityLabel("结果预览")
                }
                HStack {
                    Button("复制结果") { model.copy(model.result) }.disabled(model.result.isEmpty)
                    Button("替换原选区") { model.apply(insertAfter: false) }.disabled(!model.complete || !model.writeAvailable || !model.hasSelectedText || model.busy)
                    Button("插入选区后") { model.apply(insertAfter: true) }.disabled(!model.complete || !model.writeAvailable || model.busy)
                }
                if !model.answerSources.isEmpty { sourceList(model.answerSources) }
            }.padding(22)
        }
        .onChange(of: model.input) { _, _ in model.clearTargetIfInputChanged() }
        .onChange(of: store.value.selectedConnectionID) { _, _ in do { try store.save() } catch { model.status = error.localizedDescription } }
        .onChange(of: model.promptID) { _, id in if store.value.prompts.first(where: { $0.id == id })?.name == "知识库问答" { model.useKnowledge = true } }
    }
    private var notesSearch: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("搜索标题、摘要或文件夹", text: $model.noteQuery).textFieldStyle(.roundedBorder)
                Button("加载 Notes") { model.loadNotes() }.disabled(model.indexing)
            }
            Text("点击打开笔记；勾选后可把正文快照加入个人知识库。数据库始终只读。")
                .font(.caption).foregroundStyle(.secondary)
            List(model.filteredNotes) { note in
                HStack {
                    Toggle("选中", isOn: Binding(get: { model.selectedNotes.contains(note.identifier) }, set: { on in if on { model.selectedNotes.insert(note.identifier) } else { model.selectedNotes.remove(note.identifier) } })).labelsHidden()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title).font(.headline)
                        Text(note.folderName + " · " + note.snippet).lineLimit(2).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开") { model.openSource(NotesDBReader.shared.buildNoteURL(identifier: note.identifier)) }
                }.padding(.vertical, 4)
            }
            HStack {
                Text("已选 \(model.selectedNotes.count) 篇").foregroundStyle(.secondary)
                Spacer()
                Button("清除选择") { model.selectedNotes = [] }
                Button("导入所选正文") { model.importSelectedNotes() }.disabled(model.selectedNotes.isEmpty || model.indexing).buttonStyle(.borderedProminent)
            }
        }.padding(22)
    }
    @State private var retrievalQuery = ""
    private var knowledge: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("保存你主动导入的资料快照，在本机分词和检索。生成回答时只发送召回片段；来源更新后需要刷新快照。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("添加 Markdown / 文本 / PDF") { model.chooseFiles() }
                    Button("从 Notes 选择") { model.section = .search; model.loadNotes() }
                    Button("更新 Notes 快照") { model.refreshNotesSnapshots() }
                }.disabled(model.indexing || model.busy)
                GroupBox("资料 · \(model.documents.count)") {
                    if model.documents.isEmpty {
                        ContentUnavailableView("还没有资料", systemImage: "books.vertical", description: Text("选择需要用于问答的笔记或文件。"))
                    } else {
                        ForEach(model.documents) { document in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(document.title).font(.headline)
                                    Text((document.collectionDetail.isEmpty ? "" : document.collectionDetail + " / ") + document.collection + " · " + Date(timeIntervalSince1970: document.indexedAt).formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("原文") { model.openSource(document.locator) }
                                Button("移除") { model.removeDocument(document.id) }.disabled(model.indexing || model.busy)
                            }.padding(8)
                            Divider()
                        }
                    }
                }
                HStack {
                    TextField("先试试检索，例如：合同", text: $retrievalQuery).textFieldStyle(.roundedBorder)
                    Picker("集合", selection: $model.collection) { Text("全部").tag(nil as String?); if let selected = model.collection, !model.selectedCollectionExists { Text("原集合已变化，请重新选择").tag(Optional(selected)) }; ForEach(model.collections) { Text($0.label).tag(Optional($0.id)) } }.frame(width: 180)
                    Button("本地检索") { model.previewRetrieval(retrievalQuery) }.disabled(model.busy)
                }
                if !model.retrievalHits.isEmpty { sourceList(model.retrievalHits) }
                Button("使用这些资料提问", systemImage: "text.bubble") {
                    model.instruction = retrievalQuery; model.useKnowledge = true
                    model.promptID = store.value.prompts.first(where: { $0.name == "知识库问答" })?.id
                    model.section = .writing
                }
            }.padding(22)
        }
    }
    private func sourceList(_ hits: [KnowledgeHit]) -> some View {
        GroupBox("本次参考资料") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                    VStack(alignment: .leading, spacing: 4) {
                        Button("[S\(i + 1)] \(hit.title)") { model.openSource(hit.locator) }.buttonStyle(.link)
                        Text(hit.text).font(.caption).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
}

struct ConnectionsView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var draft = ModelConnection()
    @State private var key = ""
    @State private var message = ""
    @State private var testing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("配置自己的模型服务").font(.headline)
                    Spacer()
                    Button("新连接") { draft = ModelConnection(); key = ""; message = "" }
                }
                ForEach(store.value.connections) { connection in
                    HStack {
                        Button(connection.name + " · " + connection.model) { draft = connection; key = ""; message = "密钥已保存时，留空即可沿用。" }.buttonStyle(.link)
                        Spacer()
                        if store.value.selectedConnectionID == connection.id { Label("默认", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                        Button("设为默认") { store.value.selectedConnectionID = connection.id; saveConfig() }
                        Button("删除") {
                            do {
                                try store.deleteConnection(connection.id)
                            } catch { message = error.localizedDescription }
                        }
                    }
                }
                Divider()
                Form {
                    TextField("名称", text: $draft.name)
                    Picker("协议", selection: $draft.api) { ForEach(ModelProtocol.allCases) { api in Text(api.title).tag(api) } }
                    TextField("Base URL", text: $draft.baseURL)
                    TextField("模型 ID", text: $draft.model)
                    SecureField("API Key（Ollama 可留空）", text: $key)
                    TextField("最大输出 token", value: $draft.maxOutputTokens, format: .number)
                }.textFieldStyle(.roundedBorder)
                Text("地址填写 API 根路径：OpenAI 为 https://api.openai.com/v1；DeepSeek 为 https://api.deepseek.com；Anthropic 为 https://api.anthropic.com/v1；Ollama 为 http://127.0.0.1:11434。")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("保存连接与密钥") {
                        do {
                            draft = try store.saveConnection(draft, newKey: key)
                            key = ""
                            message = store.status
                        } catch { message = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                    Button(testing ? "测试中…" : "用合成文本测试") { testConnection() }.disabled(testing)
                    Button("清除该连接密钥") { do { try store.clearCredential(draft.id); key = ""; if let saved = store.value.connections.first(where: { $0.id == draft.id }) { draft = saved }; message = store.status } catch { message = error.localizedDescription } }
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
        .onChange(of: draft.api) { old, new in if draft.baseURL == old.defaultURL { draft.baseURL = new.defaultURL } }
    }
    private func saveConfig() { do { try store.save() } catch { message = error.localizedDescription } }
    private func testConnection() {
        testing = true; message = "使用固定文字测试，不发送笔记。"
        let connection = draft, enteredKey = key
        Task {
            do {
                if enteredKey.isEmpty, let old = store.value.connections.first(where: { $0.id == connection.id }),
                   !connection.hasSameCredentialOrigin(as: old) {
                    throw AIError.message("测试地址与已保存服务不同，请输入该服务的密钥。")
                }
                let secret = try enteredKey.isEmpty ? ProviderKeychain.read(connection.keychainID) : enteredKey
                let result = try await ModelClient().generate(connection: connection, key: secret, system: "Follow the instruction.", user: "Reply with exactly OK.") { _ in }
                message = "生成与流式结束测试成功：" + String(result.prefix(120))
            } catch { message = error.localizedDescription }
            testing = false
        }
    }
    private func exportConfiguration() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "OpenNotes-settings.json"; panel.allowedContentTypes = [.json]
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
            message = "配置已导入，请为导入的连接单独保存密钥。"
        } catch { message = error.localizedDescription }
    }
}

struct PromptLibraryView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var draft = PromptAction(name: "新指令", instruction: "根据要求处理以下材料：\n{text}")
    @State private var message = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("系统提示词") { TextEditor(text: $store.value.systemPrompt).frame(height: 100) }
                TextField("写作偏好", text: $store.value.writingPreferences, axis: .vertical).textFieldStyle(.roundedBorder)
                HStack { Button("保存系统配置") { save() }; Spacer(); Button("新指令") { draft = .init(name: "新指令", instruction: "{instruction}\n{text}") } }
                ForEach(store.value.prompts) { prompt in
                    HStack {
                        Button(prompt.name) { draft = prompt }.buttonStyle(.link)
                        Spacer()
                        Button("删除") { store.value.prompts.removeAll { $0.id == prompt.id }; save() }
                    }
                }
                Divider()
                TextField("指令名称", text: $draft.name).textFieldStyle(.roundedBorder)
                GroupBox("指令内容") { TextEditor(text: $draft.instruction).frame(height: 160) }
                Text("变量：{text} 材料、{instruction} 补充要求、{language} 目标语言、{sources} 本次知识片段。变量只替换一次，不执行脚本。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("保存指令") {
                    if let i = store.value.prompts.firstIndex(where: { $0.id == draft.id }) { store.value.prompts[i] = draft } else { store.value.prompts.append(draft) }
                    save()
                }.buttonStyle(.borderedProminent)
                Text(message).foregroundStyle(.secondary)
            }.padding(22)
        }
    }
    private func save() { do { try store.save(); message = "已保存" } catch { message = error.localizedDescription } }
}

struct TemplateLibraryView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @ObservedObject private var model = WorkspaceModel.shared
    @State private var draft = SnippetTemplate(name: "新模板", content: "日期：{date}\n")
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("模板无需模型。{date} 为当天日期；设置快捷词后可在 Notes 中用 /快捷词 插入，或输入 /template 搜索中文名称。")
                    .foregroundStyle(.secondary)
                ForEach(store.value.templates) { template in
                    HStack {
                        Button(template.name) { draft = template }.buttonStyle(.link)
                        Spacer()
                        Button("预览与插入") { model.useTemplate(template) }.disabled(model.busy)
                        Button("删除") { store.value.templates.removeAll { $0.id == template.id }; save() }
                    }
                }
                Divider()
                Button("新模板") { draft = .init(name: "新模板", content: "") }
                TextField("名称", text: $draft.name).textFieldStyle(.roundedBorder)
                TextField("快捷词（可选，如 meeting，不含 /）", text: Binding(get: { draft.shortcut ?? "" }, set: { draft.shortcut = $0 })).textFieldStyle(.roundedBorder)
                GroupBox("模板正文") { TextEditor(text: $draft.content).frame(height: 260) }
                Button("保存模板") {
                    if let i = store.value.templates.firstIndex(where: { $0.id == draft.id }) { store.value.templates[i] = draft } else { store.value.templates.append(draft) }
                    save()
                }.buttonStyle(.borderedProminent)
            }.padding(22)
        }
    }
    private func save() { do { try store.save(); model.status = "模板已保存" } catch { model.status = error.localizedDescription } }
}

@MainActor final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 560,height: 520),styleMask: [.titled,.closable],backing: .buffered,defer: false)
        window.title = "OpenNotes 设置"; window.isReleasedWhenClosed = false
        super.init(window: window); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(appState: AppState) {
        window?.contentView = NSHostingView(rootView: SettingsView().environmentObject(appState))
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
}
