import SwiftUI
import AppKit

struct NativeNotesAnnotationView: View {
    @ObservedObject var controller: NativeNotesAnnotationController
    @ObservedObject var model: WritingSessionModel
    var body: some View {
        FloatingSurface(kind: .panel) {
            VStack(spacing: 0) {
                EditorPanelHeader(title: "原文批注 · \(model.draft?.annotations.count ?? 0)", symbol: "text.bubble") {
                    options
                    EditorPanelCloseButton { controller.close() }.disabled(model.applying)
                }.accessibilityValue("当前可见 \(controller.visibleCommentCount) 条")
                Divider()
                VStack(alignment: .leading, spacing: EditorPanelStyle.spacing) {
                    if !model.agents.isEmpty {
                        HStack(spacing: 8) {
                            Text("Agent").font(EditorPanelStyle.captionFont).foregroundStyle(.secondary)
                            Picker("Agent", selection: Binding(get: { model.selectedAgentID }, set: model.selectAgent)) {
                                ForEach(model.agents) { Text($0.name).tag(Optional($0.id)) }
                            }.labelsHidden().disabled(model.busy || model.applying).accessibilityLabel("Agent角色")
                        }
                    }
                    if controller.showComments {
                        comments
                    } else if controller.showPreview, let draft = model.draft, draft.candidate != draft.source {
                        preview
                    }
                    TextField("当前正文的整体意见（可选）…", text: Binding(get: { model.draft?.instruction ?? "" }, set: model.updateInstruction), axis: .vertical)
                        .lineLimit(2...3).editorPanelInput().accessibilityLabel("整体意见")
                        .disabled(model.busy || model.applying)
                    HStack {
                        if let draft = model.draft, draft.candidate != draft.source, !controller.showPreview {
                            Button("查看修改建议") { controller.showPreview = true; controller.showComments = false; controller.resize() }
                                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                        } else {
                            Text(model.draft?.skills.map(\.name).joined(separator: "、") ?? "")
                                .font(EditorPanelStyle.captionFont).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if model.busy { Button("停止") { model.stop() } }
                        else { Button("统一优化") { controller.optimize() }.buttonStyle(.borderedProminent).disabled(model.applying || controller.stale) }
                    }
                    Text(!model.error.isEmpty ? model.error : (controller.message.isEmpty ? model.status : controller.message))
                        .font(EditorPanelStyle.captionFont).foregroundStyle(controller.stale || !model.error.isEmpty ? Color.orange : .secondary)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(EditorPanelStyle.inset)
            }.font(EditorPanelStyle.bodyFont).controlSize(.small)
        }
    }

    private var options: some View {
        Menu {
            if controller.hasOpenComment { Button("继续当前批注") { controller.resumeComment() } }
            Button("添加当前选区") { controller.addSelection() }
            Button("查看全部批注") { controller.showComments.toggle(); controller.resize() }
            Button("更新当前角色与 Skill") { model.refreshSkills() }
            Button("从当前正文重新开始") { controller.restart() }
            Divider()
            Button("模型连接设置") { controller.openModelSettings() }
        } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary) }
            .menuStyle(.borderlessButton).frame(width: 22).accessibilityLabel("原文批注选项")
    }

    private var comments: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.draft?.annotations ?? []) { item in
                        Button { controller.openComment(item) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.quote).font(.system(size: 12, weight: .medium)).lineLimit(2).foregroundStyle(.primary)
                                Text(item.comment).lineLimit(3).foregroundStyle(.secondary)
                                if let result = model.draft?.versions.last?.assessments.first(where: { $0.annotationID == item.id }) {
                                    Label(result.explanation, systemImage: result.status == "addressed" ? "checkmark" : "exclamationmark.bubble").foregroundStyle(.secondary)
                                }
                            }.font(EditorPanelStyle.captionFont).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(QuillsideStyle.secondaryFill, in: RoundedRectangle(cornerRadius: EditorPanelStyle.controlRadius))
                        }.buttonStyle(.plain).disabled(model.busy || model.applying || controller.stale)
                    }
                }
            }.frame(maxHeight: .infinity)
            Button("返回整体意见") { controller.showComments = false; controller.resize() }
                .font(EditorPanelStyle.captionFont).buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }
    }

    private var preview: some View {
        Group {
            HStack {
                Text("修改建议").font(EditorPanelStyle.captionFont).foregroundStyle(.secondary)
                Spacer()
                Button("收起") { controller.showPreview = false; controller.resize() }
                    .font(EditorPanelStyle.captionFont).buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
            TextEditor(text: Binding(get: { model.draft?.candidate ?? "" }, set: model.editCandidate))
                .scrollContentBackground(.hidden).editorPanelInput().frame(minHeight: 90, maxHeight: .infinity)
                .accessibilityLabel("Notes 修改建议").disabled(model.busy || model.applying)
            HStack {
                Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.draft?.candidate ?? "", forType: .string) }
                Spacer()
                Button("插入后方") { model.apply(insertAfter: true) }.disabled(!model.canApply || controller.stale)
                Button("应用到原文") { model.apply(insertAfter: false) }.disabled(!model.canApply || controller.stale)
            }
        }
    }

}

/// Key ownership is scoped to each input panel; merely displaying the dock does
/// not suppress Notes typing, its slash commands, or its selection toolbar.
final class NotesAnnotationInputPanel: NotesInlinePanel {
    let owner: InlinePanelOwner
    init(owner: InlinePanelOwner, size: CGSize) {
        self.owner = owner
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        InlinePopoverStyle.configure(self)
        level = .floating; isFloatingPanel = true; hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }
    override func becomeKey() { super.becomeKey(); updateInputGate() }
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let changed = super.makeFirstResponder(responder); updateInputGate(); return changed
    }
    private func updateInputGate() {
        let editing = owner == .notesComment || firstResponder is NSTextView || firstResponder is NSTextField
        InlineInteractionGate.shared.setActive(isKeyWindow && editing, owner: owner)
    }
    override func resignKey() { super.resignKey(); InlineInteractionGate.shared.setActive(false, owner: owner) }
}
