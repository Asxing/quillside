import SwiftUI

enum BacklinksPanelLayout {
    static let width: CGFloat = 320
    static let fallbackHeight: CGFloat = 320
}

struct BacklinksPanelView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: BacklinksPanelViewModel
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            FloatingSurface(kind: .panel) {
                VStack(spacing: 0) {
                    headerView

                    if !viewModel.currentNoteTitle.isEmpty {
                        Divider()
                        currentNoteView
                    }

                    Divider()

                    if appState.notesDatabaseAccess != .available {
                        databaseUnavailableView
                    } else if viewModel.resolutionState != .resolved {
                        emptyStateView
                    } else {
                        switch viewModel.queryPhase {
                        case .loading:
                            VStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在读取反链快照").font(.caption) }.padding(24)
                        case let .failed(message):
                            VStack(spacing: 8) {
                                Text("反链读取失败").font(.headline)
                                Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("重新读取") { viewModel.retry() }
                            }.padding(20)
                        case .targetMissing:
                            VStack(spacing: 8) {
                                Text("当前笔记尚未进入本地快照").font(.callout)
                                Button("刷新") { viewModel.retry() }
                            }.padding(20)
                        case .ready:
                            if !viewModel.coverage.complete {
                                Text(viewModel.coverage.summary).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true).padding(12)
                                Divider()
                            }
                            if viewModel.backlinks.isEmpty { emptyStateView } else { backlinksListView }
                            Divider()
                            Button("预览正文反链…") {
                                BacklinkDocumentController.shared.present(identifier: viewModel.currentNoteIdentifier, items: viewModel.backlinks, coverage: viewModel.coverage)
                            }.padding(12)
                        }
                    }
                }
            }
            .frame(width: BacklinksPanelLayout.width)
            .frame(maxHeight: 400)

            TrianglePointer()
                .fill(
                    QuillsideStyle.utilityOpaqueSurface(
                        for: colorScheme
                    )
                )
                .frame(width: 16, height: 8)
                .offset(y: -1)
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(QuillsideStyle.enabledControl)

            Text("反向链接")
                .font(.system(size: 13, weight: .semibold))

            Spacer()
            Button { viewModel.retry() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).disabled(!appState.canUseBacklinks || viewModel.queryPhase == .loading)
                .accessibilityLabel("重新读取反链")

            if appState.canUseBacklinks, !viewModel.backlinks.isEmpty {
                Text("\(viewModel.backlinks.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("关闭反向链接")
                .accessibilityLabel("关闭反向链接")
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var currentNoteView: some View {
        HStack(spacing: 6) {
            Text("当前笔记")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Text(viewModel.currentNoteTitle)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Color.accentColor.opacity(0.09))
    }

    private var databaseUnavailableView: some View {
        VStack(spacing: 9) {
            Image(systemName: databaseUnavailableSymbol)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            Text(databaseUnavailableTitle)
                .font(.system(size: 12, weight: .semibold))

            Text(databaseUnavailableDetail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if appState.notesDatabaseAccess != .checking {
                Button("打开完全磁盘访问设置") {
                    AccessibilityBridge.shared.openFullDiskAccessSettings()
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    private var databaseUnavailableSymbol: String {
        appState.notesDatabaseAccess == .checking ? "clock" : "externaldrive.badge.exclamationmark"
    }

    private var databaseUnavailableTitle: String {
        switch appState.notesDatabaseAccess {
        case .checking:
            return "正在检查 Notes 数据库"
        case .permissionRequired:
            return "需要完全磁盘访问"
        case .unavailable:
            return "Notes 数据库暂不可用"
        case .available:
            return ""
        }
    }

    private var databaseUnavailableDetail: String {
        switch appState.notesDatabaseAccess {
        case .checking:
            return "完成后会自动刷新 Backlinks。"
        case .permissionRequired:
            return "授权后即可只读查询原生 Backlinks。"
        case .unavailable:
            return "请先打开 Apple Notes 创建一条笔记，或检查完全磁盘访问权限。"
        case .available:
            return ""
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 7) {
            switch viewModel.resolutionState {
            case .resolving:
                ProgressView()
                    .controlSize(.small)
                Text("正在识别当前笔记")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .unavailable:
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text("无法识别当前笔记")
                    .font(.system(size: 12, weight: .semibold))
                Text("请在 Apple Notes 中选择一条笔记后重试。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .resolved:
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(viewModel.coverage.complete ? "当前笔记暂无反向链接" : "已读取内容中未发现反链")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var backlinksListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.backlinks) { backlink in
                    Button {
                        openNote(backlink)
                    } label: {
                        BacklinkRow(backlink: backlink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开笔记：\(backlink.noteTitle)")

                    if backlink.id != viewModel.backlinks.last?.id {
                        Divider()
                            .padding(.leading, 46)
                    }
                }
            }
        }
        .frame(
            height: min(
                max(CGFloat(viewModel.backlinks.count) * 64, 64),
                320
            )
        )
    }

    private func openNote(_ backlink: BacklinksService.BacklinkInfo) {
        let url = NotesDBReader.shared.buildNoteURL(identifier: backlink.identifier)
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct TrianglePointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
        }
    }
}

struct BacklinkRow: View {
    let backlink: BacklinksService.BacklinkInfo
    @State private var isHovered = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(backlink.noteTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    Text(Self.dateFormatter.string(from: backlink.modificationDate))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                if !backlink.context.isEmpty {
                    Text(backlink.context)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? QuillsideStyle.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
