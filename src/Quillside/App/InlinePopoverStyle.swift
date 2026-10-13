import AppKit
import SwiftUI

enum InlinePopoverStyle {
    static let accent = Color(nsColor: .controlAccentColor)
    static func configure(_ panel: NSPanel) {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // FloatingSurface supplies the same shadow as Slash.
        panel.animationBehavior = .utilityWindow
    }
}

/// A single soft surface shared by writing tools. No separate app window chrome.
struct InlinePopoverSurface<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        FloatingSurface(kind: .panel) { content }
    }
}

struct InlineCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).frame(width: 22, height: 22) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("关闭 · Esc").accessibilityLabel("关闭")
    }
}
