import Foundation
import Security

nonisolated enum ConfigurationVault {
    static var repository: SubscriptionRepository { .init(storage: KeychainSubscriptionStorage()) }
    static func load() throws -> Data? { try loadRecord()?.source }
    static func loadRecord() throws -> StoredConfiguration? { try repository.activeRecord() }
}

nonisolated struct KeychainSubscriptionStorage: SubscriptionStorage {
    func keys() throws -> [String] {
        var request = try query("")
        request.removeValue(forKey: kSecAttrAccount as String)
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitAll
        var items: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &items)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = items as? [[String: Any]] else { throw PrototypeError.keychain }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
    private func query(_ key: String) throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String,
              !group.isEmpty, !group.contains("$(") else { throw PrototypeError.keychain }
        var attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Kenote.Clash.prototype",
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: group,
            kSecAttrSynchronizable as String: false]
        #if os(macOS)
        // Access groups are enforced by the Data Protection Keychain on native Mac.
        attributes[kSecUseDataProtectionKeychain as String] = true
        #endif
        return attributes
    }
    func read(_ key: String) throws -> Data? {
        var request = try query(key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw PrototypeError.keychain }
        return data
    }
    func write(_ data: Data, for key: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let base = try query(key)
        var status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(base.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw PrototypeError.keychain }
    }
    func remove(_ key: String) throws {
        let status = SecItemDelete(try query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PrototypeError.keychain }
    }
}
