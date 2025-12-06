import Foundation

/// Response structure from the NoteTaker agent
struct NoteTakerResponse: Codable {
    let keyIdeas: [KeyIdeaResponse]
    let stories: [StoryResponse]
    let claims: [ClaimResponse]
    let gaps: [GapResponse]
    let contradictions: [ContradictionResponse]
    let sectionCoverage: [SectionCoverageResponse]
    let quotableLines: [QuotableLineResponse]
    let possibleTitles: [String]

    enum CodingKeys: String, CodingKey {
        case keyIdeas = "key_ideas"
        case stories
        case claims
        case gaps
        case contradictions
        case sectionCoverage = "section_coverage"
        case quotableLines = "quotable_lines"
        case possibleTitles = "possible_titles"
    }

    struct KeyIdeaResponse: Codable {
        let text: String
        let relatedQuestionIds: [String]

        enum CodingKeys: String, CodingKey {
            case text
            case relatedQuestionIds = "related_question_ids"
        }
    }

    struct StoryResponse: Codable {
        let summary: String
        let impact: String
    }

    struct ClaimResponse: Codable {
        let text: String
        let confidence: String
    }

    struct GapResponse: Codable {
        let description: String
        let suggestedFollowup: String

        enum CodingKeys: String, CodingKey {
            case description
            case suggestedFollowup = "suggested_followup"
        }
    }

    struct ContradictionResponse: Codable {
        let description: String
        let firstQuote: String
        let secondQuote: String
        let suggestedClarificationQuestion: String

        enum CodingKeys: String, CodingKey {
            case description
            case firstQuote = "first_quote"
            case secondQuote = "second_quote"
            case suggestedClarificationQuestion = "suggested_clarification_question"
        }
    }

    struct SectionCoverageResponse: Codable {
        let sectionId: String
        let sectionTitle: String
        let coverageQuality: String
        let keyPointsCovered: [String]
        let missingAspects: [String]
        let suggestedFollowup: String?

        enum CodingKeys: String, CodingKey {
            case sectionId = "section_id"
            case sectionTitle = "section_title"
            case coverageQuality = "coverage_quality"
            case keyPointsCovered = "key_points_covered"
            case missingAspects = "missing_aspects"
            case suggestedFollowup = "suggested_followup"
        }
    }

    struct QuotableLineResponse: Codable {
        let text: String
        let potentialUse: String
        let topic: String
        let strength: String

        enum CodingKeys: String, CodingKey {
            case text
            case potentialUse = "potential_use"
            case topic
            case strength
        }
    }

    /// Convert response to NotesState
    func toNotesState() -> NotesState {
        NotesState(
            keyIdeas: keyIdeas.map { KeyIdea(text: $0.text, relatedQuestionIds: $0.relatedQuestionIds) },
            stories: stories.map { Story(summary: $0.summary, impact: $0.impact) },
            claims: claims.map { Claim(text: $0.text, confidence: $0.confidence) },
            gaps: gaps.map { Gap(description: $0.description, suggestedFollowup: $0.suggestedFollowup) },
            contradictions: contradictions.map {
                Contradiction(
                    description: $0.description,
                    firstQuote: $0.firstQuote,
                    secondQuote: $0.secondQuote,
                    suggestedClarificationQuestion: $0.suggestedClarificationQuestion
                )
            },
            possibleTitles: possibleTitles,
            sectionCoverage: sectionCoverage.map {
                SectionCoverage(
                    id: $0.sectionId,
                    sectionTitle: $0.sectionTitle,
                    coverageQuality: $0.coverageQuality,
                    keyPointsCovered: $0.keyPointsCovered,
                    missingAspects: $0.missingAspects,
                    suggestedFollowup: $0.suggestedFollowup
                )
            },
            quotableLines: quotableLines.map {
                QuotableLine(
                    text: $0.text,
                    potentialUse: $0.potentialUse,
                    topic: $0.topic,
                    strength: $0.strength
                )
            }
        )
    }
}

