import Foundation
import AppKit
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class AppleNotesAutomationAccessTests {
    @Test
    func testMapsAppleEventPermissionStatuses() {
        #expect(AppleNotesAutomationStatus(osStatus: noErr) == .granted)
        #expect(AppleNotesAutomationStatus(osStatus: -1744) == .notDetermined)
        #expect(AppleNotesAutomationStatus(osStatus: -1743) == .denied)
        #expect(AppleNotesAutomationStatus(osStatus: -600) == .targetNotRunning)
        #expect(AppleNotesAutomationStatus(osStatus: -1) == .unavailable)
    }

    @Test
    func testKeepsKnownDecisionWhileNotesIsNotRunning() {
        #expect(AppleNotesAutomationStatus.displayStatus(
                previous: .granted,
                observed: .targetNotRunning
            ) == .granted)
        #expect(AppleNotesAutomationStatus.displayStatus(
                previous: .denied,
                observed: .targetNotRunning
            ) == .denied)
        #expect(AppleNotesAutomationStatus.displayStatus(
                previous: .checking,
                observed: .targetNotRunning
            ) == .targetNotRunning)
    }
}
