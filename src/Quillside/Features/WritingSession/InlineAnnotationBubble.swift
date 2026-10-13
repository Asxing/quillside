import SwiftUI

struct InlineAnnotationBubble: View {
    let anchor: InlineAnnotationAnchor
    let items: [WritingAnnotation]
    let save: (UUID?, InlineAnnotationAnchor, String, Bool) -> Bool
    let delete: (UUID) -> Void
    let close: () -> Void
    @State private var selectedID: UUID?
    @State private var comment: String
    @State private var enabled: Bool
    @State private var failed = false
    @FocusState private var editing: Bool
    init(anchor: InlineAnnotationAnchor, items: [WritingAnnotation],
         save: @escaping (UUID?, InlineAnnotationAnchor, String, Bool) -> Bool,
         delete: @escaping (UUID) -> Void, close: @escaping () -> Void) {
        self.anchor = anchor; self.items = items; self.save = save; self.delete = delete; self.close = close
        _selectedID = State(initialValue: items.first?.id)
        _comment = State(initialValue: items.first?.comment ?? "")
        _enabled = State(initialValue: items.first?.enabled ?? true)
    }
    private var item: WritingAnnotation? { items.first { $0.id == selectedID } }
    var body: some View {
        FloatingSurface(kind: .panel) {
            VStack(spacing: 0) {
                EditorPanelHeader(title: items.isEmpty ? "添加批注" : "批注", symbol: "text.bubble") {
                    if items.count > 1 {
                        Picker("此行批注", selection: $selectedID) {
                            ForEach(items) { Text(String($0.quote.prefix(18))).tag(Optional($0.id)) }
                        }.labelsHidden().frame(maxWidth: 115)
                    }
                    EditorPanelCloseButton(label: "关闭批注气泡", action: close)
                }
                Divider()
                VStack(alignment: .leading, spacing: EditorPanelStyle.spacing) {
                    Text(item?.quote ?? anchor.quote).foregroundStyle(.secondary).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(Color.accentColor.opacity(0.45)).frame(width: 2) }
                    TextField("这段文字希望怎样修改？", text: $comment, axis: .vertical)
                        .lineLimit(3...6).editorPanelInput()
                        .focused($editing).accessibilityLabel("批注意见")
                    if failed {
                        Text("未保存，请检查正文是否变化。意见仍保留在这里。")
                            .font(EditorPanelStyle.captionFont).foregroundStyle(.orange)
                    }
                    HStack {
                        if let item {
                            Toggle("参与优化", isOn: $enabled).toggleStyle(.checkbox)
                            Button(role: .destructive) { delete(item.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).accessibilityLabel("删除这条批注")
                        } else { Text("⌘↩ 保存").font(EditorPanelStyle.captionFont).foregroundStyle(.secondary) }
                        Spacer()
                        Button("保存批注") {
                            if let item { failed = !save(item.id, .init(annotation: item), comment, enabled) }
                            else { failed = !save(nil, anchor, comment, enabled) }
                        }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                            .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.padding(EditorPanelStyle.inset)
            }.font(EditorPanelStyle.bodyFont).controlSize(.small)
        }.frame(width: EditorPanelStyle.width)
            .onAppear { if items.isEmpty { editing = true } }
            .onExitCommand(perform: close)
            .onChange(of: selectedID) { _, _ in comment = item?.comment ?? ""; enabled = item?.enabled ?? true; failed = false }
    }
}
