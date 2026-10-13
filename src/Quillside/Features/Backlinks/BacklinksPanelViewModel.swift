import Foundation
import Combine
import os.log

final class BacklinksPanelViewModel: ObservableObject {
    enum ResolutionState {
        case resolving
        case resolved
        case unavailable
    }
    
    @Published var currentNoteTitle: String = ""
    @Published var currentNoteIdentifier: String = ""
    @Published private(set) var backlinks: [BacklinksService.BacklinkInfo] = []
    @Published private(set) var resolutionState: ResolutionState = .resolving
    
    @Published private(set) var queryPhase: BacklinksQueryPhase = .loading
    @Published private(set) var coverage = BacklinksCoverage()
    private let backlinksService: BacklinksService
    private let logger = Logger(subsystem: "com.opennotes.app", category: "BacklinksPanel")
    private var cancellables = Set<AnyCancellable>()
    
    init(service: BacklinksService = .shared) {
        self.backlinksService = service
        $currentNoteIdentifier
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] identifier in
                self?.refreshBacklinks(forIdentifier: identifier)
            }
            .store(in: &cancellables)
        
        backlinksService.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.currentNoteIdentifier.isEmpty else { return }
                self.refreshBacklinks(forIdentifier: self.currentNoteIdentifier)
            }
            .store(in: &cancellables)
    }
    
    func reset() {
        currentNoteTitle = ""
        currentNoteIdentifier = ""
        backlinks = []
        resolutionState = .resolving
        queryPhase = .loading; coverage = .init()
    }
    
    func setCurrentNote(identifier: String, title: String) {
        if currentNoteIdentifier != identifier { backlinks = []; queryPhase = .loading }
        currentNoteIdentifier = identifier
        currentNoteTitle = title
        resolutionState = .resolved
        logger.info("Current note resolved")
        refreshBacklinks(forIdentifier: identifier)
    }
    
    func markCurrentNoteUnavailable() {
        currentNoteTitle = ""
        currentNoteIdentifier = ""
        backlinks = []
        resolutionState = .unavailable
        logger.warning("Current note could not be resolved")
    }

    func retry() {
        backlinksService.buildLinkGraph(force: true)
        forceRefresh()
    }
    func forceRefresh() {
        refreshBacklinks(forIdentifier: currentNoteIdentifier)
    }

    #if DEBUG
    func configureForPreview(
        backlinks: [BacklinksService.BacklinkInfo]
    ) {
        cancellables.removeAll()
        self.backlinks = backlinks
        resolutionState = .resolved
        queryPhase = .ready
    }
    #endif
    
    private func refreshBacklinks(forIdentifier identifier: String) {
        guard !identifier.isEmpty else {
            backlinks = []
            return
        }
        let query = backlinksService.lookup(identifier)
        backlinks = query.items; queryPhase = query.phase; coverage = query.coverage
        if query.phase == .ready {
            logger.info("Backlink snapshot available: count=\(self.backlinks.count), complete=\(self.coverage.complete)")
        }
    }
}
