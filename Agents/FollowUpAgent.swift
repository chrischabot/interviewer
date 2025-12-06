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
    let gaps: [String]
    let contradictions: [String]
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
    private let client: OpenAIClient

    init(client: OpenAIClient = .shared) {
        self.client = client
    }

    /// Analyze a completed session and suggest follow-up topics
    func analyzeForFollowUp(
        session: SessionSnapshot,
        plan: PlanSnapshot
    ) async throws -> FollowUpAnalysis {
        NSLog("[FollowUpAgent] 🔍 Analyzing session for follow-up opportunities...")

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

        let response = try await client.chatCompletion(
            messages: [
                Message.system(systemPrompt),
                Message.user(userPrompt)
            ],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "followup_analysis", schema: Self.jsonSchema)
        )

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            throw OpenAIError.invalidResponse
        }

        let analysis = try JSONDecoder().decode(FollowUpAnalysis.self, from: data)

        NSLog("[FollowUpAgent] ✅ Found %d follow-up topics", analysis.suggestedTopics.count)

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

        if !notes.gaps.isEmpty {
            parts.append("**Identified Gaps:** " + notes.gaps.joined(separator: "; "))
        }

        if !notes.contradictions.isEmpty {
            parts.append("**Contradictions:** " + notes.contradictions.joined(separator: "; "))
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
