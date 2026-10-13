import SwiftUI
import AppKit
import ServiceManagement

enum SettingsTab: String, Hashable, CaseIterable, Identifiable {
    case general, toolbar, ai, agents, skills, templates, shortcuts, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "通用"
        case .toolbar: return "编辑工具条"
        case .ai: return "模型连接"
        case .agents: return "Agent"
        case .skills: return "Skill"
        case .templates: return "模板"
        case .shortcuts: return "快捷键"
        case .about: return "关于"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gear"
        case .toolbar: return "slider.horizontal.3"
        case .ai: return "network"
        case .agents: return "person.crop.rectangle"
        case .skills: return "puzzlepiece.extension"
        case .templates: return "doc.on.doc"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @AppStorage("settings.selectedTab") private var storedTab = SettingsTab.general.rawValue
    @State private var selectedTab: SettingsTab
    private let initialTab: SettingsTab?
    private let displayVersionOverride: String?
    init(initialTab: SettingsTab? = nil, displayVersionOverride: String? = nil) {
        self.initialTab = initialTab; self.displayVersionOverride = displayVersionOverride
        _selectedTab = State(initialValue: initialTab ?? .general)
    }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: Binding<SettingsTab?>(get: { selectedTab }, set: { if let tab = $0 { selectedTab = tab } })) {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.symbol)
                            .font(EditorPanelStyle.bodyFont).tag(tab)
                    }
                }.listStyle(.sidebar).navigationTitle("Quillside")
                VStack(alignment: .leading, spacing: 8) {
                    Button("回到 Apple Notes", systemImage: "arrow.uturn.backward") {
                        SettingsWindowController.shared.returnToNotes()
                    }.buttonStyle(.bordered).controlSize(.small)
                    Text("编辑与 AI 操作直接在 Notes 中完成。")
                        .font(EditorPanelStyle.captionFont).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
        } detail: {
            VStack(spacing: 0) {
                EditorPanelHeader(title: selectedTab.title, symbol: selectedTab.symbol) { EmptyView() }
                Divider()
                Group {
                    switch selectedTab {
                    case .general: GeneralSettingsTab()
                    case .toolbar: ToolbarCustomizationView()
                    case .ai: ConnectionsView()
                    case .agents: AgentSettingsView()
                    case .skills: SkillLibrarySettingsView()
                    case .templates: TemplateLibraryView()
                    case .shortcuts: ShortcutsSettingsTab()
                    case .about: AboutSettingsTab(previewVersion: displayVersionOverride)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
            }.background(QuillsideStyle.utilityOpaqueSurface(for: colorScheme))
        }
        .navigationSplitViewStyle(.balanced)
        .font(EditorPanelStyle.bodyFont)
        .tint(InlinePopoverStyle.accent).accentColor(InlinePopoverStyle.accent)
        .frame(minWidth: 850, minHeight: 640)
        .onAppear { if initialTab == nil { selectedTab = SettingsTab(rawValue: storedTab) ?? .general } }
        .onChange(of: selectedTab) { _, value in storedTab = value.rawValue }
    }

}


@MainActor final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var runtimeState: AppState?
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 690), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Quillside 设置"; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 850, height: 640)
        super.init(window: window); window.delegate = self; window.center(); window.setFrameAutosaveName("OpenNotesSettings")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func bind(appState: AppState) { runtimeState = appState }
    func show(appState: AppState? = nil, tab: SettingsTab? = nil) {
        if let appState { runtimeState = appState }
        guard let state = runtimeState else { return }
        window?.contentView = NSHostingView(rootView: SettingsView(initialTab: tab).environmentObject(state))
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func returnToNotes() {
        window?.close()
        if let notes = NSRunningApplication.runningApplications(withBundleIdentifier: AppleNotesTarget.bundleIdentifier).first {
            notes.activate(options: [.activateAllWindows])
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Notes.app"), configuration: configuration)
        }
    }
}

struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @AppStorage("com.opennotes.toolbar.enabled") private var toolbarEnabled = true
    @AppStorage("com.opennotes.slash.enabled") private var slashEnabled = true
    @AppStorage("com.opennotes.markdown.enabled") private var markdownEnabled = true
    @State private var loginStatus = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    var body: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动 Quillside", isOn: Binding(get: { loginStatus }, set: { value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginStatus = SMAppService.mainApp.status == .enabled
                    } catch { loginError = error.localizedDescription }
                }))
                if !loginError.isEmpty { Text(loginError).font(.caption).foregroundStyle(.secondary) }
            }
            Section("编辑增强") {
                Toggle("选区工具栏", isOn: $toolbarEnabled)
                Toggle("斜杠命令", isOn: $slashEnabled)
                Toggle("Markdown 快捷输入", isOn: $markdownEnabled)
            }
            Section("权限与运行") {
                PermissionSettingRow(
                    symbol: "accessibility",
                    title: "辅助功能",
                    detail: "格式操作和当前窗口识别",
                    state: appState.hasAccessibilityPermission ? .granted : .actionRequired,
                    actionTitle: appState.hasAccessibilityPermission ? nil : "打开系统设置",
                    action: AccessibilityBridge.shared.openAccessibilitySettings
                )
                .padding(.vertical, 4)

                PermissionSettingRow(
                    symbol: "externaldrive.fill",
                    title: "完全磁盘访问",
                    detail: "只读查询原生笔记链接与 Backlinks",
                    state: appState.notesDatabaseAccess.permissionLabelState,
                    actionTitle: appState.canUseBacklinks ? nil : "打开系统设置",
                    action: AccessibilityBridge.shared.openFullDiskAccessSettings
                )
                .padding(.vertical, 4)

                PermissionSettingRow(
                    symbol: "hand.tap",
                    title: "Apple Notes 自动化",
                    detail: "仅在你主动操作时读取当前笔记信息",
                    state: appState.automationAccess.permissionLabelState,
                    actionTitle:
                        appState.automationAccess == .denied
                            ? "打开系统设置"
                            : nil,
                    action:
                        AppleNotesAutomationAccess.shared.openSettings
                )
                .padding(.vertical, 4)
            }

            Section("当前状态") {
                LabeledContent("Quillside") {
                    Text(appState.statusDescription)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Apple Notes") {
                    Text(appState.isNotesRunning ? "正在运行" : "未运行")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Quillside 无账户和遥测。AI 请求仅在你主动选择 AI 动作或提交修改要求时发送到所配置的服务商；仅处理捕获的选区或当前笔记内容。反链关系在本机读取，Apple Notes 数据库始终只读。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }

}

struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section("笔记操作（Notes 内）") {
                ShortcutRow(
                    name: "复制 Markdown",
                    shortcut: "⌥⌘M",
                    description: "复制当前整篇笔记"
                )
                ShortcutRow(
                    name: "复制笔记链接",
                    shortcut: "⌥⌘L",
                    description: "复制当前笔记原生链接"
                )
                ShortcutRow(
                    name: "Backlinks",
                    shortcut: "⌥⇧⌘B",
                    description: "查看来源并预览正文反链"
                )
            }

            Section("Apple Notes 内") {
                ShortcutRow(name: "AI 编辑…", shortcut: "⌥⌘A")
                ShortcutRow(
                    name: "Slash Commands",
                    shortcut: "/",
                    description: "输入后继续键入以筛选命令，支持官网命令别名"
                )
            }

            Section("Markdown 快捷输入") {
                MarkdownTriggerSettingsView()
                Text("按需关闭单个触发。输入法组合状态无法确认时，候选键交给系统处理；可从斜杠菜单点选动作。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("常用格式快捷键") {
                ShortcutRow(name: "Bold", shortcut: "⌘B")
                ShortcutRow(name: "Italic", shortcut: "⌘I")
                ShortcutRow(name: "Underline", shortcut: "⌘U")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }
}

struct ShortcutRow: View {
    let name: String
    let shortcut: String
    var description: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

struct MarkdownTriggerRow: View {
    let trigger: String
    let result: String

    var body: some View {
        HStack(spacing: 10) {
            Text(trigger)
                .font(.system(.body, design: .monospaced))
                .frame(width: 42, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(result)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 1)
    }
}

struct AboutSettingsTab: View {
    private let previewVersion: String?

    init(previewVersion: String? = nil) {
        self.previewVersion = previewVersion
    }

    private var version: String {
        if let previewVersion {
            return previewVersion
        }
        return Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Development"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            QuillsideBrandIcon(size: 76)

            Text("Quillside")
                .font(.system(size: 22, weight: .bold))

            Text("Version \(version)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("让 Apple Notes 真正连起来")
                .font(.system(size: 13, weight: .medium))

            Text("原生增强 Apple Notes，自选模型、提示词与模板。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)


            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
