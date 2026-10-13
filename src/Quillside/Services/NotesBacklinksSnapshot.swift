import Foundation

struct BacklinksCoverage: Equatable {
    var lockedNotes = 0
    var unreadableNotes = 0
    var unresolvedLinks = 0
    var complexContainers = 0
    var complete: Bool { lockedNotes == 0 && unreadableNotes == 0 && unresolvedLinks == 0 && complexContainers == 0 }
    var summary: String {
        var parts: [String] = []
        if lockedNotes > 0 { parts.append("跳过 \(lockedNotes) 篇密码保护笔记") }
        if unreadableNotes > 0 { parts.append("\(unreadableNotes) 篇正文未能读取") }
        if unresolvedLinks > 0 { parts.append("\(unresolvedLinks) 个链接未能解析") }
        if complexContainers > 0 { parts.append("\(complexContainers) 个复杂内容容器尚未检查") }
        return parts.isEmpty ? "" : parts.joined(separator: "；") + "，结果可能不完整。"
    }
    mutating func merge(_ other: Self) {
        lockedNotes += other.lockedNotes; unreadableNotes += other.unreadableNotes
        unresolvedLinks += other.unresolvedLinks; complexContainers += other.complexContainers
    }
}

struct NotesBacklinksSnapshot {
    let notes: [NotesDBReader.NoteInfo]
    let links: [NotesDBReader.NoteLinkData]
    var coverage = BacklinksCoverage()
}

struct NativeLinkAttachment {
    let sourceNoteID: Int64
    let identifier: String
    let type: String
    let urls: [String]
}

enum ActiveNoteLinkExtractor {
    struct Result { let identifiers: [String]; let coverage: BacklinksCoverage }
    static func extract(_ note: AppleNotesDecodedNote, sourceID: Int64, attachments: [String: NativeLinkAttachment], excluding: [NSRange] = [], only included: NSRange? = nil) throws -> Result {
        let text = note.noteText as NSString
        var offset = 0, identifiers = Set<String>(), coverage = BacklinksCoverage()
        for run in note.attributeRuns {
            guard run.length >= 0, run.length <= text.length - offset else { throw AppleNotesNoteDecodingError.invalidProtobuf }
            let runRange = NSRange(location: offset, length: run.length)
            let fragment = text.substring(with: runRange)
            offset += run.length
            guard run.length > 0 else { continue }
            if let included, NSIntersectionRange(included, runRange).length == 0 { continue }
            if excluding.contains(where: { NSIntersectionRange($0, runRange).length == runRange.length }) { continue }
            let direct = run.link.map { NativeNoteLinkParser.identifiers(inURL: $0) } ?? []
            if direct.isEmpty, let link = run.link, NativeNoteLinkParser.isPotentialNoteLink(link) { coverage.unresolvedLinks += 1 }
            identifiers.formUnion(direct)
            guard let attachment = run.attachmentInfo, fragment.contains("\u{FFFC}") else { continue }
            let type = attachment.typeUti
            if type.hasPrefix("com.apple.notes.table") { coverage.complexContainers += 1; continue }
            guard type == "com.apple.notes.inlinetextattachment.link" || type == "public.url" else {
                if type.lowercased().contains("link") { coverage.complexContainers += 1 }
                continue
            }
            if !direct.isEmpty { continue }
            guard let metadata = attachments[attachment.attachmentIdentifier.uppercased()], metadata.sourceNoteID == sourceID else {
                coverage.unresolvedLinks += 1; continue
            }
            guard metadata.type.isEmpty || metadata.type == type else { coverage.unresolvedLinks += 1; continue }
            var found = Set(metadata.urls.flatMap { NativeNoteLinkParser.identifiers(inURL: $0) })
            if metadata.urls.isEmpty { coverage.unresolvedLinks += 1; continue }
            if type == "com.apple.notes.inlinetextattachment.link" {
                found.formUnion(metadata.urls.compactMap { UUID(uuidString: $0)?.uuidString })
                if found.isEmpty { coverage.unresolvedLinks += 1 }
            }
            identifiers.formUnion(found)
        }
        return .init(identifiers: identifiers.sorted(), coverage: coverage)
    }
}
