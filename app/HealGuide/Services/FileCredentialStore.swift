import Foundation
import os

// Keychain 이 서명 identity 변경으로 접근 불가해질 위험(로컬 dev 빌드)을
// 회피하기 위해 Application Support 하위 파일(0600)에 자격증명을 저장한다.
// 프로토콜명(KeychainStoring)은 유지 — 호출부에서 드롭인 교체 가능.
final class FileCredentialStore: KeychainStoring {
    private struct Credentials: Codable {
        var clientID: String?
        var clientSecret: String?
    }

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "FileCredStore")

    init(fileName: String = "credentials.json") {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("HealGuide", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.fileURL = dir.appendingPathComponent(fileName)
    }

    func save(_ secret: String) throws {
        var creds = loadCredentials()
        creds.clientSecret = secret
        try write(creds)
    }

    func load() -> String? {
        loadCredentials().clientSecret
    }

    func delete() {
        var creds = loadCredentials()
        creds.clientSecret = nil
        try? write(creds)
    }

    func saveClientID(_ clientID: String) throws {
        var creds = loadCredentials()
        creds.clientID = clientID
        try write(creds)
    }

    func loadClientID() -> String? {
        loadCredentials().clientID
    }

    func deleteClientID() {
        var creds = loadCredentials()
        creds.clientID = nil
        try? write(creds)
    }

    // MARK: - Private

    private func loadCredentials() -> Credentials {
        guard let data = try? Data(contentsOf: fileURL) else { return Credentials() }
        return (try? JSONDecoder().decode(Credentials.self, from: data)) ?? Credentials()
    }

    private func write(_ creds: Credentials) throws {
        let data = try JSONEncoder().encode(creds)
        try data.write(to: fileURL, options: [.atomic])
        // 권한 0600 — 사용자 본인만 읽기/쓰기
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
