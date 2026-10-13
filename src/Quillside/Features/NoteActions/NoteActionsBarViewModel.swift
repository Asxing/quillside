import Foundation
import Combine

final class NoteActionsBarViewModel: ObservableObject {
    struct Feedback: Equatable {
        enum Kind: Equatable {
            case success
            case error
        }

        let kind: Kind
        let message: String
    }

    typealias Executor = (@escaping () -> Void) -> Void
    typealias TimeoutScheduler =
        (TimeInterval, @escaping () -> Void) -> Void

    @Published private(set) var currentNote: ResolvedCurrentNote?
    @Published private(set) var activeAction: NoteActionKind?
    @Published private(set) var feedback: Feedback?
    @Published private(set) var isResolving = false

    var onShowBacklinks: ((ResolvedCurrentNote) -> Void)?

    private let service: NoteActionsServicing
    private let execute: Executor
    private let deliver: Executor
    private let scheduleTimeout: TimeoutScheduler
    private let operationTimeout: TimeInterval
    private var generation = 0

    convenience init() {
        self.init(service: NoteActionsService())
    }

    init(
        service: NoteActionsServicing,
        operationTimeout: TimeInterval = 3,
        execute: @escaping Executor = { operation in
            DispatchQueue.global(qos: .userInitiated)
                .async(execute: operation)
        },
        deliver: @escaping Executor = { operation in
            DispatchQueue.main.async(execute: operation)
        },
        scheduleTimeout: @escaping TimeoutScheduler = {
            delay,
            operation in
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay,
                execute: operation
            )
        }
    ) {
        self.service = service
        self.operationTimeout = operationTimeout
        self.execute = execute
        self.deliver = deliver
        self.scheduleTimeout = scheduleTimeout
    }

    func setCurrentNote(_ note: ResolvedCurrentNote?) {
        guard
            note != currentNote
                || activeAction != nil
                || isResolving
        else {
            return
        }
        generation += 1
        currentNote = note
        activeAction = nil
        feedback = nil
        isResolving = false
    }

    func refreshCurrentNote() {
        guard !isResolving, activeAction == nil else { return }
        beginCurrentNoteResolution()
    }

    func noteContextDidChange() {
        generation += 1
        activeAction = nil
        feedback = nil
        isResolving = false
        beginCurrentNoteResolution()
    }

    private func beginCurrentNoteResolution() {
        generation += 1
        let requestGeneration = generation
        isResolving = true
        scheduleResolutionTimeout(generation: requestGeneration)
        execute { [weak self] in
            guard let self else { return }
            let result = self.service.resolveCurrentNote()
            self.deliver { [weak self] in
                guard
                    let self,
                    self.generation == requestGeneration
                else {
                    return
                }
                self.isResolving = false
                switch result {
                case let .success(note):
                    self.currentNote = note
                case .failure:
                    self.currentNote = nil
                }
            }
        }
    }

    func perform(
        _ action: NoteActionKind,
        resolveIfNeeded: Bool = false
    ) {
        guard activeAction == nil else { return }
        let expectedNote = resolveIfNeeded ? nil : currentNote
        guard resolveIfNeeded || expectedNote != nil else {
            feedback = Feedback(
                kind: .error,
                message: "无法读取当前笔记，请重试"
            )
            return
        }

        generation += 1
        let operationGeneration = generation
        let startingNote = expectedNote
        activeAction = action
        feedback = nil
        execute { [weak self] in
            guard let self else { return }
            let result = self.service.perform(
                action,
                expectedNote: expectedNote
            )
            self.deliver { [weak self] in
                guard let self else { return }
                guard self.generation == operationGeneration else {
                    return
                }
                if let startingNote {
                    guard
                        let currentNote = self.currentNote,
                        currentNote.refersToSameNote(as: startingNote)
                    else {
                        self.activeAction = nil
                        return
                    }
                }

                self.activeAction = nil
                switch result {
                case let .success(outcome):
                    if let payload = outcome.pasteboardPayload,
                       !self.service.commitPasteboard(payload) {
                        self.feedback = Feedback(
                            kind: .error,
                            message: NoteActionError
                                .pasteboardFailed
                                .userMessage
                        )
                        self.scheduleFeedbackDismissal(
                            generation: operationGeneration
                        )
                        return
                    }
                    self.currentNote = outcome.note
                    if action == .backlinks {
                        self.onShowBacklinks?(outcome.note)
                    }
                    if let message = outcome.feedbackMessage {
                        self.feedback = Feedback(
                            kind: .success,
                            message: message
                        )
                        self.scheduleFeedbackDismissal(
                            generation: operationGeneration
                        )
                    }
                case let .failure(error):
                    self.feedback = Feedback(
                        kind: .error,
                        message: error.userMessage
                    )
                    self.scheduleFeedbackDismissal(
                        generation: operationGeneration
                    )
                }
            }
        }
    }

    private func scheduleResolutionTimeout(generation: Int) {
        scheduleTimeout(operationTimeout) { [weak self] in
            guard
                let self,
                self.generation == generation,
                self.isResolving
            else {
                return
            }
            self.generation += 1
            self.isResolving = false
            self.currentNote = nil
        }
    }

    private func scheduleFeedbackDismissal(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard self.generation == generation else { return }
            self.feedback = nil
        }
    }
}
