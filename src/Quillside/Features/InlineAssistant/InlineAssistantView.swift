import AppKit
import SwiftUI

@MainActor enum InlineAssistantLayout {
    static let width: CGFloat = 392
    static func resultHeight(_ content: String) -> CGFloat {
        let measured = (String(content.prefix(8000)) as NSString).boundingRect(
            with: CGSize(width: width - 40, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 13)])
        return min(240, max(64, ceil(measured.height) + 24))
    }
    static func originalHeight(_ content: String) -> CGFloat {
        let measured = (String(content.prefix(2000)) as NSString).boundingRect(
            with: CGSize(width: width - 24, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin],
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        return min(80, max(28, ceil(measured.height) + 8))
    }
    static func size(model: InlineAssistantModel, options: Bool = false, original: Bool = false) -> CGSize {
        let choosing = model.phase == .choosing
        let rows = ceil(Double(min(6, model.prompts.count)) / 2)
        let content = choosing ? CGFloat(rows) * 32 + 8 : resultHeight(model.result) + 38
        let warning = (!model.targetValid || model.phase == .failed) ? CGFloat(52) : 0
        let empty = model.selectedConnection == nil ? CGFloat(66) : 0
        return CGSize(width: width, height: 142 + content + warning + empty + (model.agents.isEmpty ? 0 : 34) + (options ? 66 : 0) + (original ? originalHeight(model.source) + 10 : 0))
    }
}

struct InlineAssistantView: View {
    @ObservedObject var model: InlineAssistantModel
    let close: () -> Void
    let configure: () -> Void
    var layoutChanged: (CGSize) -> Void = { _ in }
    var revise: () -> Void = {}
    @State private var showOriginal = false
    @State private var showOptions = false
    @FocusState private var instructionFocused: Bool
    private var size: CGSize { InlineAssistantLayout.size(model: model, options: showOptions, original: showOriginal) }
    private var commonPrompts: [PromptAction] {
        if model.agentSnapshot?.profile.actionIDs.isEmpty == false { return Array(model.prompts.prefix(6)) }
        let names = ["润色", "纠错", "缩短", "展开", "摘要", "翻译"]
        let preferred = names.compactMap { name in model.prompts.first { $0.name == name } }
        return Array((preferred + model.prompts.filter { item in !preferred.contains { $0.id == item.id } }).prefix(6))
    }
    private var remainingPrompts: [PromptAction] { model.prompts.filter { item in !commonPrompts.contains { $0.id == item.id } } }
    private func symbol(_ name: String) -> String {
        switch name {
        case "润色": return "wand.and.stars"
        case "纠错": return "checkmark"
        case "缩短": return "arrow.down.right.and.arrow.up.left"
        case "展开", "续写": return "text.append"
        case "翻译": return "character.bubble"
        default: return "text.alignleft"
        }
    }
    var body: some View {
        InlinePopoverSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(.secondary)
                    Text(model.phase == .choosing ? "写作工具" : (model.actionName.isEmpty ? "写作工具" : model.actionName)).fontWeight(.medium)
                    Text(model.hasSelection ? "选中文字" : "当前笔记").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Spacer()
                    Button { showOptions.toggle() } label: { Image(systemName: "ellipsis").frame(width: 24, height: 22) }
                        .buttonStyle(.plain).help("模型与语言").accessibilityLabel("模型与语言").disabled(model.busy)
                    InlineCloseButton(action: close).disabled(model.phase == .applying)
                }.font(.system(size: 12))

                if !model.agents.isEmpty {
                    Picker("Agent", selection: Binding(get: { model.selectedAgentID }, set: model.selectAgent)) {
                        ForEach(model.agents) { Text($0.name).tag(Optional($0.id)) }
                    }.controlSize(.small).disabled(model.busy).accessibilityLabel("Agent角色")
                }

