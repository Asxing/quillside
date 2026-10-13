import Foundation
import AppKit
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class WindowTrackingTests {
    @Test
    func testHealthCheckSkipsFullSnapshotWhenStatusIsStable() {
        #expect(!(WindowHealthCheckPolicy.requiresFullSnapshot(
                currentIsRunning: true,
                currentIsFrontmost: true,
                observedIsRunning: true,
                observedIsFrontmost: true,
                observerAction: .none
            )))
        #expect(WindowHealthCheckPolicy.requiresFullSnapshot(
                currentIsRunning: true,
                currentIsFrontmost: true,
                observedIsRunning: true,
                observedIsFrontmost: false,
                observerAction: .none
            ))
    }

    @Test
    func testNoteActionsIgnoresHealthCheckEvents() {
        #expect(!(NoteActionsRefreshPolicy.shouldRefresh(for: .healthCheck)))
        #expect(NoteActionsRefreshPolicy.shouldRefresh(
                for: .selectionChanged
            ))
    }

    @Test
    func testObserverLifecycleReplacesObserverWhenNotesRestarts() {
        #expect(AXObserverLifecyclePolicy.action(
                observedPID: 101,
                observerInstalled: true,
                snapshotPID: 202,
                isTrusted: true
            ) == .replace(202))
    }

    @Test
    func testObserverLifecycleRemovesObserverWhenPermissionIsRevoked() {
        #expect(AXObserverLifecyclePolicy.action(
                observedPID: 101,
                observerInstalled: true,
                snapshotPID: 101,
                isTrusted: false
            ) == .remove)
        #expect(AXObserverLifecyclePolicy.action(
                observedPID: nil,
                observerInstalled: false,
                snapshotPID: 101,
                isTrusted: true
            ) == .install(101))
    }

    @Test
    func testNoteActionsPositionUsesSecondaryDisplayCoordinates() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(
            x: 1440,
            y: 0,
            width: 1920,
            height: 1080
        )
        let notesOnSecondaryInAXCoordinates = CGRect(
            x: 1540,
            y: -80,
            width: 1200,
            height: 800
        )

        let origin = WindowGeometry.noteActionsOrigin(
            axNotesFrame: notesOnSecondaryInAXCoordinates,
            panelSize: CGSize(width: 240, height: 70),
            primaryScreenFrame: primary,
            visibleScreenFrames: [primary, secondary]
        )

        #expect(origin.x == 2484)
        #expect(origin.y == 196)
        #expect(secondary.contains(origin))
    }

    @Test
    func testCocoaConversionSupportsDisplayAbovePrimary() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let axRect = CGRect(x: 100, y: -700, width: 800, height: 600)

        #expect(WindowGeometry.cocoaRect(
                fromAX: axRect,
                primaryScreenFrame: primary
            ) == CGRect(x: 100, y: 1000, width: 800, height: 600))
    }

    @Test
    func testBacklinksFallbackUsesSecondaryDisplayCoordinates() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(
            x: 1440,
            y: 0,
            width: 1920,
            height: 1080
        )
        let axFrame = CGRect(
            x: 1540,
            y: -80,
            width: 1200,
            height: 800
        )

        #expect(WindowGeometry.backlinksOrigin(
                axNotesFrame: axFrame,
                panelSize: CGSize(
                    width: BacklinksPanelLayout.width,
                    height: BacklinksPanelLayout.fallbackHeight
                ),
                primaryScreenFrame: primary,
                visibleScreenFrames: [primary, secondary]
            ) == CGPoint(x: 2400, y: 240))
    }
}
