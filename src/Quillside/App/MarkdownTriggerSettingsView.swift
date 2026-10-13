import SwiftUI

enum MarkdownTriggerPreferences {
    static let key = "com.opennotes.markdown.triggers"
    static var all: Set<String> { Set(MarkdownTriggerDefinition.all.map(\.pattern)) }
    static func enabled(defaults: UserDefaults = .standard) -> Set<String> {
        defaults.stringArray(forKey: key).map { Set($0).intersection(all) } ?? all
    }
    static func set(_ pattern: String, enabled: Bool, defaults: UserDefaults = .standard) {
        guard all.contains(pattern) else { return }
        var value = Self.enabled(defaults: defaults)
        if enabled { value.insert(pattern) } else { value.remove(pattern) }
        defaults.set(value.sorted(), forKey: key)
    }
}

struct MarkdownTriggerSettingsView: View {
    @State private var enabled = MarkdownTriggerPreferences.enabled()
    var body: some View {
        ForEach(MarkdownTriggerDefinition.all) { trigger in
            Toggle(isOn: Binding(get: { enabled.contains(trigger.pattern) }, set: { value in
                MarkdownTriggerPreferences.set(trigger.pattern, enabled: value)
                enabled = MarkdownTriggerPreferences.enabled()
            })) {
                HStack {
                    Text(trigger.pattern).font(.body.monospaced()).frame(width: 44, alignment: .leading)
                    Text(trigger.resultName)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in enabled = MarkdownTriggerPreferences.enabled() }
    }
}
