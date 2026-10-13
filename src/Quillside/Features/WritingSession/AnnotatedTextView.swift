import AppKit
import SwiftUI

/// Native text selection, anchors and popover focus stay inside this editor.
struct AnnotatedTextView: NSViewRepresentable {
    let text: String
    let documentID: UUID
    let annotations: [WritingAnnotation]
    let editable: Bool
    let focusRange: NSRange?
    let onChange: (String) -> Void
    let onSelect: (NSRange) -> Void
    let onSave: (UUID?, InlineAnnotationAnchor, String, Bool) -> Bool
    let onDelete: (UUID) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = AnnotationTextEditor(frame: .zero)
        view.isRichText = false; view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.font = .systemFont(ofSize: 15); view.textColor = .labelColor; view.backgroundColor = .clear; view.drawsBackground = false
        // A small gutter holds comment bubbles without covering the text.
        view.textContainerInset = NSSize(width: 38, height: 22)
        view.setAccessibilityLabel("修订候选稿"); view.delegate = context.coordinator
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? AnnotationTextEditor else { return }
        context.coordinator.parent = self; context.coordinator.updating = true
        if view.string != text || view.documentID != documentID {
            view.closeAnnotation()
            if view.string != text { view.string = text; view.font = .systemFont(ofSize: 15); view.textColor = .labelColor }
            view.documentID = documentID
        }
        view.isEditable = editable; view.annotationEnabled = editable
        view.annotations = annotations; view.saveAnnotation = onSave; view.deleteAnnotation = onDelete
        let full = NSRange(location: 0, length: (text as NSString).length)
        view.layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
        view.layoutManager?.removeTemporaryAttribute(.underlineColor, forCharacterRange: full)
        view.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        for item in annotations where UTF16TextRange.valid(item.range, in: text) {
            view.layoutManager?.addTemporaryAttributes([
                .underlineStyle: item.enabled ? NSUnderlineStyle.single.rawValue : NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue,
                .underlineColor: item.enabled ? NSColor.systemOrange : NSColor.tertiaryLabelColor,
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(item.enabled ? 0.10 : 0.03)], forCharacterRange: item.range)
        }
        if let focusRange, focusRange != context.coordinator.lastFocus, UTF16TextRange.valid(focusRange, in: text) {
            view.setSelectedRange(focusRange); view.scrollRangeToVisible(focusRange)
            context.coordinator.lastFocus = focusRange
            view.scheduleSelectionAction()
        } else if focusRange == nil { context.coordinator.lastFocus = nil }
        context.coordinator.updating = false
        view.refreshBubbles()
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? AnnotationTextEditor)?.closeAnnotation()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AnnotatedTextView
        var updating = false
        var lastFocus: NSRange?
        init(_ parent: AnnotatedTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? AnnotationTextEditor else { return }
            view.closeAnnotation(); parent.onChange(view.string)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating, let view = notification.object as? AnnotationTextEditor else { return }
            // Mouse tracking publishes once on release; keyboard/AX changes use
            // the native range after the current event, never a delayed old range.
            view.scheduleSelectionAction()
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, !view.isSelecting else { return }
                self.parent.onSelect(view.selectedRange())
            }
        }
    }
}

