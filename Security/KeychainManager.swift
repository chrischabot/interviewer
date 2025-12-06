import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed
    case unexpectedError(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .readFailed(let status):
            return "Failed to read from Keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain: \(status)"
        case .dataConversionFailed:
            return "Failed to convert data"
        case .unexpectedError(let message):
            return message
        }
    }
}

actor KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.interviewer.app"
    private let apiKeyAccount = "openai_api_key"
    private let anthropicAccount = "anthropic_api_key"
    private var openAIKeyCache: String?
    private var anthropicKeyCache: String?

    private init() {}

    // MARK: - Prefetch both keys (minimize auth prompts)

    /// Load both keys in a single keychain query to avoid multiple authentication prompts.
    func loadAllKeys() throws -> (openAI: String?, anthropic: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            openAIKeyCache = nil
            anthropicKeyCache = nil
            return (nil, nil)
        }

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        var openAIKey: String?
        var anthropicKey: String?

        if let items = result as? [[String: Any]] {
            for item in items {
                guard
                    let account = item[kSecAttrAccount as String] as? String,
                    let data = item[kSecValueData as String] as? Data,
                    let key = String(data: data, encoding: .utf8)
                else { continue }

                if account == apiKeyAccount {
                    openAIKey = key
                } else if account == anthropicAccount {
                    anthropicKey = key
                }
            }
        }

        openAIKeyCache = openAIKey
        anthropicKeyCache = anthropicKey

        return (openAIKey, anthropicKey)
    }

    // MARK: - API Key Management

    func saveAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        // Delete existing key first
        try? deleteAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
        openAIKeyCache = key
    }

    func retrieveAPIKey() throws -> String? {
        if let cached = openAIKeyCache { return cached }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        openAIKeyCache = key
        return key
    }

    func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
        openAIKeyCache = nil
    }

    func hasAPIKey() async -> Bool {
        do {
            return try retrieveAPIKey() != nil
        } catch {
            return false
        }
    }

    // MARK: - Anthropic Key Management

    func saveAnthropicKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        try? deleteAnthropicKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: anthropicAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
        anthropicKeyCache = key
    }

    func retrieveAnthropicKey() throws -> String? {
        if let cached = anthropicKeyCache { return cached }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: anthropicAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }

        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        anthropicKeyCache = key
        return key
    }

    func deleteAnthropicKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: anthropicAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
        anthropicKeyCache = nil
    }

    func hasAnthropicKey() async -> Bool {
        do {
            return try retrieveAnthropicKey() != nil
        } catch {
            return false
        }
    }

    // MARK: - Cached accessors for callers that want “one prompt”

    func currentOpenAIKey() async throws -> String? {
        if let cached = openAIKeyCache { return cached }
        return try retrieveAPIKey()
    }

    func currentAnthropicKey() async throws -> String? {
        if let cached = anthropicKeyCache { return cached }
        return try retrieveAnthropicKey()
    }
}
