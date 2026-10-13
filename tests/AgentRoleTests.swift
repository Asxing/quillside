import Foundation
import Testing
@testable import Quillside

@MainActor @Suite(.serialized) struct AgentRoleTests {
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func fixtureSkill() -> WritingSkill {
        .init(name: "humanizer-zh", description: "test", instructions: "删除空话但保留事实", resources: ["references/a.md":"保持暂定性质"], fingerprint: "fixture-hash", origin: "fixture", tools: [], compatibility: "text")
    }
    func config() -> AIConfiguration {
        var c = AIConfiguration(); let connection = ModelConnection(name: "fixture", api: .ollama, baseURL: "http://127.0.0.1:1", model: "fixture")
        c.connections = [connection]; c.selectedConnectionID = connection.id; return c
    }
    @Test func firstMigrationPreservesLegacyInstructionsCredentialsAndIsIdempotent() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        var c = config(); c.systemPrompt = "原自定义说明"; c.writingPreferences = "短句"
        let file = dir.appendingPathComponent("agents.json"), original = try JSONEncoder().encode(c)
        let store = AgentStore(file: file, legacy: c, enabledSkills: [fixtureSkill()])
        #expect(!store.loadFailed); #expect(store.catalog.profiles.count == 4)
        let legacy = try #require(store.catalog.profiles.first)
        #expect(legacy.prompt.contains(c.systemPrompt)); #expect(legacy.prompt.contains("短句"))
        #expect(legacy.skillIDs == [fixtureSkill().id])
        let reopened = AgentStore(file: file, legacy: AIConfiguration(), enabledSkills: [])
        #expect(reopened.catalog == store.catalog)
        let folders = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("before-agent") }
        #expect(folders.count == 1)
        let saved = try JSONDecoder().decode(AIConfiguration.self, from: Data(contentsOf: folders[0].appendingPathComponent("settings.json")))
        #expect(saved.connections == c.connections); #expect(saved.prompts == c.prompts); #expect(saved.systemPrompt == "原自定义说明")
        #expect(try JSONDecoder().decode(AIConfiguration.self, from: original).selectedConnectionID == c.selectedConnectionID)
    }
    @Test func failedMigrationAndCorruptFilesNeverBecomeWritable() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("agents.json")
        let failed = AgentStore(file: file, legacy: config(), enabledSkills: [], persist: { _,_ in throw AIError.message("disk full") })
        #expect(failed.loadFailed); #expect(!FileManager.default.fileExists(atPath: file.path))
        try Data("broken".utf8).write(to: file)
        let corrupt = AgentStore(file: file, legacy: config(), enabledSkills: [])
        #expect(corrupt.loadFailed)
        #expect(throws: AIError.self) { try corrupt.save(AgentProfile(name:"new")) }
        #expect(try String(contentsOf: file) == "broken")
    }
    @Test func sharedContextRespectsActionBoundsAndActuallyIncludesSkillResources() throws {
        let skill = fixtureSkill(), profiles = AgentProfile.presets(skillIDs: [skill.id])
        for profile in profiles {
            let snapshot = try AgentContextBuilder.resolve(profile: profile, availableSkills: [skill])
            let rewrite = try AgentContextBuilder.quickSystem(snapshot, operation: .rewrite)
            #expect(rewrite.contains(profile.prompt))
            #expect(rewrite.contains("references/a.md")); #expect(rewrite.contains("保持暂定性质"))
            let proof = try AgentContextBuilder.quickSystem(snapshot, operation: .proofread)
            #expect(proof.contains("不新增段落")); #expect(!proof.contains("<skill"))
            #expect(AgentContextBuilder.system(snapshot, operation: .revision).contains(profile.prompt))
        }
        #expect(throws: AIError.self) { try AgentContextBuilder.resolve(profile: profiles[0], availableSkills: []) }
    }
    @Test func updatingSkillPackageKeepsAgentReferenceAndSnapshotsImmutable() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let pkg = dir.appendingPathComponent("example"); try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let skillFile = pkg.appendingPathComponent("SKILL.md")
        try "---\nname: example\ndescription: test\n---\n旧规则".write(to: skillFile, atomically: true, encoding: .utf8)
        let store = WritingSkillStore(file: dir.appendingPathComponent("skills.json"), bundled: nil)
        try store.importFolder(pkg); let old = try #require(store.catalog.skills.first)
        let profile = AgentProfile(name: "role", skillIDs: [old.id])
        let snapshot = try AgentContextBuilder.resolve(profile: profile, availableSkills: store.catalog.skills)
        try "---\nname: example\ndescription: test\n---\n新规则".write(to: skillFile, atomically: true, encoding: .utf8)
        try store.importFolder(pkg); let changed = try #require(store.catalog.skills.first)
        #expect(old.id == changed.id); #expect(old.fingerprint != changed.fingerprint)
        #expect(snapshot.skills[0].instructions == "旧规则")
        #expect(try AgentContextBuilder.resolve(profile: profile, availableSkills: store.catalog.skills).skills[0].instructions == "新规则")
    }
    @Test func quickRoleSwitchUsesLatestCandidateAndKeepsModelConnection() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let config = config(), roles = AgentStore(file: dir.appendingPathComponent("agents.json"), legacy: config, enabledSkills: [])
        let skills = WritingSkillStore(file: dir.appendingPathComponent("skills.json"), bundled: nil)
        var systems: [String] = [], inputs: [String] = []
        let model = InlineAssistantModel(generate: { _,system,user,_ in systems.append(system); inputs.append(user); return "上一轮候选" })
        model.begin(target: .init(text:"30分钟缩短到10分钟。",hasSelection:true,validate:{},apply:{_,_ in}),configuration:config)
        model.configureAgents(roles,skills:skills);let ids=AgentProfile.presets().map(\.id)
        model.selectAgent(ids[0]); model.instruction="保留数字"; model.runCustom()
        try await wait { model.phase == .ready }
        model.result="人工修改后的候选";model.selectAgent(ids[2]);model.instruction="从汇报视角精简";model.runCustom()
        try await wait { systems.count == 2 && model.phase == .ready }
        #expect(systems[0].contains("Agent角色：公众号")); #expect(systems[1].contains("Agent角色：汇报"))
        #expect(!systems[1].contains("读者的问题")); #expect(inputs[1].contains("人工修改后的候选"))
        #expect(model.connectionID == config.selectedConnectionID)
    }
    @Test func legacyDraftDecodeAndRoleSwitchKeepAnnotationsAndPersistSnapshot() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let config=config(),roles=AgentStore(file:dir.appendingPathComponent("agents.json"),legacy:config,enabledSkills:[])
        let skills=WritingSkillStore(file:dir.appendingPathComponent("skills.json"),bundled:nil)
        let store=try WritingDraftStore(directory:dir.appendingPathComponent("drafts"))
        var draft=WritingDraft(noteIdentity:"test",baseline:"原句30分钟",rangeLocation:0,rangeLength:6,hasSelection:true,candidate:"原句30分钟")
        try draft.annotate(range:NSRange(location:2,length:4),comment:"保留数字")
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(draft)) as! [String:Any];object.removeValue(forKey:"agent")
        let old=try JSONDecoder().decode(WritingDraft.self,from:JSONSerialization.data(withJSONObject:object))
        #expect(old.agent == nil)
        let model=WritingSessionModel(generate:{_,_,_,_ in ""},store:store);model.begin(old,config:config);model.configureAgents(roles,skills:skills)
        model.selectAgent(AgentProfile.presets()[2].id)
        let saved=try store.load(note:"test")
        #expect(saved?.agent?.profile.name == "汇报");#expect(saved?.annotations == draft.annotations);#expect(saved?.candidate == draft.candidate)
    }
    @Test func revisionUsesOnePinnedRoleThroughAllStagesAndRecordsIt() async throws {
        let dir=try directory(); defer { try? FileManager.default.removeItem(at:dir) }
        let config=config(),roles=AgentStore(file:dir.appendingPathComponent("agents.json"),legacy:config,enabledSkills:[])
        let skills=WritingSkillStore(file:dir.appendingPathComponent("skills.json"),bundled:nil)
        var systems:[String]=[],stages:[String]=[]
        var changedDuringRun=false
        let model=WritingSessionModel(generate:{_,system,user,_ in
            systems.append(system)
            let request=try JSONSerialization.jsonObject(with:Data(user.utf8)) as! [String:Any]
            let stage=request["stage"] as! String;stages.append(stage)
            let task=request["task"] as! [String:Any]
            let comments=task["annotations"] as! [[String:Any]]
            if !changedDuringRun {
                var profile=roles.catalog.profiles.first { $0.name == "汇报" }!
                profile.prompt="运行中刚修改的新规则"
                try roles.save(profile); changedDuringRun=true
            }
            let assessments=comments.map { ["annotationID":$0["id"]!,"status":"addressed","explanation":"保留数字"] }
            let output:[String:Any]
            if stage == "plan" { output=["plan":"按汇报标准修订","resourceRequests":[]] }
            else if stage == "audit" { output=["passed":true,"issues":[],"assessments":assessments] }
            else { output=["document":"处理时间30分钟。","issues":[],"assessments":assessments] }
            return String(decoding:try JSONSerialization.data(withJSONObject:output),as:UTF8.self)
        },store:try WritingDraftStore(directory:dir.appendingPathComponent("drafts")))
        var draft=WritingDraft(noteIdentity:"revision",baseline:"30分钟",rangeLocation:0,rangeLength:4,hasSelection:true,candidate:"30分钟")
        try draft.annotate(range:NSRange(location:0,length:4),comment:"保留数字")
        model.begin(draft,config:config);model.configureAgents(roles,skills:skills);model.selectAgent(AgentProfile.presets()[2].id);model.run()
        try await wait { !model.busy }
        #expect(stages == ["plan","revise","audit"])
        #expect(Set(systems).count == 1)
        #expect(systems[0].contains("Agent角色：汇报"))
        #expect(!systems[0].contains("运行中刚修改的新规则"))
        #expect(model.draft?.versions.last?.agent?.profile.name == "汇报")
        #expect(model.draft?.versions.last?.agent?.profile.revision == AgentProfile.presets()[2].revision)
        #expect(model.draft?.requirements.count == 1)
    }
    @Test func builtInStyleUpgradePreservesCustomRolesAndBindings() throws {
        let dir=try directory();defer {try? FileManager.default.removeItem(at:dir)}
        let file=dir.appendingPathComponent("agents.json")
        var profiles=AgentProfile.presetsV1(skillIDs:["kept-skill"])
        profiles[0].actionIDs=[UUID()]
        profiles[1].prompt="用户自定义笔记风格"
        let old=AgentStore.Catalog(schema:1,profiles:profiles,defaultID:profiles[1].id)
        try AppFiles.save(old,to:file)
        let store=AgentStore(file:file,legacy:config(),enabledSkills:[])
        #expect(!store.loadFailed)
        #expect(store.catalog.profiles[0].revision == 3)
        #expect(store.catalog.profiles[0].actionIDs == profiles[0].actionIDs)
        #expect(store.catalog.profiles[0].skillIDs == ["kept-skill"])
        #expect(store.catalog.profiles[1] == profiles[1])
        #expect(store.catalog.defaultID == old.defaultID)
        let again=AgentStore(file:file,legacy:config(),enabledSkills:[])
        #expect(again.catalog == store.catalog)
        let backups=try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).filter {$0.lastPathComponent.hasPrefix("agents-before-prompt-v3-")}
        #expect(backups.count == 1)
        let saved=try JSONDecoder().decode(AgentStore.Catalog.self,from:Data(contentsOf:backups[0]))
        #expect(saved == old)
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return };try await Task.sleep(nanoseconds:1_000_000) }
        try #require(condition())
    }
}