final class AnnotationTextEditor: NSTextView {
    var documentID = UUID()
    var annotations: [WritingAnnotation] = []
    var annotationEnabled = true { didSet { if !annotationEnabled { closeAnnotation() } } }
    var saveAnnotation: ((UUID?, InlineAnnotationAnchor, String, Bool) -> Bool)?
    var deleteAnnotation: ((UUID) -> Void)?
    private(set) var isSelecting = false
    private var action: NSButton?
    private var pendingAnchor: InlineAnnotationAnchor?
    private var bubbleButtons: [NSButton] = []
    private var bubbleGroups: [[WritingAnnotation]] = []
    private var bubble: NSView?
    private var clipObserver: NSObjectProtocol?
    private var selectionTask: DispatchWorkItem?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver); self.clipObserver = nil }
        guard window != nil, let clip = enclosingScrollView?.contentView else { closeAnnotation(); return }
        clip.postsBoundsChangedNotifications = true
        clipObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            self?.action?.isHidden = true
            self?.closeAnnotation()
            self?.refreshBubbles()
        }
    }
    deinit {
        selectionTask?.cancel()
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        DispatchQueue.main.async { [weak self] in self?.refreshBubbles() }
    }
    override func mouseDown(with event: NSEvent) {
        closeAnnotation()
        isSelecting = true
        super.mouseDown(with: event)
        isSelecting = false
        if selectedRange().length > 0 { scheduleSelectionAction(); return }
        guard annotationEnabled, event.clickCount == 1, let layoutManager, let textContainer else { return }
        let point = convert(event.locationInWindow, from: nil)
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs else { return }
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        let matches = annotations.filter { NSLocationInRange(character, $0.range) }
        guard !matches.isEmpty, let rect = visibleAnchor(for: NSRange(location: character, length: 1)),
              rect.insetBy(dx: -4, dy: -3).contains(point) else { return }
        showComments(matches, at: rect)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if annotationEnabled, InlineAnnotationAnchor(versionID: documentID, range: selectedRange(), text: string) != nil {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "添加批注…", action: #selector(addSelectedComment), keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        return menu
    }
    func scheduleSelectionAction() {
        selectionTask?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.offerSelectionAction() }
        selectionTask = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }
    private func offerSelectionAction() {
        guard annotationEnabled, !isSelecting, bubble == nil,
              let anchor = InlineAnnotationAnchor(versionID: documentID, range: selectedRange(), text: string),
              let rect = visibleAnchor(for: anchor.range) else { action?.isHidden = true; return }
        pendingAnchor = anchor
        let button: NSButton
        if let action { button = action }
        else {
            button = NSButton(title: "添加批注", image: NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)!, target: self, action: #selector(addSelectedComment))
            button.bezelStyle = .rounded; button.controlSize = .small; button.font = .systemFont(ofSize: 12)
            button.setAccessibilityLabel("为选中文字添加批注"); button.toolTip = "添加批注"
            addSubview(button); action = button
        }
        let visible = visibleRect
        let width: CGFloat = 108, height: CGFloat = 28
        let below = rect.maxY + 4
        button.frame = NSRect(x: max(visible.minX + 6, min(rect.minX, visible.maxX - width - 8)),
                              y: below + height <= visible.maxY ? below : max(visible.minY + 4, rect.minY - height - 4), width: width, height: height)
        button.isHidden = false
    }
    @objc private func addSelectedComment() {
        guard annotationEnabled else { return }
        let anchor = pendingAnchor ?? InlineAnnotationAnchor(versionID: documentID, range: selectedRange(), text: string)
        guard let anchor, anchor.versionID == documentID, UTF16TextRange.valid(anchor.range, in: string),
              (string as NSString).substring(with: anchor.range) == anchor.quote,
              let rect = visibleAnchor(for: anchor.range) else { return }
        presentBubble(anchor: anchor, items: [], rect: rect)
    }
    func refreshBubbles() {
        bubbleButtons.forEach { $0.removeFromSuperview() }; bubbleButtons = []; bubbleGroups = []
        guard annotationEnabled, window != nil else { return }
        var lines: [(CGFloat, [WritingAnnotation], NSRect)] = []
        for item in annotations {
            guard let rect = visibleAnchor(for: item.range) else { continue }
            if let index = lines.firstIndex(where: { abs($0.0 - rect.minY) < 4 }) { lines[index].1.append(item) }
            else { lines.append((rect.minY, [item], rect)) }
        }
        for (_, items, rect) in lines {
            let title = items.count > 1 ? "\(items.count)" : ""
            let button = NSButton(title: title, image: NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil)!, target: self, action: #selector(openBubble(_:)))
            button.isBordered = false; button.font = .systemFont(ofSize: 10, weight: .medium); button.contentTintColor = .systemOrange
            button.imagePosition = items.count > 1 ? .imageLeading : .imageOnly
            button.frame = NSRect(x: visibleRect.minX + 3, y: rect.midY - 11, width: 32, height: 22)
            button.tag = bubbleGroups.count
            button.toolTip = items.map { String($0.quote.prefix(32)) + "：" + String($0.comment.prefix(80)) }.joined(separator: "\n")
            button.setAccessibilityLabel(items.count == 1 ? "查看批注：" + String(items[0].quote.prefix(32)) : "查看此行的\(items.count)条批注")
            bubbleGroups.append(items); bubbleButtons.append(button); addSubview(button)
        }
    }
    @objc private func openBubble(_ sender: NSButton) {
        guard bubbleGroups.indices.contains(sender.tag) else { return }
        showComments(bubbleGroups[sender.tag], at: sender.frame)
    }
    private func showComments(_ items: [WritingAnnotation], at rect: NSRect) {
        guard let first = items.first, let anchor = InlineAnnotationAnchor(versionID: documentID, range: first.range, text: string) else { return }
        presentBubble(anchor: anchor, items: items, rect: rect)
    }
    private func presentBubble(anchor: InlineAnnotationAnchor, items: [WritingAnnotation], rect: NSRect) {
        closeAnnotation()
        let content = InlineAnnotationBubble(anchor: anchor, items: items, save: { [weak self] id, target, text, enabled in
            guard let self, self.saveAnnotation?(id, target, text, enabled) == true else { return false }
            self.setSelectedRange(NSRange(location: NSMaxRange(target.range), length: 0))
            self.closeAnnotation(); return true
        }, delete: { [weak self] id in self?.deleteAnnotation?(id); self?.closeAnnotation() }, close: { [weak self] in self?.closeAnnotation() })
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: EditorPanelStyle.width, height: 260)
        hosting.layoutSubtreeIfNeeded()
        let visible = visibleRect.insetBy(dx: 6, dy: 6)
        let size = NSSize(width: min(EditorPanelStyle.width, visible.width), height: min(max(210, hosting.fittingSize.height), visible.height))
        let below = rect.maxY + 10
        let y = below + size.height <= visible.maxY ? below : max(visible.minY, rect.minY - size.height - 10)
        let frame = NSRect(x: max(visible.minX, min(rect.midX - size.width / 2, visible.maxX - size.width)), y: y, width: size.width, height: size.height)
        let container = NSVisualEffectView(frame: frame)
        container.material = .popover; container.blendingMode = .withinWindow; container.state = .active
        container.wantsLayer = true; container.layer?.cornerRadius = QuillsideStyle.cornerRadius; container.layer?.masksToBounds = true
        container.layer?.borderWidth = 0.5; container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.setAccessibilityLabel("批注气泡")
        hosting.frame = container.bounds; hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting); bubble = container
        addSubview(container, positioned: .above, relativeTo: nil)
        if items.isEmpty {
            DispatchQueue.main.async { [weak self, weak container] in
                guard let self, let container, self.bubble === container,
                      let field = Self.editableControl(in: container) else { return }
                self.window?.makeFirstResponder(field)
            }
        }
    }
    private static func editableControl(in view: NSView) -> NSView? {
        if let field = view as? NSTextField, field.isEditable { return field }
        if let field = view as? NSTextView, field.isEditable { return field }
        for child in view.subviews { if let found = editableControl(in: child) { return found } }
        return nil
    }
    func closeAnnotation() {
        selectionTask?.cancel(); selectionTask = nil; action?.isHidden = true; pendingAnchor = nil
        if bubble != nil { window?.makeFirstResponder(self) }
        bubble?.removeFromSuperview(); bubble = nil
    }
    override func accessibilityChildren() -> [Any]? {
        var children = super.accessibilityChildren() ?? []
        children += bubbleButtons.filter { !$0.isHidden }
        if let action, !action.isHidden { children.append(action) }
        if let bubble { children.append(bubble) }
        return children
    }
    private func visibleAnchor(for range: NSRange) -> NSRect? {
        guard range.length > 0, UTF16TextRange.valid(range, in: string), let layoutManager, let textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var result: NSRect?
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
            let rect = rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
            if rect.intersects(self.visibleRect.insetBy(dx: 0, dy: 2)) { result = rect.intersection(self.visibleRect) }
        }
        return result
    }
}
