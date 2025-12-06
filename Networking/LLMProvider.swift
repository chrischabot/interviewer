import Foundation

enum LLMProvider: String, CaseIterable, Sendable, Identifiable {
    case openAI

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
        // OpenAI only
        return LLMModelConfig(insightModel: "gpt-5.1", speedModel: "gpt-5-mini")
    }
}
