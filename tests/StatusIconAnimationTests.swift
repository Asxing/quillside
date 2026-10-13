import AppKit
import Testing
@testable import Quillside

@MainActor @Suite(.serialized) struct StatusIconAnimationTests {
    private func icon() throws -> NSImage {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let image = try #require(NSImage(contentsOf: root.appendingPathComponent("resources/Brand/MenuBarTemplate.png")))
        image.size = StatusIconAnimation.size; image.isTemplate = true
        return image
    }

    @Test func renderedFramesKeepNativeSizeAndClearEdges() throws {
        let frames = StatusIconAnimation.frames(from: try icon())
        var unique = Set<Data>()
        for image in frames {
            #expect(image.size == NSSize(width: 18, height: 18))
            #expect(image.isTemplate)
            let bitmap = try #require(image.representations.first as? NSBitmapImageRep)
            #expect(bitmap.pixelsWide == 72 && bitmap.pixelsHigh == 72)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            unique.insert(png)
            // A hop/tilt must not clip at the fixed canvas edges.
            for coordinate in 0..<72 {
                for (x, y) in [(coordinate, 0), (coordinate, 71), (0, coordinate), (71, coordinate)] {
                    #expect((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 1) < 0.01)
                }
            }
        }
        #expect(unique.count > 10)
        #expect(frames.first?.tiffRepresentation == frames.last?.tiffRepresentation)
    }

    @Test func animationRunsDuringMenuTrackingAndReturnsToRest() throws {
        let rest = try icon()
        var displayed: [NSImage] = []
        let animator = StatusIconAnimator(image: rest, reduceMotion: { false }) { displayed.append($0) }
        defer { animator.stop() }
        animator.play()
        let deadline = Date().addingTimeInterval(1.5)
        while animator.isPlaying && Date() < deadline {
            _ = RunLoop.main.run(mode: .eventTracking, before: deadline)
        }
        #expect(!animator.isPlaying)
        #expect(displayed.count > 5)
        #expect(displayed.last === rest)
        #expect(displayed.contains { $0 !== rest })
        animator.play()
        animator.play() // Restarting replaces the timer, never adds an idle loop.
        animator.stop()
        #expect(!animator.isPlaying)
        #expect(displayed.last === rest)
    }

    @Test func reducedMotionSkipsAndCanInterruptPlayback() throws {
        let rest = try icon()
        var reduced = true
        var last: NSImage?
        let animator = StatusIconAnimator(image: rest, reduceMotion: { reduced }) { last = $0 }
        defer { animator.stop() }
        animator.play()
        #expect(!animator.isPlaying && last === rest)
        reduced = false
        animator.play()
        #expect(animator.isPlaying)
        reduced = true
        let deadline = Date().addingTimeInterval(0.5)
        while animator.isPlaying && Date() < deadline {
            _ = RunLoop.main.run(mode: .eventTracking, before: deadline)
        }
        #expect(!animator.isPlaying && last === rest)
    }

    @Test func nativeMenuPreservesActionsShortcutsAndPermissionGates() throws {
        let state = AppState()
        state.hasAccessibilityPermission = true
        state.notesDatabaseAccess = .available
        state.isNotesRunning = true
        state.isNotesFrontmost = false
        func actions() -> [MenuBarAction: NSMenuItem] {
            Dictionary(uniqueKeysWithValues: StatusBarController.menuItems(for: state).compactMap { item in
                (item.representedObject as? MenuBarAction).map { ($0, item) }
            })
        }
        let inactive = actions()
        #expect(inactive[.copyMarkdown]?.isEnabled == false)
        #expect(inactive[.copyNoteLink]?.isEnabled == false)
        #expect(inactive[.settings]?.isEnabled == true)
        #expect(inactive[.askAI]?.title == "AI 编辑…")
        state.isNotesFrontmost = true
        let active = actions()
        #expect(active[.copyMarkdown]?.isEnabled == true)
        #expect(active[.copyMarkdown]?.keyEquivalent == "m")
        #expect(active[.copyMarkdown]?.keyEquivalentModifierMask == [.command, .option])
        #expect(active[.backlinks]?.keyEquivalentModifierMask == [.command, .option, .shift])
        #expect(active[.settings]?.keyEquivalent == ",")
        #expect(active[.quit]?.keyEquivalent == "q")
        state.hasAccessibilityPermission = false
        state.notesDatabaseAccess = .permissionRequired
        #expect(actions()[.accessibilitySettings] != nil)
        #expect(actions()[.fullDiskAccessSettings] != nil)
    }
}
