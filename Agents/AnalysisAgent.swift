import Foundation

/// Response structure from the Analysis agent
struct AnalysisResponse: Codable {
    let researchGoal: String
    let mainClaims: [MainClaimResponse]
    let themes: [String]
    let tensions: [String]
    let quotes: [QuoteResponse]
    let suggestedTitle: String
    let suggestedSubtitle: String

    enum CodingKeys: String, CodingKey {
        case researchGoal = "research_goal"
        case mainClaims = "main_claims"
        case themes
        case tensions
        case quotes
        case suggestedTitle = "suggested_title"
        case suggestedSubtitle = "suggested_subtitle"
    }

    struct MainClaimResponse: Codable {
        let text: String
        let evidenceStoryIds: [String]

        enum CodingKeys: String, CodingKey {
            case text
            case evidenceStoryIds = "evidence_story_ids"
        }
    }

    struct QuoteResponse: Codable {
        let text: String
        let role: String

        enum CodingKeys: String, CodingKey {
            case text
            case role
        }
    }

    /// Convert to AnalysisSummary for app use
    func toAnalysisSummary() -> AnalysisSummary {
        AnalysisSummary(
            researchGoal: researchGoal,
            mainClaims: mainClaims.map { MainClaim(text: $0.text, evidenceStoryIds: $0.evidenceStoryIds) },
            themes: themes,
            tensions: tensions,
            quotes: quotes.map { Quote(text: $0.text, role: $0.role) },
            suggestedTitle: suggestedTitle,
            suggestedSubtitle: suggestedSubtitle
        )
    }
}

