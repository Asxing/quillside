import Foundation
import Testing
@testable import Quillside

@MainActor @Suite struct AgentPromptMigrationTests {
    @Test func legacyFieldsBecomeOnePromptAndBackupIsTheOriginalFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = UUID(), action = UUID(), file = folder.appendingPathComponent("agents.json")
        let profile: [String: Any] = ["id": id.uuidString, "name": "我的角色", "audience": "我的读者🙂", "purpose": "保留目的\n和第二行", "perspective": "原判断视角", "style": "自定义表达", "quality": "原判断标准", "instructions": "不要删掉原句。", "skillIDs": ["existing-skill"], "actionIDs": [action.uuidString], "skillOperations": ["proofread"], "revision": 7, "isLegacy": false]
        let bytes = try JSONSerialization.data(withJSONObject: ["schema": 1, "profiles": [profile], "defaultID": id.uuidString])
        try bytes.write(to: file)
        let store = AgentStore(file: file, legacy: AIConfiguration(), enabledSkills: [])
        #expect(!store.loadFailed); #expect(store.catalog.schema == 2)
        let migrated = try #require(store.catalog.profiles.first)
        for field in ["audience", "purpose", "perspective", "style", "quality", "instructions"] {
            #expect(migrated.prompt.contains(profile[field] as! String))
        }
        #expect(migrated.id == id); #expect(migrated.revision == 7)
        #expect(migrated.skillIDs == ["existing-skill"]); #expect(migrated.actionIDs == [action])
        #expect(migrated.skillOperations == [.proofread]); #expect(store.catalog.defaultID == id)
        let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("agents-before-prompt-v3-") }
        #expect(backups.count == 1); #expect(try Data(contentsOf: backups[0]) == bytes)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as! [String: Any]
        #expect(encoded["prompt"] as? String == migrated.prompt)
        for key in ["audience", "purpose", "perspective", "style", "quality", "instructions"] { #expect(encoded[key] == nil) }
        let again = AgentStore(file: file, legacy: AIConfiguration(), enabledSkills: [])
        #expect(again.catalog == store.catalog)
    }
    @Test func explicitNewPromptWinsIncludingAnIntentionallyEmptyPrompt() throws {
        for prompt in ["新角色", ""] {
            let bytes = try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "name": "角色", "prompt": prompt, "instructions": "旧规则不能复活", "style": "旧风格"])
            let decoded = try JSONDecoder().decode(AgentProfile.self, from: bytes)
            #expect(decoded.prompt == prompt)
        }
    }
    @Test func failedUpgradeCannotReplaceLegacyFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("agents.json"), id = UUID()
        let bytes = try JSONSerialization.data(withJSONObject: ["schema": 1, "defaultID": id.uuidString, "profiles": [["id": id.uuidString, "name": "旧角色", "instructions": "原说明"]]])
        try bytes.write(to: file)
        let store = AgentStore(file: file, legacy: AIConfiguration(), enabledSkills: [], persist: { _,_ in throw AIError.message("disk full") })
        #expect(store.loadFailed); #expect(try Data(contentsOf: file) == bytes)
    }
    @Test func oldTaskSnapshotKeepsItsOriginalRoleText() throws {
        let old = LegacyAgentProfile.presetsV1()[0]
        let profile = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old))
        let data = try JSONSerialization.data(withJSONObject: ["profile": profile, "skills": []])
        let snapshot = try JSONDecoder().decode(AgentSnapshot.self, from: data)
        #expect(snapshot.profile.revision == 1)
        #expect(snapshot.profile.prompt.contains(old.style))
        #expect(snapshot.profile.prompt != AgentProfile.presets()[0].prompt)
    }
}
