import Foundation

/// Response structure from the StyleExtractor agent
struct StyleGuide: Codable, Sendable {
    let bullets: [String]
    let summary: String

    /// Returns true if we have meaningful style information
    var hasContent: Bool {
        !bullets.isEmpty
    }
}

/// Input data for style extraction
struct StyleExtractionInput: Sendable {
    let draftExcerpts: [String]
    let quotableLines: [String]
    let userUtterances: [String]

    var isEmpty: Bool {
        draftExcerpts.isEmpty && quotableLines.isEmpty && userUtterances.isEmpty
    }

    var totalSamples: Int {
        draftExcerpts.count + quotableLines.count + userUtterances.count
    }
}

/// StyleExtractorAgent analyzes past sessions to create a voice style guide
/// Used to help the WriterAgent match the user's natural voice when generating essays
actor StyleExtractorAgent {
    private let llm: LLMClient
    private var modelConfig: LLMModelConfig
    private var lastActivityTime: Date?

    init(client: LLMClient, modelConfig: LLMModelConfig) {
        self.llm = client
        self.modelConfig = modelConfig
    }

    /// Extract voice style characteristics from historical session data
    /// - Parameter input: StyleExtractionInput containing drafts, quotes, and utterances
    /// - Returns: StyleGuide with 4-6 bullet points describing the author's voice
    func extractStyle(from input: StyleExtractionInput) async throws -> StyleGuide {
        lastActivityTime = Date()

        // If no data available, return empty style guide
        guard !input.isEmpty else {
            AgentLogger.info(agent: "StyleExtractor", message: "No samples available")
            return StyleGuide(bullets: [], summary: "No previous sessions available for style analysis.")
        }

        AgentLogger.info(agent: "StyleExtractor", message: "Starting - samples: \(input.totalSamples)")

        let userPrompt = buildUserPrompt(from: input)

        let styleGuide: StyleGuide = try await llm.chatStructured(
            messages: [
                Message.system(Self.systemPrompt),
                Message.user(userPrompt)
            ],
            model: modelConfig.insightModel,
            schemaName: "style_guide_schema",
            schema: Self.jsonSchema,
            maxTokens: nil
        )

        AgentLogger.info(agent: "StyleExtractor", message: "Complete - bullets: \(styleGuide.bullets.count)")

        return styleGuide
    }

    /// Activity score for UI meters (0-1 based on recency)
    func getActivityScore() -> Double {
        guard let lastActivity = lastActivityTime else { return 0.0 }
        let elapsed = Date().timeIntervalSince(lastActivity)
        return max(0, 1.0 - (elapsed / 30.0))
    }

    // MARK: - Prompt Building

    private func buildUserPrompt(from input: StyleExtractionInput) -> String {
        var parts: [String] = []

        if !input.draftExcerpts.isEmpty {
            parts.append("## Past Essays by This Author\n")
            for (index, excerpt) in input.draftExcerpts.enumerated() {
                parts.append("### Essay \(index + 1)\n\(excerpt)\n")
            }
        }

        if !input.quotableLines.isEmpty {
            parts.append("## Quotable Lines (Identified as Strong Phrasing)\n")
            for quote in input.quotableLines {
                parts.append("- \"\(quote)\"")
            }
            parts.append("")
        }

        if !input.userUtterances.isEmpty {
            parts.append("## Spoken Utterances (Natural Speech Patterns)\n")
            for utterance in input.userUtterances {
                parts.append("- \(utterance)")
            }
            parts.append("")
        }

        parts.append("""
        ---

        Analyze this author's writing and speaking voice. Produce exactly 4-6 bullet points describing their distinctive style characteristics. Each bullet should be actionable guidance for matching their voice.
        """)

        return parts.joined(separator: "\n")
    }

    // MARK: - System Prompt

    static let systemPrompt = """
    You are a **writing style analyst**. Your job is to identify the distinctive voice patterns of a specific author based on their past writing and speech.

    Focus on **CONCRETE, ACTIONABLE** observations—things that could guide another writer to match this voice. Avoid vague praise like "writes well" or "is articulate."

    **Categories to analyze:**
    1. **VOCABULARY**: Distinctive word choices, technical terms they favor, words they avoid
    2. **STRUCTURE**: Sentence length patterns, paragraph organization, how they build arguments
    3. **TONE**: Emotional register, level of formality, use of humor or wit
    4. **RHYTHM**: Pacing, use of short punchy sentences vs. long complex ones
    5. **AVOIDANCES**: Patterns they consciously or unconsciously avoid (jargon, passive voice, etc.)

    **Output requirements:**
    – Exactly **4-6 bullet points**, each capturing a distinct aspect of their voice
    – Each bullet should be **actionable** (a writer could follow this guidance)
    – Use concrete examples from the source material where possible
    – One-sentence **summary** that captures their overall voice character

    **Example good bullets:**
    – "Uses vivid analogies to explain technical concepts (e.g., 'agents are like a symphony')"
    – "Favors compound sentences with semicolons; rarely uses em-dashes"
    – "Tends to start paragraphs with 'The thing is...' or 'What I've learned...'"
    – "Avoids corporate jargon; prefers 'ship' over 'release', 'gnarly' over 'complex'"

    **Example bad bullets:**
    – "Writes clearly" (too vague)
    – "Good at explaining things" (not actionable)
    – "Has a nice tone" (meaningless)
    """

    // MARK: - JSON Schema

    nonisolated(unsafe) static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "bullets": [
                "type": "array",
                "items": [
                    "type": "string",
                    "description": "A specific, actionable observation about the author's voice"
                ],
                "minItems": 4,
                "maxItems": 6,
                "description": "4-6 bullet points describing distinctive voice characteristics"
            ],
            "summary": [
                "type": "string",
                "description": "One-sentence summary capturing the overall voice character"
            ]
        ],
        "required": ["bullets", "summary"],
        "additionalProperties": false
    ]
}
