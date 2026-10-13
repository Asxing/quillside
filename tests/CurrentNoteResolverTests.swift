import Foundation
import AppKit
import Testing
@testable import Quillside

@MainActor
@Suite(.serialized)
final class CurrentNoteResolverTests {
    @Test func testSQLFailureIsExplicitWhenNativeIdentityIsRequired() {
        let provider = SelectionProviderStub(result: .success(.init(coreDataIdentifier: "x-coredata://store/ICNote/p42", title: "Current", htmlBody: "<p>body</p>")))
        let resolver = CurrentNoteResolver(environment: CurrentNoteResolverEnvironment(
            isNotesRunning: { true }, isNotesFrontmost: { true }, databaseAccessStatus: { .available },
            selectedTextCandidates: { ["Current"] }, allNotes: { throw AIError.message("synthetic SQL failure") },
            identifierByPrimaryKey: { _ in throw AIError.message("synthetic SQL failure") }, noteByIdentifier: { _ in nil }), selectionProvider: provider)
        #expect(resolver.resolve(requiresNativeIdentifier: true) == .failure(.databaseUnavailable))
        #expect(provider.requests.isEmpty)
        let plain = try? resolver.resolve(requiresNativeIdentifier: false).get()
        #expect(plain?.identity == "x-coredata://store/ICNote/p42")
        #expect(plain?.nativeIdentifier == nil)
    }
    @Test func testMetadataMappingFailureDoesNotBreakScriptBodyRead() {
        let provider = SelectionProviderStub(result: .success(.init(coreDataIdentifier: "x-coredata://store/ICNote/p42", title: "Current", htmlBody: "<p>body</p>")))
        let resolver = CurrentNoteResolver(environment: CurrentNoteResolverEnvironment(
            isNotesRunning: { true }, isNotesFrontmost: { true }, databaseAccessStatus: { .available },
            selectedTextCandidates: { [] }, allNotes: { [] },
            identifierByPrimaryKey: { _ in throw AIError.message("synthetic SQL failure") }, noteByIdentifier: { _ in nil }), selectionProvider: provider)
        #expect(resolver.resolve(requiresNativeIdentifier: true) == .failure(.databaseUnavailable))
        let content = try? resolver.resolveContent(expectedNote: nil).get()
        #expect(content?.htmlBody == "<p>body</p>")
        #expect(content?.note.nativeIdentifier == nil)
    }
    @Test
    func testRequestsAutomationConsentOnlyForUserInitiatedAction() {
        var requestCount = 0
        #expect(SystemAppleNotesSelectionProvider.authorizationStatus(
                allowAutomationPrompt: true,
                currentStatus: .notDetermined,
                requestStatus: {
                    requestCount += 1
                    return .granted
                }
            ) == .granted)
        #expect(requestCount == 1)

        #expect(SystemAppleNotesSelectionProvider.authorizationStatus(
                allowAutomationPrompt: true,
                currentStatus: .granted,
                requestStatus: {
                    requestCount += 1
                    return .denied
                }
            ) == .granted)
        #expect(SystemAppleNotesSelectionProvider.authorizationStatus(
                allowAutomationPrompt: false,
                currentStatus: .notDetermined,
                requestStatus: {
                    requestCount += 1
                    return .granted
                }
            ) == .notDetermined)
        #expect(requestCount == 1)
    }

    @Test
    func testResolvesUniqueAccessibilityTitleWithoutAutomation() {
        let provider = SelectionProviderStub(
            result: .failure(.automationDenied)
        )
        let resolver = makeResolver(
            candidates: ["Project Alpha"],
            notes: [
                note(identifier: "alpha-id", title: "Project Alpha", id: 42),
                note(identifier: "beta-id", title: "Project Beta", id: 43),
            ],
            selectionProvider: provider
        )

        #expect((try? resolver.resolve().get()) == ResolvedCurrentNote(identifier: "alpha-id", title: "Project Alpha"))
        #expect(provider.requests == [])
    }

    @Test
    func testFallsBackToAutomationForAmbiguousAccessibilityTitle() {
        let provider = SelectionProviderStub(
            result: .success(
                AppleNotesSelection(
                    coreDataIdentifier:
                        "x-coredata://store/ICNote/p43",
                    title: "Duplicate",
                    htmlBody: nil
                )
            )
        )
        let resolver = makeResolver(
            candidates: ["Duplicate"],
            notes: [
                note(identifier: "first-id", title: "Duplicate", id: 42),
                note(identifier: "second-id", title: "Duplicate", id: 43),
            ],
            selectionProvider: provider
        )

        #expect((try? resolver.resolve().get()) == ResolvedCurrentNote(identifier: "second-id", title: "Duplicate"))
        #expect(provider.requests == [false])
        #expect(provider.promptPolicies == [true])
    }

    @Test
    func testPassiveResolutionNeverAllowsAutomationPrompt() {
        let provider = SelectionProviderStub(
            result: .failure(.automationNotDetermined)
        )
        let resolver = makeResolver(
            candidates: ["Duplicate"],
            notes: [
                note(identifier: "first-id", title: "Duplicate", id: 42),
                note(identifier: "second-id", title: "Duplicate", id: 43),
            ],
            selectionProvider: provider
        )

        #expect(resolver.resolve(allowAutomationPrompt: false) == .failure(.automationNotDetermined))
        #expect(provider.promptPolicies == [false])
    }

    @Test
    func testReturnsTypedTimeoutError() {
        let resolver = makeResolver(
            selectionProvider: SelectionProviderStub(
                result: .failure(.timedOut)
            )
        )

        #expect(resolver.resolve() == .failure(.timedOut))
    }

    @Test
    func testRejectsUnavailableNotesContextsBeforeAutomation() {
        let notRunningProvider = SelectionProviderStub(
            result: .failure(.automationDenied)
        )
        #expect(makeResolver(
                isRunning: false,
                selectionProvider: notRunningProvider
            ).resolve() == .failure(.notesNotRunning))
        #expect(notRunningProvider.requests.isEmpty)

        let notFrontmostProvider = SelectionProviderStub(
            result: .failure(.automationDenied)
        )
        #expect(makeResolver(
                isFrontmost: false,
                selectionProvider: notFrontmostProvider
            ).resolve() == .failure(.notesNotFrontmost))
        #expect(notFrontmostProvider.requests.isEmpty)
    }

    @Test
    func testRejectsMissingContentAndInvalidSelectionIdentity() {
        #expect(makeResolver(
                selectionProvider: SelectionProviderStub(
                    result: .success(
                        AppleNotesSelection(
                            coreDataIdentifier:
                                "x-coredata://store/ICNote/p42",
                            title: "Current",
                            htmlBody: nil
                        )
                    )
                )
            ).resolveContent(expectedNote: nil) == .failure(.contentUnavailable))

        #expect(makeResolver(
                selectionProvider: SelectionProviderStub(
                    result: .success(
                        AppleNotesSelection(
                            coreDataIdentifier: "not-a-core-data-id",
                            title: "Current",
                            htmlBody: nil
                        )
                    )
                )
            ).resolve() == .failure(.invalidIdentifier))
    }

    @Test
    func testRejectsSelectionWithoutCurrentNoteTitle() {
        #expect(makeResolver(
                accessStatus: .permissionRequired,
                selectionProvider: SelectionProviderStub(
                    result: .success(
                        AppleNotesSelection(
                            coreDataIdentifier:
                                "x-coredata://store/ICNote/p42",
                            title: "",
                            htmlBody: nil
                        )
                    )
                )
            ).resolve() == .failure(.noCurrentNote))
    }

    @Test
    func testRejectsBodyAfterCurrentNoteChanged() {
        let resolver = makeResolver(
            notes: [
                note(identifier: "current-id", title: "Current", id: 42),
            ],
            selectionProvider: SelectionProviderStub(
                result: .success(
                AppleNotesSelection(
                    coreDataIdentifier:
                        "x-coredata://store/ICNote/p42",
                    title: "Current",
                    htmlBody: "<div>Body</div>"
                    )
                )
            )
        )

        #expect(resolver.resolveContent(
                expectedNote: ResolvedCurrentNote(
                    identifier: "previous-id",
                    title: "Previous"
                )
            ) == .failure(.staleNote))
    }

    @Test
    func testReturnsEntireSelectedNoteBodyForExpectedIdentifier() {
        let resolver = makeResolver(
            notes: [
                note(identifier: "current-id", title: "Current", id: 42),
            ],
            selectionProvider: SelectionProviderStub(
                result: .success(
                AppleNotesSelection(
                    coreDataIdentifier:
                        "x-coredata://store/ICNote/p42",
                    title: "Current",
                    htmlBody: "<div><b>Entire body</b></div>"
                    )
                )
            )
        )

        #expect((try? resolver
                .resolveContent(
                    expectedNote: ResolvedCurrentNote(
                        identifier: "current-id",
                        title: "Current"
                    )
                )
                .get()) == ResolvedCurrentNoteContent(
                note: ResolvedCurrentNote(
                    identifier: "current-id",
                    title: "Current"
                ),
                htmlBody: "<div><b>Entire body</b></div>"
            ))
    }

    @Test
    func testResolvesContentWithoutDatabaseAccess() {
        let resolver = makeResolver(
            accessStatus: .permissionRequired,
            selectionProvider: SelectionProviderStub(
                result: .success(
                    AppleNotesSelection(
                        coreDataIdentifier:
                            "x-coredata://store/ICNote/p42",
                        title: "Current",
                        htmlBody: "<p>Entire body</p>"
                    )
                )
            )
        )

        #expect((try? resolver.resolveContent(expectedNote: nil).get()) == ResolvedCurrentNoteContent(
                note: ResolvedCurrentNote(
                    identity:
                        "x-coredata://store/ICNote/p42",
                    nativeIdentifier: nil,
                    title: "Current"
                ),
                htmlBody: "<p>Entire body</p>"
            ))
    }

    @Test
    func testNativeIdentifierResolutionStillRequiresDatabase() {
        let resolver = makeResolver(
            accessStatus: .permissionRequired,
            selectionProvider: SelectionProviderStub(
                result: .failure(.automationNotDetermined)
            )
        )

        #expect(resolver.resolve(
                allowAutomationPrompt: true,
                requiresNativeIdentifier: true
            ) == .failure(.databaseUnavailable))
    }

    private func makeResolver(
        isRunning: Bool = true,
        isFrontmost: Bool = true,
        accessStatus: NotesDatabaseAccessStatus = .available,
        candidates: Set<String> = [],
        notes: [NotesDBReader.NoteInfo] = [
            note(identifier: "current-id", title: "Current", id: 42),
        ],
        selectionProvider: SelectionProviderStub
    ) -> CurrentNoteResolver {
        CurrentNoteResolver(
            environment: CurrentNoteResolverEnvironment(
                isNotesRunning: { isRunning },
                isNotesFrontmost: { isFrontmost },
                databaseAccessStatus: { accessStatus },
                selectedTextCandidates: { candidates },
                allNotes: { notes },
                identifierByPrimaryKey: { primaryKey in
                    notes.first(where: { $0.id == primaryKey })?.identifier
                },
                noteByIdentifier: { identifier in
                    notes.first(where: { $0.identifier == identifier })
                }
            ),
            selectionProvider: selectionProvider
        )
    }

    nonisolated private static func note(
        identifier: String,
        title: String,
        id: Int64
    ) -> NotesDBReader.NoteInfo {
        NotesDBReader.NoteInfo(
            id: id,
            identifier: identifier,
            title: title,
            snippet: "",
            folderName: "Quillside Demo",
            modificationDate: Date(timeIntervalSince1970: 0),
            isPinned: false
        )
    }

    private func note(
        identifier: String,
        title: String,
        id: Int64
    ) -> NotesDBReader.NoteInfo {
        Self.note(identifier: identifier, title: title, id: id)
    }
}

private final class SelectionProviderStub: AppleNotesSelectionProviding {
    let result: Result<AppleNotesSelection, CurrentNoteResolutionError>
    private(set) var requests: [Bool] = []
    private(set) var promptPolicies: [Bool] = []

    init(result: Result<AppleNotesSelection, CurrentNoteResolutionError>) {
        self.result = result
    }

    func selectedNote(
        includeBody: Bool,
        allowAutomationPrompt: Bool
    ) -> Result<AppleNotesSelection, CurrentNoteResolutionError> {
        requests.append(includeBody)
        promptPolicies.append(allowAutomationPrompt)
        return result
    }
}