/// AnalysisAgent processes the complete interview transcript post-interview
/// to extract claims, themes, tensions, and quotable lines
actor AnalysisAgent {
    private let client: OpenAIClient
    private var lastActivityTime: Date?

    init(client: OpenAIClient = .shared) {
        self.client = client
    }

    /// Analyze the complete interview transcript
    func analyze(
        transcript: [TranscriptEntry],
        notes: NotesState,
        plan: PlanSnapshot
    ) async throws -> AnalysisSummary {
        lastActivityTime = Date()

        let wordCount = transcript.reduce(0) { $0 + $1.text.split(separator: " ").count }
        AgentLogger.analysisStarted(wordCount: wordCount)

        // Build full transcript
        let transcriptText = transcript.map { entry in
            let speaker = entry.speaker == "assistant" ? "Interviewer" : "Expert"
            return "[\(speaker)]: \(entry.text)"
        }.joined(separator: "\n\n")

        // Build notes summary
        let notesSummary = buildNotesSummary(notes)

        let userPrompt = """
        ## Interview Context

        **Topic:** \(plan.topic)
        **Research Goal:** \(plan.researchGoal)
        **Angle:** \(plan.angle)

        ## Notes from Live Interview
        \(notesSummary)

        ## Full Transcript
        \(transcriptText)

        ---

        Please analyze this interview and extract:

        1. **Research Goal Assessment**: How well did the interview answer the research goal? Summarize what we learned.

        2. **Main Claims**: The 3-5 most important assertions or insights from the expert. Each claim should be:
           - A complete, standalone statement
           - Backed by stories or evidence from the interview
           - Something that could form a section of an essay

        3. **Themes**: 3-5 recurring threads that weave through the conversation

        4. **Tensions**: Any interesting contradictions, trade-offs, or nuances the expert navigated

        5. **Quotable Lines**: 5-10 direct quotes that are:
           - Vivid, memorable, or surprising
           - Could serve as essay subheadings or pull quotes
           - Capture the expert's voice

        6. **Suggested Title & Subtitle**: A compelling essay title that captures the angle, plus a subtitle that adds context
        """

        let response = try await client.chatCompletion(
            messages: [
                Message.system(Self.systemPrompt),
                Message.user(userPrompt)
            ],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "analysis_schema", schema: Self.jsonSchema)
        )

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            AgentLogger.error(agent: "Analyst", message: "Invalid response from API")
            throw OpenAIError.invalidResponse
        }

        let analysisResponse = try JSONDecoder().decode(AnalysisResponse.self, from: data)
        let analysis = analysisResponse.toAnalysisSummary()

        AgentLogger.analysisComplete(
            claims: analysis.mainClaims.count,
            themes: analysis.themes,
            quotes: analysis.quotes.count,
            title: analysis.suggestedTitle
        )

        return analysis
    }

    /// Activity score for UI meters (0-1 based on recency)
    func getActivityScore() -> Double {
        guard let lastActivity = lastActivityTime else { return 0.0 }
        let elapsed = Date().timeIntervalSince(lastActivity)
        return max(0, 1.0 - (elapsed / 30.0))
    }

    // MARK: - Helpers

    private func buildNotesSummary(_ notes: NotesState) -> String {
        var parts: [String] = []

        if !notes.keyIdeas.isEmpty {
            parts.append("**Key Ideas:**\n" + notes.keyIdeas.map { "- \($0.text)" }.joined(separator: "\n"))
        }

        if !notes.stories.isEmpty {
            parts.append("**Stories:**\n" + notes.stories.map { "- \($0.summary) (Impact: \($0.impact))" }.joined(separator: "\n"))
        }

        if !notes.claims.isEmpty {
            parts.append("**Claims:**\n" + notes.claims.map { "- \($0.text) [confidence: \($0.confidence)]" }.joined(separator: "\n"))
        }

        if !notes.gaps.isEmpty {
            parts.append("**Gaps (unexplored):**\n" + notes.gaps.map { "- \($0.description)" }.joined(separator: "\n"))
        }

        if !notes.contradictions.isEmpty {
            parts.append("**Contradictions:**\n" + notes.contradictions.map { "- \($0.description)" }.joined(separator: "\n"))
        }

        if !notes.possibleTitles.isEmpty {
            parts.append("**Possible Titles (from live session):**\n" + notes.possibleTitles.map { "- \($0)" }.joined(separator: "\n"))
        }

        return parts.isEmpty ? "(No notes from live session)" : parts.joined(separator: "\n\n")
    }

    // MARK: - System Prompt

    static let systemPrompt = """
    You are an expert content analyst specializing in interview-based essays. Your job is to analyze a completed interview and extract the key elements needed to write a compelling narrative essay.

    **Your Analysis Philosophy:**

    Think like a magazine editor reviewing raw interview footage. You're looking for:

    1. **The Core Thesis** - What's the one big idea this expert is really saying? Even if they never stated it directly, what argument emerges from the conversation?

    2. **The Evidence** - What stories, examples, and data points support that thesis? These become the body of the essay.

    3. **The Tension** - Great essays aren't one-sided. Where does the expert acknowledge trade-offs, exceptions, or contrary views? This adds nuance and credibility.

    4. **The Voice** - What phrases, analogies, or turns of phrase capture how THIS expert thinks? These quotes bring the essay to life.

    **Guidelines:**

    - **Main Claims** should be essay-ready statements, not just topics. "Teams need psychological safety" is weak. "The moment a team member is afraid to admit a mistake, you've lost the ability to learn from it" is strong.

    - **Themes** are threads that recur throughout the conversation. They help organize the essay structure.

    - **Tensions** are where the interesting stuff lives. If the expert said "X is crucial" but also "sometimes X backfires," that's gold.

    - **Quotes** should be in the expert's exact words. Look for:
      - Origin stories ("It all started when...")
      - Turning points ("The moment I realized...")
      - Strong opinions ("I fundamentally believe...")
      - Vivid analogies ("It's like...")
      - Surprising admissions ("What most people don't know is...")

    - **Titles** should be specific and intriguing. "The Expert's Guide to X" is boring. "Why I Stopped Doing X After 10 Years" is better.
    """

    // MARK: - JSON Schema

    nonisolated(unsafe) static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "research_goal": [
                "type": "string",
                "description": "Summary of how well the interview answered the research goal"
            ],
            "main_claims": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "The claim as a complete, essay-ready statement"],
                        "evidence_story_ids": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "References to stories/examples that support this claim"
                        ]
                    ],
                    "required": ["text", "evidence_story_ids"],
                    "additionalProperties": false
                ]
            ],
            "themes": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Recurring threads in the conversation"
            ],
            "tensions": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Trade-offs, contradictions, or nuances the expert navigated"
            ],
            "quotes": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "The exact quote from the expert"],
                        "role": [
                            "type": "string",
                            "enum": ["origin", "turning_point", "opinion"],
                            "description": "The type of quote"
                        ]
                    ],
                    "required": ["text", "role"],
                    "additionalProperties": false
                ]
            ],
            "suggested_title": [
                "type": "string",
                "description": "A compelling essay title"
            ],
            "suggested_subtitle": [
                "type": "string",
                "description": "A subtitle that adds context"
            ]
        ],
        "required": ["research_goal", "main_claims", "themes", "tensions", "quotes", "suggested_title", "suggested_subtitle"],
        "additionalProperties": false
    ]
}
