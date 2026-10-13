import SwiftUI

/// Shared with the slash menu: compact header, neutral surface and quiet controls.
enum EditorPanelStyle {
    static let width: CGFloat = 320
    static let headerHeight: CGFloat = 38
    static let inset: CGFloat = 12
    static let spacing: CGFloat = 8
    static let controlRadius: CGFloat = 6
    static let bodyFont = Font.system(size: 12)
    static let captionFont = Font.system(size: 10)
}

struct EditorPanelKeyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(QuillsideStyle.hover, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct EditorPanelHeader<Actions: View>: View {
    let title: String
    let symbol: String
    var secondary = false
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if symbol == "slash" { Text("/") }
                else { Image(systemName: symbol) }
            }.font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 12, weight: secondary ? .regular : .medium))
                .foregroundStyle(secondary ? .secondary : .primary).lineLimit(1)
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, EditorPanelStyle.inset)
        .frame(height: EditorPanelStyle.headerHeight)
    }
}

struct EditorPanelCloseButton: View {
    var label = "关闭"
    let action: () -> Void
    var body: some View {
        Button(action: action) { EditorPanelKeyHint(text: "Esc") }
            .buttonStyle(.plain).help("关闭 · Esc").accessibilityLabel(label)
    }
}

private struct EditorPanelInput: ViewModifier {
    func body(content: Content) -> some View {
        content.font(EditorPanelStyle.bodyFont).textFieldStyle(.plain)
            .padding(8)
            .background(QuillsideStyle.secondaryFill, in: RoundedRectangle(cornerRadius: EditorPanelStyle.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: EditorPanelStyle.controlRadius)
                .strokeBorder(QuillsideStyle.border, lineWidth: 0.5))
    }
}

extension View {
    func editorPanelInput() -> some View { modifier(EditorPanelInput()) }
}
