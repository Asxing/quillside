import Foundation

enum EditorFeaturePreferences {
    static func enabled(_ feature: String, defaults: UserDefaults = .standard) -> Bool {
        let key = "com.opennotes.\(feature).enabled"
        return defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}

enum SlashInputContext {
    static func token(body: String, caret: Int) -> String? {
        let text = body as NSString
        guard caret >= 0, caret <= text.length else { return nil }
        // A command is at most 128 UTF-8 bytes. Never scan the entire note to
        // locate a token at the caret (especially for long Unicode documents).
        let start = max(0, caret - 129)
        let prefix = text.substring(with: NSRange(location: start, length: caret - start))
        let token = prefix.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        guard let last = prefix.last, !last.isWhitespace, token.first == "/", token.utf8.count <= 128,
              token.dropFirst().unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") }) else { return nil }
        return token
    }
}
