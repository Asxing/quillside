import Foundation
import Combine

@MainActor final class AgentStore: ObservableObject {
    static let shared = AgentStore()
    struct Catalog: Codable, Equatable {
        var schema = 2
        var profiles: [AgentProfile]
        var defaultID: UUID
        func validate() throws {
            guard (1...2).contains(schema), !profiles.isEmpty, profiles.count <= 100,
                  Set(profiles.map(\.id)).count == profiles.count, profiles.contains(where: { $0.id == defaultID }) else { throw AIError.message("Agent配置版本、角色ID或默认角色无效。") }
            try profiles.forEach { try $0.validate() }
        }
    }
    @Published private(set) var catalog: Catalog
    @Published private(set) var status = ""
    @Published private(set) var loadFailed = false
    /// Shared choice for the next inline entry; saved note sessions keep theirs.
    var activeID: UUID
    private let file: URL?
    private let persist: (Catalog, URL) throws -> Void
    init(file: URL? = nil, legacy: AIConfiguration? = nil, enabledSkills: [WritingSkill]? = nil,
         persist: @escaping (Catalog, URL) throws -> Void = { try AppFiles.save($0, to: $1) }) {
        let config = legacy ?? ConfigurationStore.shared.committed
        let skills = enabledSkills ?? WritingSkillStore.shared.enabledSkills
        let inheritedPrompt = config.systemPrompt + (config.writingPreferences.isEmpty ? "" : "\n\n写作偏好：" + config.writingPreferences)
        let old = AgentProfile(name: "默认助手（原配置）", prompt: inheritedPrompt,
            skillIDs: skills.map(\.id), isLegacy: true)
        let newRoles = AgentProfile.presets(skillIDs: skills.filter { $0.name == "humanizer-zh" }.map(\.id))
        let initial = Catalog(profiles: [old] + newRoles, defaultID: old.id)
        catalog = initial; activeID = initial.defaultID; self.persist = persist
        self.file = file ?? (try? AppFiles.directory().appendingPathComponent("agents.json"))
        do {
            if legacy == nil, ConfigurationStore.shared.loadFailed { throw AIError.message("原模型/提示词配置无法读取，请先恢复原配置。") }
            guard let url = self.file else { throw AIError.message("Agent配置目录不可访问。") }
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                guard data.count <= 4_000_000 else { throw AIError.message("Agent配置超过4MB。") }
                let loaded = try JSONDecoder().decode(Catalog.self, from: data); try loaded.validate()
                var upgraded = loaded
                upgraded.schema = 2
                upgraded.profiles = loaded.profiles.map { $0.upgradingBuiltInStyle() }
                if upgraded != loaded {
                    let backup = url.deletingLastPathComponent().appendingPathComponent("agents-before-prompt-v3-\(UUID().uuidString).json")
                    try data.write(to: backup, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
                    try upgraded.validate(); try persist(upgraded, url)
                    status = "已将旧角色合并为一份 Prompt；原配置已备份。"
                }
                catalog = upgraded; activeID = upgraded.defaultID
            } else {
                // Back up legacy values before the first write. No credential
                // reads and no rewrite of settings.json or old note drafts.
                try initial.validate()
                let backup = url.deletingLastPathComponent().appendingPathComponent("before-agent-migration-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try AppFiles.save(config, to: backup.appendingPathComponent("settings.json"))
                try AppFiles.save(skills, to: backup.appendingPathComponent("enabled-skills.json"))
                try persist(initial, url)
                status = "已保留原配置，并加入三个场景Agent。"
            }
        } catch { loadFailed = true; status = "读取或迁移Agent失败，原文件保留：" + error.localizedDescription }
    }
    func snapshot(id: UUID? = nil, skills: [WritingSkill]) throws -> AgentSnapshot {
        guard !loadFailed, let profile = catalog.profiles.first(where: { $0.id == (id ?? activeID) }) else { throw AIError.message("Agent配置不可用，请先检查设置。") }
        return try AgentContextBuilder.resolve(profile: profile, availableSkills: skills)
    }
    func save(_ profile: AgentProfile) throws {
        var next = catalog; var replacement = profile
        if let index = next.profiles.firstIndex(where: { $0.id == profile.id }) {
            replacement.revision = next.profiles[index].revision + 1; next.profiles[index] = replacement
        } else { next.profiles.append(replacement) }
        try commit(next)
    }
    func setDefault(_ id: UUID) throws { var next = catalog; next.defaultID = id; try commit(next); activeID = id }
    func delete(_ id: UUID) throws {
        guard catalog.profiles.count > 1 else { throw AIError.message("至少保留一个Agent。") }
        var next = catalog; next.profiles.removeAll { $0.id == id }
        if next.defaultID == id { next.defaultID = next.profiles[0].id }
        try commit(next); if activeID == id { activeID = next.defaultID }
    }
    private func commit(_ next: Catalog) throws {
        guard !loadFailed, let file else { throw AIError.message("Agent配置无法读取，未覆盖原文件。") }
        try next.validate()
        guard try JSONEncoder().encode(next).count <= 4_000_000 else { throw AIError.message("Agent配置过大。") }
        try persist(next, file); catalog = next; status = "已保存；当前运行中的任务保持原版本。"
    }
}
