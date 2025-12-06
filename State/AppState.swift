import SwiftUI
import Observation

// MARK: - Navigation State

enum NavigationDestination: Hashable {
    case home
    case planning(planId: UUID)
    case interview(planId: UUID)
    case analysis(sessionId: UUID)
    case draft(sessionId: UUID)
    case followUp(sessionId: UUID)  // Continue a previous session
    case settings
}

// MARK: - App State

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    // MARK: - Navigation

    var navigationPath = NavigationPath()
    var showSettings = false

    // MARK: - API Key State

    var hasAPIKey = false
    var isCheckingAPIKey = false
    var apiKeyError: String?

    // MARK: - Loading States

    var isLoading = false
    var loadingMessage: String?

    // MARK: - Analysis/Draft State (for passing between views)

    var selectedDraftStyle: DraftStyle = .standard
    var currentAnalysis: AnalysisSummary?

    private init() {
        Task {
            await checkAPIKey()
        }
    }

    // MARK: - API Key Management

    func checkAPIKey() async {
        isCheckingAPIKey = true
        hasAPIKey = await KeychainManager.shared.hasAPIKey()
        isCheckingAPIKey = false

        // Show settings if no API key
        if !hasAPIKey {
            showSettings = true
        }
    }

    func saveAPIKey(_ key: String) async throws {
        apiKeyError = nil

        // Validate the key first
        try await KeychainManager.shared.saveAPIKey(key)

        do {
            let isValid = try await OpenAIClient.shared.validateAPIKey()
            if isValid {
                hasAPIKey = true
                showSettings = false
            } else {
                try await KeychainManager.shared.deleteAPIKey()
                apiKeyError = "Invalid API key. Please check and try again."
                hasAPIKey = false
            }
        } catch {
            try? await KeychainManager.shared.deleteAPIKey()
            apiKeyError = "Failed to validate API key: \(error.localizedDescription)"
            hasAPIKey = false
            throw error
        }
    }

    func deleteAPIKey() async throws {
        try await KeychainManager.shared.deleteAPIKey()
        hasAPIKey = false
        showSettings = true
    }

    func getAPIKey() async -> String? {
        try? await KeychainManager.shared.retrieveAPIKey()
    }

    // MARK: - Navigation Helpers

    func navigate(to destination: NavigationDestination) {
        navigationPath.append(destination)
    }

    func navigateTo(_ destination: NavigationDestination) {
        navigationPath.append(destination)
    }

    func navigateBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }

    func popNavigation() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }

    func resetNavigation() {
        navigationPath = NavigationPath()
    }

    // MARK: - Loading Helpers

    func setLoading(_ loading: Bool, message: String? = nil) {
        isLoading = loading
        loadingMessage = message
    }
}
