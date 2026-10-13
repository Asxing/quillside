import AppKit
import ApplicationServices

enum SelectionFormattingAnalyzer {
    static func actions(
        in attributedString: NSAttributedString?
    ) -> Set<FloatingToolbarAction> {
        guard
            let attributedString,
            attributedString.length > 0
        else {
            return []
        }

        var commonActions: Set<FloatingToolbarAction>?
        attributedString.enumerateAttributes(
            in: NSRange(location: 0, length: attributedString.length)
        ) { attributes, _, _ in
            let runActions = actions(in: attributes)
            if let existing = commonActions {
                commonActions = existing.intersection(runActions)
            } else {
                commonActions = runActions
            }
        }
        return commonActions ?? []
    }

    private static func actions(
        in attributes: [NSAttributedString.Key: Any]
    ) -> Set<FloatingToolbarAction> {
        var actions = Set<FloatingToolbarAction>()

        if let font = attributes[
            key(kAXFontTextAttribute)
        ] as? NSDictionary {
            let names = [
                font.object(forKey: raw(kAXFontNameKey)),
                font.object(forKey: raw(kAXFontFamilyKey)),
                font.object(forKey: raw(kAXVisibleNameKey)),
            ]
                .compactMap { $0 as? String }
                .joined(separator: " ")
                .lowercased()

            if names.contains("bold") || names.contains("semibold") {
                actions.insert(.bold)
            }
            if names.contains("italic") || names.contains("oblique") {
                actions.insert(.italic)
            }
            if names.contains("mono")
                || names.contains("menlo")
                || names.contains("courier") {
                actions.insert(.monospaced)
            }
        }

        if numberValue(
            attributes[key(kAXUnderlineTextAttribute)]
        ) != 0 {
            actions.insert(.underline)
        }
        if boolValue(
            attributes[key(kAXStrikethroughTextAttribute)]
        ) {
            actions.insert(.strikethrough)
        }
        if attributes[key(kAXBackgroundColorTextAttribute)] != nil {
            actions.insert(.highlight)
        }
        if attributes[key(kAXLinkTextAttribute)] != nil { actions.insert(.link) }

        if let prefix = listPrefix(
            attributes[key(kAXListItemPrefixTextAttribute)]
        ) {
            if ["☐", "☑", "☒"].contains(prefix) {
                actions.insert(.checklist)
            } else if prefix.range(
                of: #"^\d+[\.\)]?$"#,
                options: String.CompareOptions.regularExpression
            ) != nil {
                actions.insert(.numbered)
            } else if ["-", "–", "—"].contains(prefix) {
                actions.insert(.dash)
            } else {
                actions.insert(.bullet)
            }
        }

        return actions
    }

    private static func key(
        _ value: Unmanaged<CFString>
    ) -> NSAttributedString.Key {
        NSAttributedString.Key(rawValue: raw(value))
    }

    private static func raw(
        _ value: Unmanaged<CFString>
    ) -> String {
        value.takeUnretainedValue() as String
    }

    private static func numberValue(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func boolValue(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }

    private static func listPrefix(_ value: Any?) -> String? {
        let raw: String?
        switch value {
        case let string as String:
            raw = string
        case let attributed as NSAttributedString:
            raw = attributed.string
        default:
            raw = nil
        }
        let trimmed = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
