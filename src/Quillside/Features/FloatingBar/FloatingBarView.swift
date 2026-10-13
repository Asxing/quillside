import SwiftUI

struct FloatingBarView: View {
    @ObservedObject var viewModel: FloatingBarViewModel
    @ObservedObject var settings = ToolbarSettingsStore.shared
    @State private var hoveredButton: String?

    var body: some View {
        FloatingSurface(cornerRadius: 8, kind: .compact) {
            VStack(spacing: 0) {
                if let feedback = viewModel.feedback {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.circle")
                        Text(feedback).font(.caption).lineLimit(2)
                        Spacer(minLength: 0)
                        Button { viewModel.clearFeedback() } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("关闭提示")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).frame(height: 42)
                    .accessibilityElement(children: .contain)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 1) {
                        ForEach(settings.configuration.visibleItems) { item in
                            switch item {
                            case .font: fontMenu
                            case .alignment: alignmentMenu
                            default:
                                ToolbarButton(icon: item.icon, tooltip: item.title,
                                    isSelected: item.selectionAction.map(viewModel.selectedActions.contains) ?? false,
                                    isHovered: hoveredButton == item.id,
                                    onHover: { hoveredButton = $0 ? item.id : nil },
                                    action: { viewModel.perform(item) })
                                .frame(width: 28)
                            }
                        }
                    }.padding(.horizontal, 6).padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .frame(height: ToolbarLayout.rowHeight)
            }
        }
    }
    private var fontMenu: some View {
        ToolbarPopUpButton(title: "字体与段落", symbol: ToolbarItemID.font.icon, items: [
            .init("大标题") { viewModel.setHeading(.title) },
            .init("标题") { viewModel.setHeading(.heading) },
            .init("副标题") { viewModel.setHeading(.subheading) },
            .init("正文") { viewModel.setHeading(.body) },
            .init("等宽") { viewModel.insertMonospaced() },
            .separator,
            .init("增大字号") { viewModel.changeFontSize(larger: true) },
            .init("减小字号") { viewModel.changeFontSize(larger: false) },
            .init("显示 Notes 字体面板…") { viewModel.showFonts() }
        ]).frame(width: 28, height: 26)
    }
    private var alignmentMenu: some View {
        ToolbarPopUpButton(title: "对齐", symbol: ToolbarItemID.alignment.icon,
            items: NoteAlignment.allCases.map { alignment in .init(alignment.title) { viewModel.align(alignment) } })
            .frame(width: 28, height: 26)
    }
}

/// An AppKit pull-down control owns menu tracking and accessibility actions
/// inside the nonactivating toolbar panel.
struct ToolbarPopUpButton: NSViewRepresentable {
    struct Item {
        let title: String
        let action: (() -> Void)?
        init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
        private init() { title = ""; action = nil }
        static var separator: Self { .init() }
    }
    let title: String
    let symbol: String
    let items: [Item]
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.refusesFirstResponder = true
        button.preferredEdge = .maxY
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.items = items
        button.setAccessibilityLabel(title)
        button.toolTip = title
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        let icon = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        menu.addItem(icon)
        for (index, item) in items.enumerated() {
            guard item.action != nil else { menu.addItem(.separator()); continue }
            let row = NSMenuItem(title: item.title, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
            row.target = context.coordinator; row.tag = index
            menu.addItem(row)
        }
        button.menu = menu
    }
    final class Coordinator: NSObject {
        var items: [Item] = []
        @objc func choose(_ item: NSMenuItem) {
            guard items.indices.contains(item.tag) else { return }
            items[item.tag].action?()
        }
    }
}

struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }
}

struct ToolbarButton: View {
    let icon: String
    let tooltip: String
    let isSelected: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    private var accessibilityName: String {
        tooltip.components(separatedBy: " (").first ?? tooltip
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(
            FloatingToolbarButtonStyle(
                isSelected: isSelected,
                isHovered: isHovered
            )
        )
        .onHover(perform: onHover)
        .help(tooltip)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(isSelected ? "已选中" : "")
        .accessibilityHint("作用于当前选区")
    }
}

private struct FloatingToolbarButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                isSelected
                    ? Color.white
                    : configuration.isPressed
                        ? Color.accentColor
                        : QuillsideStyle.enabledControl
            )
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isSelected
                            ? Color.accentColor
                            : configuration.isPressed
                                ? Color.accentColor.opacity(0.16)
                            : isHovered
                                ? QuillsideStyle.hover
                                : Color.clear
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
    }
}
