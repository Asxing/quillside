import Foundation

struct WritingAnnotation: Codable, Identifiable, Equatable {
    let id: UUID
    let versionID: UUID
    let location: Int
    let length: Int
    let quote: String
    var comment: String
    var enabled = true
    var range: NSRange { NSRange(location: location, length: length) }
}
struct WritingAssessment: Codable, Equatable {
    let annotationID: UUID
    let status: String
    let explanation: String
}
struct WritingVersion: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let instruction: String
    let assessments: [WritingAssessment]
    let issues: [String]
    var formattingNote: String?
    var agent: AgentSnapshot?
}
struct WritingDraft: Codable {
    var schema = 1
    var id = UUID()
    let noteIdentity: String
    let baseline: String
    let rangeLocation: Int
    let rangeLength: Int
    let hasSelection: Bool
    var candidate: String
    var versionID = UUID()
    var annotations: [WritingAnnotation] = []
    var versions: [WritingVersion] = []
    var skills: [WritingSkill] = []
    var agent: AgentSnapshot?
    var includeContext = true
    var instruction = ""
    var updatedAt = Date()
    var range: NSRange { NSRange(location: rangeLocation, length: rangeLength) }
    var source: String { (baseline as NSString).substring(with: range) }
    var currentAnnotations: [WritingAnnotation] { annotations.filter { $0.versionID == versionID } }
    var pendingAnnotations: [WritingAnnotation] { currentAnnotations.filter(\.enabled) }
    /// Previous-version comments remain revision requirements. Their old ranges
    /// are never drawn on the new text, but their meaning must not disappear.
    var requirements: [WritingAnnotation] { annotations.filter(\.enabled) }
    mutating func annotate(range: NSRange, comment: String) throws {
        guard currentAnnotations.count < 50, annotations.count < 200, range.length > 0, UTF16TextRange.valid(range, in: candidate),
              !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, comment.utf8.count <= 4000 else {
            throw AIError.message("请选择候选稿文字并填写批注；每版最多 50 条，每个任务最多 200 条。")
        }
        annotations.append(.init(id: UUID(), versionID: versionID, location: range.location, length: range.length,
                                 quote: (candidate as NSString).substring(with: range), comment: comment))
    }
    mutating func changeCandidate(_ value: String) {
        guard value != candidate else { return }
        if !currentAnnotations.isEmpty, !versions.contains(where: { $0.id == versionID }) {
            versions.append(.init(id: versionID, text: candidate, instruction: "手动编辑前", assessments: [], issues: [], agent: agent))
            if versions.count > 12 { versions.removeFirst() }
        }
        candidate = value
        // Never silently move comments after a manual edit. Their old versions
        // and quotes remain visible in history; current ranges no longer apply.
        versionID = UUID()
    }
    mutating func accept(_ proposal: WritingProposal, instruction: String) {
        if versions.isEmpty || versions.last?.text != candidate {
            versions.append(.init(id: versionID, text: candidate, instruction: "修订前稿", assessments: [], issues: [], agent: agent))
        }
        candidate = proposal.document; versionID = UUID()
        versions.append(.init(id: versionID, text: candidate, instruction: instruction, assessments: proposal.assessments, issues: proposal.issues, formattingNote: proposal.formattingNote, agent: agent))
        if versions.count > 12 { versions.removeFirst(versions.count - 12) }
        // Pruning old full-text versions must not silently erase user requirements.
    }
    mutating func restore(_ version: WritingVersion) {
        candidate = version.text; versionID = version.id
        if let agent = version.agent { self.agent = agent; skills = AgentContextBuilder.skills(agent, operation: .revision) }
    }
    func validate() throws {
        try agent?.validate()
        guard schema == 1, baseline.utf8.count <= 200_000, candidate.utf8.count <= 200_000,
              UTF16TextRange.valid(range, in: baseline), !noteIdentity.isEmpty, versions.count <= 12,
              annotations.count <= 200, skills.count <= 8 else { throw AIError.message("修订草稿无效或超出容量。") }
        for item in currentAnnotations {
            guard UTF16TextRange.valid(item.range, in: candidate), (candidate as NSString).substring(with: item.range) == item.quote else {
                throw AIError.message("批注位置与候选稿不一致，请恢复对应版本或重新批注。")
            }
        }
    }
}

struct WritingDraftStore {
    let directory: URL
    init(directory: URL? = nil) throws {
        self.directory = try directory ?? AppFiles.directory().appendingPathComponent("WritingDrafts", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    private func url(_ identity: String) -> URL { directory.appendingPathComponent(TextFingerprint.hash(identity) + ".json") }
    func load(note: String) throws -> WritingDraft? {
        let file = url(note)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        guard data.count <= 8_000_000 else { throw AIError.message("修订草稿过大，原文件已保留。") }
        let draft = try JSONDecoder().decode(WritingDraft.self, from: data)
        try draft.validate()
        guard draft.noteIdentity == note else { throw AIError.message("修订草稿身份不一致。") }
        return draft
    }
    func save(_ draft: WritingDraft) throws {
        try draft.validate()
        let data = try JSONEncoder().encode(draft)
        guard data.count <= 8_000_000 else { throw AIError.message("修订历史已超过 8 MB，请复制保留后开启新任务。") }
        try AppFiles.save(draft, to: url(draft.noteIdentity))
    }
    func remove(note: String) throws {
        let file = url(note)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

struct WritingProposal: Codable, Equatable {
    let document: String
    let assessments: [WritingAssessment]
    let issues: [String]
    var formattingNote: String?
    func validate(annotations: [WritingAnnotation]) throws {
        guard !document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, document.utf8.count <= 200_000,
              assessments.count == annotations.count,
              Set(assessments.map(\.annotationID)) == Set(annotations.map(\.id)),
              assessments.allSatisfy({ ["addressed", "conflict", "unresolved"].contains($0.status) && !$0.explanation.isEmpty }),
              issues.count <= 30 else { throw AIError.message("模型未完整核对全部批注，未更新候选稿。请重试或调整要求。") }
    }
}
