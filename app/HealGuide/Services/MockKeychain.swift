import Security

final class MockKeychain: KeychainStoring {
    var stored: String?
    var shouldThrowOnSave: Bool = false

    func save(_ secret: String) throws {
        if shouldThrowOnSave { throw AppError.keychainError(errSecInvalidData) }
        stored = secret
    }

    func load() -> String? {
        stored
    }

    func delete() {
        stored = nil
    }
}
