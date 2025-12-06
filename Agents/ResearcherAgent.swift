import Foundation

/// Response structure from the Researcher agent (identifies topics to research)
struct ResearcherAnalysis: Codable {
    let topicsToResearch: [TopicToResearch]

    enum CodingKeys: String, CodingKey {
        case topicsToResearch = "topics_to_research"
    }

    struct TopicToResearch: Codable {
        let topic: String
        let kind: String  // "definition" | "counterpoint" | "example" | "metric"
        let searchQuery: String
        let whyUseful: String

        enum CodingKeys: String, CodingKey {
            case topic
            case kind
            case searchQuery = "search_query"
            case whyUseful = "why_useful"
        }
    }
}

/// Response structure for research results
struct ResearcherResponse: Codable {
    let items: [ResearchItemResponse]

    struct ResearchItemResponse: Codable {
        let topic: String
        let kind: String
        let summary: String
        let howToUseInQuestion: String
        let priority: Int
        // Claim verification fields (optional, used when kind = "claim_verification")
        let verificationStatus: String?
        let verificationNote: String?

        enum CodingKeys: String, CodingKey {
            case topic
            case kind
            case summary
            case howToUseInQuestion = "how_to_use_in_question"
            case priority
            case verificationStatus = "verification_status"
            case verificationNote = "verification_note"
        }

        func toResearchItem() -> ResearchItem {
            ResearchItem(
                topic: topic,
                kind: kind,
                summary: summary,
                howToUseInQuestion: howToUseInQuestion,
                priority: priority,
                verificationStatus: verificationStatus,
                verificationNote: verificationNote
            )
        }
    }
}

