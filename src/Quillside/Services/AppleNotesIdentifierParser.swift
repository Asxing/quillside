import Foundation

enum AppleNotesIdentifierParser {
    static func primaryKey(from coreDataIdentifier: String) -> Int64? {
        guard
            let lastComponent = coreDataIdentifier
                .split(separator: "/")
                .last,
            lastComponent.first == "p"
        else {
            return nil
        }

        return Int64(lastComponent.dropFirst())
    }
}

enum NativeNoteLinkParser {
    static func identifiers(in text: String) -> [String] {
        Array(Set(text.split(whereSeparator: \.isWhitespace).flatMap { identifiers(inURL: String($0)) })).sorted()
    }
    static func identifiers(inURL text: String) -> [String] {
        guard let url = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["notes", "applenotes", "mobilenotes"].contains(scheme) else { return [] }
        if scheme == "applenotes", url.host == nil, url.path.hasPrefix("note/") {
            let parts = url.path.split(separator: "/")
            return parts.count >= 2 ? UUID(uuidString: String(parts[1])).map { [$0.uuidString] } ?? [] : []
        }
        guard url.host?.lowercased() == "shownote" else { return [] }
        let items = (url.queryItems ?? []).filter { $0.name == "identifier" }
        let parsed = items.compactMap { $0.value.flatMap(UUID.init(uuidString:))?.uuidString }
        let ids = Set(parsed)
        return parsed.count == items.count && ids.count == 1 ? Array(ids) : []
    }
    static func isPotentialNoteLink(_ text: String) -> Bool {
        guard let url = URLComponents(string: text), let scheme = url.scheme?.lowercased(),
              ["notes", "applenotes", "mobilenotes"].contains(scheme) else { return false }
        return url.host?.lowercased() == "shownote" || url.path.hasPrefix("note/")
    }
}

enum SelectedNoteMatcher {
    static func identifier(
        textCandidates: Set<String>,
        notes: [(title: String, identifier: String)]
    ) -> String? {
        let matches = Set<String>(
            notes.compactMap { note in
                guard textCandidates.contains(note.title), !note.identifier.isEmpty else {
                    return nil
                }
                return note.identifier
            }
        )
        return matches.count == 1 ? matches.first : nil
    }
}
