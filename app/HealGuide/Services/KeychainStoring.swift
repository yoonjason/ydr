protocol KeychainStoring {
    func save(_ secret: String) throws
    func load() -> String?
    func delete()

    func saveClientID(_ clientID: String) throws
    func loadClientID() -> String?
    func deleteClientID()
}
