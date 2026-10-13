import Foundation

enum MarkdownConversionError: Error, Equatable {
    case invalidHTML
}

struct AppleNotesMarkdownConverter {
    func convert(
        title: String,
        htmlBody: String
    ) throws -> String {
        let document: XMLDocument
        do {
            document = try XMLDocument(
                xmlString: htmlBody,
                options: [.documentTidyHTML]
            )
        } catch {
            throw MarkdownConversionError.invalidHTML
        }

        guard let root = document.rootElement() else {
            throw MarkdownConversionError.invalidHTML
        }
        let contentRoot: XMLNode =
            firstElement(named: "body", in: root) ?? root
        let rendered = normalizeBlocks(renderChildren(of: contentRoot))
        let escapedTitle = escapeText(title)
        let normalizedTitle = collapseWhitespace(title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstBlockText = firstBlockPlainText(in: contentRoot)

        if firstBlockText == normalizedTitle {
            return rendered
        }

        if rendered.isEmpty {
            return "# \(escapedTitle)"
        }
        return "# \(escapedTitle)\n\n\(rendered)"
    }

    private func renderChildren(
        of node: XMLNode,
        preserveWhitespace: Bool = false
    ) -> String {
        (node.children ?? [])
            .map {
                render(
                    $0,
                    preserveWhitespace: preserveWhitespace
                )
            }
            .joined()
    }

    private func render(
        _ node: XMLNode,
        preserveWhitespace: Bool = false
    ) -> String {
        if node.kind == .text {
            let value = node.stringValue ?? ""
            return preserveWhitespace
                ? value
                : escapeText(collapseWhitespace(value))
        }

        guard
            node.kind == .element,
            let element = node as? XMLElement
        else {
            return ""
        }

        let name = element.name?.lowercased() ?? ""
        switch name {
        case "html", "body", "main", "article", "section":
            return renderChildren(of: element)
        case "head", "script", "style", "meta", "link":
            return ""
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(name.dropFirst()) ?? 1
            return "\(String(repeating: "#", count: level)) \(inlineText(in: element))\n\n"
        case "p", "div":
            let content = trimInline(renderChildren(of: element))
            return content.isEmpty ? "" : "\(content)\n\n"
        case "strong", "b":
            return wrapped("**", content: inlineText(in: element))
        case "em", "i":
            return wrapped("*", content: inlineText(in: element))
        case "s", "strike", "del":
            return wrapped("~~", content: inlineText(in: element))
        case "u":
            let content = inlineText(in: element)
            return content.isEmpty ? "" : "<u>\(content)</u>"
        case "a":
            let label = inlineText(in: element)
            guard
                !label.isEmpty,
                let href = attribute("href", in: element),
                let destination = safeLinkDestination(href)
            else {
                return label
            }
            return "[\(label)](\(destination))"
        case "br":
            return "\n"
        case "hr":
            return "\n\n---\n\n"
        case "blockquote":
            let content = normalizeBlocks(renderChildren(of: element))
            guard !content.isEmpty else { return "" }
            return content
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line in line.isEmpty ? ">" : "> \(line)" }
                .joined(separator: "\n") + "\n\n"
        case "code":
            let content = rawText(in: element)
            let fence = codeFence(for: content, minimumLength: 1)
            return "\(fence)\(content)\(fence)"
        case "pre":
            let content = rawText(in: element)
                .trimmingCharacters(in: .newlines)
            let fence = codeFence(
                for: content,
                minimumLength: 3
            )
            return "\(fence)\n\(content)\n\(fence)\n\n"
        case "ul":
            return renderList(element, ordered: false, depth: 0)
        case "ol":
            return renderList(element, ordered: true, depth: 0)
        case "table":
            return renderTable(element)
        case "img":
            let alt = attribute("alt", in: element)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return alt.map { !$0.isEmpty ? "[图片: \($0)]" : "[图片]" }
                ?? "[图片]"
        case "object", "embed", "attachment":
            return attachmentPlaceholder(for: element)
        case "input":
            return ""
        default:
            return renderChildren(of: element)
        }
    }

    private func renderList(
        _ list: XMLElement,
        ordered: Bool,
        depth: Int
    ) -> String {
        let items = childElements(of: list)
            .filter { $0.name?.lowercased() == "li" }
        var lines: [String] = []

        for (index, item) in items.enumerated() {
            let children = item.children ?? []
            let nestedLists = children.compactMap { $0 as? XMLElement }
                .filter {
                    let name = $0.name?.lowercased()
                    return name == "ul" || name == "ol"
                }
            let inlineContent = children
                .filter { node in
                    guard let element = node as? XMLElement else {
                        return true
                    }
                    let name = element.name?.lowercased()
                    return name != "ul" && name != "ol"
                }
                .map { render($0) }
                .joined()
            let itemText = trimInline(normalizeBlocks(inlineContent))
            let indentation = String(repeating: "  ", count: depth)
            let marker: String
            if let checked = checklistState(for: item) {
                marker = checked ? "- [x]" : "- [ ]"
            } else {
                marker = ordered ? "\(index + 1)." : "-"
            }
            lines.append("\(indentation)\(marker) \(itemText)")

            for nested in nestedLists {
                let nestedName = nested.name?.lowercased()
                let rendered = renderList(
                    nested,
                    ordered: nestedName == "ol",
                    depth: depth + 1
                )
                .trimmingCharacters(in: .newlines)
                if !rendered.isEmpty {
                    lines.append(rendered)
                }
            }
        }

        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n\n"
    }

