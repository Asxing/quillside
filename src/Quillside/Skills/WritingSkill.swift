import Foundation
import Yams

struct WritingSkill: Codable, Identifiable, Equatable {
    var installationID: String?
    var id: String { installationID ?? fingerprint }
    let name: String
    let description: String
    let instructions: String
    let resources: [String: String]
    let fingerprint: String
    let origin: String
    let tools: [String]
    var compatibility: String
}

enum WritingSkillLoader {
    static let fileLimit = 131_072
    static let packageLimit = 524_288
    static func read(_ folder: URL) throws -> WritingSkill {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        func readText(_ file: URL) throws -> String {
            let resolved = file.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(root.path + "/"),
                  let count = try resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize, count <= fileLimit else {
                throw AIError.message("Skill 文件超出目录或超过 128 KB。")
            }
            let data = try Data(contentsOf: resolved)
            guard data.count <= fileLimit, let text = String(data: data, encoding: .utf8) else { throw AIError.message("Skill 只支持有界 UTF-8 文本。") }
            return text
        }
        let text = try readText(root.appendingPathComponent("SKILL.md")).replacingOccurrences(of: "\r\n", with: "\n")
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex),
              let metadata = try Yams.load(yaml: String(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound])) as? [String: Any],
              let name = metadata["name"] as? String, name.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil, name.count <= 64,
              let description = metadata["description"] as? String, !description.isEmpty, description.count <= 1024 else { throw AIError.message("SKILL.md 缺少有效的 name / description 或 YAML 头。") }
        let body = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw AIError.message("Skill 指令为空。") }
        let tools = (metadata["allowed-tools"] as? [String]) ?? (metadata["allowed-tools"] as? String)?.split(whereSeparator: \.isWhitespace).map(String.init) ?? []
        var resources: [String: String] = [:], size = text.utf8.count
        for directory in ["references", "assets"] {
            let url = root.appendingPathComponent(directory)
            if !FileManager.default.fileExists(atPath: url.path) { continue }
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in enumerator {
                guard ["md", "txt", "json", "yaml", "yml", "csv"].contains(file.pathExtension.lowercased()) else { continue }
                let resolved = file.resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path.hasPrefix(root.path + "/") else { throw AIError.message("Skill 资源越出导入目录。") }
                let relative = String(resolved.path.dropFirst(root.path.count + 1))
                guard relative.split(separator: "/").count <= 5, resources.count < 32 else { throw AIError.message("Skill 资源过多或目录过深。") }
                let value = try readText(file); size += value.utf8.count
                guard size <= packageLimit else { throw AIError.message("Skill 文本资源合计超过 512 KB。") }
                resources[relative] = value
            }
        }
        let hash = TextFingerprint.hash(text + resources.keys.sorted().map { $0 + (resources[$0] ?? "") }.joined())
        return .init(name: name, description: description, instructions: body, resources: resources, fingerprint: hash, origin: folder.path,
                     tools: tools, compatibility: "支持指令与文本资源；不执行脚本、网络和宿主专属工具。" + ((metadata["compatibility"] as? String).map { " 要求：" + $0 } ?? ""))
    }
}

@MainActor final class WritingSkillStore: ObservableObject {
    static let shared = WritingSkillStore()
    struct Catalog: Codable { var schema = 1; var skills: [WritingSkill] = []; var enabled: Set<String> = [] }
    @Published private(set) var catalog = Catalog()
    @Published var status = ""
    private let file: URL?
    private var loadFailed = false
    init(file: URL? = nil, bundled: URL? = Bundle.main.resourceURL?.appendingPathComponent("Skills/humanizer-zh")) {
        self.file = file ?? (try? AppFiles.directory().appendingPathComponent("writing-skills.json"))
        do {
            if let file = self.file, FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file); guard data.count <= 4_000_000 else { throw AIError.message("Skill 配置过大。") }
                catalog = try JSONDecoder().decode(Catalog.self, from: data)
                guard catalog.schema == 1 else { throw AIError.message("Skill 配置版本不支持。") }
            } else if let bundled, FileManager.default.fileExists(atPath: bundled.path) {
                let skill = try WritingSkillLoader.read(bundled); catalog.skills = [skill]
            }
        } catch { loadFailed = true; status = "读取 Skill 失败，原文件已保留：" + error.localizedDescription }
    }
    var enabledSkills: [WritingSkill] { catalog.skills.filter { catalog.enabled.contains($0.id) } }
    func setEnabled(_ skill: WritingSkill, _ enabled: Bool) {
        var next = catalog
        if enabled { next.enabled.insert(skill.id) } else { next.enabled.remove(skill.id) }
        save(next)
    }
    func importFolder(_ url: URL) throws {
        guard !loadFailed else { throw AIError.message("请先恢复损坏的 writing-skills.json，未覆盖原文件。") }
        var skill = try WritingSkillLoader.read(url)
        guard catalog.skills.count < 32 || catalog.skills.contains(where: { $0.name == skill.name }) else { throw AIError.message("最多导入 32 个 Skill。") }
        var next = catalog
        let old = next.skills.first { $0.name == skill.name }
        skill.installationID = old?.id ?? UUID().uuidString
        if let old { next.skills.removeAll { $0.id == old.id }; if next.enabled.remove(old.id) != nil { next.enabled.insert(skill.id) } }
        next.skills.append(skill)
        guard let file else { throw AIError.message("无法保存 Skill。") }
        guard try JSONEncoder().encode(next).count <= 4_000_000 else { throw AIError.message("Skill 配置总量超过 4 MB，请减少资源文件后导入。") }
        try AppFiles.save(next, to: file); catalog = next; status = "已导入；在会话开始时固定所启用的版本。"
    }
    func remove(_ id: String) { var next = catalog; next.skills.removeAll { $0.id == id }; next.enabled.remove(id); save(next) }
    private func save(_ next: Catalog) {
        do {
            guard !loadFailed, let file else { throw AIError.message("Skill 配置无法读取，未覆盖原文件。") }
            guard try JSONEncoder().encode(next).count <= 4_000_000 else { throw AIError.message("Skill 配置总量超过 4 MB。") }
            try AppFiles.save(next, to: file); catalog = next; status = "已保存"
        }
        catch { status = error.localizedDescription }
    }
}
