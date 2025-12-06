import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed

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
        }
    }
}

actor KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.interviewer.app"
    private let apiKeyAccount = "openai_api_key"
    private var openAIKeyCache: String?

    private init() {}

    // MARK: - API Key Management (OpenAI only)

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

    func currentOpenAIKey() async throws -> String? {
        if let cached = openAIKeyCache { return cached }
        return try retrieveAPIKey()
    }
}
