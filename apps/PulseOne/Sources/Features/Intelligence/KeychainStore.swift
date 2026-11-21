import Foundation
import Security

/// Where the Anthropic API key lives. The real store is the Keychain; UI tests use memory only.
protocol SecretStore: Sendable {
    func read() -> String?
    func save(_ secret: String) throws
    func delete()
}

struct KeychainError: Error, Equatable {
    let status: OSStatus
}

/// Keychain entry for the API key (spec §2): generic password, this device only, never synced to
/// iCloud, readable only while the iPhone is unlocked. The key is never logged or exported.
struct KeychainStore: SecretStore {
    let service = "de.sommerlabs.pulseone.anthropic"
    let account = "api-key"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ secret: String) throws {
        delete()
        var q = query
        q[kSecValueData as String] = Data(secret.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// Test scenarios: a fake key in memory, never a real call.
final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(_ value: String? = nil) { self.value = value }

    func read() -> String? { lock.withLock { value } }
    func save(_ secret: String) throws { lock.withLock { value = secret } }
    func delete() { lock.withLock { value = nil } }
}

extension String {
    /// "sk-ant-…1234" for display; the key itself is never shown in full again.
    var maskedKey: String {
        guard count > 12 else { return "••••" }
        return String(prefix(7)) + "…" + String(suffix(4))
    }
}
