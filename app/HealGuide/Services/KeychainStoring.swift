protocol KeychainStoring {
    func save(_ secret: String) throws
    func load() -> String?
    func delete()
}
