import SwiftUI

struct PromptLibraryView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var selectedID: UUID?
    @State private var draft = PromptAction(name: "新指令", instruction: "{instruction}\n{text}")
    @State private var status = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("简单指令").font(.headline)
                Text("保存后会出现在 Notes 的 AI 浮动面板中，点击动作即可处理当前内容。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    VStack {
                        List(selection: $selectedID) { ForEach(store.committed.prompts) { Text($0.name).tag($0.id) } }
                            .frame(width: 155).frame(minHeight: 260)
                        Button("新建动作") { selectedID = nil; draft = .init(name: "新指令", instruction: "{instruction}\n{text}"); status = "" }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("动作名称", text: $draft.name).textFieldStyle(.roundedBorder)
                        Picker("适用动作", selection: Binding(get: { draft.effectiveOperation }, set: { draft.operation = $0 })) {
                            ForEach(AgentOperation.allCases.filter { $0 != .revision }) { Text($0.title).tag($0) }
                        }
                        TextEditor(text: $draft.instruction).frame(minHeight: 225)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                        Text("变量：{text} 当前内容，{instruction} 修改要求，{language} 目标语言。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("保存动作") { savePrompt() }.buttonStyle(.borderedProminent)
                            if selectedID != nil { Button("删除") { deletePrompt() } }
                        }
                    }
                }
                Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(20)
        }
        .onAppear {
            if selectedID == nil, let first = store.committed.prompts.first { selectedID = first.id; draft = first }
        }
        .onChange(of: selectedID) { _, id in
            if let prompt = store.committed.prompts.first(where: { $0.id == id }) { draft = prompt; status = "" }
        }
    }
    private func savePrompt() {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !draft.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "请填写名称和提示词。"; return }
        var next = store.committed
        if let i = next.prompts.firstIndex(where: { $0.id == draft.id }) { next.prompts[i] = draft } else { next.prompts.append(draft) }
        do { try store.commit(next); selectedID = draft.id; status = "动作已保存，可在 Notes 中使用" } catch { status = error.localizedDescription }
    }
    private func deletePrompt() {
        var next = store.committed; next.prompts.removeAll { $0.id == selectedID }
        do { try store.commit(next); selectedID = next.prompts.first?.id; if selectedID == nil { draft = .init(name: "新指令", instruction: "{instruction}\n{text}") }; status = "已删除" } catch { status = error.localizedDescription }
    }
}

struct TemplateLibraryView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var selectedID: UUID?
    @State private var draft = SnippetTemplate(name: "新模板", content: "日期：{date}\n")
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("在这里维护模板；回到 Notes 输入 /快捷词，或 /template 选择并插入。")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                VStack {
                    List(selection: $selectedID) {
                        ForEach(store.committed.templates) { template in
                            VStack(alignment: .leading) {
                                Text(template.name)
                                if let shortcut = TemplateShortcutRules.normalized(template.shortcut) { Text("/" + shortcut).font(.caption).foregroundStyle(.secondary) }
                            }.tag(template.id)
                        }
                    }.frame(width: 170)
                    Button("新建模板") { selectedID = nil; draft = .init(name: "新模板", content: ""); status = "" }
                }
                VStack(alignment: .leading, spacing: 12) {
                    TextField("模板名称", text: $draft.name).textFieldStyle(.roundedBorder)
                    TextField("快捷词，如 meeting（不含 /）", text: Binding(get: { draft.shortcut ?? "" }, set: { draft.shortcut = $0 })).textFieldStyle(.roundedBorder)
                    TextEditor(text: $draft.content).frame(minHeight: 220)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
                    Text("{date} 自动替换为当天日期；目前按纯文本插入。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("保存模板") { save() }.buttonStyle(.borderedProminent)
                        if selectedID != nil { Button("删除") { delete() } }
                    }
                }
            }
            Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(20)
        .onAppear { if selectedID == nil, let first = store.committed.templates.first { selectedID = first.id; draft = first } }
        .onChange(of: selectedID) { _, id in if let item = store.committed.templates.first(where: { $0.id == id }) { draft = item; status = "" } }
    }
    private func save() {
        var next = store.committed
        if let i = next.templates.firstIndex(where: { $0.id == draft.id }) { next.templates[i] = draft } else { next.templates.append(draft) }
        do { try store.commit(next); selectedID = draft.id; status = "模板已保存" } catch { status = error.localizedDescription }
    }
    private func delete() {
        var next = store.committed; next.templates.removeAll { $0.id == selectedID }
        do { try store.commit(next); selectedID = next.templates.first?.id; if selectedID == nil { draft = .init(name: "新模板", content: "") }; status = "已删除" } catch { status = error.localizedDescription }
    }
}
