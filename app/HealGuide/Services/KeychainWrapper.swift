import Foundation
import Security
import os

final class KeychainWrapper: KeychainStoring {
    private let service: String
    private let secretAccount: String
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "Keychain")

    init(service: String = "com.yeongseok.healguide", account: String = "client_secret") {
        self.service = service
        self.secretAccount = account
    }

    func save(_ secret: String) throws {
        try saveValue(secret, account: secretAccount)
    }

    func load() -> String? {
        loadValue(account: secretAccount)
    }

    func delete() {
        deleteValue(account: secretAccount)
    }

    func saveClientID(_ clientID: String) throws {
        try saveValue(clientID, account: "client_id")
    }

    func loadClientID() -> String? {
        loadValue(account: "client_id")
    }

    func deleteClientID() {
        deleteValue(account: "client_id")
    }

    private func saveValue(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AppError.keychainError(errSecParam)
        }

        var item = baseQuery(account: account)
        item[kSecValueData] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateAttrs = [kSecValueData: data] as CFDictionary
            let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, updateAttrs)
            guard updateStatus == errSecSuccess else {
                throw AppError.keychainError(updateStatus)
            }
        } else if addStatus != errSecSuccess {
            throw AppError.keychainError(addStatus)
        }
    }

    private func loadValue(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteValue(account: String) {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed for \(account): \(status)")
            return
        }
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
