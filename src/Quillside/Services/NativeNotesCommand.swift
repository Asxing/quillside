import AppKit
import ApplicationServices

enum NativeNotesCommand: String, CaseIterable {
    case bold, italic, underline, strikethrough
    case title, heading, subheading, body
    case bulletList, numberedList, todoList, dashList
    case quote, codeBlock, highlight, table, link
    case alignLeft, alignCenter, alignRight, alignJustified
    case fontLarger, fontSmaller, showFonts, paste

    var menuTitles: [String] {
        switch self {
        case .paste: return ["Paste", "粘贴", "貼上"]
        case .bold: return ["Bold", "粗体", "粗體"]
        case .italic: return ["Italic", "斜体", "斜體"]
        case .underline: return ["Underline", "下划线", "底線"]
        case .strikethrough: return ["Strikethrough", "删除线", "刪除線"]
        case .title: return ["Title", "标题", "標題"]
        case .heading: return ["Heading", "小标题", "標頭"]
        case .subheading: return ["Subheading", "副标题", "副標題", "次標題"]
        case .body: return ["Body", "正文", "內文"]
        case .bulletList: return ["Bulleted List", "项目符号列表", "項目符號列表"]
        case .numberedList: return ["Numbered List", "编号列表", "編號列表"]
        case .todoList: return ["Checklist", "核对清单", "檢查列表", "清单"]
        case .dashList: return ["Dashed List", "短划线列表", "破折號列表"]
        case .quote: return ["Block Quote", "块引用", "區塊引用"]
        case .codeBlock: return ["Monostyled", "Monospaced", "等宽", "等寬"]
        case .highlight: return ["Highlight", "高亮显示", "醒目提示"]
        case .table: return ["Table", "表格"]
        case .link: return ["Add Link", "Edit Link", "添加链接", "编辑链接", "加入連結", "編輯連結"]
        case .alignLeft: return ["Align Left", "左对齐", "靠左對齊"]
        case .alignCenter: return ["Center", "居中", "置中"]
        case .alignRight: return ["Align Right", "右对齐", "靠右對齊"]
        case .alignJustified: return ["Justify", "两端对齐", "左右對齊"]
        case .fontLarger: return ["Bigger", "较大", "放大", "放大字體"]
        case .fontSmaller: return ["Smaller", "较小", "縮小", "缩小", "縮小字體"]
        case .showFonts: return ["Show Fonts", "显示字体", "顯示字體"]
        }
    }
    /// AX menu modifier bits: Shift 1, Option 2, Control 4; Command is implicit unless bit 8 is set.
    var shortcut: (character: String, modifiers: Int)? {
        switch self {
        case .paste: return ("v", 0)
        case .bold: return ("b", 0)
        case .italic: return ("i", 0)
        case .underline: return ("u", 0)
        case .strikethrough: return ("x", 1)
        case .title: return ("t", 1)
        case .heading: return ("h", 1)
        case .subheading: return ("j", 1)
        case .body: return ("b", 1)
        case .bulletList: return ("7", 1)
        case .dashList: return ("8", 1)
        case .numberedList: return ("9", 1)
        case .todoList: return ("l", 1)
        case .quote: return ("'", 0)
        case .codeBlock: return ("m", 1)
        case .highlight: return ("e", 1)
        case .table: return ("t", 2)
        case .link: return ("k", 0)
        case .alignLeft: return ("{", 0)
        case .alignCenter: return ("|", 0)
        case .alignRight: return ("}", 0)
        case .showFonts: return ("t", 0)
        case .fontLarger, .fontSmaller, .alignJustified: return nil
        }
    }
    var expectedTopMenus: [String] {
        self == .link || self == .paste ? ["Edit", "编辑", "編輯"] : ["Format", "格式"]
    }
    var allowedSubmenus: [String] {
        switch self {
        case .bold, .italic, .underline, .strikethrough, .highlight, .fontLarger, .fontSmaller, .showFonts:
            return ["Font", "字体", "字體"]
        case .alignLeft, .alignCenter, .alignRight, .alignJustified:
            return ["Text", "文本", "文字"]
        default: return []
        }
    }
}

struct NotesMenuItemDescription: Equatable {
    var title: String
    var ancestors: [String]
    var enabled: Bool
    var commandCharacter: String? = nil
    var commandModifiers: Int? = nil
    var hidden = false
    var alternate = false
}

enum NotesMenuResolution: Equatable {
    case item(Int), disabled, unavailable, ambiguous
}

