// KeychainManager.swift
// Secure credential storage using iOS Keychain.
// Credentials never touch UserDefaults, logs, or any third-party service.

import Foundation
import Security

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .encodingFailed:           return "Failed to encode credential data."
        case .saveFailed(let s):        return "Keychain save failed (OSStatus \(s))."
        case .readFailed(let s):        return "Keychain read failed (OSStatus \(s))."
        case .deleteFailed(let s):      return "Keychain delete failed (OSStatus \(s))."
        case .itemNotFound:             return "Credential not found in Keychain."
        }
    }
}

final class KeychainManager {

    // MARK: - Singleton
    static let shared = KeychainManager()
    private init() {}

    // MARK: - Key constants  (never change these — would invalidate stored creds)
    private enum Keys {
        static let accessKey  = "ultara.cloud.CloudSnooze.accessKeyId"
        static let secretKey  = "ultara.cloud.CloudSnooze.secretAccessKey"
        static let region     = "ultara.cloud.CloudSnooze.defaultRegion"
    }

    // MARK: - Public API

    /// Persist all three credential fields atomically.
    func saveCredentials(accessKey: String,
                         secretKey: String,
                         region: String) throws {
        try save(value: accessKey, forKey: Keys.accessKey)
        try save(value: secretKey, forKey: Keys.secretKey)
        try save(value: region,    forKey: Keys.region)
    }

    /// Retrieve stored credentials. Returns nil if not yet set.
    func loadCredentials() -> AWSCredentials? {
        guard
            let access = try? load(forKey: Keys.accessKey),
            let secret = try? load(forKey: Keys.secretKey),
            let region = try? load(forKey: Keys.region)
        else { return nil }
        return AWSCredentials(accessKeyId: access,
                              secretAccessKey: secret,
                              region: region)
    }

    /// Remove all stored credentials from the Keychain.
    func deleteCredentials() throws {
        try delete(forKey: Keys.accessKey)
        try delete(forKey: Keys.secretKey)
        try delete(forKey: Keys.region)
    }

    /// Returns true when credentials exist in the Keychain.
    var hasCredentials: Bool {
        loadCredentials() != nil
    }

    // MARK: - Private helpers

    private func save(value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete any existing item first (upsert pattern)
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:                 kSecClassGenericPassword,
            kSecAttrService:           key,
            kSecValueData:             data,
            kSecAttrAccessible:        kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func load(forKey key: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.encodingFailed
            }
            return string
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.readFailed(status)
        }
    }

    private func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Credential value type (never serialised, lives only in memory)

struct AWSCredentials {
    let accessKeyId:     String
    let secretAccessKey: String
    let region:          String
}
