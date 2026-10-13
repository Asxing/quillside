import Foundation

struct ConnectionEditorState {
    var draft = ModelConnection()
    private(set) var editingID: UUID?
    private var initialized = false

    mutating func open(_ configuration: AIConfiguration) {
        guard !initialized else { return }
        initialized = true
        if let saved = configuration.connections.first(where: { $0.id == configuration.selectedConnectionID }) ?? configuration.connections.first { edit(saved) }
    }
    mutating func edit(_ connection: ModelConnection) { draft = connection; editingID = connection.id; initialized = true }
    mutating func create() { draft = ModelConnection(); editingID = nil; initialized = true }
    mutating func selectProtocol(_ api: ModelProtocol) {
        if draft.baseURL == draft.api.defaultURL { draft.baseURL = api.defaultURL }
        draft.api = api
    }
    mutating func reconcile(_ configuration: AIConfiguration) {
        guard let editingID, !configuration.connections.contains(where: { $0.id == editingID }) else { return }
        if let first = configuration.connections.first { edit(first) } else { create() }
    }
}
