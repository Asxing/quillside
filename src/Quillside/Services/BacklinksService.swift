import Foundation
import os.log
import AppKit

enum BacklinkGraphBuilder {
    static func canonicalNotes(_ notes: [NotesDBReader.NoteInfo]) -> [NotesDBReader.NoteInfo] {
        Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.modificationDate >= b.modificationDate ? a : b }).values.sorted {
            $0.modificationDate == $1.modificationDate ? $0.id < $1.id : $0.modificationDate > $1.modificationDate
        }
    }
    static func build(
        notes: [NotesDBReader.NoteInfo],
        links: [NotesDBReader.NoteLinkData]
    ) -> [Int64: Set<Int64>] {
        let ordered = canonicalNotes(notes)
        let notesByID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        var identifiersToIDs: [String: Int64] = [:]
        for note in ordered where !note.identifier.isEmpty {
            if identifiersToIDs[note.identifier.uppercased()] == nil { identifiersToIDs[note.identifier.uppercased()] = note.id }
        }

        var graph: [Int64: Set<Int64>] = [:]
        for link in links {
            guard let source = notesByID[link.noteId] else { continue }
            let sourceIdentifier = source.identifier.uppercased()
            let targets = Set(
                link.linkedIdentifiers.compactMap {
                    identifiersToIDs[$0.uppercased()]
                }
            ).filter {
                notesByID[$0]?.identifier.uppercased() != sourceIdentifier
            }
            if !targets.isEmpty {
                graph[link.noteId] = targets
            }
        }
        return graph
    }

    static func sourceNoteIDs(
        linkingTo targetNoteID: Int64,
        in graph: [Int64: Set<Int64>]
    ) -> [Int64] {
        graph.compactMap { sourceID, targetIDs in
            targetIDs.contains(targetNoteID) ? sourceID : nil
        }.sorted()
    }
}

enum BacklinksBuildCommitPolicy {
    static func canCommit(
        buildGeneration: Int,
        currentGeneration: Int
    ) -> Bool {
        buildGeneration == currentGeneration
    }
}

enum BacklinksIdentifierRefreshPolicy {
    static func shouldRequestBuild(
        identifierFound: Bool,
        alreadyRequested: Bool
    ) -> Bool {
        !identifierFound && !alreadyRequested
    }
}

enum BacklinksQueryPhase: Equatable {
    case loading, ready, targetMissing, failed(String)
}

struct BacklinksQuery {
    let phase: BacklinksQueryPhase
    let items: [BacklinksService.BacklinkInfo]
    var coverage = BacklinksCoverage()
}

final class BacklinksService: ObservableObject {
    static let shared = BacklinksService()
    enum State: Equatable { case idle, loading, ready, failed(String) }
    @Published private(set) var state: State = .idle
    @Published private(set) var isBuilding = false
    private(set) var lastBuildTime: Date?
    private var linkGraph: [Int64: Set<Int64>] = [:]
    private var notesByID: [Int64: NotesDBReader.NoteInfo] = [:]
    private var identifiers: [String: Int64] = [:]
    private var coverage = BacklinksCoverage()
    private var generation = 0
    private var pending = false
    private var refreshedIdentifiers = Set<String>()
    private var completions: [() -> Void] = []
    private let load: () throws -> NotesBacklinksSnapshot
    private let execute: (@escaping () -> Void) -> Void
    private let deliver: (@escaping () -> Void) -> Void
    private let now: () -> Date

    struct BacklinkInfo: Identifiable {
        let id: Int64
        let noteTitle: String
        let identifier: String
        let context: String
        let modificationDate: Date
    }
    init(load: @escaping () throws -> NotesBacklinksSnapshot = { try NotesDBReader.shared.readBacklinksSnapshot() },
         execute: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.global(qos: .userInitiated).async(execute: $0) },
         deliver: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
         now: @escaping () -> Date = Date.init) {
        self.load = load; self.execute = execute; self.deliver = deliver; self.now = now
    }
    func buildLinkGraph(force: Bool = false, completion: (() -> Void)? = nil) {
        if let completion { completions.append(completion) }
        if isBuilding { if force { pending = true }; return }
        isBuilding = true; state = .loading
        let buildGeneration = generation
        execute { [weak self] in
            guard let self else { return }
            let result = Result { try self.load() }
            self.deliver { [weak self] in
                guard let self else { return }
                self.isBuilding = false
                if !BacklinksBuildCommitPolicy.canCommit(buildGeneration: buildGeneration, currentGeneration: self.generation) || self.pending {
                    self.pending = false; self.buildLinkGraph(); return
                }
                switch result {
                case let .success(snapshot):
                    self.linkGraph = BacklinkGraphBuilder.build(notes: snapshot.notes, links: snapshot.links)
                    let ordered = BacklinkGraphBuilder.canonicalNotes(snapshot.notes)
                    self.notesByID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
                    self.identifiers = [:]
                    for note in ordered {
                        if self.identifiers[note.identifier.uppercased()] == nil { self.identifiers[note.identifier.uppercased()] = note.id }
                    }
                    self.coverage = snapshot.coverage; self.lastBuildTime = self.now(); self.state = .ready
                case let .failure(error):
                    self.state = .failed(error.localizedDescription)
                }
                let callbacks = self.completions; self.completions.removeAll()
                callbacks.forEach { $0() }
            }
        }
    }
    func lookup(_ identifier: String) -> BacklinksQuery {
        switch state {
        case .failed(let message): return .init(phase: .failed(message), items: [])
        case .loading: return .init(phase: .loading, items: [])
        case .idle: buildLinkGraph(); return .init(phase: .loading, items: [])
        case .ready: break
        }
        if let lastBuildTime, now().timeIntervalSince(lastBuildTime) > 30 {
            buildLinkGraph(); return .init(phase: .loading, items: [])
        }
        let key = identifier.uppercased()
        guard let target = identifiers[key] else {
            if BacklinksIdentifierRefreshPolicy.shouldRequestBuild(identifierFound: false, alreadyRequested: refreshedIdentifiers.contains(key)) {
                refreshedIdentifiers.insert(key); buildLinkGraph(); return .init(phase: .loading, items: [])
            }
            return .init(phase: .targetMissing, items: [], coverage: coverage)
        }
        refreshedIdentifiers.remove(key)
        let items = BacklinkGraphBuilder.sourceNoteIDs(linkingTo: target, in: linkGraph).compactMap { notesByID[$0] }.map { note in
            BacklinkInfo(id: note.id, noteTitle: note.title, identifier: note.identifier, context: note.snippet, modificationDate: note.modificationDate)
        }.sorted { $0.modificationDate > $1.modificationDate }
        return .init(phase: .ready, items: items, coverage: coverage)
    }
    func invalidateCache() {
        generation += 1; lastBuildTime = nil; linkGraph = [:]; notesByID = [:]; identifiers = [:]; coverage = .init(); refreshedIdentifiers = []
        if isBuilding { pending = true } else { state = .idle }
    }
}
