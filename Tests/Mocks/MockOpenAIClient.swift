import Foundation
@testable import Interviewer

// MARK: - Mock OpenAI Client

/// A mock OpenAI client that returns deterministic responses for testing
/// This allows us to test agent behavior without making actual API calls
final class MockOpenAIClient {
    /// Recorded calls for verification
    var recordedCalls: [RecordedCall] = []

    /// Pre-configured responses for specific scenarios
    var responses: [String: String] = [:]

    /// Whether to simulate failures
    var shouldFail = false
    var failureError: Error = OpenAIError.invalidResponse

    struct RecordedCall: Equatable {
        let messages: [String]  // Simplified - just the content
        let model: String
        let responseFormatName: String?
    }

    func reset() {
        recordedCalls = []
        responses = [:]
        shouldFail = false
    }

    /// Configure a response for a specific response format name
    func setResponse(forFormat formatName: String, response: String) {
        responses[formatName] = response
    }

    /// Simulate a chat completion call
    func chatCompletion(
        messages: [Message],
        model: String,
        responseFormat: ResponseFormat?
    ) async throws -> ChatCompletionResponse {
        // Record the call
        let call = RecordedCall(
            messages: messages.map { $0.content },
            model: model,
            responseFormatName: responseFormat?.schemaName
        )
        recordedCalls.append(call)

        // Check for failure mode
        if shouldFail {
            throw failureError
        }

        // Find matching response
        let formatName = responseFormat?.schemaName ?? "default"
        guard let responseContent = responses[formatName] else {
            throw MockError.noResponseConfigured(formatName: formatName)
        }

        return ChatCompletionResponse(
            id: "mock-\(UUID().uuidString)",
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [
                ChatCompletionResponse.Choice(
                    index: 0,
                    message: ChatCompletionResponse.ResponseMessage(
                        role: "assistant",
                        content: responseContent,
                        toolCalls: nil
                    ),
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 100,
                completionTokens: 50,
                totalTokens: 150
            )
        )
    }

    enum MockError: Error {
        case noResponseConfigured(formatName: String)
    }
}

// MARK: - LLMClient conformance

extension MockOpenAIClient: LLMClient, @unchecked Sendable {
    func chatStructured<T>(
        messages: [Message],
        model: String,
        schemaName: String,
        schema: [String: Any],
        maxTokens: Int?
    ) async throws -> T where T : Decodable, T : Sendable {
        let response = try await chatCompletion(
            messages: messages,
            model: model,
            responseFormat: .jsonSchema(name: schemaName, schema: schema)
        )
        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            throw MockError.noResponseConfigured(formatName: schemaName)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func chatText(
        messages: [Message],
        model: String,
        maxTokens: Int?
    ) async throws -> String {
        let response = try await chatCompletion(
            messages: messages,
            model: model,
            responseFormat: nil
        )
        return response.choices.first?.message.content ?? ""
    }

    func chatTextStreaming(
        messages: [Message],
        model: String,
        maxTokens: Int?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let text = try await chatText(messages: messages, model: model, maxTokens: maxTokens)
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - ResponseFormat Extension

extension ResponseFormat {
    var schemaName: String? {
        jsonSchema?.name
    }
}

// MARK: - Test Fixtures

/// Pre-built test data for consistent testing
enum TestFixtures {

    // MARK: - Transcripts

    static let shortTranscript: [TranscriptEntry] = [
        TranscriptEntry(speaker: "assistant", text: "Welcome! Tell me about your experience with building startups.", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "user", text: "I've been building startups for 15 years. The biggest lesson was learning to fail fast. We once spent 2 years on a product nobody wanted.", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "assistant", text: "That's a powerful insight. What made you realize you needed to change?", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "user", text: "We ran out of money, honestly. But in hindsight, all the signs were there. We just weren't listening to customers.", timestamp: Date(), isFinal: true)
    ]

    static let mediumTranscript: [TranscriptEntry] = shortTranscript + [
        TranscriptEntry(speaker: "assistant", text: "How do you approach customer feedback now?", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "user", text: "We talk to customers every single week. I have a rule: no feature ships without 5 customer conversations. It sounds slow but it's actually faster because we build the right thing.", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "assistant", text: "Can you give me a specific example?", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "user", text: "Sure. Last quarter we were about to build an AI feature. After talking to customers, we realized they didn't want AI - they wanted better search. Saved us 3 months of wasted work.", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "assistant", text: "That's fascinating. What about when customers ask for conflicting things?", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "user", text: "That's the hard part. You have to find the underlying need. Usually conflicting requests point to the same problem with different solutions. Our job is to find the third option.", timestamp: Date(), isFinal: true)
    ]

    static let longTranscript: [TranscriptEntry] = mediumTranscript + [
        TranscriptEntry(speaker: "assistant", text: "Let's talk about team building. How do you hire?", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "user", text: "I look for people who've failed and learned. I'd rather hire someone who's been through a startup failure than someone with a perfect resume from big tech.", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "assistant", text: "Why is that?", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "user", text: "Because startups are about dealing with uncertainty. Big tech teaches you to optimize within constraints. Startups require you to question the constraints themselves.", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "assistant", text: "Any hiring mistakes you've made?", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "user", text: "Oh absolutely. I once hired a brilliant engineer who couldn't work without a spec. Took 6 months to realize the fit was wrong. Now I always test for ambiguity tolerance.", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "assistant", text: "As we wrap up, what's the one thing you'd tell your younger self?", timestamp: Date(), isFinal: true),
        TranscriptEntry(speaker: "user", text: "Talk to customers before writing any code. I know everyone says it, but nobody actually does it. The first startup I failed at, I built for 18 months before showing anyone. Never again.", timestamp: Date(), isFinal: true)
    ]

    // MARK: - Plans

    /// Standard plan using actual PlanSnapshot structure
    static let standardPlan: PlanSnapshot = PlanSnapshot(
        topic: "Building Startups",
        researchGoal: "Understand the key lessons learned from serial entrepreneurs about building successful startups",
        angle: "Focus on failures and pivots that led to success",
        sections: [
            PlanSnapshot.SectionSnapshot(
                id: "opening",
                title: "Background & Context",
                importance: "high",
                questions: [
                    PlanSnapshot.QuestionSnapshot(id: "q1", text: "Tell me about your journey as an entrepreneur", role: "backbone", priority: 1, notesForInterviewer: "")
                ]
            ),
            PlanSnapshot.SectionSnapshot(
                id: "failures",
                title: "Failures & Lessons",
                importance: "high",
                questions: [
                    PlanSnapshot.QuestionSnapshot(id: "q2", text: "What's the biggest failure you've experienced?", role: "backbone", priority: 1, notesForInterviewer: ""),
                    PlanSnapshot.QuestionSnapshot(id: "q3", text: "How did that failure change your approach?", role: "followup", priority: 2, notesForInterviewer: "")
                ]
            ),
            PlanSnapshot.SectionSnapshot(
                id: "customers",
                title: "Customer Development",
                importance: "high",
                questions: [
                    PlanSnapshot.QuestionSnapshot(id: "q4", text: "How do you approach customer feedback?", role: "backbone", priority: 1, notesForInterviewer: ""),
                    PlanSnapshot.QuestionSnapshot(id: "q5", text: "Can you give a specific example?", role: "followup", priority: 2, notesForInterviewer: "")
                ]
            ),
            PlanSnapshot.SectionSnapshot(
                id: "team",
                title: "Team Building",
                importance: "medium",
                questions: [
                    PlanSnapshot.QuestionSnapshot(id: "q6", text: "How do you approach hiring?", role: "backbone", priority: 2, notesForInterviewer: "")
                ]
            ),
            PlanSnapshot.SectionSnapshot(
                id: "closing",
                title: "Closing Reflections",
                importance: "medium",
                questions: [
                    PlanSnapshot.QuestionSnapshot(id: "q7", text: "What would you tell your younger self?", role: "backbone", priority: 1, notesForInterviewer: "")
                ]
            )
        ]
    )

    /// Standard target duration for testing
    static let standardTargetSeconds = 840

    // MARK: - Notes State

    static let emptyNotes = NotesState.empty

    static let partialNotes = NotesState(
        keyIdeas: [
            KeyIdea(text: "Fail fast is critical for startups"),
            KeyIdea(text: "Customer feedback should drive product decisions")
        ],
        stories: [
            Story(summary: "Spent 2 years building product nobody wanted", impact: "Led to fail-fast methodology")
        ],
        claims: [
            Claim(text: "No feature ships without 5 customer conversations", confidence: "high")
        ],
        gaps: [
            Gap(description: "Haven't explored team building yet", suggestedFollowup: "How do you approach hiring?")
        ],
        contradictions: [],
        possibleTitles: ["The Art of Failing Fast"],
        sectionCoverage: [
            SectionCoverage(id: "opening", sectionTitle: "Background & Context", coverageQuality: "adequate"),
            SectionCoverage(id: "failures", sectionTitle: "Failures & Lessons", coverageQuality: "deep"),
            SectionCoverage(id: "customers", sectionTitle: "Customer Development", coverageQuality: "shallow", missingAspects: ["Specific examples", "Conflicting feedback handling"]),
            SectionCoverage(id: "team", sectionTitle: "Team Building", coverageQuality: "none"),
            SectionCoverage(id: "closing", sectionTitle: "Closing Reflections", coverageQuality: "none")
        ],
        quotableLines: [
            QuotableLine(text: "We spent 2 years building a product nobody wanted", potentialUse: "hook", topic: "failures", strength: "great"),
            QuotableLine(text: "No feature ships without 5 customer conversations", potentialUse: "pull_quote", topic: "customers", strength: "exceptional")
        ]
    )

    static let fullNotes = NotesState(
        keyIdeas: [
            KeyIdea(text: "Fail fast is critical for startups"),
            KeyIdea(text: "Customer feedback should drive product decisions"),
            KeyIdea(text: "Hire for ambiguity tolerance"),
            KeyIdea(text: "Question constraints, don't just optimize within them")
        ],
        stories: [
            Story(summary: "Spent 2 years building product nobody wanted", impact: "Led to fail-fast methodology"),
            Story(summary: "Almost built AI feature but customers wanted better search", impact: "Saved 3 months of work"),
            Story(summary: "Hired brilliant engineer who couldn't work without specs", impact: "Now tests for ambiguity tolerance")
        ],
        claims: [
            Claim(text: "No feature ships without 5 customer conversations", confidence: "high"),
            Claim(text: "Startup failures teach more than big tech success", confidence: "high"),
            Claim(text: "Conflicting customer requests usually point to same underlying problem", confidence: "medium")
        ],
        gaps: [],
        contradictions: [],
        possibleTitles: ["The Art of Failing Fast", "18 Months of Silence: Why I Never Build Before Talking"],
        sectionCoverage: [
            SectionCoverage(id: "opening", sectionTitle: "Background & Context", coverageQuality: "adequate"),
            SectionCoverage(id: "failures", sectionTitle: "Failures & Lessons", coverageQuality: "deep"),
            SectionCoverage(id: "customers", sectionTitle: "Customer Development", coverageQuality: "deep"),
            SectionCoverage(id: "team", sectionTitle: "Team Building", coverageQuality: "adequate"),
            SectionCoverage(id: "closing", sectionTitle: "Closing Reflections", coverageQuality: "deep")
        ],
        quotableLines: [
            QuotableLine(text: "We spent 2 years building a product nobody wanted", potentialUse: "hook", topic: "failures", strength: "great"),
            QuotableLine(text: "No feature ships without 5 customer conversations", potentialUse: "pull_quote", topic: "customers", strength: "exceptional"),
            QuotableLine(text: "Talk to customers before writing any code", potentialUse: "conclusion", topic: "advice", strength: "exceptional"),
            QuotableLine(text: "Startups require you to question the constraints themselves", potentialUse: "section_header", topic: "mindset", strength: "great")
        ]
    )

    // MARK: - Research Items

    static let emptyResearch: [ResearchItem] = []

    static let sampleResearch: [ResearchItem] = [
        ResearchItem(
            topic: "Lean Startup Methodology",
            kind: "definition",
            summary: "Build-measure-learn framework popularized by Eric Ries",
            howToUseInQuestion: "Ask how their approach compares to lean startup principles",
            priority: 2
        ),
        ResearchItem(
            topic: "90% of startups fail",
            kind: "claim_verification",
            summary: "Statistics vary but failure rates are high",
            howToUseInQuestion: "Validate their perspective on failure rates",
            priority: 2,
            verificationStatus: "partially_true",
            verificationNote: "Actual rate is closer to 70-75% within 10 years"
        )
    ]

    // MARK: - Mock Responses

    static let noteTakerResponse = """
    {
        "key_ideas": [
            {"text": "Fail fast is critical for startups", "related_question_ids": ["q2"]},
            {"text": "Customer feedback should drive product decisions", "related_question_ids": ["q4"]}
        ],
        "stories": [
            {"summary": "Spent 2 years building product nobody wanted", "impact": "Led to fail-fast methodology"}
        ],
        "claims": [
            {"text": "No feature ships without 5 customer conversations", "confidence": "high"}
        ],
        "gaps": [
            {"description": "Haven't explored team building", "suggested_followup": "How do you approach hiring?"}
        ],
        "contradictions": [],
        "section_coverage": [
            {"section_id": "opening", "section_title": "Background", "coverage_quality": "adequate", "key_points_covered": ["Journey"], "missing_aspects": [], "suggested_followup": null},
            {"section_id": "failures", "section_title": "Failures", "coverage_quality": "deep", "key_points_covered": ["2 year failure", "Lessons learned"], "missing_aspects": [], "suggested_followup": null}
        ],
        "quotable_lines": [
            {"text": "We spent 2 years building a product nobody wanted", "potential_use": "hook", "topic": "failures", "strength": "great"}
        ],
        "possible_titles": ["The Art of Failing Fast"]
    }
    """

    static let orchestratorResponse = """
    {
        "phase": "deep_dive",
        "next_question": {
            "text": "Can you give me a specific example of how customer feedback changed your product direction?",
            "target_section_id": "customers",
            "source": "plan",
            "source_question_id": "q5",
            "expected_answer_seconds": 90
        },
        "interviewer_brief": "They mentioned the 5-conversation rule - probe for a concrete story that illustrates this in practice."
    }
    """

    static let researcherIdentifyResponse = """
    {
        "topics_to_research": [
            {
                "topic": "Lean Startup Methodology",
                "kind": "definition",
                "search_query": "lean startup methodology build measure learn",
                "why_useful": "Can ask how their approach compares"
            }
        ]
    }
    """

    static let researcherResultResponse = """
    {
        "topic": "Lean Startup Methodology",
        "kind": "definition",
        "summary": "Build-measure-learn framework popularized by Eric Ries emphasizing validated learning",
        "how_to_use_in_question": "Ask how their 5-conversation rule relates to lean startup principles",
        "priority": 2
    }
    """

    static let analysisResponse = """
    {
        "research_goal": "The interview revealed deep insights about learning from failure and customer-centric development",
        "main_claims": [
            {"text": "Failing fast is essential - spending years on wrong product is the biggest startup mistake", "evidence_story_ids": ["story-1"]},
            {"text": "Customer feedback must be systematic, not ad-hoc - the 5-conversation rule ensures this", "evidence_story_ids": ["story-2"]},
            {"text": "Hiring for ambiguity tolerance matters more than technical brilliance in startups", "evidence_story_ids": ["story-3"]}
        ],
        "themes": ["Learning from failure", "Customer obsession", "Hiring for uncertainty"],
        "tensions": ["Speed vs thoroughness in customer research", "Technical excellence vs startup adaptability"],
        "quotes": [
            {"text": "We spent 2 years building a product nobody wanted", "role": "origin"},
            {"text": "No feature ships without 5 customer conversations", "role": "opinion"},
            {"text": "Talk to customers before writing any code", "role": "opinion"}
        ],
        "suggested_title": "The 5-Conversation Rule: What 15 Years of Startup Failures Taught Me",
        "suggested_subtitle": "How systematic customer feedback transformed my approach to building products"
    }
    """

    static let followUpResponse = """
    {
        "summary": "The interview covered startup failures, customer development methodology, and hiring philosophy. Strong coverage of failure lessons and customer feedback systems.",
        "suggested_topics": [
            {
                "id": "topic-1",
                "title": "Scaling Customer Feedback",
                "description": "How the 5-conversation rule scales as the company grows",
                "questions": ["How do you maintain customer closeness as you scale?", "Who does customer conversations - founders or product team?"]
            },
            {
                "id": "topic-2",
                "title": "The Ambiguity Tolerance Interview",
                "description": "Deep dive into how they actually test for ambiguity tolerance in hiring",
                "questions": ["What specific questions or exercises do you use?", "Can you walk me through a recent interview?"]
            }
        ],
        "unexplored_gaps": ["Fundraising experience", "Board dynamics", "Competition strategy"],
        "strengthen_areas": ["More specific examples of the AI vs search pivot", "Details on the failed engineer hire"]
    }
    """
}
