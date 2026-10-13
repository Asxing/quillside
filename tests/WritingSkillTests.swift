import Foundation
import Testing
@testable import Quillside

@Suite struct WritingSkillTests {
    func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    @Test func realHumanizerPackageLoadsWithYAMLArrayMetadata() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("resources/Skills/humanizer-zh")
        let skill = try WritingSkillLoader.read(root)
        #expect(skill.name == "humanizer-zh")
        #expect(skill.tools.contains("Read"))
        #expect(skill.instructions.contains("事实"))
        #expect(skill.fingerprint.count == 64)
    }
    @Test func resourceTraversalAndOversizedFilesAreRejected() throws {
        let folder=try root();defer{try? FileManager.default.removeItem(at:folder)}
        try "---\nname: sample\ndescription: |\n  多行描述\n  保留规则\nallowed-tools: Read Edit\n---\n保留事实".write(to:folder.appendingPathComponent("SKILL.md"),atomically:true,encoding:.utf8)
        let ref=folder.appendingPathComponent("references");try FileManager.default.createDirectory(at:ref,withIntermediateDirectories:true)
        try "规则".write(to:ref.appendingPathComponent("one.md"),atomically:true,encoding:.utf8)
        #expect(try WritingSkillLoader.read(folder).resources["references/one.md"] == "规则")
        let outside=try root();defer{try? FileManager.default.removeItem(at:outside)}
        try "outside".write(to:outside.appendingPathComponent("secret.md"),atomically:true,encoding:.utf8)
        try FileManager.default.createSymbolicLink(at:ref.appendingPathComponent("escape.md"),withDestinationURL:outside.appendingPathComponent("secret.md"))
        #expect(throws: AIError.self) { try WritingSkillLoader.read(folder) }
        try FileManager.default.removeItem(at:ref.appendingPathComponent("escape.md"))
        try String(repeating:"x",count:140_000).write(to:ref.appendingPathComponent("large.md"),atomically:true,encoding:.utf8)
        #expect(throws: AIError.self) { try WritingSkillLoader.read(folder) }
    }
}
