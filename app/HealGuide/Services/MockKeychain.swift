import Security

final class MockKeychain: KeychainStoring {
    var stored: String?
    var storedClientID: String?
    var shouldThrowOnSave: Bool = false

    func save(_ secret: String) throws {
        if shouldThrowOnSave { throw AppError.keychainError(errSecInvalidData) }
        stored = secret
    }

    func load() -> String? { stored }

    func delete() { stored = nil }

    func saveClientID(_ clientID: String) throws {
        if shouldThrowOnSave { throw AppError.keychainError(errSecInvalidData) }
        storedClientID = clientID
    }

    func loadClientID() -> String? { storedClientID }

    func deleteClientID() { storedClientID = nil }
}