enum NotesMenuMatcher {
    static func normalize(_ title: String) -> String {
        title.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static func resolve(_ command: NativeNotesCommand, in items: [NotesMenuItemDescription]) -> NotesMenuResolution {
        let titles = Set(command.menuTitles.map(normalize))
        let roots = Set(command.expectedTopMenus.map(normalize))
        let allowedAncestors = roots.union(command.allowedSubmenus.map(normalize))
        let candidates: [(Int, Int)] = items.enumerated().compactMap { index, item in
            guard !item.hidden, !item.alternate else { return nil }
            let expectedRoot = item.ancestors.contains { roots.contains(normalize($0)) }
            let named = titles.contains(normalize(item.title)) && expectedRoot
                && item.ancestors.allSatisfy { allowedAncestors.contains(normalize($0)) }
            let shortcut = command.shortcut.map {
                item.commandCharacter?.lowercased() == $0.character && item.commandModifiers == $0.modifiers
            } ?? false
            guard named || shortcut else { return nil }
            return (index, named ? (shortcut ? 110 : 100) : 50)
        }
        guard let best = candidates.map(\.1).max() else { return .unavailable }
        let winners = candidates.filter { $0.1 == best }
        let enabled = winners.filter { items[$0.0].enabled }
        guard !enabled.isEmpty else { return .disabled }
        guard enabled.count == 1, let index = enabled.first?.0 else { return .ambiguous }
        return .item(index)
    }
    static func eventFlags(menuModifiers: Int) -> CGEventFlags {
        var flags: CGEventFlags = menuModifiers & 8 == 0 ? [.maskCommand] : []
        if menuModifiers & 1 != 0 { flags.insert(.maskShift) }
        if menuModifiers & 2 != 0 { flags.insert(.maskAlternate) }
        if menuModifiers & 4 != 0 { flags.insert(.maskControl) }
        return flags
    }
    static func canPostShortcut(virtualKey: Int?, character: String?, modifiers: Int?) -> Bool {
        guard let virtualKey, let character, !character.isEmpty, let modifiers else { return false }
        return (0...Int(UInt16.max)).contains(virtualKey) && (0...15).contains(modifiers)
    }
}

enum NotesFormatFailure: Error, LocalizedError, Equatable {
    case noEditor, changedSelection, unavailable, disabled, ambiguous, rejected
    var errorDescription: String? {
        switch self {
        case .noEditor: return "请先选择 Apple Notes 正文中的文字。"
        case .changedSelection: return "选区或窗口已经变化，请重新选择。"
        case .unavailable: return "当前 Notes 未提供此菜单操作，或菜单暂时不可读。"
        case .disabled: return "当前 Notes 已禁用此操作。"
        case .ambiguous: return "菜单命令不唯一，已停止操作。"
        case .rejected: return "Notes 未接受菜单操作，请在原生菜单中重试。"
        }
    }
}

/// AX only. A command is selected from the current app menu; no fixed-coordinate clicks or blind hotkeys.
final class NotesMenuExecutor {
    private struct LiveItem {
        let element: AXUIElement
        let description: NotesMenuItemDescription
        let virtualKey: Int?
    }
    private struct EditorAnchor {
        let pid: pid_t
        let editor: AXUIElement
        let window: AXUIElement
        let range: CFRange
        let selected: String
        let bodyFingerprint: String
        let allowsCell: Bool
        static func capture(allowsCell: Bool = false) -> Self? {
            let bridge = AccessibilityBridge.shared
            guard let context = NotesEditorContext.read(), context.scope == .body || (allowsCell && context.scope == .cell) else { return nil }
            guard bridge.isNotesFrontmost(), let pid = bridge.getNotesAppPID(),
                  let editor = bridge.getFocusedUIElement(), let window = bridge.getFocusedWindow()?.element,
                  SelectionTransaction.value(kAXRoleAttribute, of: editor) as? String == kAXTextAreaRole,
                  let body = SelectionTransaction.value(kAXValueAttribute, of: editor) as? String,
                  let raw = SelectionTransaction.value(kAXSelectedTextRangeAttribute, of: editor), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            var range = CFRange()
            guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
            return .init(pid: pid, editor: editor, window: window, range: range,
                         selected: SelectionTransaction.value(kAXSelectedTextAttribute, of: editor) as? String ?? "",
                         bodyFingerprint: TextFingerprint.hash(body), allowsCell: allowsCell)
        }
        func stillMatches() -> Bool {
            guard let current = Self.capture(allowsCell: allowsCell) else { return false }
            return current.pid == pid && CFEqual(current.editor, editor) && CFEqual(current.window, window)
                && current.range.location == range.location && current.range.length == range.length && current.selected == selected
                && current.bodyFingerprint == bodyFingerprint
        }
    }

