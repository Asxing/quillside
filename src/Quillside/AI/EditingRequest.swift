import Foundation

/// An editing request can only receive the material displayed in the current workspace.
enum EditingRequest {
    static func render(prompt: PromptAction, text: String, instruction: String, language: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.message("请先捕获当前笔记内容，或输入材料和要求。")
        }
        guard !prompt.instruction.contains("{sources}") else {
            throw AIError.message("此旧指令依赖已移除的资料检索。请将指令改为使用 {text}，或选择“就当前内容提问”。")
        }
        var result = PromptRenderer.render(prompt.instruction, values: ["text": text, "instruction": instruction, "language": language])
        if !text.isEmpty && !prompt.instruction.contains("{text}") { result += "\n当前材料：\n" + text }
        if !instruction.isEmpty && !prompt.instruction.contains("{instruction}") { result += "\n补充要求：" + instruction }
        guard result.utf8.count <= 200_000 else { throw AIError.message("本次材料与指令超过 200 KB，请分段处理。") }
        return result
    }
}
