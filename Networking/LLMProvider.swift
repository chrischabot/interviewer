import Foundation

enum LLMProvider: String, CaseIterable, Sendable, Identifiable {
    case openAI
    case anthropic

    var id: String { rawValue }
}

struct LLMModelConfig: Sendable {
    let insightModel: String
    let speedModel: String
}

enum AgentModelProfile {
    case insight
    case speed
}

enum LLMModelResolver {
    static func config(for provider: LLMProvider) -> LLMModelConfig {
        switch provider {
        case .openAI:
            return LLMModelConfig(insightModel: "gpt-5.1", speedModel: "gpt-5-mini")
        case .anthropic:
            return LLMModelConfig(insightModel: "claude-opus-4-5", speedModel: "claude-sonnet-4-5")
        }
    }
}
