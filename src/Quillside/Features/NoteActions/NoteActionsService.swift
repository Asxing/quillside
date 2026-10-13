import AppKit
import Foundation

enum NoteActionKind: String, Equatable {
    case copyMarkdown
    case copyNoteLink
    case backlinks

    var successMessage: String? {
        switch self {
        case .copyMarkdown:
            return "已复制 Markdown"
        case .copyNoteLink:
            return "已复制笔记链接"
        case .backlinks:
            return nil
        }
    }
}

enum NoteActionItem: String, CaseIterable, Identifiable {
    case copyMarkdown = "copy-markdown"
    case copyNoteLink = "copy-note-link"
    case backlinks
    case askAI = "ask-ai"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copyMarkdown:
            return "复制 Markdown"
        case .copyNoteLink:
            return "复制笔记链接"
        case .backlinks:
            return "显示 Backlinks"
        case .askAI:
            return "AI 编辑"
        }
    }

    var symbol: String {
        switch self {
        case .copyMarkdown:
            return "doc.text"
        case .copyNoteLink:
            return "link"
        case .backlinks:
            return "arrow.triangle.branch"
        case .askAI:
            return "sparkles"
        }
    }

    var isEnabled: Bool {
        true
    }
    func isBusy(activeAction: NoteActionKind?) -> Bool {
        guard let actionKind, let activeAction else { return false }
        return actionKind == activeAction
    }

    var actionKind: NoteActionKind? {
        switch self {
        case .copyMarkdown:
            return .copyMarkdown
        case .copyNoteLink:
            return .copyNoteLink
        case .backlinks:
            return .backlinks
        case .askAI:
            return nil
        }
    }
}

enum NoteActionError: Error, Equatable {
    case resolution(CurrentNoteResolutionError)
    case conversionFailed
    case pasteboardFailed

    var userMessage: String {
        switch self {
        case .resolution(.notesNotRunning):
            return "请先打开 Apple Notes"
        case .resolution(.notesNotFrontmost):
            return "请先选择一篇笔记"
        case .resolution(.databaseUnavailable):
            return "无法读取当前笔记，请检查完全磁盘访问"
        case .resolution(.automationDenied):
            return "请允许 Notes 自动化访问"
        case .resolution(.automationNotDetermined):
            return "请再次触发操作并允许 Notes 自动化访问"
        case .resolution(.timedOut):
            return "Apple Notes 响应超时，请重试"
        case .resolution(.staleNote):
            return "笔记已切换，请重试"
        case .resolution:
            return "无法读取当前笔记，请重试"
        case .conversionFailed:
            return "无法转换当前笔记，请重试"
        case .pasteboardFailed:
            return "复制失败，请重试"
        }
    }
}

struct NoteActionPasteboardPayload: Equatable {
    let value: String
    let types: [NSPasteboard.PasteboardType]
}

struct NoteActionOutcome: Equatable {
    let note: ResolvedCurrentNote
    let feedbackMessage: String?
    let pasteboardPayload: NoteActionPasteboardPayload?
}

protocol PasteboardWriting: AnyObject {
    func write(
        _ value: String,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool
}

final class SystemPasteboardWriter: PasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(
        _ value: String,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        pasteboard.clearContents()
        return types.reduce(true) { didWriteAll, type in
            pasteboard.setString(value, forType: type) && didWriteAll
        }
    }
}

protocol NoteActionsServicing: AnyObject {
    func resolveCurrentNote()
        -> Result<ResolvedCurrentNote, NoteActionError>

    func perform(
        _ action: NoteActionKind,
        expectedNote: ResolvedCurrentNote?
    ) -> Result<NoteActionOutcome, NoteActionError>

    func commitPasteboard(
        _ payload: NoteActionPasteboardPayload
    ) -> Bool
}

final class NoteActionsService: NoteActionsServicing {
    private let resolver: CurrentNoteResolver
    private let converter: AppleNotesMarkdownConverter
    private let pasteboard: PasteboardWriting

    init(
        resolver: CurrentNoteResolver = CurrentNoteResolver(),
        converter: AppleNotesMarkdownConverter =
            AppleNotesMarkdownConverter(),
        pasteboard: PasteboardWriting = SystemPasteboardWriter()
    ) {
        self.resolver = resolver
        self.converter = converter
        self.pasteboard = pasteboard
    }

    func resolveCurrentNote()
        -> Result<ResolvedCurrentNote, NoteActionError>
    {
        resolver
            .resolve(allowAutomationPrompt: false)
            .mapError(NoteActionError.resolution)
    }

    func perform(
        _ action: NoteActionKind,
        expectedNote: ResolvedCurrentNote?
    ) -> Result<NoteActionOutcome, NoteActionError> {
        switch action {
        case .copyMarkdown:
            return copyMarkdown(expectedNote: expectedNote)
        case .copyNoteLink:
            return copyNoteLink(expectedNote: expectedNote)
        case .backlinks:
            return resolveExpectedNote(expectedNote).map {
                NoteActionOutcome(
                    note: $0,
                    feedbackMessage: nil,
                    pasteboardPayload: nil
                )
            }
        }
    }

    func commitPasteboard(
        _ payload: NoteActionPasteboardPayload
    ) -> Bool {
        pasteboard.write(
            payload.value,
            types: payload.types
        )
    }

    private func copyMarkdown(
        expectedNote: ResolvedCurrentNote?
    ) -> Result<NoteActionOutcome, NoteActionError> {
        resolver
            .resolveContent(
                expectedNote: expectedNote
            )
            .mapError(NoteActionError.resolution)
            .flatMap { content in
                let markdown: String
                do {
                    markdown = try converter.convert(
                        title: content.note.title,
                        htmlBody: content.htmlBody
                    )
                } catch {
                    return .failure(.conversionFailed)
                }

                return .success(
                    NoteActionOutcome(
                        note: content.note,
                        feedbackMessage:
                            NoteActionKind.copyMarkdown.successMessage,
                        pasteboardPayload:
                            NoteActionPasteboardPayload(
                                value: markdown,
                                types: [.string]
                            )
                    )
                )
            }
    }

    private func copyNoteLink(
        expectedNote: ResolvedCurrentNote?
    ) -> Result<NoteActionOutcome, NoteActionError> {
        resolveExpectedNote(expectedNote).flatMap { note in
            guard let nativeIdentifier = note.nativeIdentifier else {
                return .failure(
                    .resolution(.databaseUnavailable)
                )
            }
            let value = NotesDBReader.shared.buildNoteURL(
                identifier: nativeIdentifier
            )
            return .success(
                NoteActionOutcome(
                    note: note,
                    feedbackMessage:
                        NoteActionKind.copyNoteLink.successMessage,
                    pasteboardPayload:
                        NoteActionPasteboardPayload(
                            value: value,
                            types: [.string, .URL]
                        )
                )
            )
        }
    }

    private func resolveExpectedNote(
        _ expectedNote: ResolvedCurrentNote?
    ) -> Result<ResolvedCurrentNote, NoteActionError> {
        resolver
            .resolve(
                allowAutomationPrompt: true,
                requiresNativeIdentifier: true
            )
            .mapError(NoteActionError.resolution)
            .flatMap { resolved in
            if let expectedNote,
               !resolved.refersToSameNote(as: expectedNote) {
                return .failure(.resolution(.staleNote))
            }
            return .success(resolved)
            }
    }
}
