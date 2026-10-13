import AppKit

struct BacklinkDocumentEntry: Codable, Equatable {
    let identifier: String
    let title: String
    var url: String { "applenotes:note/" + identifier }
}

struct BacklinkDocumentRegion: Codable, Equatable {
    static let heading = "引用此笔记 · Quillside"
    static let previousBrandHeading = "引用此笔记 · AppleNotesPro"
    static let legacyHeading = "引用此笔记 · OpenNotes"
    static let knownHeadings = [heading, previousBrandHeading, legacyHeading]
    static let ending = "引用列表结束"
    let entries: [BacklinkDocumentEntry]
    /// Missing in pre-rename persisted regions; preserve their exact text so
    /// ownership, Undo and generated-link exclusion remain valid.
    var headingText: String? = nil
    var renderedHeading: String { headingText ?? Self.legacyHeading }
    var text: String { ([renderedHeading] + entries.map(\.title) + [Self.ending]).joined(separator: "\n") }

    static func make(_ entries: [BacklinkDocumentEntry], retaining previous: Self? = nil) throws -> Self {
        var unique: [String: BacklinkDocumentEntry] = [:]
        for entry in (previous?.entries ?? []) + entries {
            guard let uuid = UUID(uuidString: entry.identifier) else { throw AIError.message("来源缺少有效的原生笔记标识。") }
            let title = entry.title.components(separatedBy: .newlines).joined(separator: " ")
                .replacingOccurrences(of: "\u{FFFC}", with: " ").trimmingCharacters(in: .whitespaces)
            guard !Self.knownHeadings.contains(where: title.contains), !title.contains(Self.ending) else { throw AIError.message("来源标题与反链区域标记冲突，请先调整标题。") }
            unique[uuid.uuidString] = .init(identifier: uuid.uuidString, title: title.isEmpty ? "未命名笔记" : title)
        }
        return .init(entries: unique.values.sorted { $0.title == $1.title ? $0.identifier < $1.identifier : $0.title < $1.title }, headingText: Self.heading)
    }

    func range(in body: String) -> NSRange? {
        let value = body as NSString, range = value.range(of: text)
        guard range.location != NSNotFound,
              Self.knownHeadings.reduce(0, { $0 + body.components(separatedBy: $1).count - 1 }) == 1,
              body.components(separatedBy: Self.ending).count == 2,
              range.location == 0 || value.substring(with: NSRange(location: range.location - 1, length: 1)) == "\n",
              value.substring(from: NSMaxRange(range)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return range
    }

    func attributed(prefix: String) -> NSAttributedString {
        let value = NSMutableAttributedString(string: prefix + text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        var offset = (prefix + renderedHeading + "\n" as NSString).length
        for entry in entries {
            let range = NSRange(location: offset, length: (entry.title as NSString).length)
            value.addAttribute(.link, value: entry.url, range: range)
            offset = NSMaxRange(range) + 1
        }
        return value
    }

    /// Notes may split a label into several anchors. Compare targets, not serialized HTML layout.
    func linksMatch(html: String) -> Bool {
        guard let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]) else { return false }
        var text = "", links: [(NSRange, String)] = []
        func walk(_ node: XMLNode) {
            if node.kind == .text {
                text += (node.stringValue ?? "").replacingOccurrences(of: "\u{00A0}", with: " ")
                return
            }
            let start = (text as NSString).length
            for child in node.children ?? [] { walk(child) }
            if let element = node as? XMLElement, element.name?.lowercased() == "a", let href = element.attribute(forName: "href")?.stringValue {
                links.append((NSRange(location: start, length: (text as NSString).length - start), href))
            }
            if ["div", "p", "br", "li"].contains(node.name?.lowercased() ?? "") { text += "\n" }
        }
        walk(document)
        let source = text as NSString, start = source.range(of: renderedHeading)
        guard start.location != NSNotFound else { return false }
        let end = source.range(of: Self.ending, range: NSRange(location: NSMaxRange(start), length: source.length - NSMaxRange(start)))
        guard end.location != NSNotFound else { return false }
        let region = NSRange(location: NSMaxRange(start), length: end.location - NSMaxRange(start))
        var identifiers = Set<String>()
        for (range, href) in links where NSIntersectionRange(range, region).length > 0 {
            let targets = NativeNoteLinkParser.identifiers(inURL: href)
            guard !targets.isEmpty else { return false }
            identifiers.formUnion(targets)
        }
        return identifiers == Set(entries.map(\.identifier))
    }
}

struct BacklinkDocumentPlan {
    let range: NSRange
    let prefix: String
    let region: BacklinkDocumentRegion
    let unchanged: Bool
    let previous: BacklinkDocumentRegion?
    static func make(body: String, html: String, known: [BacklinkDocumentRegion], entries: [BacklinkDocumentEntry], complete: Bool,
                     validateLinks: ((BacklinkDocumentRegion, NSRange) -> Bool)? = nil) throws -> Self {
        let previous = known.first { $0.range(in: body) != nil }
        if previous == nil, BacklinkDocumentRegion.knownHeadings.contains(where: body.contains) || body.contains(BacklinkDocumentRegion.ending) {
            throw AIError.message("正文反链区域已被修改，或缺少本机记录。请保留需要的内容并移除旧生成区域后重试。")
        }
        if let previous, let range = previous.range(in: body), !(validateLinks?(previous, range) ?? previous.linksMatch(html: html)) {
            throw AIError.message("正文中的反链目标已改变或无法核实，未覆盖你的修改。")
        }
        let region = try BacklinkDocumentRegion.make(entries, retaining: complete ? nil : previous)
        guard previous != nil || !region.entries.isEmpty else { throw AIError.message("没有可写入的反向链接。") }
        let range = previous?.range(in: body) ?? NSRange(location: (body as NSString).length, length: 0)
        let prefix = previous == nil ? (body.hasSuffix("\n") ? "\n" : "\n\n") : ""
        return .init(range: range, prefix: prefix, region: region, unchanged: previous == region, previous: previous)
    }
}

/// Stores only generated link sections, never a second copy of the user's note bodies.
final class BacklinkRegionStore {
    static let shared = BacklinkRegionStore(url: try? AppFiles.directory().appendingPathComponent("backlink-regions.json"))
    struct State: Codable { var version = 1; var regions: [String: [BacklinkDocumentRegion]] = [:] }
    private let url: URL?
    private let lock = NSLock()
    private var state = State()
    private var failure = false
    init(url: URL?) {
        self.url = url
        guard let url else { failure = true; return }
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
                guard state.version == 1 else { throw AIError.message("未知版本") }
            } catch { failure = true }
        }
    }
    func snapshot() throws -> [String: [BacklinkDocumentRegion]] {
        lock.lock(); defer { lock.unlock() }
        guard !failure else { throw AIError.message("反链区域记录无法读取，原文件已保留，暂不进行正文反链维护。") }
        return state.regions
    }
    func prepare(_ region: BacklinkDocumentRegion, noteID: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard !failure, let url else { throw AIError.message("无法保存反链区域记录，正文未改变。") }
        var next = state
        let key = noteID.uppercased()
        var history = next.regions[key] ?? []
        history.removeAll { $0 == region }; history.insert(region, at: 0)
        // Preserve earlier generated forms so Undo does not turn reverse edges into user references.
        next.regions[key] = history
        try AppFiles.save(next, to: url)
        state = next
    }
}
