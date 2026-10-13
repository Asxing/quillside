import Foundation
import AppKit
import CoreGraphics
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class AppShortcutTests {
    @Test
    func testKeyboardRoutingRequiresLiveNotesFrontmostState() {
        #expect(KeyboardEventRoutingPolicy.shouldHandle(
                cachedIsNotesFrontmost: true,
                liveFrontmostBundleIdentifier:
                    AppleNotesTarget.bundleIdentifier
            ))
        #expect(!(KeyboardEventRoutingPolicy.shouldHandle(
                cachedIsNotesFrontmost: true,
                liveFrontmostBundleIdentifier: "com.apple.Safari"
            )))
        #expect(!(KeyboardEventRoutingPolicy.shouldHandle(
                cachedIsNotesFrontmost: false,
                liveFrontmostBundleIdentifier:
                    AppleNotesTarget.bundleIdentifier
            )))
    }

    @Test
    func testGlobalCopyShortcutsMatchNotesFrontmostEntryPoints() {
        #expect(AppShortcutMatcher.action(
                keyCode: 46,
                modifiers: [.maskCommand, .maskAlternate]
            ) == .copyMarkdown)
        #expect(AppShortcutMatcher.action(
                keyCode: 37,
                modifiers: [.maskCommand, .maskAlternate]
            ) == .copyNoteLink)
    }

    @Test
    func testGlobalCopyShortcutsRejectWrongModifiers() {
        #expect(AppShortcutMatcher.action(
                keyCode: 46,
                modifiers: [.maskCommand]
            ) == nil)
        #expect(AppShortcutMatcher.action(
                keyCode: 37,
                modifiers: [
                    .maskCommand,
                    .maskAlternate,
                    .maskShift,
                ]
            ) == nil)
    }

    @Test
    func testBacklinksShortcutMatchesCommandOptionShiftB() {
        #expect(AppShortcutMatcher.isBacklinksShortcut(
                keyCode: 11,
                modifiers: [.maskCommand, .maskAlternate, .maskShift]
            ))
    }

    @Test
    func testBacklinksShortcutAllowsUnrelatedSystemFlags() {
        #expect(AppShortcutMatcher.isBacklinksShortcut(
                keyCode: 11,
                modifiers: [
                    .maskCommand,
                    .maskAlternate,
                    .maskShift,
                    .maskAlphaShift,
                ]
            ))
    }

    @Test
    func testBacklinksShortcutRejectsMissingOptionOrWrongKey() {
        #expect(!(AppShortcutMatcher.isBacklinksShortcut(
                keyCode: 11,
                modifiers: [.maskCommand]
            )))
        #expect(!(AppShortcutMatcher.isBacklinksShortcut(
                keyCode: 35,
                modifiers: [.maskCommand, .maskAlternate, .maskShift]
            )))
    }

    @Test
    func testBacklinksShortcutDoesNotStealNativeBodyShortcut() {
        #expect(!(AppShortcutMatcher.isBacklinksShortcut(
                keyCode: 11,
                modifiers: [.maskCommand, .maskShift]
            )))
        #expect(!(AppShortcutMatcher.isBacklinksShortcut(
                keyCode: 11,
                modifiers: [
                    .maskCommand,
                    .maskAlternate,
                    .maskShift,
                    .maskControl,
                ]
            )))
    }
}
