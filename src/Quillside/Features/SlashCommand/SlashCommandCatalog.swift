import Foundation

/// Canonical actions are distinct from aliases; exact aliases always outrank fuzzy display-name matches.
enum SlashCommandCatalog {
    static let builtins: [SlashCommand] = [
        .init(id: "h1", name: "Title", description: "大标题", icon: "textformat.size.larger", category: .structure, action: .title, aliases: ["title"]),
        .init(id: "h2", name: "Heading", description: "中标题", icon: "textformat.size", category: .structure, action: .heading, aliases: ["heading"]),
        .init(id: "h3", name: "Subheading", description: "小标题", icon: "textformat.size.smaller", category: .structure, action: .subheading, aliases: ["subheading"]),
        .init(id: "body", name: "Body", description: "正文", icon: "text.alignleft", category: .structure, action: .body),
        .init(id: "bullet", name: "Bulleted List", description: "项目符号列表", icon: "list.bullet", category: .structure, action: .bulletList, aliases: ["bulletedlist"]),
        .init(id: "dash", name: "Dashed List", description: "短划线列表", icon: "list.dash", category: .structure, action: .dashList, aliases: ["dashedlist"]),
        .init(id: "number", name: "Numbered List", description: "编号列表", icon: "list.number", category: .structure, action: .numberedList, aliases: ["numberedlist"]),
        .init(id: "todo", name: "Checklist", description: "待办事项", icon: "checklist", category: .structure, action: .todoList, aliases: ["checklist"]),
        .init(id: "quote", name: "Quote", description: "块引用", icon: "text.quote", category: .structure, action: .quote, aliases: ["blockquote", "block"]),
        .init(id: "code", name: "Monostyled", description: "等宽文本", icon: "chevron.left.forwardslash.chevron.right", category: .structure, action: .codeBlock, aliases: ["monostyled"]),
        .init(id: "table", name: "Table", description: "原生表格", icon: "tablecells", category: .structure, action: .table),
        .init(id: "link", name: "Link", description: "添加或编辑链接", icon: "link", category: .formatting, action: .link),
        .init(id: "bold", name: "Bold", description: "粗体", icon: "bold", category: .formatting, action: .bold),
        .init(id: "italic", name: "Italic", description: "斜体", icon: "italic", category: .formatting, action: .italic),
        .init(id: "underline", name: "Underline", description: "下划线", icon: "underline", category: .formatting, action: .underline),
        .init(id: "strike", name: "Strikethrough", description: "删除线", icon: "strikethrough", category: .formatting, action: .strikethrough, aliases: ["strikethrough"]),
        .init(templatePicker: ())
    ]
    static func commands(templates: [SnippetTemplate]) -> [SlashCommand] { builtins + templates.map(SlashCommand.init(template:)) }

    static func exact(_ query: String, in commands: [SlashCommand] = builtins) -> SlashCommand? {
        let query = query.lowercased()
        return commands.first { $0.tokens.contains(where: { $0.lowercased() == query }) }
    }

    static func suggestions(_ query: String, in commands: [SlashCommand] = builtins) -> [SlashCommand] {
        guard !query.isEmpty else { return commands }
        let exact = exact(query, in: commands)
        let matching = commands.filter { command in
            command.tokens.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                || command.name.localizedCaseInsensitiveContains(query)
                || command.description.localizedCaseInsensitiveContains(query)
        }
        return exact.map { selected in [selected] + matching.filter { $0.id != selected.id } } ?? matching
    }
}
