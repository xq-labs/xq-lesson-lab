import Foundation
import Security

/// The macOS Keychain, for the one secret this app handles: a teacher's own
/// API key for off-device reviews.
///
/// Deliberately the only place a key is ever written. It is never held in a
/// `@Published` property, never in `PersistedState`, never in `UserDefaults`,
/// and never in the audit log — it is read at send time into a local `String`,
/// used once, and dropped.
enum Keychain {

    struct Item {
        var service: String
        var account: String
    }

    enum Failure: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let code):
                let message = SecCopyErrorMessageString(code, nil) as String?
                return message ?? "Keychain error \(code)."
            }
        }
    }

    /// The file-based keychain, not the data-protection one.
    ///
    /// `kSecUseDataProtectionKeychain: true` looks like the modern default and
    /// is wrong here: it requires a `keychain-access-groups` entitlement, and
    /// this app is not sandboxed and ships no entitlements file. Every call
    /// fails with `errSecMissingEntitlement` (-34018) — including from a
    /// `swift run` binary and from an ad-hoc-signed `.app`. The file-based
    /// keychain is the right home for a non-sandboxed Mac app.
    ///
    /// The "this Mac" promise still holds, from two things:
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` on write, and the fact
    /// that a file-based item never syncs to iCloud unless it asks to with
    /// `kSecAttrSynchronizable` — which nothing here does.
    private static func baseQuery(_ item: Item) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: item.service,
         kSecAttrAccount as String: item.account]
    }

    static func store(_ secret: String, in item: Item) throws {
        let data = Data(secret.utf8)
        var query = baseQuery(item)

        // Update in place when something is already there; SecItemAdd would
        // fail with errSecDuplicateItem and lose the new key.
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw Failure.status(updateStatus) }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Failure.status(addStatus) }
    }

    static func read(_ item: Item) -> String? {
        var query = baseQuery(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ item: Item) throws {
        let status = SecItemDelete(baseQuery(item) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.status(status)
        }
    }

    static func exists(_ item: Item) -> Bool {
        var query = baseQuery(item)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