    private func checklistState(for item: XMLElement) -> Bool? {
        if let value = attribute("data-checked", in: item)?
            .lowercased() {
            return ["true", "yes", "1", "checked"].contains(value)
        }

        if let className = attribute("class", in: item)?
            .lowercased(), className.contains("checklist") {
            return className.contains("checked")
                && !className.contains("unchecked")
        }

        for child in childElements(of: item)
        where child.name?.lowercased() == "input"
            && attribute("type", in: child)?.lowercased() == "checkbox" {
            return attribute("checked", in: child) != nil
        }
        return nil
    }

    private func renderTable(_ table: XMLElement) -> String {
        let rows: [[String]] = descendants(
            named: "tr",
            in: table
        ).compactMap { row -> [String]? in
            let cells = childElements(of: row).filter {
                let name = $0.name?.lowercased()
                return name == "th" || name == "td"
            }
            guard !cells.isEmpty else { return nil }
            return cells.map {
                inlineText(in: $0)
                    .replacingOccurrences(of: "|", with: "\\|")
                    .replacingOccurrences(of: "\n", with: "<br>")
            }
        }
        guard let firstRow = rows.first else { return "" }

        let columnCount = rows.map { $0.count }.max() ?? firstRow.count
        func padded(_ row: [String]) -> [String] {
            row + Array(
                repeating: "",
                count: max(columnCount - row.count, 0)
            )
        }
        func line(_ row: [String]) -> String {
            "| \(padded(row).joined(separator: " | ")) |"
        }

        var output = [
            line(firstRow),
            line(Array(repeating: "---", count: columnCount)),
        ]
        output.append(contentsOf: rows.dropFirst().map(line))
        return output.joined(separator: "\n") + "\n\n"
    }

    private func attachmentPlaceholder(for element: XMLElement) -> String {
        let rawName = attribute("title", in: element)
            ?? attribute("name", in: element)
            ?? attribute("data", in: element)
            ?? attribute("src", in: element)
        guard
            let rawName,
            !rawName.isEmpty
        else {
            return "[附件]"
        }
        let name = URL(fileURLWithPath: rawName).lastPathComponent
        return "[附件: \(escapeText(name))]"
    }

    private func firstElement(
        named name: String,
        in node: XMLNode?
    ) -> XMLElement? {
        guard let node else { return nil }
        if let element = node as? XMLElement,
           element.name?.lowercased() == name {
            return element
        }
        for child in node.children ?? [] {
            if let match = firstElement(named: name, in: child) {
                return match
            }
        }
        return nil
    }

    private func firstBlockPlainText(in node: XMLNode) -> String? {
        let blockNames: Set<String> = [
            "h1", "h2", "h3", "h4", "h5", "h6",
            "p", "li", "blockquote", "pre", "td", "th",
        ]
        for child in node.children ?? [] {
            guard let element = child as? XMLElement else { continue }
            let name = element.name?.lowercased() ?? ""
            if blockNames.contains(name) {
                let text = collapseWhitespace(rawText(in: element))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
            if let nested = firstBlockPlainText(in: element) {
                return nested
            }
            if name == "div" {
                let text = collapseWhitespace(rawText(in: element))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    private func descendants(
        named name: String,
        in node: XMLNode
    ) -> [XMLElement] {
        var result: [XMLElement] = []
        for child in node.children ?? [] {
            if let element = child as? XMLElement {
                if element.name?.lowercased() == name {
                    result.append(element)
                }
                result.append(contentsOf: descendants(named: name, in: element))
            }
        }
        return result
    }

    private func childElements(of node: XMLNode) -> [XMLElement] {
        (node.children ?? []).compactMap { $0 as? XMLElement }
    }

    private func attribute(
        _ name: String,
        in element: XMLElement
    ) -> String? {
        element.attribute(forName: name)?.stringValue
    }

    private func inlineText(in node: XMLNode) -> String {
        trimInline(renderChildren(of: node))
    }

    private func rawText(in node: XMLNode) -> String {
        if node.kind == .text {
            return node.stringValue ?? ""
        }
        return (node.children ?? []).map(rawText).joined()
    }

    private func wrapped(_ marker: String, content: String) -> String {
        content.isEmpty ? "" : "\(marker)\(content)\(marker)"
    }

    private func codeFence(
        for content: String,
        minimumLength: Int
    ) -> String {
        var maximumRun = 0
        var currentRun = 0
        for character in content {
            if character == "`" {
                currentRun += 1
                maximumRun = max(maximumRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return String(
            repeating: "`",
            count: max(minimumLength, maximumRun + 1)
        )
    }

    private func collapseWhitespace(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
    }

    private func trimInline(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"[ \t]*\n[ \t]*"#,
                with: "\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeBlocks(_ value: String) -> String {
        value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                String(line).replacingOccurrences(
                    of: #"[ \t]+$"#,
                    with: "",
                    options: .regularExpression
                )
            }
            .joined(separator: "\n")
            .replacingOccurrences(
                of: #"\n{3,}"#,
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(
                of: #"([*_\[\]])"#,
                with: #"\\$1"#,
                options: .regularExpression
            )
    }

    private func safeLinkDestination(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            let scheme = URLComponents(string: trimmed)?
                .scheme?
                .lowercased(),
            ["http", "https", "mailto", "tel", "applenotes"]
                .contains(scheme)
        else {
            return nil
        }
        return escapeLinkDestination(trimmed)
    }

    private func escapeLinkDestination(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }
}