/// ResearcherAgent identifies and researches unfamiliar concepts from the interview
actor ResearcherAgent {
    private let llm: LLMClient
    private var modelConfig: LLMModelConfig
    private var lastActivityTime: Date?

    // Track topics we've ATTEMPTED to research (not just successful)
    private var attemptedTopics: Set<String> = []
    // Track topics that returned useful results
    private var successfulTopics: Set<String> = []
    // Track when topics were attempted (for potential refresh)
    private var attemptedAt: [String: Date] = [:]
    // Track when topics were successfully researched (for refresh after new context emerges)
    private var successfulAt: [String: Date] = [:]

    // Time after which a topic can be researched again (for fresh context)
    private let topicRefreshInterval: TimeInterval = 300  // 5 minutes

    // Track consecutive failures to avoid wasting API calls
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures = 5

    // Content hash to detect if transcript has actually changed
    private var lastTranscriptHash: Int = 0

    init(client: LLMClient, modelConfig: LLMModelConfig) {
        self.llm = client
        self.modelConfig = modelConfig
    }

    /// Reset state for a new interview session
    func reset() {
        attemptedTopics = []
        successfulTopics = []
        attemptedAt = [:]
        successfulAt = [:]
        lastActivityTime = nil
        consecutiveFailures = 0
        lastTranscriptHash = 0
    }

    /// Research new concepts mentioned in the transcript
    func research(
        transcript: [TranscriptEntry],
        existingResearch: [ResearchItem],
        topic: String
    ) async throws -> [ResearchItem] {
        lastActivityTime = Date()

        // Check if transcript has actually changed since last call
        let currentHash = computeTranscriptHash(transcript)
        guard currentHash != lastTranscriptHash else {
            AgentLogger.researcherSkipped(reason: "transcript unchanged")
            return []
        }
        lastTranscriptHash = currentHash

        AgentLogger.researcherStarted()

        // If we've had too many consecutive failures, reduce frequency
        if consecutiveFailures >= maxConsecutiveFailures {
            AgentLogger.researcherSkipped(reason: "too many recent failures, cooling down")
            // Reset after some cycles to try again
            if consecutiveFailures > maxConsecutiveFailures + 3 {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
            }
            return []
        }

        // Refresh attempted topics - allow retry after refresh interval
        let now = Date()
        attemptedTopics = attemptedTopics.filter { topicKey in
            guard let attemptTime = attemptedAt[topicKey] else { return false }
            return now.timeIntervalSince(attemptTime) < topicRefreshInterval
        }

        // Refresh successful topics - allow re-research after interval if new context emerges
        // This catches cases where new contradictory info comes up later in the interview
        successfulTopics = successfulTopics.filter { topicKey in
            guard let successTime = successfulAt[topicKey] else { return false }
            return now.timeIntervalSince(successTime) < topicRefreshInterval
        }

        // Also keep track of what's already been successfully researched
        for item in existingResearch {
            successfulTopics.insert(item.topic.lowercased())
        }

        // First, analyze transcript to identify topics worth researching
        let topicsToResearch = try await identifyTopics(
            transcript: transcript,
            existingResearch: existingResearch,
            topic: topic
        )

        guard !topicsToResearch.isEmpty else {
            AgentLogger.researcherIdentifiedTopics([])
            return []
        }

        AgentLogger.researcherIdentifiedTopics(topicsToResearch.map { $0.topic })

        // Research each topic using knowledge-based approach
        var newResearchItems: [ResearchItem] = []
        var hadSuccess = false

        for searchTopic in topicsToResearch.prefix(3) {  // Limit to 3 per cycle
            let topicKey = searchTopic.topic.lowercased()

            // Skip if we've already attempted this topic recently
            if attemptedTopics.contains(topicKey) {
                AgentLogger.researcherSkipped(reason: "already attempted '\(searchTopic.topic)'")
                continue
            }

            AgentLogger.researcherLookingUp(topic: searchTopic.topic, reason: searchTopic.kind)

            // Mark as attempted BEFORE the call
            attemptedTopics.insert(topicKey)
            attemptedAt[topicKey] = Date()

            do {
                if let item = try await researchTopic(searchTopic) {
                    successfulTopics.insert(topicKey)
                    successfulAt[topicKey] = Date()  // Track when for refresh logic
                    newResearchItems.append(item)
                    hadSuccess = true
                    AgentLogger.researcherFound(topic: item.topic, summary: item.summary)
                }
            } catch {
                // Log the actual error instead of swallowing it
                AgentLogger.researcherError(topic: searchTopic.topic, error: error.localizedDescription)
            }
        }

        // Track consecutive failures for cooldown logic
        if hadSuccess {
            consecutiveFailures = 0
        } else if !topicsToResearch.isEmpty {
            consecutiveFailures += 1
        }

        AgentLogger.researcherComplete(count: newResearchItems.count)

        return newResearchItems
    }

    /// Compute a simple hash of transcript content to detect changes
    private func computeTranscriptHash(_ transcript: [TranscriptEntry]) -> Int {
        var hasher = Hasher()
        hasher.combine(transcript.count)
        // Hash only the last few entries for efficiency
        for entry in transcript.suffix(10) {
            hasher.combine(entry.text)
            hasher.combine(entry.isFinal)
        }
        return hasher.finalize()
    }

    /// Activity score for UI meters (0-1 based on recency)
    func getActivityScore() -> Double {
        guard let lastActivity = lastActivityTime else { return 0.0 }
        let elapsed = Date().timeIntervalSince(lastActivity)
        return max(0, 1.0 - (elapsed / 30.0))
    }

    // MARK: - Private Methods

    private func identifyTopics(
        transcript: [TranscriptEntry],
        existingResearch: [ResearchItem],
        topic: String
    ) async throws -> [ResearcherAnalysis.TopicToResearch] {
        let transcriptText = transcript.map { entry in
            let speaker = entry.speaker == "assistant" ? "Interviewer" : "Expert"
            return "[\(speaker)]: \(entry.text)"
        }.joined(separator: "\n\n")

        // Combine existing research AND attempted topics to avoid repeats
        var alreadyHandled: [String] = existingResearch.map { $0.topic }
        alreadyHandled.append(contentsOf: attemptedTopics.map { $0 })
        let researchedList = alreadyHandled.isEmpty ? "None yet" : alreadyHandled.joined(separator: ", ")

        let userPrompt = """
        ## Interview Topic
        \(topic)

        ## Already Researched/Attempted (DO NOT SUGGEST THESE)
        \(researchedList)

        ## Recent Transcript
        \(transcriptText)

        ---

        **Your mission:** Find 1-2 SPECIFIC, UNIQUE things from this conversation that would be worth providing context on.

        Look for:
        - Specific names (people, companies, products, frameworks) that were JUST mentioned
        - Technical terms or jargon the expert used
        - Specific claims about numbers, statistics, or outcomes
        - References to specific events, tools, or methodologies

        **CRITICAL RULES:**
        1. DO NOT suggest generic topics like "AI-native applications" or the main interview topic itself
        2. DO NOT suggest anything in the "Already Researched/Attempted" list
        3. ONLY suggest specific, concrete things the expert mentioned (names, products, companies, specific terms)
        4. If nothing specific and new was mentioned, return an EMPTY array

        For each topic:
        - Be VERY specific (e.g., "GPT-4" not "language models")
        - Explain WHY it would help the interviewer with a follow-up question
        """

        let analysis: ResearcherAnalysis = try await llm.chatStructured(
            messages: [
                Message.system(Self.identifySystemPrompt),
                Message.user(userPrompt)
            ],
            model: modelConfig.insightModel,
            schemaName: "research_topics_schema",
            schema: Self.identifyJsonSchema,
            maxTokens: nil
        )

        // Filter out already-attempted topics (case-insensitive)
        return analysis.topicsToResearch.filter { topic in
            let key = topic.topic.lowercased()
            return !attemptedTopics.contains(key) && !successfulTopics.contains(key)
        }
    }

    private func researchTopic(_ topic: ResearcherAnalysis.TopicToResearch) async throws -> ResearchItem? {
        // Use model's knowledge to provide context (web search not available in Chat Completions API)
        let userPrompt = """
        Provide helpful context about this topic that would help an interviewer ask better follow-up questions.

        Topic: \(topic.topic)
        Research Type: \(topic.kind)
        Context for why this is useful: \(topic.whyUseful)

        Based on your knowledge, provide:
        1. A brief factual summary (2-3 sentences) - include specific facts, dates, or numbers if you know them
        2. A specific follow-up question the interviewer could ask using this context

        If you don't have reliable information about this topic, return a summary that acknowledges this
        and suggest what the interviewer might ask to learn more from the expert.
        """

        let result: ResearcherResponse.ResearchItemResponse = try await llm.chatStructured(
            messages: [
                Message.system(Self.researchSystemPrompt),
                Message.user(userPrompt)
            ],
            model: modelConfig.insightModel,
            schemaName: "research_result_schema",
            schema: Self.researchResultJsonSchema,
            maxTokens: nil
        )
        return result.toResearchItem()
    }

    // MARK: - System Prompts

    static let identifySystemPrompt = """
    You are a research assistant helping during a live interview. Your job is to identify SPECIFIC, CONCRETE topics that would benefit from additional context OR claims that should be fact-checked.

    **IMPORTANT: Be VERY selective.** Only suggest topics when:
    1. The expert mentioned a SPECIFIC name, company, product, framework, or technical term
    2. The topic is genuinely unfamiliar or has nuances worth exploring
    3. Providing context would help the interviewer ask a better follow-up question
    4. The expert made a VERIFIABLE CLAIM with specific numbers, dates, or facts

    **DO NOT suggest:**
    - The main interview topic itself (e.g., if interviewing about "AI-native apps", don't suggest "AI-native applications")
    - Generic or broad topics
    - Things that are common knowledge
    - Anything in the "Already Researched/Attempted" list

    **ONLY suggest:**
    - Specific company names the expert mentioned
    - Specific people or researchers referenced
    - Specific products, frameworks, or tools
    - Technical terms or jargon that might need clarification
    - **VERIFIABLE CLAIMS** - Use kind "claim_verification" for:
      * Statistics or percentages the expert cited ("90% of startups fail")
      * Historical facts or dates ("GPT-4 was released in...")
      * Market data or metrics ("The market is worth $X billion")
      * Attributions ("Einstein said..." or "According to study X...")

    **Output:** Return 0-2 highly specific topics. If nothing concrete was mentioned, return an empty array. Quality over quantity.
    """

    static let researchSystemPrompt = """
    You are a knowledgeable research assistant providing context during an interview.

    **Your role:**
    - Provide factual, useful context from your knowledge
    - Help the interviewer ask informed follow-up questions
    - Be honest about uncertainty - if you're not sure about something, say so
    - **VERIFY CLAIMS** when the research type is "claim_verification"

    **Guidelines:**
    - Include specific facts, dates, numbers when you know them
    - Suggest how this context could lead to a better question
    - Keep summaries concise (2-3 sentences)
    - If the topic is outside your knowledge, suggest what the interviewer might ask the expert

    **For claim_verification:**
    - Check if the claim is accurate based on your knowledge
    - Set verification_status to one of:
      * "verified" - The claim is accurate
      * "contradicted" - The claim appears to be incorrect (provide the correct info)
      * "partially_true" - The claim has some truth but is oversimplified or missing context
      * "unverifiable" - You cannot verify this from your knowledge
    - ALWAYS provide a verification_note explaining your finding
    - If contradicted, the how_to_use_in_question should help the interviewer gently probe the discrepancy
    """

    // MARK: - JSON Schemas

    nonisolated(unsafe) static let identifyJsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "topics_to_research": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "topic": ["type": "string", "description": "The concept, term, or claim to research/verify"],
                        "kind": [
                            "type": "string",
                            "enum": ["definition", "counterpoint", "example", "metric", "person", "company", "context", "trend", "claim_verification"],
                            "description": "What type of research is needed. Use 'claim_verification' for specific facts/stats to verify."
                        ],
                        "search_query": ["type": "string", "description": "A good search query to find this information"],
                        "why_useful": ["type": "string", "description": "How this research would help the interview"]
                    ],
                    "required": ["topic", "kind", "search_query", "why_useful"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["topics_to_research"],
        "additionalProperties": false
    ]

    nonisolated(unsafe) static let researchResultJsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "topic": ["type": "string", "description": "The topic that was researched"],
            "kind": [
                "type": "string",
                "enum": ["definition", "counterpoint", "example", "metric", "person", "company", "context", "trend", "claim_verification"],
                "description": "The type of research"
            ],
            "summary": ["type": "string", "description": "Concise factual summary (2-3 sentences)"],
            "how_to_use_in_question": ["type": "string", "description": "How to use this in a follow-up question"],
            "priority": [
                "type": "integer",
                "description": "How important this is (1 = very, 2 = moderate, 3 = nice-to-have)"
            ],
            "verification_status": [
                "type": "string",
                "enum": ["verified", "contradicted", "partially_true", "unverifiable"],
                "description": "For claim_verification: whether the claim is accurate. Required when kind is claim_verification."
            ],
            "verification_note": [
                "type": "string",
                "description": "For claim_verification: explanation of the verification result. Required when kind is claim_verification."
            ]
        ],
        "required": ["topic", "kind", "summary", "how_to_use_in_question", "priority", "verification_status", "verification_note"],
        "additionalProperties": false
    ]
}
