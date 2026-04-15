import Foundation
import Security
import os

final class KeychainWrapper: KeychainStoring {
    private let service: String
    private let account: String
    private let logger = Logger(subsystem: "com.yeongseok.healguide", category: "Keychain")

    init(service: String = "com.yeongseok.healguide", account: String = "client_secret") {
        self.service = service
        self.account = account
    }

    func save(_ secret: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw AppError.keychainError(errSecParam)
        }

        var item = baseQuery()
        item[kSecValueData] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateAttrs = [kSecValueData: data] as CFDictionary
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, updateAttrs)
            guard updateStatus == errSecSuccess else {
                throw AppError.keychainError(updateStatus)
            }
        } else if addStatus != errSecSuccess {
            throw AppError.keychainError(addStatus)
        }
    }

    func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        let query = baseQuery()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed: \(status)")
            return
        }
    }

    private func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
