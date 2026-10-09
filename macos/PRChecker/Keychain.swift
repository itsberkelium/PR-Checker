import Foundation
import Security

/// Where access tokens are kept. Abstracted so failures can be tested.
protocol TokenStore {
    func read(account: String) -> String?
    func save(_ token: String, account: String) throws
    func delete(account: String) throws
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
        return L10n.keychainSaveFailed(detail: detail)
    }
}

/// Generic-password items in the login keychain, one per server.
struct Keychain: TokenStore {
    private static let service = "dev.berke.PRChecker"
    /// Before tokens were scoped per server there was one item under this account.
    static let legacyAccount = "bitbucket-access-token"

    static func account(for server: ServerAddress) -> String {
        "token:\(server.id)"
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }

    func read(account: String) -> String? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Updates the item in place, adding it only when missing, so a failed write
    /// never leaves the previous token deleted.
    func save(_ token: String, account: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query(account: account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query(account: account)
            item[kSecValueData as String] = data
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        default:
            throw KeychainError(status: status)
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
