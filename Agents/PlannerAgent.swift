import Foundation

/// Response structure from the Planner agent (Codable for JSON decoding)
struct PlannerResponse: Codable {
    let researchGoal: String
    let angle: String
    let sections: [PlannerSection]

    enum CodingKeys: String, CodingKey {
        case researchGoal = "research_goal"
        case angle
        case sections
    }
}

struct PlannerSection: Codable {
    let title: String
    let importance: String
    let estimatedSeconds: Int
    let questions: [PlannerQuestion]

    enum CodingKeys: String, CodingKey {
        case title
        case importance
        case estimatedSeconds = "estimated_seconds"
        case questions
    }
}

struct PlannerQuestion: Codable {
    let text: String
    let role: String
    let priority: Int
    let notesForInterviewer: String

    enum CodingKeys: String, CodingKey {
        case text
        case role
        case priority
        case notesForInterviewer = "notes_for_interviewer"
    }
}

/// PlannerAgent generates interview plans from topic + context
actor PlannerAgent {
    private let client: OpenAIClient
    private var lastActivityTime: Date?

    init(client: OpenAIClient = .shared) {
        self.client = client
    }

    /// Generate an interview plan from topic, context, and target duration
    func generatePlan(topic: String, context: String, targetMinutes: Int) async throws -> PlannerResponse {
        lastActivityTime = Date()

        AgentLogger.plannerStarted(topic: topic, duration: targetMinutes)

        let userPrompt = """
        Topic: \(topic)
        Context: \(context.isEmpty ? "None provided" : context)
        Target duration: \(targetMinutes) minutes
        """

        let response = try await client.chatCompletion(
            messages: [
                Message.system(Self.systemPrompt),
                Message.user(userPrompt)
            ],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "plan_schema", schema: Self.jsonSchema)
        )

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            AgentLogger.error(agent: "Planner", message: "Invalid response from API")
            throw OpenAIError.invalidResponse
        }

        let plan = try JSONDecoder().decode(PlannerResponse.self, from: data)
        let totalQuestions = plan.sections.reduce(0) { $0 + $1.questions.count }

        AgentLogger.plannerComplete(sections: plan.sections.count, questions: totalQuestions, angle: plan.angle)

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
    You are a **senior narrative designer and interviewer**.
    Your job is to design interview rubrics that help a subject-matter expert talk their way into a **killer essay**, not a social-science report.

    The user will provide:
    – A topic they want to talk about.
    – Optional free-form notes or constraints.
    – A target duration in minutes.

    Your output is a **plan** for a voice interview that:
    – Has a clearly articulated **research goal** (what this piece is trying to understand or argue).
    – Proposes a sharp **angle** (why this will be interesting to read).
    – Is structured as 3–6 **sections** that feel like a good story arc.
    – Contains both **backbone questions** that must be hit and more flexible **follow-up questions** for tangents.
    – Fits roughly within the time budget.

    **Anthropic-style learnings to incorporate:**
    – Start from a **research goal**: what we're trying to learn or clarify, not just the topic.
    – Encode **hypotheses** or expectations where relevant, so the interviewer knows what to probe or challenge.
    – Maintain a balance between **consistency** (backbone questions) and **flexibility** (room for tangents).
    – Assume a **human-in-the-loop review**: your plan will be shown in a UI where the expert can edit.
    – Prefer questions that elicit **stories, failures, trade-offs, and strong opinions**.

    **Time allocation guidance:**
    – Opening/context: ~15-20% of time
    – Deep dive sections: ~60-70% of time
    – Wrap-up/reflection: ~15-20% of time
    – Each backbone question typically takes 1-2 minutes to answer
    – Follow-up questions are shorter, ~30 seconds each

    **Question guidelines:**
    – Backbone questions are essential and must be asked
    – Follow-up questions are optional probes based on how the conversation develops
    – Priority 1 = must-hit, Priority 2 = important, Priority 3 = nice-to-have
    – Notes for interviewer should include what to listen for or how to probe deeper
    """

    // MARK: - JSON Schema

    nonisolated(unsafe) static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "research_goal": [
                "type": "string",
                "description": "The core question or thesis this interview is trying to explore or validate"
            ],
            "angle": [
                "type": "string",
                "description": "The unique perspective or hook that makes this interesting to readers"
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
                        "importance": [
                            "type": "string",
                            "enum": ["high", "medium", "low"],
                            "description": "How critical this section is to the overall narrative"
                        ],
                        "estimated_seconds": [
                            "type": "integer",
                            "description": "Estimated time for this section in seconds"
                        ],
                        "questions": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "text": [
                                        "type": "string",
                                        "description": "The question to ask"
                                    ],
                                    "role": [
                                        "type": "string",
                                        "enum": ["backbone", "followup"],
                                        "description": "Whether this is a must-ask backbone question or optional follow-up"
                                    ],
                                    "priority": [
                                        "type": "integer",
                                        "description": "1 = must-hit, 2 = important, 3 = nice-to-have"
                                    ],
                                    "notes_for_interviewer": [
                                        "type": "string",
                                        "description": "Guidance on what to listen for or how to probe"
                                    ]
                                ],
                                "required": ["text", "role", "priority", "notes_for_interviewer"],
                                "additionalProperties": false
                            ]
                        ]
                    ],
                    "required": ["title", "importance", "estimated_seconds", "questions"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["research_goal", "angle", "sections"],
        "additionalProperties": false
    ]
}
