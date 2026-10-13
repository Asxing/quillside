import AppKit
import Foundation
import os.log

struct ResolvedCurrentNote: Equatable {
    let identity: String
    let nativeIdentifier: String?
    let title: String

    init(identifier: String, title: String) {
        self.identity = identifier
        self.nativeIdentifier = identifier
        self.title = title
    }

    init(
        identity: String,
        nativeIdentifier: String?,
        title: String
    ) {
        self.identity = identity
        self.nativeIdentifier = nativeIdentifier
        self.title = title
    }

    var identifier: String {
        nativeIdentifier ?? identity
    }

    func refersToSameNote(as other: ResolvedCurrentNote) -> Bool {
        if let nativeIdentifier,
           let otherNativeIdentifier = other.nativeIdentifier {
            return nativeIdentifier == otherNativeIdentifier
        }
        return identity == other.identity
    }

    static func == (
        lhs: ResolvedCurrentNote,
        rhs: ResolvedCurrentNote
    ) -> Bool {
        lhs.title == rhs.title
            && lhs.refersToSameNote(as: rhs)
    }
}

struct ResolvedCurrentNoteContent: Equatable {
    let note: ResolvedCurrentNote
    let htmlBody: String
}

struct AppleNotesSelection: Equatable {
    let coreDataIdentifier: String
    let title: String
    let htmlBody: String?
}

enum CurrentNoteResolutionError: Error, Equatable {
    case notesNotRunning
    case notesNotFrontmost
    case databaseUnavailable
    case noCurrentNote
    case invalidIdentifier
    case contentUnavailable
    case automationNotDetermined
    case automationDenied
    case timedOut
    case automationFailed(Int)
    case staleNote
}

protocol AppleNotesSelectionProviding: AnyObject {
    func selectedNote(
        includeBody: Bool,
        allowAutomationPrompt: Bool
    ) -> Result<AppleNotesSelection, CurrentNoteResolutionError>
}

struct CurrentNoteResolverEnvironment {
    let isNotesRunning: () -> Bool
    let isNotesFrontmost: () -> Bool
    let databaseAccessStatus: () -> NotesDatabaseAccessStatus
    let selectedTextCandidates: () -> Set<String>
    let allNotes: () throws -> [NotesDBReader.NoteInfo]
    let identifierByPrimaryKey: (Int64) throws -> String?
    let noteByIdentifier: (String) throws -> NotesDBReader.NoteInfo?

    static let live = CurrentNoteResolverEnvironment(
        isNotesRunning: {
            AccessibilityBridge.shared.isNotesRunning()
        },
        isNotesFrontmost: {
            AccessibilityBridge.shared.isNotesFrontmost()
        },
        databaseAccessStatus: {
            NotesDBReader.shared.accessStatus()
        },
        selectedTextCandidates: {
            AccessibilityBridge.shared.getSelectedNoteTextCandidates()
        },
        allNotes: {
            try NotesDBReader.shared.readAllNotes()
        },
        identifierByPrimaryKey: {
            try NotesDBReader.shared.readIdentifierByPK($0)
        },
        noteByIdentifier: {
            try NotesDBReader.shared.readNoteByIdentifier($0)
        }
    )
}

final class CurrentNoteResolver {
    private let environment: CurrentNoteResolverEnvironment
    private let selectionProvider: AppleNotesSelectionProviding

    convenience init() {
        self.init(
            environment: .live,
            selectionProvider: SystemAppleNotesSelectionProvider()
        )
    }

    init(
        environment: CurrentNoteResolverEnvironment,
        selectionProvider: AppleNotesSelectionProviding
    ) {
        self.environment = environment
        self.selectionProvider = selectionProvider
    }

    func resolve(
        allowAutomationPrompt: Bool = true,
        requiresNativeIdentifier: Bool = false
    )
        -> Result<ResolvedCurrentNote, CurrentNoteResolutionError>
    {
        if let error = preflightError(
            requiresDatabase: requiresNativeIdentifier
        ) {
            return .failure(error)
        }

        if environment.databaseAccessStatus() == .available {
            do {
            let notes = try environment.allNotes()
            if let identifier = SelectedNoteMatcher.identifier(
                textCandidates:
                    environment.selectedTextCandidates(),
                notes: notes.map {
                    ($0.title, $0.identifier)
                }
            ), let note = notes.first(where: {
                $0.identifier == identifier
            }) {
                return .success(
                    ResolvedCurrentNote(
                        identifier: note.identifier,
                        title: note.title
                    )
                )
            }

            } catch { if requiresNativeIdentifier { return .failure(.databaseUnavailable) } }
        }
        switch selectionProvider.selectedNote(
            includeBody: false,
            allowAutomationPrompt: allowAutomationPrompt
        ) {
        case let .success(selection):
            return resolve(
                selection: selection,
                requiresNativeIdentifier:
                    requiresNativeIdentifier
            )
                .map(\.note)
        case let .failure(error):
            return .failure(error)
        }
    }

