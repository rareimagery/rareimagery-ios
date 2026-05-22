import Foundation
import Security

public actor KeychainStore {
    public enum Failure: Error {
        case status(OSStatus)
        case notFound
        case encoding
    }

    public enum Key: String, Sendable {
        case accessToken = "ri.access_token"
        case refreshToken = "ri.refresh_token"
        case accessTokenExpiry = "ri.access_token_expiry"
    }

    private let service: String

    public init(service: String = "com.rareimagery.studio") {
        self.service = service
    }

    public func set(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else { throw Failure.encoding }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Failure.status(addStatus) }
        } else if status != errSecSuccess {
            throw Failure.status(status)
        }
    }

    public func get(_ key: Key) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.status(status)
        }
    }

    public func remove(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.status(status)
        }
    }

    public func clearAll() throws {
        for key in [Key.accessToken, .refreshToken, .accessTokenExpiry] {
            try remove(key)
        }
    }
}
