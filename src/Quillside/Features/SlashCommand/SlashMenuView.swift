import Combine
import SwiftUI

struct SlashMenuView: View {
    @State private var commands: [SlashCommand] = []
    @State private var selectedIndex = 0
    @State private var commandBuffer = ""
    @State private var pendingScrollWorkItem: DispatchWorkItem?

    private let commandsPublisher: AnyPublisher<[SlashCommand], Never>
    private let selectedIndexPublisher: AnyPublisher<Int, Never>
    private let commandBufferPublisher: AnyPublisher<String, Never>
    private let onSelect: (Int) -> Void

    init(
        commands: AnyPublisher<[SlashCommand], Never>,
        selectedIndex: AnyPublisher<Int, Never>,
        commandBuffer: AnyPublisher<String, Never>,
        initialCommands: [SlashCommand] = [],
        initialSelectedIndex: Int = 0,
        initialCommandBuffer: String = "",
        onSelect: @escaping (Int) -> Void
    ) {
        _commands = State(initialValue: initialCommands)
        _selectedIndex = State(initialValue: initialSelectedIndex)
        _commandBuffer = State(initialValue: initialCommandBuffer)
        self.commandsPublisher = commands
        self.selectedIndexPublisher = selectedIndex
        self.commandBufferPublisher = commandBuffer
        self.onSelect = onSelect
    }

    var body: some View {
        FloatingSurface(kind: .panel) {
            VStack(spacing: 0) {
                searchHeader

                Divider()

                if commands.isEmpty {
                    emptyState
                } else {
                    commandList
                }
            }
        }
        .frame(width: EditorPanelStyle.width)
        .onReceive(commandsPublisher) { commands = $0 }
        .onReceive(selectedIndexPublisher) { selectedIndex = $0 }
        .onReceive(commandBufferPublisher) { commandBuffer = $0 }
    }

    private var searchHeader: some View {
        EditorPanelHeader(title: commandBuffer.isEmpty ? "输入命令" : commandBuffer,
                          symbol: "slash", secondary: commandBuffer.isEmpty) {
            EditorPanelKeyHint(text: "Esc")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("没有匹配的命令")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var commandList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(SlashCommandCategory.allCases, id: \.self) { category in
                        let entries = indexedCommands(in: category)
                        if !entries.isEmpty {
                            Text(category.title)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            ForEach(entries, id: \.element.id) { entry in
                                Button {
                                    onSelect(entry.offset)
                                } label: {
                                    CommandRow(
                                        command: entry.element,
                                        isSelected:
                                            entry.offset == selectedIndex
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(entry.element.id)
                                .accessibilityLabel(
                                    "\(entry.element.name)，\(entry.element.description)"
                                )
                                .accessibilityAddTraits(
                                    entry.offset == selectedIndex
                                        ? .isSelected
                                        : []
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .onAppear {
                scrollToSelection(using: proxy, animated: false)
            }
            .onChange(of: selectedIndex) { _, _ in
                pendingScrollWorkItem?.cancel()
                let workItem = DispatchWorkItem {
                    scrollToSelection(using: proxy, animated: true)
                }
                pendingScrollWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
            }
        }
    }

    private func indexedCommands(
        in category: SlashCommandCategory
    ) -> [(offset: Int, element: SlashCommand)] {
        Array(commands.enumerated()).filter { $0.element.category == category }
    }

    private func scrollToSelection(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard commands.indices.contains(selectedIndex) else { return }
        let action = {
            proxy.scrollTo(commands[selectedIndex].id, anchor: .center)
        }
        if animated
            && !NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion {
            withAnimation(.easeOut(duration: 0.14)) {
                action()
            }
        } else {
            action()
        }
    }
}

struct CommandRow: View {
    let command: SlashCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: command.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : QuillsideStyle.enabledControl
                )
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(command.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(command.description)
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.72) : Color.secondary)
            }

            Spacer()

            Text(command.displayToken)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(isSelected ? Color.white.opacity(0.72) : Color.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            isSelected ? Color.accentColor : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .padding(.horizontal, 5)
    }
}