    func resolveContent(
        expectedNote: ResolvedCurrentNote?
    ) -> Result<ResolvedCurrentNoteContent, CurrentNoteResolutionError> {
        if let error = preflightError(requiresDatabase: false) {
            return .failure(error)
        }

        switch selectionProvider.selectedNote(
            includeBody: true,
            allowAutomationPrompt: true
        ) {
        case let .success(selection):
            guard let htmlBody = selection.htmlBody else {
                return .failure(.contentUnavailable)
            }
            return resolve(
                selection: selection,
                requiresNativeIdentifier: false
            ).flatMap { resolved in
                if let expectedNote,
                   !resolved.note.refersToSameNote(
                        as: expectedNote
                   ) {
                    return .failure(.staleNote)
                }
                return .success(
                    ResolvedCurrentNoteContent(
                        note: resolved.note,
                        htmlBody: htmlBody
                    )
                )
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    private func preflightError(
        requiresDatabase: Bool
    ) -> CurrentNoteResolutionError? {
        guard environment.isNotesRunning() else {
            return .notesNotRunning
        }
        guard environment.isNotesFrontmost() else {
            return .notesNotFrontmost
        }
        guard
            !requiresDatabase
                || environment.databaseAccessStatus() == .available
        else {
            return .databaseUnavailable
        }
        return nil
    }

    private func resolve(
        selection: AppleNotesSelection,
        requiresNativeIdentifier: Bool
    ) -> Result<ResolvedCurrentNoteContent, CurrentNoteResolutionError> {
        guard
            let primaryKey = AppleNotesIdentifierParser.primaryKey(
                from: selection.coreDataIdentifier
            )
        else {
            return .failure(.invalidIdentifier)
        }

        do {
        if environment.databaseAccessStatus() == .available,
           let identifier =
                try environment.identifierByPrimaryKey(primaryKey),
           !identifier.isEmpty,
           let note = try environment.noteByIdentifier(identifier) {
            return .success(
                ResolvedCurrentNoteContent(
                    note: ResolvedCurrentNote(
                        identity: selection.coreDataIdentifier,
                        nativeIdentifier: note.identifier,
                        title: note.title
                    ),
                    htmlBody: selection.htmlBody ?? ""
                )
            )
        }

        } catch { if requiresNativeIdentifier { return .failure(.databaseUnavailable) } }

        if requiresNativeIdentifier {
            return .failure(.databaseUnavailable)
        }
        guard !selection.title.isEmpty else {
            return .failure(.noCurrentNote)
        }

        return .success(
            ResolvedCurrentNoteContent(
                note: ResolvedCurrentNote(
                    identity: selection.coreDataIdentifier,
                    nativeIdentifier: nil,
                    title: selection.title
                ),
                htmlBody: selection.htmlBody ?? ""
            )
        )
    }
}

final class SystemAppleNotesSelectionProvider:
    AppleNotesSelectionProviding
{
    static func authorizationStatus(
        allowAutomationPrompt: Bool,
        currentStatus: AppleNotesAutomationStatus,
        requestStatus: () -> AppleNotesAutomationStatus
    ) -> AppleNotesAutomationStatus {
        if allowAutomationPrompt,
           currentStatus == .notDetermined {
            return requestStatus()
        }
        return currentStatus
    }

    private let logger = Logger(
        subsystem: "com.opennotes.app",
        category: "CurrentNoteResolver"
    )

    func selectedNote(
        includeBody: Bool,
        allowAutomationPrompt: Bool
    ) -> Result<AppleNotesSelection, CurrentNoteResolutionError> {
        let automationStatus =
            Self.authorizationStatus(
                allowAutomationPrompt: allowAutomationPrompt,
                currentStatus:
                    AppleNotesAutomationAccess.shared.currentStatus(),
                requestStatus: {
                    AppleNotesAutomationAccess.shared.requestStatus()
                }
            )
        switch automationStatus {
        case .granted:
            break
        case .notDetermined, .targetNotRunning, .checking:
            return .failure(.automationNotDetermined)
        case .denied:
            return .failure(.automationDenied)
        case .unavailable:
            return .failure(.automationFailed(0))
        }

        let selectedProperties = includeBody
            ? "{id of selectedNote, name of selectedNote, body of selectedNote}"
            : "{id of selectedNote, name of selectedNote}"
        let emptyResult = includeBody
            ? "{\"\", \"\", \"\"}"
            : "{\"\", \"\"}"
        let script = """
        with timeout of 2 seconds
            tell application "Notes"
                set selectedNotes to selection
                if (count of selectedNotes) is 0 then
                    return \(emptyResult)
                end if
                set selectedNote to item 1 of selectedNotes
                return \(selectedProperties)
            end tell
        end timeout
        """

        guard let appleScript = NSAppleScript(source: script) else {
            return .failure(.automationFailed(0))
        }

        var errorInfo: NSDictionary?
        let output = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            logger.error(
                "Apple Notes selection request failed: code=\(code)"
            )
            switch code {
            case -1743:
                return .failure(.automationDenied)
            case -1712:
                return .failure(.timedOut)
            default:
                return .failure(.automationFailed(code))
            }
        }

        guard
            output.numberOfItems >= 2,
            let coreDataIdentifier = output.atIndex(1)?.stringValue,
            !coreDataIdentifier.isEmpty,
            let title = output.atIndex(2)?.stringValue,
            !title.isEmpty
        else {
            return .failure(.noCurrentNote)
        }

        let htmlBody: String?
        if includeBody {
            guard
                output.numberOfItems >= 3,
                let body = output.atIndex(3)?.stringValue
            else {
                return .failure(.contentUnavailable)
            }
            htmlBody = body
        } else {
            htmlBody = nil
        }

        return .success(
            AppleNotesSelection(
                coreDataIdentifier: coreDataIdentifier,
                title: title,
                htmlBody: htmlBody
            )
        )
    }
}
