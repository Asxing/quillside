import AppKit
import ApplicationServices

/// Uses the live editor's link attributes. Notes' AppleScript HTML can omit
/// native note links, so it cannot establish that a generated region is intact.
enum NotesNativeLinks {
    static let accessibilityKey = NSAttributedString.Key("AXLink")

    static func identifiers(in text: NSAttributedString, resolve: (Any) -> String? = destination) -> Set<String>? {
        var result = Set<String>(), valid = true
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { values, _, _ in
            for key in [NSAttributedString.Key.link, accessibilityKey] {
                guard let value = values[key] else { continue }
                guard let url = resolve(value) else { valid = false; continue }
                let identifiers = NativeNoteLinkParser.identifiers(inURL: url)
                guard !identifiers.isEmpty else { valid = false; continue }
                result.formUnion(identifiers)
            }
        }
        return valid ? result : nil
    }

    static func destination(_ value: Any) -> String? {
        if let url = value as? URL { return url.absoluteString }
        if let string = value as? String { return string }
        let object = value as CFTypeRef
        guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(object, to: AXUIElement.self)
        for name in [kAXURLAttribute, kAXValueAttribute] {
            var output: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &output) == .success else { continue }
            if let url = output as? URL { return url.absoluteString }
            if let string = output as? String, URL(string: string)?.scheme != nil { return string }
        }
        return nil
    }
}

extension SelectionTransaction {
    func nativeLinksMatch(_ region: BacklinkDocumentRegion, at range: NSRange) -> Bool {
        var parameterRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &parameterRange) else { return false }
        var output: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXAttributedStringForRangeParameterizedAttribute as CFString, parameter, &output) == .success,
              let rich = output as? NSAttributedString, rich.string == region.text,
              let identifiers = NotesNativeLinks.identifiers(in: rich) else { return false }
        return identifiers == Set(region.entries.map(\.identifier))
    }
}
