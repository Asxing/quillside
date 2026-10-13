import AppKit

/// AppKit owns menu tracking and highlighting; opening the menu starts the feedback.
@MainActor final class StatusBarController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let animator: StatusIconAnimator

    init(appState: AppState) {
        self.appState = appState
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        let icon = StatusIconAnimation.loadIcon()
        item.button?.image = icon
        animator = StatusIconAnimator(image: icon) { [weak button = item.button] image in
            button?.image = image
        }
        super.init()
        item.autosaveName = "QuillsideStatusItem"
        item.button?.toolTip = "Quillside"
        item.button?.setAccessibilityLabel("Quillside")
        let menu = NSMenu(title: "Quillside")
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        menuNeedsUpdate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        Self.menuItems(for: appState, target: self).forEach(menu.addItem)
    }

    static func menuItems(for appState: AppState, target: AnyObject? = nil) -> [NSMenuItem] {
        func actionItem(_ action: MenuBarAction, title: String, symbol: String?) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = action
            item.isEnabled = MenuBarCommands.isEnabled(action, appState: appState)
            item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            return item
        }
        var items = [actionItem(.askAI, title: "AI 编辑…", symbol: "sparkles"), NSMenuItem.separator()]
        for entry in MenuBarContent.entries(for: appState) {
            switch entry.kind {
            case .divider: items.append(.separator())
            case .status:
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.image = entry.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
                items.append(item)
            case let .action(action):
                let item = actionItem(action, title: entry.title, symbol: entry.symbol)
                if let shortcut = entry.shortcut {
                    item.keyEquivalent = String(shortcut.key.character)
                    var mask: NSEvent.ModifierFlags = []
                    if shortcut.modifiers.contains(.command) { mask.insert(.command) }
                    if shortcut.modifiers.contains(.option) { mask.insert(.option) }
                    if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
                    item.keyEquivalentModifierMask = mask
                }
                items.append(item)
            }
        }
        return items
    }

    @objc private func performAction(_ item: NSMenuItem) {
        guard let action = item.representedObject as? MenuBarAction else { return }
        MenuBarCommands.perform(action, appState: appState)
    }

    func menuWillOpen(_ menu: NSMenu) { animator.play() }
    func menuDidClose(_ menu: NSMenu) { animator.stop() }

    func stop() {
        animator.stop()
        statusItem.menu?.delegate = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