    func perform(_ command: NativeNotesCommand) -> Result<Void, NotesFormatFailure> {
        guard let anchor = EditorAnchor.capture(allowsCell: command == .paste) else { return .failure(.noEditor) }
        let app = AXUIElementCreateApplication(anchor.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let rawMenu = SelectionTransaction.value(kAXMenuBarAttribute, of: app),
              CFGetTypeID(rawMenu) == AXUIElementGetTypeID(),
              let items = readMenu(rawMenu as! AXUIElement, command: command) else { return .failure(.unavailable) }
        let result = NotesMenuMatcher.resolve(command, in: items.map(\.description))
        let index: Int
        switch result {
        case let .item(value): index = value
        case .disabled: return .failure(.disabled)
        case .unavailable: return .failure(.unavailable)
        case .ambiguous: return .failure(.ambiguous)
        }
        guard anchor.stillMatches() else { return .failure(.changedSelection) }
        let item = items[index]
        guard SelectionTransaction.value(kAXEnabledAttribute, of: item.element) as? Bool == true else { return .failure(.disabled) }
        var actions: CFArray?
        AXUIElementCopyActionNames(item.element, &actions)
        if (actions as? [String])?.contains(kAXPressAction as String) == true {
            return AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success ? .success(()) : .failure(.rejected)
        }
        // Use only a shortcut actually exposed by this enabled menu item, when it has no AXPress.
        guard NotesMenuMatcher.canPostShortcut(virtualKey: item.virtualKey, character: item.description.commandCharacter, modifiers: item.description.commandModifiers),
              let key = item.virtualKey,
              let modifiers = item.description.commandModifiers,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: false),
              anchor.stillMatches() else { return .failure(.rejected) }
        down.flags = NotesMenuMatcher.eventFlags(menuModifiers: modifiers); up.flags = down.flags
        down.postToPid(anchor.pid); up.postToPid(anchor.pid)
        return .success(())
    }

    private func readMenu(_ root: AXUIElement, command: NativeNotesCommand) -> [LiveItem]? {
        let attributes = [kAXRoleAttribute, kAXTitleAttribute, kAXEnabledAttribute, kAXChildrenAttribute,
                          kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute, kAXMenuItemCmdVirtualKeyAttribute,
                          kAXHiddenAttribute, kAXMenuItemPrimaryUIElementAttribute] as [CFString]
        var result: [LiveItem] = [], visited = 0
        let deadline = Date().addingTimeInterval(1.5)
        func walk(_ element: AXUIElement, parents: [String], depth: Int) -> Bool {
            guard depth < 12, visited < 1200, Date() < deadline else { return false }
            visited += 1
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &raw) == .success,
                  let values = raw as? [Any], values.count == attributes.count else { return false }
            let role = values[0] as? String, title = values[1] as? String ?? ""
            if role == kAXMenuItemRole {
                let primary = values[8] as CFTypeRef
                let alternate = CFGetTypeID(primary) == AXUIElementGetTypeID() && !CFEqual(primary, element)
                result.append(.init(element: element,
                    description: .init(title: title, ancestors: parents, enabled: values[2] as? Bool == true,
                                       commandCharacter: values[4] as? String, commandModifiers: (values[5] as? NSNumber)?.intValue,
                                       hidden: values[7] as? Bool ?? false, alternate: alternate),
                    virtualKey: (values[6] as? NSNumber)?.intValue))
            }
            let nextParents = title.isEmpty ? parents : parents + [title]
            for child in values[3] as? [AXUIElement] ?? [] {
                if !walk(child, parents: nextParents, depth: depth + 1) { return false }
            }
            return true
        }
        guard let topItems = SelectionTransaction.value(kAXChildrenAttribute, of: root) as? [AXUIElement] else { return nil }
        let expected = Set(command.expectedTopMenus.map(NotesMenuMatcher.normalize))
        let narrowed = topItems.filter { item in
            (SelectionTransaction.value(kAXTitleAttribute, of: item) as? String).map { expected.contains(NotesMenuMatcher.normalize($0)) } ?? false
        }
        for item in narrowed.isEmpty ? topItems : narrowed {
            guard walk(item, parents: [], depth: 0) else { return nil }
        }
        return result
    }
}
