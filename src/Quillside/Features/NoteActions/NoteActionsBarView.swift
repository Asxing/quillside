import SwiftUI

enum NoteActionsLayout {
    static let barSize = CGSize(width: 126, height: 36)
    static let panelSize = CGSize(width: 240, height: 70)
    static let buttonSize: CGFloat = 28
    static let buttonGap: CGFloat = 2
    static let outerPadding: CGFloat = 4
}

struct NoteActionsBarView: View {
    @ObservedObject var viewModel: NoteActionsBarViewModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 6) {
                if let feedback = viewModel.feedback {
                    feedbackCapsule(feedback)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.96))
                        )
                }

                FloatingSurface(cornerRadius: 10, kind: .compact) {
                    HStack(spacing: NoteActionsLayout.buttonGap) {
                        ForEach(NoteActionItem.allCases) { item in
                            NoteActionButton(
                                item: item,
                                isBusy:
                                    item.isBusy(activeAction: viewModel.activeAction),
                                operationInProgress:
                                    viewModel.activeAction != nil
                            ) {
                                if item == .askAI {
                                    InlineAssistantController.shared.present()
                                    return
                                }
                                guard let action = item.actionKind else {
                                    return
                                }
                                viewModel.perform(action)
                            }
                        }
                    }
                    .padding(NoteActionsLayout.outerPadding)
                }
                .frame(
                    width: NoteActionsLayout.barSize.width,
                    height: NoteActionsLayout.barSize.height
                )
            }
        }
        .frame(
            width: NoteActionsLayout.panelSize.width,
            height: NoteActionsLayout.panelSize.height,
            alignment: .bottomTrailing
        )
        .animation(.easeOut(duration: 0.14), value: viewModel.feedback)
    }

    private func feedbackCapsule(
        _ feedback: NoteActionsBarViewModel.Feedback
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(feedbackColor(feedback.kind))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(feedback.message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(feedbackColor(feedback.kind))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(
            FloatingSurface(cornerRadius: 8, kind: .compact) {
                Color.clear
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feedback.message)
    }

    private func feedbackColor(
        _ kind: NoteActionsBarViewModel.Feedback.Kind
    ) -> Color {
        switch kind {
        case .success:
            return .green
        case .error:
            return .red
        }
    }
}

private struct NoteActionButton: View {
    let item: NoteActionItem
    let isBusy: Bool
    let operationInProgress: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var isInteractive: Bool {
        item.isEnabled && !operationInProgress
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.accentColor)
                } else {
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(
                width: NoteActionsLayout.buttonSize,
                height: NoteActionsLayout.buttonSize
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(
            NoteActionButtonStyle(
                isHovered: isHovered && isInteractive,
                isRoadmapDisabled: !item.isEnabled
            )
        )
        .disabled(!isInteractive)
        .onHover { hovering in
            guard isInteractive else {
                isHovered = false
                return
            }
            isHovered = hovering
        }
        .help(item.title)
        .accessibilityLabel(Text(item.title))
        .accessibilityHint(
            item == .askAI
                ? Text("捕获当前文字并打开 AI 预览")
                : Text("作用于当前 Apple Notes 笔记")
        )
    }
}

private struct NoteActionButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isRoadmapDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor(configuration: configuration))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor(configuration: configuration))
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(
                .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
    }

    private func foregroundColor(
        configuration: Configuration
    ) -> Color {
        if isRoadmapDisabled {
            return QuillsideStyle.disabledControl
        }
        if configuration.isPressed {
            return .accentColor
        }
        return QuillsideStyle.enabledControl
    }

    private func backgroundColor(
        configuration: Configuration
    ) -> Color {
        if isRoadmapDisabled {
            return .clear
        }
        if configuration.isPressed {
            return Color.accentColor.opacity(0.16)
        }
        return isHovered ? QuillsideStyle.hover : .clear
    }
}
