import Foundation

/// Response structure from the ReversePlanner agent (generates plan from existing transcript)
struct ReversePlanResponse: Codable {
    let topic: String
    let researchGoal: String
    let angle: String
    let sections: [ReversePlanSection]

    enum CodingKeys: String, CodingKey {
        case topic
        case researchGoal = "research_goal"
        case angle
        case sections
    }
}

struct ReversePlanSection: Codable {
    let title: String
    let summary: String
    let keyPoints: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case summary
        case keyPoints = "key_points"
    }
}

/// ReversePlannerAgent analyzes a transcript to generate a retroactive "plan"
/// describing what was discussed. Used for imported content (YouTube videos, etc.)
actor ReversePlannerAgent {
    private let llm: LLMClient
    private var modelConfig: LLMModelConfig
    private var lastActivityTime: Date?

    init(client: LLMClient, modelConfig: LLMModelConfig) {
        self.llm = client
        self.modelConfig = modelConfig
    }

    /// Generate a plan by analyzing what was discussed in a transcript
    /// - Parameter transcript: The full transcript text
    /// - Returns: A ReversePlanResponse with inferred topic, goal, angle, and sections
    func generatePlan(from transcript: String) async throws -> ReversePlanResponse {
        lastActivityTime = Date()

        AgentLogger.info(agent: "ReversePlanner", message: "Starting - transcript length: \(transcript.count) chars")

        let userPrompt = """
        ## Transcript

        \(transcript)

        ---

        Analyze this transcript and extract:
        1. The main **topic** being discussed
        2. The apparent **research goal** or thesis
        3. A compelling **angle** that captures what's interesting
        4. The **sections** or distinct themes covered (3-5 sections)

        For each section, identify the key points made.
        """

        let plan: ReversePlanResponse = try await llm.chatStructured(
            messages: [
                Message.system(Self.systemPrompt),
                Message.user(userPrompt)
            ],
            model: modelConfig.insightModel,
            schemaName: "reverse_plan_schema",
            schema: Self.jsonSchema,
            maxTokens: nil
        )

        AgentLogger.info(agent: "ReversePlanner", message: "Complete - topic: \(plan.topic), sections: \(plan.sections.count)")

        return plan
    }

    /// Activity score for UI meters (0-1 based on recency)
    func getActivityScore() -> Double {
        guard let lastActivity = lastActivityTime else { return 0.0 }
        let elapsed = Date().timeIntervalSince(lastActivity)
        return max(0, 1.0 - (elapsed / 30.0))
    }

    // MARK: - System Prompt

    static let systemPrompt = """
    You are a **content analyst** reviewing a transcript to understand its structure and themes.

    Your job is to reverse-engineer a "plan" from content that was already created:
    – Identify the main **topic** being discussed.
    – Infer the **research goal** or core question the speaker is exploring.
    – Propose a compelling **angle** that captures why this content is interesting.
    – Break the content into **sections** that represent distinct themes or phases.

    **Guidelines:**
    – The topic should be specific, not generic (e.g., "Building AI agents in Swift" not "Technology").
    – The research goal should capture what the speaker is trying to understand, argue, or teach.
    – The angle should be the "hook" - what makes this worth reading.
    – Sections should follow the natural flow of the content, not impose an artificial structure.
    – Each section should have a clear title, brief summary, and 2-4 key points.

    **Think like a magazine editor** reviewing a transcript to decide how to structure an essay.
    """

    // MARK: - JSON Schema

    nonisolated(unsafe) static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "topic": [
                "type": "string",
                "description": "The main topic or subject being discussed"
            ],
            "research_goal": [
                "type": "string",
                "description": "The core question, thesis, or goal the speaker is exploring"
            ],
            "angle": [
                "type": "string",
                "description": "The unique perspective or hook that makes this interesting"
            ],
            "sections": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "Section title/theme"
                        ],
                        "summary": [
                            "type": "string",
                            "description": "Brief summary of what this section covers"
                        ],
                        "key_points": [
                            "type": "array",
                            "items": [
                                "type": "string"
                            ],
                            "description": "2-4 key points made in this section"
                        ]
                    ],
                    "required": ["title", "summary", "key_points"],
                    "additionalProperties": false
                ],
                "minItems": 3,
                "maxItems": 6
            ]
        ],
        "required": ["topic", "research_goal", "angle", "sections"],
        "additionalProperties": false
    ]
}
