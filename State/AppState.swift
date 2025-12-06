import SwiftUI
import Observation
import AnthropicSwift

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
    var selectedProvider: LLMProvider?
    var openAIValid = false
    var anthropicValid = false
    var openAIError: String?
    var anthropicError: String?
    var openAIKeyCached: String?
    var anthropicKeyCached: String?

    // MARK: - Loading States

    var isLoading = false
    var loadingMessage: String?

    // MARK: - Analysis/Draft State (for passing between views)

    var selectedDraftStyle: DraftStyle = .standard
    var currentAnalysis: AnalysisSummary?

    private init() {
        Task {
            await bootstrapKeys()
        }
    }

    // MARK: - API Key Management & Provider Selection

    private func bootstrapKeys() async {
        isCheckingAPIKey = true
        defer { isCheckingAPIKey = false }

        // Load from keychain
        if let keys = try? await KeychainManager.shared.loadAllKeys() {
            openAIKeyCached = keys.openAI
            anthropicKeyCached = keys.anthropic
        }

        // If missing, try environment prefill
        if openAIKeyCached == nil, let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            try? await KeychainManager.shared.saveAPIKey(envKey)
            openAIKeyCached = envKey
        }
        if anthropicKeyCached == nil, let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            try? await KeychainManager.shared.saveAnthropicKey(envKey)
            anthropicKeyCached = envKey
        }

        await validateAvailableProviders()
        updateSelectionBasedOnValidity()
        await applyProviderToAgents()

        if !hasAPIKey {
            showSettings = true
        }
    }

    func saveAPIKey(_ key: String, provider: LLMProvider) async {
        switch provider {
        case .openAI:
            openAIError = nil
            do {
                try await KeychainManager.shared.saveAPIKey(key)
                openAIKeyCached = key
                openAIValid = try await OpenAIClient.shared.validateAPIKey()
            } catch {
                openAIValid = false
                openAIError = error.localizedDescription
            }
        case .anthropic:
            anthropicError = nil
            do {
                try await KeychainManager.shared.saveAnthropicKey(key)
                anthropicKeyCached = key
                anthropicValid = try await validateAnthropicKey(key: key)
            } catch {
                anthropicValid = false
                anthropicError = error.localizedDescription
            }
        }
        updateSelectionBasedOnValidity()
        await applyProviderToAgents()
    }

    func deleteAPIKey(provider: LLMProvider) async {
        switch provider {
        case .openAI:
            try? await KeychainManager.shared.deleteAPIKey()
            openAIKeyCached = nil
            openAIValid = false
        case .anthropic:
            try? await KeychainManager.shared.deleteAnthropicKey()
            anthropicKeyCached = nil
            anthropicValid = false
        }
        updateSelectionBasedOnValidity()
        await applyProviderToAgents()
        if !hasAPIKey { showSettings = true }
    }

    private func validateAvailableProviders() async {
        if let key = openAIKeyCached, !key.isEmpty {
            openAIValid = (try? await OpenAIClient.shared.validateAPIKey()) ?? false
        }
        if let key = anthropicKeyCached, !key.isEmpty {
            anthropicValid = (try? await validateAnthropicKey(key: key)) ?? false
        }
    }

    private func validateAnthropicKey(key: String) async throws -> Bool {
        let client = AnthropicClient(apiKey: key)
        do {
            _ = try await client.models.list()
            return true
        } catch {
            return false
        }
    }

    private func updateSelectionBasedOnValidity() {
        if openAIValid && anthropicValid {
            if selectedProvider == nil { selectedProvider = .openAI }
            hasAPIKey = true
        } else if openAIValid {
            selectedProvider = .openAI
            hasAPIKey = true
        } else if anthropicValid {
            selectedProvider = .anthropic
            hasAPIKey = true
        } else {
            selectedProvider = nil
            hasAPIKey = false
        }
    }

    func selectProvider(_ provider: LLMProvider) async {
        selectedProvider = provider
        await applyProviderToAgents()
    }

    private func applyProviderToAgents() async {
        guard let provider = selectedProvider else {
            hasAPIKey = false
            return
        }

        let modelConfig = LLMModelResolver.config(for: provider)
        switch provider {
        case .openAI:
            guard openAIValid else { hasAPIKey = false; return }
            let adapter = OpenAIAdapter()
            await AgentCoordinator.shared.updateLLM(client: adapter, modelConfig: modelConfig, provider: provider)
            hasAPIKey = true
        case .anthropic:
            guard anthropicValid, let key = anthropicKeyCached else { hasAPIKey = false; return }
            let adapter = AnthropicAdapter(apiKey: key)
            await AgentCoordinator.shared.updateLLM(client: adapter, modelConfig: modelConfig, provider: provider)
            hasAPIKey = true
        }
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