                if showOptions {
                    VStack(spacing: 6) {
                        HStack {
                            Picker("模型", selection: $model.connectionID) {
                                ForEach(model.connections) { Text($0.name).tag(Optional($0.id)) }
                            }.labelsHidden()
                            Button("设置…", action: configure).buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("翻译为").foregroundStyle(.secondary)
                            TextField("目标语言", text: $model.language).textFieldStyle(.roundedBorder)
                            Text("\(model.source.count) 字").foregroundStyle(.secondary)
                        }
                    }.font(.system(size: 11)).disabled(model.busy)
                }

                if model.selectedConnection == nil {
                    HStack(alignment: .center) {
                        Text("连接模型后，即可在笔记中使用 AI。").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button("配置模型", action: configure).controlSize(.small)
                    }.padding(.vertical, 10)
                }

                if model.phase == .choosing {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                        ForEach(commonPrompts) { prompt in
                            Button { model.run(prompt) } label: {
                                Label(prompt.name, systemImage: symbol(prompt.name))
                                    .font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 9).frame(height: 29)
                            }.buttonStyle(InlineActionStyle()).disabled(!model.canGenerate)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            if model.phase == .generating {
                                ProgressView().controlSize(.mini)
                                Text("正在生成…").foregroundStyle(.secondary)
                                Spacer()
                                Button("停止") { model.stop() }.buttonStyle(.plain)
                            } else {
                                Text(model.phase == .applying ? "正在应用…" : "候选结果 · 可直接编辑").foregroundStyle(.secondary)
                                Spacer()
                                Button { model.retry() } label: { Image(systemName: "arrow.clockwise") }
                                    .buttonStyle(.plain).help("重新生成").accessibilityLabel("重新生成").disabled(!model.canRetry)
                                Button {
                                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.result, forType: .string)
                                } label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.plain).help("复制结果").accessibilityLabel("复制结果").disabled(model.result.isEmpty)
                            }
                        }.font(.system(size: 11))
                        TextEditor(text: $model.result).font(.system(size: 13))
                            .scrollContentBackground(.hidden).padding(5)
                            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                            .frame(height: InlineAssistantLayout.resultHeight(model.result)).disabled(model.busy)
                            .accessibilityLabel("AI 候选结果")
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField(model.phase == .choosing ? "描述你想如何修改…" : "继续修改…", text: $model.instruction, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...2).focused($instructionFocused)
                        .onSubmit { if model.canGenerate { model.runCustom() } }
                        .disabled(model.busy).accessibilityLabel("修改要求")
                    Button { model.runCustom() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 21)) }
                        .buttonStyle(.plain).foregroundStyle(model.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.4) : InlinePopoverStyle.accent)
                        .disabled(!model.canGenerate || model.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("按要求修改").accessibilityLabel("按要求修改")
                }.padding(10).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))

                if showOriginal {
                    ScrollView { Text(model.source).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: InlineAssistantLayout.originalHeight(model.source)).accessibilityLabel("原文")
                }
                if !model.targetValid || model.phase == .failed {
                    Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(showOriginal ? "收起原文" : "原文") { showOriginal.toggle() }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Button("在 Notes 上批注", action: revise).buttonStyle(.plain).disabled(model.busy)
                    Spacer()
                    if model.phase == .choosing {
                        if !remainingPrompts.isEmpty {
                            Menu("更多动作") { ForEach(remainingPrompts) { action in Button(action.name) { model.run(action) } } }
                                .menuStyle(.borderlessButton).fixedSize().disabled(!model.canGenerate)
                        }
                    } else {
                        Button("取消", action: close).buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.phase == .applying)
                        Button(model.hasSelection ? "插入后方" : "插入光标后") { model.apply(insertAfter: true) }
                            .disabled(!model.canApply).controlSize(.small)
                        if model.hasSelection {
                            Button("替换选区") { model.apply(insertAfter: false) }.buttonStyle(.borderedProminent).controlSize(.small).disabled(!model.canApply)
                        }
                    }
                }.font(.system(size: 11)).frame(height: 24)
            }.padding(12).frame(width: InlineAssistantLayout.width).frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear { layoutChanged(size); instructionFocused = true }
        .onChange(of: size) { _, value in layoutChanged(value) }
    }
}

private struct InlineActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.primary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.035), in: RoundedRectangle(cornerRadius: 6))
    }
}
