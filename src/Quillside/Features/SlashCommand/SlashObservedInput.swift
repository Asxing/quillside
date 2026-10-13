import Foundation

enum SlashObservedInput {
    static func submission(previousBody: String, previousSelection: NSRange, body: String, selection: NSRange) -> (token: String, suffix: String)? {
        guard previousSelection.length == 0, selection.length == 0,
              let token = SlashInputContext.token(body: previousBody, caret: previousSelection.location) else { return nil }
        for suffix in ["\n", "\t", " "] {
            if selection.location == previousSelection.location + (suffix as NSString).length,
               body == (previousBody as NSString).replacingCharacters(in: previousSelection, with: suffix) {
                return (token, suffix)
            }
        }
        return nil
    }
}
