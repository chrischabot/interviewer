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

    // MARK: - API Key State (OpenAI only)

    var hasAPIKey = false
    var isCheckingAPIKey = false
    var apiKeyError: String?
    var openAIValid = false
    var openAIError: String?
    var openAIKeyCached: String?

    // MARK: - Loading States

    var isLoading = false
    var loadingMessage: String?

    // MARK: - Analysis/Draft State (for passing between views)

    var selectedDraftStyle: DraftStyle = .standard
    var currentAnalysis: AnalysisSummary?

    // MARK: - YouTube Import State

    var showYouTubeImport = false
    var importedStyleGuide: StyleGuide?

    private init() {
        Task { await bootstrapKeys() }
    }

    // MARK: - API Key Management

    private func bootstrapKeys() async {
        isCheckingAPIKey = true
        defer { isCheckingAPIKey = false }

        // Load from keychain
        openAIKeyCached = try? await KeychainManager.shared.currentOpenAIKey()

        // If missing, try environment prefill
        if openAIKeyCached == nil,
           let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !envKey.isEmpty {
            try? await KeychainManager.shared.saveAPIKey(envKey)
            openAIKeyCached = envKey
        }

        await validateKey()
        await applyProviderToAgents()

        if !hasAPIKey { showSettings = true }
    }

    func saveAPIKey(_ key: String) async {
        openAIError = nil
        do {
            try await KeychainManager.shared.saveAPIKey(key)
            openAIKeyCached = key
            openAIValid = try await OpenAIClient.shared.validateAPIKey()
        } catch {
            openAIValid = false
            openAIError = error.localizedDescription
        }
        await applyProviderToAgents()
    }

    func deleteAPIKey() async {
        try? await KeychainManager.shared.deleteAPIKey()
        openAIKeyCached = nil
        openAIValid = false
        hasAPIKey = false
        showSettings = true
    }

    private func validateKey() async {
        if let key = openAIKeyCached, !key.isEmpty {
            openAIValid = (try? await OpenAIClient.shared.validateAPIKey()) ?? false
        } else {
            openAIValid = false
        }
    }

    private func applyProviderToAgents() async {
        let modelConfig = LLMModelResolver.config(for: .openAI)
        guard openAIValid else { hasAPIKey = false; return }
        let adapter = OpenAIAdapter()
        await AgentCoordinator.shared.updateLLM(client: adapter, modelConfig: modelConfig)
        hasAPIKey = true
    }

    // MARK: - Navigation helpers

    func navigate(to destination: NavigationDestination) {
        navigationPath.append(destination)
    }

    func navigateBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }

    func resetNavigation() {
        navigationPath = NavigationPath()
    }
}
