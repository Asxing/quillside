import Carbon
import AppKit

/// Register only the chosen chord. Registering a replacement does not discard a working old binding first.
final class GlobalSearchShortcut {
    private var handler: EventHandlerRef?
    private let store: SearchShortcutStore
    init(store: SearchShortcutStore = .shared) { self.store = store }
    func register() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalSearchShortcut>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x4F4E4F54, id.id == owner.store.activeGlobalID else { return OSStatus(eventNotHandledErr) }
            Task { @MainActor in NoteSearchPanelController.shared.show() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        store.bind { chord, id in
            guard result == noErr else { throw AIError.message("无法安装系统快捷键处理器（\(result)）。") }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(chord.keyCode), chord.carbonFlags,
                EventHotKeyID(signature: 0x4F4E4F54, id: id), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else { throw AIError.message("全局快捷键注册失败（\(status)），可能已被系统或其他应用占用。请更换组合或重试。") }
            return { UnregisterEventHotKey(ref) }
        }
    }
    deinit { store.unbind(); if let handler { RemoveEventHandler(handler) } }
}
