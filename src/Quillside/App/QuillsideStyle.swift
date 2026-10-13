import SwiftUI

private struct QuillsideReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var quillsideReduceTransparencyOverride: Bool? {
        get { self[QuillsideReduceTransparencyOverrideKey.self] }
        set { self[QuillsideReduceTransparencyOverrideKey.self] = newValue }
    }
}

enum QuillsideStyle {
    static let cornerRadius: CGFloat = 10
    static let border = Color.primary.opacity(0.12)
    static let hover = Color.primary.opacity(0.065)
    static let secondaryFill = Color.primary.opacity(0.045)
    static let enabledControl = Color.primary.opacity(0.92)
    static let disabledControl = Color.primary.opacity(0.38)

    static func utilitySurfaceTint(
        for colorScheme: ColorScheme,
        kind: QuillsideSurfaceKind
    ) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.12, green: 0.12, blue: 0.11)
                .opacity(kind == .panel ? 0.66 : 0.58)
        case .light:
            return Color.white.opacity(kind == .panel ? 0.88 : 0.84)
        @unknown default:
            return Color.white.opacity(0.86)
        }
    }

    static func utilityOpaqueSurface(
        for colorScheme: ColorScheme
    ) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.15, green: 0.15, blue: 0.14)
        case .light:
            return Color.white
        @unknown default:
            return Color(nsColor: .windowBackgroundColor)
        }
    }
}

enum QuillsideSurfaceKind: Equatable {
    case compact
    case panel

    var shadowOpacity: Double {
        switch self {
        case .compact:
            return 0.12
        case .panel:
            return 0.14
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .compact:
            return 8
        case .panel:
            return 14
        }
    }

    var shadowOffset: CGFloat {
        switch self {
        case .compact:
            return 2
        case .panel:
            return 4
        }
    }
}

struct QuillsideBrandIcon: View {
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "Quillside-Mark", withExtension: "png"),
               let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "note.text")
                    .resizable().scaledToFit()
                    .foregroundStyle(Color(red: 0.66, green: 0.49, blue: 0.16))
                    .padding(size * 0.16)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PermissionStateLabel: View {
    enum State {
        case checking
        case pending
        case granted
        case actionRequired
        case unavailable
    }

    let state: State

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }

    private var title: String {
        switch state {
        case .checking:
            return "检查中"
        case .pending:
            return "首次使用时询问"
        case .granted:
            return "已授权"
        case .actionRequired:
            return "需要授权"
        case .unavailable:
            return "不可用"
        }
    }

    private var symbol: String {
        switch state {
        case .checking:
            return "clock"
        case .pending:
            return "hand.tap"
        case .granted:
            return "checkmark.circle.fill"
        case .actionRequired:
            return "exclamationmark.circle.fill"
        case .unavailable:
            return "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .checking, .pending:
            return .secondary
        case .granted:
            return .green
        case .actionRequired:
            return .orange
        case .unavailable:
            return .red
        }
    }
}

extension AppleNotesAutomationStatus {
    var permissionLabelState: PermissionStateLabel.State {
        switch self {
        case .checking:
            return .checking
        case .notDetermined, .targetNotRunning:
            return .pending
        case .granted:
            return .granted
        case .denied:
            return .actionRequired
        case .unavailable:
            return .unavailable
        }
    }
}

extension NotesDatabaseAccessStatus {
    var permissionLabelState: PermissionStateLabel.State {
        switch self {
        case .checking:
            return .checking
        case .available:
            return .granted
        case .permissionRequired:
            return .actionRequired
        case .unavailable:
            return .unavailable
        }
    }
}

struct PermissionSettingRow: View {
    let symbol: String
    let title: String
    let detail: String
    let state: PermissionStateLabel.State
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                PermissionStateLabel(state: state)

                if let actionTitle {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FloatingSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.quillsideReduceTransparencyOverride) private var reduceTransparencyOverride
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let kind: QuillsideSurfaceKind
    let content: Content

    init(
        cornerRadius: CGFloat = QuillsideStyle.cornerRadius,
        kind: QuillsideSurfaceKind = .panel,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.kind = kind
        self.content = content()
    }

    var body: some View {
        content
            .tint(InlinePopoverStyle.accent)
            .accentColor(InlinePopoverStyle.accent)
            .background {
                ZStack {
                    if reduceTransparencyOverride ?? reduceTransparency {
                        surfaceShape
                            .fill(
                                QuillsideStyle.utilityOpaqueSurface(
                                    for: colorScheme
                                )
                            )
                    } else {
                        surfaceShape
                            .fill(.regularMaterial)
                        surfaceShape
                            .fill(
                                QuillsideStyle.utilitySurfaceTint(
                                    for: colorScheme,
                                    kind: kind
                                )
                            )
                    }
                }
            }
            .overlay {
                surfaceShape
                    .strokeBorder(QuillsideStyle.border, lineWidth: 0.5)
            }
            .clipShape(surfaceShape)
            .shadow(
                color: .black.opacity(kind.shadowOpacity),
                radius: kind.shadowRadius,
                y: kind.shadowOffset
            )
    }

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
    }
}
