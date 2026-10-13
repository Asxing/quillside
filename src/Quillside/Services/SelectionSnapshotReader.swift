import Foundation

/// Geometry has its own lane: a slow format query can never delay presentation.
/// Keep only the latest pending selection, and reject results after cancellation.
final class SelectionSnapshotReader<Geometry, Style> {
    private struct Request {
        let id: Int
        let geometry: (Geometry?) -> Void
        let style: (Style) -> Void
    }
    private let readGeometry: (@escaping (Geometry?) -> Void) -> Void
    private let readStyle: (Geometry, @escaping (Style) -> Void) -> Void
    private var generation = 0
    private var geometryRunning = false
    private var styleRunning = false
    private var pending: Request?
    private var pendingStyle: (Geometry, Request)?

    init(readGeometry: @escaping (@escaping (Geometry?) -> Void) -> Void,
         readStyle: @escaping (Geometry, @escaping (Style) -> Void) -> Void) {
        self.readGeometry = readGeometry; self.readStyle = readStyle
    }
    func request(geometry: @escaping (Geometry?) -> Void, style: @escaping (Style) -> Void) {
        generation += 1
        pending = Request(id: generation, geometry: geometry, style: style)
        pendingStyle = nil
        drainGeometry()
    }
    func cancel() { generation += 1; pending = nil; pendingStyle = nil }
    private func drainGeometry() {
        guard !geometryRunning, let request = pending else { return }
        pending = nil; geometryRunning = true
        readGeometry { [weak self] value in
            guard let self else { return }
            self.geometryRunning = false
            if request.id == self.generation {
                request.geometry(value)
                if let value, request.id == self.generation { self.pendingStyle = (value, request); self.drainStyle() }
            }
            self.drainGeometry()
        }
    }
    private func drainStyle() {
        guard !styleRunning, let (geometry, request) = pendingStyle else { return }
        pendingStyle = nil
        guard request.id == generation else { return }
        styleRunning = true
        readStyle(geometry) { [weak self] value in
            guard let self else { return }
            self.styleRunning = false
            if request.id == self.generation { request.style(value) }
            self.drainStyle()
        }
    }
}
