import SwiftUI
import AppKit

struct SkillLibrarySettingsView: View {
    @State private var pane = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("Skill类型", selection: $pane) {
                Text("简单指令").tag(0)
                Text("Skill 包").tag(1)
            }.pickerStyle(.segmented).padding(16)
            if pane == 0 { PromptLibraryView() } else { WritingSkillsSettingsView() }
        }
    }
}

struct WritingSkillsSettingsView: View {
    @ObservedObject private var store = WritingSkillStore.shared
    @ObservedObject private var agents = AgentStore.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Skill 包").font(.headline); Spacer(); Button("导入 Skill 文件夹…") { importSkill() } }
                Text("已导入的能力在 Agent 中选择使用。支持 SKILL.md 和配套文本资料；更新包不会改变正在执行的任务。")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(store.catalog.skills) { skill in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(skill.name).font(.headline)
                            Spacer()
                            Button("移除") { store.remove(skill.id) }
                                .disabled(agents.catalog.profiles.contains { $0.skillIDs.contains(skill.id) })
                        }
                        Text(skill.description).font(.callout)
                        Text(skill.compatibility).font(.caption).foregroundStyle(.secondary)
                        Text("版本 " + String(skill.fingerprint.prefix(12))).font(.caption.monospaced()).foregroundStyle(.secondary)
                        let users = agents.catalog.profiles.filter { $0.skillIDs.contains(skill.id) }.map(\.name)
                        Text(users.isEmpty ? "尚未绑定Agent" : "用于：" + users.joined(separator: "、"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                Text(store.status).font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
    }
    private func importSkill() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = "选择包含 SKILL.md 的文件夹；同名包会更新，已有Agent绑定保留。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.importFolder(url) } catch { store.status = error.localizedDescription }
    }
}
