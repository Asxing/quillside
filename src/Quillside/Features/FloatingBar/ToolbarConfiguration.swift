import Foundation
import Combine
import CoreGraphics

enum ToolbarItemID: String, CaseIterable, Identifiable {
    case askAI, annotate, font, bold, italic, underline, strikethrough, highlight, link, alignment, checklist
    case bullet, dash, numbered, quote, monospaced, table
    var id: String { rawValue }
    var title: String {
        switch self {
        case .askAI: return "AI 写作"
        case .annotate: return "添加批注"
        case .font: return "字体与段落"
        case .bold: return "粗体"
        case .italic: return "斜体"
        case .underline: return "下划线"
        case .strikethrough: return "删除线"
        case .highlight: return "高亮"
        case .link: return "添加或编辑链接"
        case .alignment: return "对齐"
        case .checklist: return "清单"
        case .bullet: return "项目符号列表"
        case .dash: return "短划线列表"
        case .numbered: return "编号列表"
        case .quote: return "块引用"
        case .monospaced: return "等宽样式"
        case .table: return "表格"
        }
    }
    var icon: String {
        switch self {
        case .askAI: return "sparkles"
        case .annotate: return "text.bubble"
        case .font: return "textformat.size"
        case .bold: return "bold"
        case .italic: return "italic"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        case .highlight: return "highlighter"
        case .link: return "link"
        case .alignment: return "text.alignleft"
        case .checklist: return "checklist"
        case .bullet: return "list.bullet"
        case .dash: return "list.dash"
        case .numbered: return "list.number"
        case .quote: return "text.quote"
        case .monospaced: return "chevron.left.forwardslash.chevron.right"
        case .table: return "tablecells"
        }
    }
    var selectionAction: FloatingToolbarAction? { FloatingToolbarAction(rawValue: rawValue) }
}

struct ToolbarItemSetting: Codable, Identifiable, Equatable {
    let id: String
    var visible: Bool
}

struct ToolbarConfiguration: Codable, Equatable {
    var version = 1
    var items: [ToolbarItemSetting]
    static let defaultVisible: Set<ToolbarItemID> = [.askAI, .annotate, .font, .bold, .italic, .underline, .strikethrough, .highlight, .link, .alignment, .checklist]
    static var defaults: Self {
        .init(items: ToolbarItemID.allCases.map { .init(id: $0.rawValue, visible: defaultVisible.contains($0)) })
    }
    func normalized() -> Self {
        var seen = Set<String>()
        var result = items.filter { ToolbarItemID(rawValue: $0.id) != nil && seen.insert($0.id).inserted }
        result += Self.defaults.items.filter { !seen.contains($0.id) }
        return .init(version: version, items: result)
    }
    var visibleItems: [ToolbarItemID] { items.filter(\.visible).compactMap { ToolbarItemID(rawValue: $0.id) } }

    func moving(from offsets: IndexSet, to destination: Int) -> Self {
        guard destination >= 0, destination <= items.count, offsets.allSatisfy(items.indices.contains) else { return self }
        let moving = offsets.sorted().map { items[$0] }
        var remaining = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        return .init(version: version, items: remaining)
    }
}

final class ToolbarSettingsStore: ObservableObject {
    static let shared = ToolbarSettingsStore()
    static let key = "com.opennotes.toolbar.layout.v1"
    @Published private(set) var configuration = ToolbarConfiguration.defaults
    @Published private(set) var message = ""
    @Published private(set) var editable = true
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                let decoded = try JSONDecoder().decode(ToolbarConfiguration.self, from: data)
                guard decoded.version == 1 else { editable = false; message = "工具条设置来自较新版本，已保留原设置。"; return }
                configuration = decoded.normalized()
            } catch { editable = false; message = "工具条设置无法读取，可恢复默认；原设置尚未改动。" }
        }
    }
    func setVisible(_ id: String, _ visible: Bool) {
        guard editable, let index = configuration.items.firstIndex(where: { $0.id == id }) else { return }
        var next = configuration; next.items[index].visible = visible; save(next)
    }
    func move(from offsets: IndexSet, to destination: Int) {
        guard editable else { return }
        save(configuration.moving(from: offsets, to: destination))
    }
    func reset() {
        if let original = defaults.data(forKey: Self.key) { defaults.set(original, forKey: Self.key + ".beforeReset") }
        save(.defaults); editable = true
    }
    private func save(_ configuration: ToolbarConfiguration) {
        do {
            let next = configuration.normalized()
            defaults.set(try JSONEncoder().encode(next), forKey: Self.key)
            self.configuration = next
            message = "已保存；全部关闭时不显示工具条。"
        } catch { message = "保存失败，原设置未改变。" }
    }
}

enum ToolbarLayout {
    static let rowHeight: CGFloat = 34
    static func size(itemCount: Int, feedbackVisible: Bool, maximumWidth: CGFloat) -> CGSize {
        guard itemCount > 0 else { return .zero }
        let width = CGFloat(itemCount) * 28 + CGFloat(itemCount - 1) + 12
        return CGSize(width: min(maximumWidth, max(width, feedbackVisible ? 220 : 0)), height: rowHeight + (feedbackVisible ? 42 : 0))
    }
}
