import Foundation
import Testing
@testable import Quillside

@MainActor @Suite(.serialized) struct ConfigurationPersistenceTests {
    @Test func editingExistingConnectionKeepsIdentityCredentialAndDefaultAfterRestart() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vault = Vault(); let old = try initial(url, vault)
        let store = ConfigurationStore(url: url, credentials: vault.access)
        var editor = ConnectionEditorState(); editor.open(store.committed)
        #expect(editor.editingID == old.id)
        editor.draft.name = "Renamed"; editor.draft.model = "replacement-model"; editor.draft.maxOutputTokens = 8192
        editor.edit(try store.saveConnection(editor.draft, newKey: ""))
        let reopened = ConfigurationStore(url: url, credentials: vault.access)
        #expect(reopened.committed.connections.count == 1)
        #expect(reopened.selectedConnection?.id == old.id)
        #expect(reopened.selectedConnection?.model == "replacement-model")
        #expect(reopened.selectedConnection?.keychainID == old.keychainID)
        #expect(vault.values[old.keychainID] == "old-secret")
        editor.create(); #expect(editor.editingID == nil); #expect(editor.draft.id != old.id)
        editor.edit(old); #expect(editor.draft == old)
    }
    @Test func loadingSavedProtocolDoesNotRewriteItsCustomEndpoint() {
        var editor = ConnectionEditorState()
        let saved = ModelConnection(name: "Proxy", api: .responses, baseURL: ModelProtocol.chatCompletions.defaultURL, model: "model")
        editor.edit(saved)
        #expect(editor.draft.baseURL == saved.baseURL)
        editor.selectProtocol(.ollama)
        #expect(editor.draft.api == .ollama)
    }
    private final class Vault {
        var values: [UUID: String] = [:]
        var failCleanup = false
        var access: CredentialAccess {
            .init(read: { self.values[$0] ?? "" }, write: { self.values[$1] = $0 }, remove: {
                if self.failCleanup { throw AIError.message("synthetic cleanup failure") }
                self.values.removeValue(forKey: $0)
            })
        }
    }
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Quillside-config-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("settings.json")
    }
    private func initial(_ url: URL, _ vault: Vault) throws -> ModelConnection {
        let connection = ModelConnection(name: "old", baseURL: "https://old.example/v1", model: "fixture")
        var config = AIConfiguration(); config.connections = [connection]; config.selectedConnectionID = connection.id
        try AppFiles.save(config, to: url); vault.values[connection.keychainID] = "old-secret"
        return connection
    }

    @Test func failedEndpointSaveKeepsOldCredentialAndRestartConfiguration() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vault = Vault(); let old = try initial(url, vault)
        let before = try Data(contentsOf: url)
        let store = ConfigurationStore(url: url, credentials: vault.access, persist: { _, _ in throw AIError.message("disk full") })
        var draft = old; draft.baseURL = "https://new.example/v1"
        #expect(throws: AIError.self) { try store.saveConnection(draft, newKey: "new-secret") }
        #expect(try Data(contentsOf: url) == before)
        #expect(vault.values == [old.keychainID: "old-secret"])
        #expect(store.selectedConnection == old)
        let restarted = ConfigurationStore(url: url, credentials: vault.access)
        #expect(restarted.selectedConnection == old)
        #expect(try vault.access.read(restarted.selectedConnection!.keychainID) == "old-secret")
    }
    @Test func successfulRotationNeverReusesOldCredentialReference() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vault = Vault(); let old = try initial(url, vault)
        let store = ConfigurationStore(url: url, credentials: vault.access)
        var draft = old; draft.baseURL = "https://new.example/v1"
        vault.failCleanup = true
        let saved = try store.saveConnection(draft, newKey: "new-secret")
        #expect(saved.id == old.id)
        #expect(saved.keychainID != old.keychainID)
        #expect(vault.values[saved.keychainID] == "new-secret")
        #expect(vault.values[old.keychainID] == "old-secret")
        let restarted = ConfigurationStore(url: url, credentials: vault.access)
        #expect(restarted.selectedConnection?.keychainID == saved.keychainID)
        #expect(restarted.selectedConnection?.baseURL == "https://new.example/v1")
    }
    @Test func failedDeleteAndClearDoNotRemoveWorkingSecret() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vault = Vault(); let old = try initial(url, vault)
        let store = ConfigurationStore(url: url, credentials: vault.access, persist: { _, _ in throw AIError.message("disk full") })
        #expect(throws: AIError.self) { try store.deleteConnection(old.id) }
        #expect(throws: AIError.self) { try store.clearCredential(old.id) }
        #expect(store.selectedConnection == old)
        #expect(vault.values == [old.keychainID: "old-secret"])
    }
    @Test func unreadableConfigurationCannotBeOverwrittenByOrdinarySave() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = Data("{broken-user-configuration".utf8); try original.write(to: url)
        let vault = Vault(); let store = ConfigurationStore(url: url, credentials: vault.access)
        #expect(store.loadFailed)
        store.value.systemPrompt = "changed"
        #expect(throws: AIError.self) { try store.save() }
        #expect(try Data(contentsOf: url) == original)
        var incoming = AIConfiguration(); let connection = ModelConnection(model: "fixture", credentialID: UUID())
        incoming.connections = [connection]; incoming.selectedConnectionID = connection.id
        try store.importConfiguration(incoming)
        #expect(!store.loadFailed)
        #expect(store.selectedConnection?.keychainID != connection.keychainID)
        let backups = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("settings-unreadable-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: #require(backups.first)) == original)
    }
    @Test func unsavedUIEditsAreNotUsedForGenerationAndFailureRollsThemBack() throws {
        let url = try temporaryURL(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let vault = Vault(); let old = try initial(url, vault)
        let store = ConfigurationStore(url: url, credentials: vault.access, persist: { _, _ in throw AIError.message("disk full") })
        store.value.connections[0].baseURL = "https://unsaved.example"
        #expect(store.selectedConnection == old)
        #expect(throws: AIError.self) { try store.save() }
        #expect(store.value.connections[0] == old)
    }
}
