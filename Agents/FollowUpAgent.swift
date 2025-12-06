import Foundation

/// A snapshot of session data for thread-safe passing to actors
struct SessionSnapshot: Sendable {
    let id: UUID
    let utterances: [UtteranceSnapshot]
    let notes: NotesSnapshot?
}

struct UtteranceSnapshot: Sendable {
    let speaker: String
    let text: String
    let timestamp: Date
}

struct NotesSnapshot: Sendable {
    let keyIdeas: [String]
    let stories: [String]
    let claims: [String]
    let gaps: [GapSnapshot]
    let contradictions: [ContradictionSnapshot]
    let possibleTitles: [String]
    let sectionCoverage: [SectionCoverageSnapshot]
    let quotableLines: [QuotableLineSnapshot]
}

struct GapSnapshot: Sendable {
    let description: String
    let suggestedFollowup: String
}

struct ContradictionSnapshot: Sendable {
    let description: String
    let firstQuote: String
    let secondQuote: String
    let suggestedClarificationQuestion: String
}

struct SectionCoverageSnapshot: Sendable {
    let sectionId: String
    let sectionTitle: String
    let coverageQuality: String  // "none" | "shallow" | "adequate" | "deep"
    let missingAspects: [String]
}

struct QuotableLineSnapshot: Sendable {
    let text: String
    let potentialUse: String  // "hook" | "section_header" | "pull_quote" | "conclusion" | "tweet"
    let topic: String
    let strength: String  // "good" | "great" | "exceptional"
}

/// Response structure for follow-up analysis
struct FollowUpAnalysis: Codable {
    let summary: String  // Brief summary of what was covered
    let suggestedTopics: [FollowUpTopic]  // 3 topics to explore further
    let unexploredGaps: [String]  // Threads that were left unexplored
    let strengthenAreas: [String]  // Areas that could use more depth

    enum CodingKeys: String, CodingKey {
        case summary
        case suggestedTopics = "suggested_topics"
        case unexploredGaps = "unexplored_gaps"
        case strengthenAreas = "strengthen_areas"
    }
}

struct FollowUpTopic: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let questions: [String]  // 2-3 questions for this topic

    enum CodingKeys: String, CodingKey {
        case id, title, description, questions
    }
}

