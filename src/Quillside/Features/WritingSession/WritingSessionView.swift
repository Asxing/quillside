import SwiftUI
import AppKit

struct WritingSessionView: View {
    @ObservedObject var model: WritingSessionModel
    let close: () -> Void
    let addOriginal: () -> Void
    let startFresh: () -> Void
    @State private var showComments = false
    var body: some View {
        InlinePopoverSurface {
            VStack(spacing: 11) {
                HStack {
                    Label("批注修订", systemImage: "text.bubble").font(.headline)
                    Spacer()
                    Menu("历史 \(model.draft?.versions.count ?? 0)") {
                        ForEach(model.draft?.versions ?? []) { version in Button(version.instruction.isEmpty ? "候选稿" : String(version.instruction.prefix(32))) { model.restore(version) } }
                    }.fixedSize().disabled(model.busy || model.applying)
                    InlineCloseButton(action: close).disabled(model.applying)
                }
                if let draft = model.draft {
                    HStack(spacing: 12) {
                        if !model.agents.isEmpty {
                            Picker("Agent", selection: Binding(get: { model.selectedAgentID }, set: model.selectAgent)) {
                                ForEach(model.agents) { Text($0.name).tag(Optional($0.id)) }
                            }.frame(maxWidth: 190).accessibilityLabel("Agent角色")
                        }
                        Picker("模型", selection: $model.connectionID) { ForEach(model.connections) { Text($0.name).tag(Optional($0.id)) } }.frame(maxWidth: 200)
                        Toggle("参考当前笔记全文", isOn: Binding(get: { model.draft?.includeContext ?? false }, set: { model.draft?.includeContext = $0; model.persist() })).font(.caption)
                        Spacer()
                        Button(model.showOriginal ? "候选稿" : "对照原文") { model.showOriginal.toggle() }
                    }.disabled(model.busy || model.applying).controlSize(.small)
                    VStack(spacing: 7) {
                        HStack {
                            Text(model.showOriginal ? "原文 · 只读" : "选中文字添加批注，点击划线查看意见")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { showComments.toggle() } label: {
                                Label("批注 \(draft.annotations.count)", systemImage: "text.bubble")
                            }.controlSize(.small).disabled(model.busy || model.applying)
                        }
                        AnnotatedTextView(text: model.showOriginal ? draft.source : draft.candidate,
                            documentID: draft.versionID,
                            annotations: model.showOriginal ? [] : draft.currentAnnotations,
                            editable: !model.busy && !model.applying && !model.showOriginal,
                            focusRange: model.focusRange,
                            onChange: model.editCandidate, onSelect: { model.selection = $0 },
                            onSave: { model.saveInlineComment(id: $0, anchor: $1, comment: $2, enabled: $3) },
                            onDelete: model.removeComment)
                            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topTrailing) {
                            if showComments {
                                WritingCommentsPopover(model: model) { showComments = false }
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5) }
                                    .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
                                    .padding(.top, 30)
                            }
                        }
                    HStack {
                        Text(draft.skills.isEmpty ? "未启用 Skill" : draft.skills.map(\.name).joined(separator: "、"))
                            .font(.caption).lineLimit(1).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Button("加入 Notes 选区", action: addOriginal)
                            Button("更新启用的 Skill") { model.refreshSkills() }
                            Divider()
                            Button("从当前选区新建", action: startFresh)
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton)
                            .frame(width: 28).help("修订选项").accessibilityLabel("修订选项")
                            .disabled(model.busy || model.applying)
                    }
                    HStack(alignment: .bottom) {
                        TextField("补充整体要求，或直接按批注优化…", text: Binding(get: { model.draft?.instruction ?? "" }, set: model.updateInstruction), axis: .vertical)
                            .lineLimit(1...3).textFieldStyle(.roundedBorder).accessibilityLabel("整体修改要求").disabled(model.busy || model.applying)
                        if model.busy { Button("停止") { model.stop() } }
                        else { Button("统一优化") { model.run() }.buttonStyle(.borderedProminent).disabled(model.applying) }
                    }
                    Text(model.error.isEmpty ? model.status : model.error).font(.caption)
                        .foregroundStyle(model.error.isEmpty ? Color.secondary : Color.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(3)
                    HStack {
                        Button("保存并返回 Notes", action: close).disabled(model.applying)
                        Button("复制候选") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft.candidate, forType: .string) }
                        Spacer()
                        Button("插入后方") { model.apply(insertAfter: true) }.disabled(!model.canApply)
                        Button(draft.hasSelection ? "替换原选区" : "应用到当前笔记") { model.apply(insertAfter: false) }.disabled(!model.canApply)
                    }.controlSize(.small)
                } else { Text(model.error).foregroundStyle(.secondary); Spacer() }
            }.padding(14).frame(minWidth: 560, minHeight: 480)
                .onChange(of: model.busy) { _, busy in if busy { showComments = false } }
                .onChange(of: model.showOriginal) { _, _ in showComments = false }
        }
    }
}

private struct WritingCommentsPopover: View {
    @ObservedObject var model: WritingSessionModel
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("批注与处理说明").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭批注列表")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.draft?.annotations.isEmpty != false {
                        Text("在正文中选一句话，点击附近的“添加批注”。").foregroundStyle(.secondary)
                    }
                    ForEach(model.draft?.annotations ?? []) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Toggle("参与优化", isOn: Binding(get: { model.draft?.annotations.first(where: { $0.id == item.id })?.enabled ?? false }, set: { _ in model.toggleComment(item.id) }))
                                    .toggleStyle(.checkbox).labelsHidden().accessibilityLabel("参与优化：" + String(item.quote.prefix(20)))
                                Button { model.locate(item); close() } label: { Text(item.quote).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                                Button { model.removeComment(item.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).accessibilityLabel("删除批注：" + String(item.quote.prefix(20)))
                            }
                            if item.versionID != model.draft?.versionID { Text("历史意见 · 后续继续遵守").font(.caption).foregroundStyle(.secondary) }
                            TextField("修改意见", text: Binding(get: { model.draft?.annotations.first(where: { $0.id == item.id })?.comment ?? "" }, set: { model.changeComment(item.id, $0) }), axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(2...5)
                            if let assessment = model.draft?.versions.last?.assessments.first(where: { $0.annotationID == item.id }) {
                                Label(assessment.explanation, systemImage: assessment.status == "addressed" ? "checkmark" : "exclamationmark.bubble")
                                    .font(.caption).foregroundStyle(assessment.status == "addressed" ? Color.secondary : .orange)
                            }
                        }
                        Divider()
                    }
                    ForEach(model.draft?.versions.last?.issues ?? [], id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }.font(.callout)
            }.frame(height: min(300, CGFloat((model.draft?.annotations.count ?? 0) * 135 + 60)))
        }.padding(16).frame(width: 360).onExitCommand(perform: close)
    }
}
