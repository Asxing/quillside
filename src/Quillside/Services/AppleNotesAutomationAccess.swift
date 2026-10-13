import AppKit
import ApplicationServices
import Foundation

enum AppleNotesAutomationStatus: Equatable {
    case checking
    case notDetermined
    case granted
    case denied
    case targetNotRunning
    case unavailable

    init(osStatus: OSStatus) {
        switch osStatus {
        case noErr:
            self = .granted
        case OSStatus(errAEEventWouldRequireUserConsent):
            self = .notDetermined
        case OSStatus(errAEEventNotPermitted):
            self = .denied
        case OSStatus(procNotFound):
            self = .targetNotRunning
        default:
            self = .unavailable
        }
    }

    static func displayStatus(
        previous: AppleNotesAutomationStatus,
        observed: AppleNotesAutomationStatus
    ) -> AppleNotesAutomationStatus {
        if observed == .targetNotRunning,
           previous == .granted || previous == .denied {
            return previous
        }
        return observed
    }
}

final class AppleNotesAutomationAccess {
    static let shared = AppleNotesAutomationAccess()

    private init() {}

    /// Checks the current TCC decision without prompting the user.
    /// Call this away from the main thread because the Apple Event API may block.
    func currentStatus() -> AppleNotesAutomationStatus {
        status(askUserIfNeeded: false)
    }

    /// Requests the TCC decision after a user-initiated action.
    /// This may wait for secure user consent and must stay off the main thread.
    func requestStatus() -> AppleNotesAutomationStatus {
        status(askUserIfNeeded: true)
    }

    private func status(
        askUserIfNeeded: Bool
    ) -> AppleNotesAutomationStatus {
        var target = AEAddressDesc()
        let bundleData = Data(AppleNotesTarget.bundleIdentifier.utf8)
        let createStatus = bundleData.withUnsafeBytes { bytes in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                bytes.baseAddress,
                bytes.count,
                &target
            )
        }
        guard createStatus == noErr else {
            return .unavailable
        }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )
        return AppleNotesAutomationStatus(osStatus: status)
    }

    func openSettings() {
        guard let url = URL(
            string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
