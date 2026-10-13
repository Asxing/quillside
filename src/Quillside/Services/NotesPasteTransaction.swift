import AppKit
import ApplicationServices

enum NotesPasteContent {
    case text(String)
    case rich(NSAttributedString)
    var text: String { switch self { case .text(let value): return value; case .rich(let value): return value.string } }
    func pasteboardItem() throws -> NSPasteboardItem {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string) else { throw AIError.message("无法准备插入内容。") }
        if case .rich(let value) = self {
            let data = try value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            guard item.setData(data, forType: .rtf) else { throw AIError.message("无法准备链接格式。") }
        }
        return item
    }
}

enum UTF16TextRange {
    static func valid(_ range: NSRange, in body: String) -> Bool {
        let text = body as NSString
        guard range.location >= 0, range.length >= 0, range.location <= text.length, range.length <= text.length - range.location else { return false }
        func boundary(_ offset: Int) -> Bool {
            guard offset > 0 && offset < text.length else { return true }
            return !((0xDC00...0xDFFF).contains(text.character(at: offset)) && (0xD800...0xDBFF).contains(text.character(at: offset - 1)))
        }
        return boundary(range.location) && boundary(NSMaxRange(range))
    }
}

enum NotesPastePlan {
    static func expected(body: String, range: NSRange, replacement: String) throws -> String {
        guard UTF16TextRange.valid(range, in: body),
              !(body as NSString).substring(with: range).contains("\u{FFFC}") else {
            throw AIError.message("插入范围无效或包含原生对象，正文未改变。")
        }
        return (body as NSString).replacingCharacters(in: range, with: replacement)
    }
    static func mayRestoreClipboard(savedChange: Int, currentChange: Int) -> Bool { savedChange == currentChange }
}

extension SelectionTransaction {
    /// One native paste, no automatic fallback/retry after an uncertain write. This enters Notes' undo stack.
    @MainActor func paste(_ content: NotesPasteContent, at replacementRange: NSRange) async throws {
        try validateForWrite()
        guard !content.text.isEmpty else { throw AIError.message("没有可插入的内容。") }
        let expected = try NotesPastePlan.expected(body: body, range: replacementRange, replacement: content.text)
        let item = try content.pasteboardItem()
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { original -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in original.types { if let data = original.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        try validateForWrite()
        var range = CFRange(location: replacementRange.location, length: replacementRange.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw AIError.message("Notes 未接受插入位置，正文未改变。")
        }
        let writeTarget = Self(element: element, window: window, pid: pid, body: body, range: replacementRange,
            text: (body as NSString).substring(with: replacementRange), title: title, noteIdentity: noteIdentity, capturedSelection: replacementRange)
        try writeTarget.validateForWrite()
        board.clearContents()
        let success = board.writeObjects([item]), change = board.changeCount
        defer {
            if NotesPastePlan.mayRestoreClipboard(savedChange: change, currentChange: board.changeCount) {
                board.clearContents(); if !saved.isEmpty { board.writeObjects(saved) }
            }
        }
        guard success else { throw AIError.message("无法准备剪贴板，正文未改变。") }
        try writeTarget.validateForWrite()
        guard case .success = NotesMenuExecutor().perform(.paste) else { throw AIError.message("Notes 未接受粘贴，未自动重试。") }
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 50_000_000)
            guard AccessibilityBridge.shared.isNotesFrontmost(),
                  let currentWindow = AccessibilityBridge.shared.getFocusedWindow()?.element, CFEqual(currentWindow, window),
                  let editor = AccessibilityBridge.shared.getFocusedUIElement(), CFEqual(editor, element) else {
                throw AIError.message("粘贴期间目标已切换，请检查原笔记；未自动重试。")
            }
            if Self.value(kAXValueAttribute, of: element) as? String == expected {
                let selection = try SystemAppleNotesSelectionProvider().selectedNote(includeBody: false, allowAutomationPrompt: false).get()
                guard selection.coreDataIdentifier == noteIdentity else { throw AIError.message("写后笔记身份已变化，请检查原笔记。") }
                return
            }
        }
        throw AIError.message("写后读回未能确认。请检查 Notes，可撤销本次粘贴；未自动重试。")
    }
}
