import SwiftUI

enum OnboardingDatabaseAction: Equatable {
    case checking
    case openFullDiskAccess
    case openNotes
    case retry
    case ready

    init(status: NotesDatabaseAccessStatus) {
        switch status {
        case .checking:
            self = .checking
        case .permissionRequired:
            self = .openFullDiskAccess
        case .unavailable(.databaseMissing):
            self = .openNotes
        case .unavailable(.openFailed):
            self = .retry
        case .available:
            self = .ready
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool

    init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
    }

    var body: some View {
        HStack(spacing: 0) {
            brandPanel
            permissionPanel
        }
        .frame(width: 760, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var brandPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuillsideBrandIcon(size: 68)

            Spacer()

            Text("让笔记之间\n真正连起来。")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)

            Text("Backlinks、快捷输入和选区格式工具，都在 Apple Notes 内工作。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .padding(.top, 14)

            Label("AI 按需连接你配置的模型服务", systemImage: "lock.shield")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 24)
        }
        .padding(32)
        .frame(width: 270)
        .frame(maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.13),
                    Color.accentColor.opacity(0.035),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("完成两项系统授权")
                .font(.system(size: 22, weight: .bold))

            Text("权限用于识别当前笔记、执行主动操作，并只读查询笔记库。只有点击 AI 生成时，选定材料才会发送到你配置的模型服务。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .padding(.top, 8)

            VStack(spacing: 0) {
                PermissionSettingRow(
                    symbol: "accessibility",
                    title: "辅助功能",
                    detail: "识别窗口和执行格式操作",
                    state: appState.hasAccessibilityPermission ? .granted : .actionRequired,
                    actionTitle: appState.hasAccessibilityPermission ? nil : "打开设置",
                    action: AccessibilityBridge.shared.openAccessibilitySettings
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()
                    .padding(.leading, 48)

                PermissionSettingRow(
                    symbol: "externaldrive.fill",
                    title: "完全磁盘访问",
                    detail: "只读查询原生笔记链接与 Backlinks",
                    state: appState.notesDatabaseAccess.permissionLabelState,
                    actionTitle: databaseActionTitle,
                    action: performDatabaseAction
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(QuillsideStyle.secondaryFill)
            .clipShape(RoundedRectangle(cornerRadius: QuillsideStyle.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: QuillsideStyle.cornerRadius)
                    .stroke(QuillsideStyle.border, lineWidth: 0.5)
            }
            .padding(.top, 24)

            Label(
                "首次需要读取或消除当前笔记歧义时，macOS 会询问是否允许控制 Apple Notes。",
                systemImage: "hand.tap"
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 12)

            Spacer()

            HStack {
                Button("稍后") {
                    finishOnboarding()
                }

                Spacer()

                Button(primaryActionTitle) {
                    performPrimaryAction()
                }
                .disabled(
                    appState.hasAccessibilityPermission
                        && OnboardingDatabaseAction(
                            status: appState.notesDatabaseAccess
                        ) == .checking
                )
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.accentColor)
            }
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var primaryActionTitle: String {
        if !appState.hasAccessibilityPermission {
            return "打开辅助功能设置"
        }
        switch OnboardingDatabaseAction(
            status: appState.notesDatabaseAccess
        ) {
        case .checking:
            return "正在检查…"
        case .openFullDiskAccess:
            return "打开完全磁盘访问设置"
        case .openNotes:
            return "打开 Apple Notes"
        case .retry:
            return "重新检查"
        case .ready:
            return "开始使用"
        }
    }

    private var databaseActionTitle: String? {
        switch OnboardingDatabaseAction(
            status: appState.notesDatabaseAccess
        ) {
        case .checking, .ready:
            return nil
        case .openFullDiskAccess:
            return "打开设置"
        case .openNotes:
            return "打开 Notes"
        case .retry:
            return "重新检查"
        }
    }

    private func performPrimaryAction() {
        if !appState.hasAccessibilityPermission {
            AccessibilityBridge.shared.openAccessibilitySettings()
        } else {
            performDatabaseAction()
        }
    }

    private func performDatabaseAction() {
        switch OnboardingDatabaseAction(
            status: appState.notesDatabaseAccess
        ) {
        case .checking:
            break
        case .openFullDiskAccess:
            AccessibilityBridge.shared.openFullDiskAccessSettings()
        case .openNotes:
            let notesURL = URL(
                fileURLWithPath: "/System/Applications/Notes.app"
            )
            NSWorkspace.shared.openApplication(
                at: notesURL,
                configuration: .init()
            )
        case .retry:
            (NSApplication.shared.delegate as? AppDelegate)?
                .refreshPermissionStatus()
        case .ready:
            finishOnboarding()
        }
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isPresented = false
    }
}
