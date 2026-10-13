import SwiftUI

struct AgentSettingsView: View {
    @ObservedObject private var store = AgentStore.shared
    @ObservedObject private var skills = WritingSkillStore.shared
    @State private var selectedID: UUID?
    @State private var draft = AgentProfile(name: "新Agent")
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("定义角色 Prompt，选择需要的能力。在 Notes 中切换使用。")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                VStack {
                    List(selection: $selectedID) {
                        ForEach(store.catalog.profiles) { profile in
                            HStack { Text(profile.name); if store.catalog.defaultID == profile.id { Image(systemName: "checkmark").foregroundStyle(.secondary) } }.tag(profile.id)
                        }
                    }.frame(width: 158)
                    Button("新建 Agent") { selectedID = nil; draft = .init(name: "新Agent"); message = "" }
                    Button("复制当前角色") { var copy = draft; copy.id = UUID(); copy.name += " 副本"; copy.revision = 1; selectedID = nil; draft = copy }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        field("名称", text: $draft.name)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Prompt").font(.headline)
                            TextEditor(text: $draft.prompt)
                                .font(.system(size: 13)).scrollContentBackground(.hidden)
                                .padding(8).frame(minHeight: 190)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                .accessibilityLabel("Agent角色Prompt")
                            Text("说明角色是谁、如何处理材料，以及需要遵守的要求。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        Text("Skill").font(.headline)
                        ForEach(skills.catalog.skills) { skill in
                            Toggle(skill.name, isOn: Binding(get: { draft.skillIDs.contains(skill.id) }, set: { checked in
                                if checked { if !draft.skillIDs.contains(skill.id) { draft.skillIDs.append(skill.id) } }
                                else { draft.skillIDs.removeAll { $0 == skill.id } }
                            })).toggleStyle(.checkbox)
                        }
                        ForEach(draft.skillIDs.filter { id in !skills.catalog.skills.contains { $0.id == id } }, id: \.self) { id in
                            HStack { Text("缺失的 Skill").foregroundStyle(.orange); Button("移除引用") { draft.skillIDs.removeAll { $0 == id } } }
                        }
                        HStack {
                            Button("保存 Agent") { save() }.buttonStyle(.borderedProminent)
                            if selectedID != nil {
                                Button("设为默认") { do { try store.setDefault(draft.id); message = "默认Agent已更新。" } catch { message = error.localizedDescription } }
                                Button("删除") {
                                    do { try store.delete(draft.id); selectedID = store.catalog.defaultID }
                                    catch { message = error.localizedDescription }
                                }
                            }
                        }
                        Text("角色共享已配置的模型连接；不会随角色切换账号或服务地址。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.trailing, 6)
                }
            }.disabled(store.loadFailed)
            Text(message.isEmpty ? store.status : message).font(.caption).foregroundStyle(.secondary)
        }.padding(20)
            .onAppear { selectedID = store.catalog.defaultID; load() }
            .onChange(of: selectedID) { _, _ in load() }
    }
    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
        }
    }
    private func load() { if let profile = store.catalog.profiles.first(where: { $0.id == selectedID }) { draft = profile; message = "" } }
    private func save() {
        do {
            _ = try AgentContextBuilder.resolve(profile: draft, availableSkills: skills.catalog.skills)
            try store.save(draft); selectedID = draft.id; load(); message = "Agent已保存。"
        } catch { message = error.localizedDescription }
    }
}