/// NoteTakerAgent extracts insights from the interview transcript in real-time
actor NoteTakerAgent {
    private let client: OpenAIClient
    private var lastActivityTime: Date?

    init(client: OpenAIClient = .shared) {
        self.client = client
    }

    /// Update notes based on transcript and plan
    func updateNotes(
        transcript: [TranscriptEntry],
        currentNotes: NotesState,
        plan: PlanSnapshot
    ) async throws -> NotesState {
        lastActivityTime = Date()

        AgentLogger.noteTakerStarted(transcriptCount: transcript.count)

        // Build transcript text
        let transcriptText = transcript.map { entry in
            let speaker = entry.speaker == "assistant" ? "Interviewer" : "Expert"
            return "[\(speaker)]: \(entry.text)"
        }.joined(separator: "\n\n")

        // Build current notes summary
        let currentNotesSummary = currentNotes.buildSummary()

        // Build sections list for coverage tracking
        let sectionsList = plan.sections.map { section in
            let questions = section.questions.map { "  - \($0.text)" }.joined(separator: "\n")
            return "### \(section.title) (id: \(section.id), \(section.importance) importance)\n\(questions)"
        }.joined(separator: "\n\n")

        let userPrompt = """
        ## Interview Context

        **Topic:** \(plan.topic)
        **Research Goal:** \(plan.researchGoal)
        **Angle:** \(plan.angle)

        ## Interview Plan Sections
        \(sectionsList)

        ## Current Notes (from previous analysis)
        \(currentNotesSummary)

        ## Transcript (most recent conversation)
        \(transcriptText)

        ---

        Please analyze the transcript and update the notes. Focus on:
        1. Any NEW key ideas the expert has shared
        2. Any NEW stories or anecdotes (especially failures, turning points, or concrete examples)
        3. Any NEW claims or strong opinions (with your assessment of confidence)
        4. Any GAPS - topics touched but not fully explored
        5. Any CONTRADICTIONS - statements that seem to conflict
        6. **SECTION COVERAGE** - For each section in the plan, assess how well it's been covered
        7. **QUOTABLE LINES** - Capture memorable, vivid, or surprising quotes from the expert
        8. Possible essay titles based on the conversation so far

        Build on the existing notes - don't duplicate what's already captured, but do refine or expand.
        """

        let response = try await client.chatCompletion(
            messages: [
                Message.system(Self.systemPrompt),
                Message.user(userPrompt)
            ],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "notes_schema", schema: Self.jsonSchema)
        )

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            AgentLogger.error(agent: "NoteTaker", message: "Invalid response from API")
            throw OpenAIError.invalidResponse
        }

        let noteTakerResponse = try JSONDecoder().decode(NoteTakerResponse.self, from: data)
        let notes = noteTakerResponse.toNotesState()

        // Extract short summaries for logging
        let ideaSummaries = notes.keyIdeas.map { String($0.text.prefix(30)) }
        let storySummaries = notes.stories.map { String($0.summary.prefix(25)) }
        let claimSummaries = notes.claims.map { String($0.text.prefix(25)) }
        let gapSummaries = notes.gaps.map { String($0.description.prefix(25)) }

        AgentLogger.noteTakerFound(ideas: ideaSummaries, stories: storySummaries, claims: claimSummaries, gaps: gapSummaries)

        return notes
    }

    /// Activity score for UI meters (0-1 based on recency)
    func getActivityScore() -> Double {
        guard let lastActivity = lastActivityTime else { return 0.0 }
        let elapsed = Date().timeIntervalSince(lastActivity)
        return max(0, 1.0 - (elapsed / 30.0))
    }

    // MARK: - System Prompt

    static let systemPrompt = """
    You are a skilled research assistant taking notes during a live interview.

    Your job is to extract and organize insights from the conversation that will later be used to:
    1. Help the interviewer ask better follow-up questions
    2. Guide the writing of a compelling essay

    **What to extract:**

    **Key Ideas** - Core insights, principles, or frameworks the expert shares. These are the "aha moments" that might form the backbone of an essay.

    **Stories** - Concrete anecdotes, examples, case studies. Stories are gold for essays. Capture:
    - What happened (summary)
    - Why it matters (impact)

    **Claims** - Strong opinions or assertions. Rate confidence:
    - "high" = Expert seems certain, backed by experience
    - "medium" = Expert believes this but with some nuance
    - "low" = Expert is speculating or uncertain

    **Gaps** - Topics mentioned but not fully explored. Suggest a follow-up question.

    **Contradictions** - When the expert says something that seems to conflict with earlier statements. This is often where the most interesting insights hide - the nuance between seemingly contradictory positions.

    **Section Coverage** - For each section in the interview plan, assess:
    - coverage_quality: "none" | "shallow" | "adequate" | "deep"
      - "none" = Section hasn't been touched
      - "shallow" = Mentioned briefly but no substance
      - "adequate" = Main points covered but room for more
      - "deep" = Thoroughly explored with examples and nuance
    - key_points_covered: What specific aspects have been addressed
    - missing_aspects: What important angles haven't been explored
    - suggested_followup: If shallow, what question would deepen coverage

    **Quotable Lines** - Capture memorable quotes from the expert. Look for:
    - Vivid language or surprising phrasing
    - Strong opinions stated memorably
    - Origin stories ("It all started when...")
    - Turning points ("The moment I realized...")
    - Counterintuitive insights
    Rate each quote's strength: "good" | "great" | "exceptional"
    Suggest potential use: "hook" | "section_header" | "pull_quote" | "conclusion" | "tweet"

    **Possible Titles** - As patterns emerge, suggest essay titles that capture the angle.

    **Guidelines:**
    - Be concise but preserve the expert's voice and specific language
    - Focus on what's NEW in this transcript segment
    - Don't duplicate existing notes, but do refine or expand them
    - Prioritize quality over quantity
    - For quotable lines, use the expert's EXACT words
    """

    // MARK: - JSON Schema

    nonisolated(unsafe) static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "key_ideas": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "The key idea or insight"],
                        "related_question_ids": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "IDs of questions this relates to (optional)"
                        ]
                    ],
                    "required": ["text", "related_question_ids"],
                    "additionalProperties": false
                ]
            ],
            "stories": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "summary": ["type": "string", "description": "Brief summary of the story"],
                        "impact": ["type": "string", "description": "Why this story matters"]
                    ],
                    "required": ["summary", "impact"],
                    "additionalProperties": false
                ]
            ],
            "claims": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "The claim or strong opinion"],
                        "confidence": [
                            "type": "string",
                            "enum": ["low", "medium", "high"],
                            "description": "How confident the expert seems"
                        ]
                    ],
                    "required": ["text", "confidence"],
                    "additionalProperties": false
                ]
            ],
            "gaps": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "description": ["type": "string", "description": "What topic was touched but not explored"],
                        "suggested_followup": ["type": "string", "description": "A follow-up question to explore this gap"]
                    ],
                    "required": ["description", "suggested_followup"],
                    "additionalProperties": false
                ]
            ],
            "contradictions": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "description": ["type": "string", "description": "What the contradiction is about"],
                        "first_quote": ["type": "string", "description": "The first statement"],
                        "second_quote": ["type": "string", "description": "The conflicting statement"],
                        "suggested_clarification_question": ["type": "string", "description": "A question to resolve the contradiction"]
                    ],
                    "required": ["description", "first_quote", "second_quote", "suggested_clarification_question"],
                    "additionalProperties": false
                ]
            ],
            "section_coverage": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "section_id": ["type": "string", "description": "The ID of the section from the plan"],
                        "section_title": ["type": "string", "description": "The title of the section"],
                        "coverage_quality": [
                            "type": "string",
                            "enum": ["none", "shallow", "adequate", "deep"],
                            "description": "How thoroughly this section has been covered"
                        ],
                        "key_points_covered": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Main points that have been addressed"
                        ],
                        "missing_aspects": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Important aspects not yet explored"
                        ],
                        "suggested_followup": [
                            "type": ["string", "null"],
                            "description": "A follow-up question to deepen coverage (if shallow)"
                        ]
                    ],
                    "required": ["section_id", "section_title", "coverage_quality", "key_points_covered", "missing_aspects", "suggested_followup"],
                    "additionalProperties": false
                ],
                "description": "Coverage assessment for each section in the interview plan"
            ],
            "quotable_lines": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string", "description": "The exact quote from the expert"],
                        "potential_use": [
                            "type": "string",
                            "enum": ["hook", "section_header", "pull_quote", "conclusion", "tweet"],
                            "description": "How this quote could be used in the essay"
                        ],
                        "topic": ["type": "string", "description": "What this quote is about"],
                        "strength": [
                            "type": "string",
                            "enum": ["good", "great", "exceptional"],
                            "description": "How memorable or powerful the quote is"
                        ]
                    ],
                    "required": ["text", "potential_use", "topic", "strength"],
                    "additionalProperties": false
                ],
                "description": "Memorable quotes captured from the expert"
            ],
            "possible_titles": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Potential essay titles based on the conversation"
            ]
        ],
        "required": ["key_ideas", "stories", "claims", "gaps", "contradictions", "section_coverage", "quotable_lines", "possible_titles"],
        "additionalProperties": false
    ]
}