/// FollowUpAgent analyzes completed sessions to find opportunities for continuation
actor FollowUpAgent {
    private let llm: LLMClient
    private var modelConfig: LLMModelConfig

    init(client: LLMClient, modelConfig: LLMModelConfig) {
        self.llm = client
        self.modelConfig = modelConfig
    }

    private func log(_ message: String) {
        StructuredLogger.log(component: "FollowUp Agent", message: message)
    }

    /// Analyze a completed session and suggest follow-up topics
    func analyzeForFollowUp(
        session: SessionSnapshot,
        plan: PlanSnapshot
    ) async throws -> FollowUpAnalysis {
        log("Analyzing session for follow-up opportunities...")

        // Build transcript text
        let transcriptText = session.utterances
            .sorted { $0.timestamp < $1.timestamp }
            .map { utterance in
                let speaker = utterance.speaker == "assistant" ? "Interviewer" : "Author"
                return "[\(speaker)]: \(utterance.text)"
            }
            .joined(separator: "\n\n")

        // Build notes summary if available
        var notesSummary = ""
        if let notes = session.notes {
            notesSummary = buildNotesSummary(from: notes)
        }

        let systemPrompt = """
        You are an expert interview analyst. Your job is to review a completed interview session and identify opportunities for a meaningful follow-up conversation.

        Focus on finding:
        1. **Unexplored threads** - Topics that were mentioned but not fully explored
        2. **Gaps in the story** - Missing context, unexplained decisions, or skipped details
        3. **Areas to deepen** - Interesting points that deserve more examples or elaboration
        4. **New angles** - Fresh perspectives that emerged but weren't pursued

        The goal is to help the author add more depth and richness to their eventual essay. A good follow-up conversation should feel like a natural continuation, not a repeat.
        """

        let userPrompt = """
        ## Original Interview Plan

        **Topic:** \(plan.topic)
        **Research Goal:** \(plan.researchGoal)
        **Angle:** \(plan.angle)

        ## Session Transcript

        \(transcriptText)

        \(notesSummary.isEmpty ? "" : "## Notes from Session\n\n\(notesSummary)")

        ---

        Analyze this interview and suggest 3 compelling follow-up topics. Each topic should:
        - Feel like a natural extension, not a repeat
        - Add meaningful depth to the eventual essay
        - Include 2-3 specific questions to ask

        Be specific and actionable. Avoid vague suggestions like "explore more about X" - instead, identify the exact thread or gap.
        """

        let analysis: FollowUpAnalysis = try await llm.chatStructured(
            messages: [
                Message.system(systemPrompt),
                Message.user(userPrompt)
            ],
            model: modelConfig.insightModel,
            schemaName: "followup_analysis",
            schema: Self.jsonSchema,
            maxTokens: nil
        )

        log("Found \(analysis.suggestedTopics.count) follow-up topics")

        return analysis
    }

    private func buildNotesSummary(from notes: NotesSnapshot) -> String {
        var parts: [String] = []

        if !notes.keyIdeas.isEmpty {
            parts.append("**Key Ideas:** " + notes.keyIdeas.joined(separator: "; "))
        }

        if !notes.stories.isEmpty {
            parts.append("**Stories Captured:** " + notes.stories.joined(separator: "; "))
        }

        if !notes.claims.isEmpty {
            parts.append("**Claims Made:** " + notes.claims.joined(separator: "; "))
        }

        if !notes.gaps.isEmpty {
            let gapTexts = notes.gaps.map { "\($0.description) → \($0.suggestedFollowup)" }
            parts.append("**Identified Gaps:**\n" + gapTexts.map { "• \($0)" }.joined(separator: "\n"))
        }

        if !notes.contradictions.isEmpty {
            let contradictionTexts = notes.contradictions.map { $0.description }
            parts.append("**Contradictions:** " + contradictionTexts.joined(separator: "; "))
        }

        // Section coverage - critical for identifying undercovered areas
        if !notes.sectionCoverage.isEmpty {
            let coverageSummary = notes.sectionCoverage.map { coverage in
                let missing = coverage.missingAspects.isEmpty ? "" : " (missing: \(coverage.missingAspects.joined(separator: ", ")))"
                return "\(coverage.sectionTitle): \(coverage.coverageQuality)\(missing)"
            }
            parts.append("**Section Coverage:**\n" + coverageSummary.map { "• \($0)" }.joined(separator: "\n"))
        }

        // Quotable lines - helps identify what resonated
        if !notes.quotableLines.isEmpty {
            let exceptional = notes.quotableLines.filter { $0.strength == "exceptional" }
            if !exceptional.isEmpty {
                let quotes = exceptional.prefix(3).map { "\"\($0.text)\" (\($0.topic))" }
                parts.append("**Best Quotes:**\n" + quotes.map { "• \($0)" }.joined(separator: "\n"))
            }
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - JSON Schema

    nonisolated(unsafe) static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": [
                "type": "string",
                "description": "2-3 sentence summary of what the original interview covered"
            ],
            "suggested_topics": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "Unique identifier for this topic"
                        ],
                        "title": [
                            "type": "string",
                            "description": "Short, compelling title for the follow-up topic (3-6 words)"
                        ],
                        "description": [
                            "type": "string",
                            "description": "1-2 sentence description of what to explore"
                        ],
                        "questions": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "2-3 specific questions to ask about this topic"
                        ]
                    ],
                    "required": ["id", "title", "description", "questions"],
                    "additionalProperties": false
                ],
                "minItems": 3,
                "maxItems": 3,
                "description": "Exactly 3 follow-up topics to explore"
            ],
            "unexplored_gaps": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Threads or topics that were mentioned but not fully explored"
            ],
            "strengthen_areas": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Areas that could benefit from more examples or depth"
            ]
        ],
        "required": ["summary", "suggested_topics", "unexplored_gaps", "strengthen_areas"],
        "additionalProperties": false
    ]
}
