import SwiftUI

struct ToolbarCustomizationView: View {
    @ObservedObject var store = ToolbarSettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择显示项目，拖动行或使用上移、下移按钮排序。")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(Array(store.configuration.items.enumerated()), id: \.element.id) { index, setting in
                    if let item = ToolbarItemID(rawValue: setting.id) {
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Toggle(isOn: Binding(get: { store.configuration.items.first(where: { $0.id == setting.id })?.visible ?? false }, set: { store.setVisible(setting.id, $0) })) {
                                Label(item.title, systemImage: item.icon)
                            }.toggleStyle(.checkbox)
                            Spacer()
                            Button { store.move(from: [index], to: index - 1) } label: { Image(systemName: "arrow.up") }
                                .buttonStyle(.borderless).disabled(index == 0).accessibilityLabel("上移\(item.title)")
                            Button { store.move(from: [index], to: index + 2) } label: { Image(systemName: "arrow.down") }
                                .buttonStyle(.borderless).disabled(index == store.configuration.items.count - 1).accessibilityLabel("下移\(item.title)")
                        }.padding(.vertical, 3)
                    }
                }
                .onMove { offsets, destination in store.move(from: offsets, to: destination) }
            }.disabled(!store.editable)
            HStack {
                Text("显示 \(store.configuration.visibleItems.count) 项").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") { store.reset() }
            }
            if !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.padding(18)
    }
}
