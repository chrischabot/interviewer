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

        enum CodingKeys: String, CodingKey {
            case topic
            case kind
            case summary
            case howToUseInQuestion = "how_to_use_in_question"
            case priority
        }

        func toResearchItem() -> ResearchItem {
            ResearchItem(
                topic: topic,
                kind: kind,
                summary: summary,
                howToUseInQuestion: howToUseInQuestion,
                priority: priority
            )
        }
    }
}

/// ResearcherAgent identifies and researches unfamiliar concepts from the interview
actor ResearcherAgent {
    private let client: OpenAIClient
    private var lastActivityTime: Date?
    private var researchedTopics: Set<String> = []  // Avoid re-researching same topic
    private var researchedAt: [String: Date] = [:]  // Track when topics were researched

    // Time after which a topic can be researched again (for fresh context)
    private let topicRefreshInterval: TimeInterval = 300  // 5 minutes

    init(client: OpenAIClient = .shared) {
        self.client = client
    }

    /// Reset state for a new interview session
    func reset() {
        researchedTopics = []
        researchedAt = [:]
        lastActivityTime = nil
    }

    /// Research new concepts mentioned in the transcript
    func research(
        transcript: [TranscriptEntry],
        existingResearch: [ResearchItem],
        topic: String
    ) async throws -> [ResearchItem] {
        lastActivityTime = Date()

        AgentLogger.researcherStarted()

        // Update researched topics from existing research (only if not stale)
        let now = Date()
        for item in existingResearch {
            let topicKey = item.topic.lowercased()
            // Only mark as researched if we researched it recently
            if let researchDate = researchedAt[topicKey],
               now.timeIntervalSince(researchDate) < topicRefreshInterval {
                researchedTopics.insert(topicKey)
            }
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

        // Research each topic using web search
        var newResearchItems: [ResearchItem] = []

        for searchTopic in topicsToResearch.prefix(3) {  // Limit to 3 per cycle to manage cost/latency
            AgentLogger.researcherLookingUp(topic: searchTopic.topic, reason: searchTopic.kind)
            if let item = try? await researchTopic(searchTopic) {
                let topicKey = searchTopic.topic.lowercased()
                researchedTopics.insert(topicKey)
                researchedAt[topicKey] = Date()  // Track when we researched this
                newResearchItems.append(item)
                AgentLogger.researcherFound(topic: item.topic, summary: item.summary)
            }
        }

        AgentLogger.researcherComplete(count: newResearchItems.count)

        return newResearchItems
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

        let existingTopics = existingResearch.map { $0.topic }
        let researchedList = existingTopics.isEmpty ? "None yet" : existingTopics.joined(separator: ", ")

        let userPrompt = """
        ## Interview Topic
        \(topic)

        ## Already Researched
        \(researchedList)

        ## Recent Transcript
        \(transcriptText)

        ---

        **Your mission:** Find 2-3 specific things from this conversation that would be worth researching.

        Scan the transcript for:
        - Names (people, companies, products, frameworks)
        - Technical terms or jargon
        - Claims about trends, numbers, or outcomes
        - Challenges or problems the expert mentions
        - References to events, tools, or methodologies

        For each topic you identify:
        - Explain WHY it would help the interviewer
        - Suggest a specific search query to find useful info

        **Important:** Don't hold back! Even if a topic seems well-known, there might be recent news, statistics, or alternative perspectives worth noting. The interviewer benefits from ANY context you can provide.

        Only skip topics that are in the "Already Researched" list above.
        """

        let response = try await client.chatCompletion(
            messages: [
                Message.system(Self.identifySystemPrompt),
                Message.user(userPrompt)
            ],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "research_topics_schema", schema: Self.identifyJsonSchema)
        )

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            return []
        }

        let analysis = try JSONDecoder().decode(ResearcherAnalysis.self, from: data)

        // Filter out already-researched topics
        return analysis.topicsToResearch.filter { topic in
            !researchedTopics.contains(topic.topic.lowercased())
        }
    }

    private func researchTopic(_ topic: ResearcherAnalysis.TopicToResearch) async throws -> ResearchItem? {
        // Use web search to research the topic
        let userPrompt = """
        Research this topic and provide a concise summary that would help an interviewer ask better questions.

        Topic: \(topic.topic)
        Research Type: \(topic.kind)
        Search Query: \(topic.searchQuery)
        Why Useful: \(topic.whyUseful)

        Provide:
        1. A brief factual summary (2-3 sentences)
        2. How this information could be used to ask a better follow-up question
        """

        let response = try await client.chatCompletion(
            messages: [
                Message.system(Self.researchSystemPrompt),
                Message.user(userPrompt)
            ],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "research_result_schema", schema: Self.researchResultJsonSchema),
            tools: [.webSearch(searchContextSize: "medium")]
        )

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            return nil
        }

        let result = try JSONDecoder().decode(ResearcherResponse.ResearchItemResponse.self, from: data)
        return result.toResearchItem()
    }

    // MARK: - System Prompts

    static let identifySystemPrompt = """
    You are a sharp research assistant for a live interview. Your job is to fact-check, verify, and find context that makes the interview more rigorous.

    **BE SKEPTICAL** - When the expert makes claims, find data to verify or challenge them. Good interviews push back.

    **What to look for:**

    1. **Claims to Verify** - Expert says "most companies do X" or "studies show Y"? Find the actual data.
    2. **Numbers to Check** - Percentages, growth rates, market sizes - are they accurate?
    3. **Counterpoints** - Find opposing viewpoints, failed examples, or edge cases that complicate the narrative
    4. **Definitions** - Technical terms, frameworks, methodologies the expert uses
    5. **People & Companies** - Names mentioned - what's their actual track record?
    6. **Historical Context** - Did things really happen the way the expert describes?

    **Your job is to arm the interviewer with:**
    - Facts that support OR contradict what the expert is saying
    - Specific examples that illustrate or challenge their points
    - Data points the interviewer can cite ("Actually, I read that...")
    - Alternative perspectives worth raising

    **Guidelines:**
    - Don't assume the expert is right. Find out.
    - If they cite a study, find it. If they name-drop, verify the connection.
    - Look for the messy reality behind clean narratives
    - Aim for 2-3 topics per segment
    """

    static let researchSystemPrompt = """
    You are a fact-checker with web search capability. Find the truth, not just confirmation.

    **Guidelines:**
    - Search for actual data, studies, and primary sources
    - If the expert made a claim, find evidence for AND against it
    - Note when common beliefs are wrong or more complicated than they seem
    - Include specific numbers, dates, and names - vague summaries are useless
    - If you can't verify something, say so
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
                        "topic": ["type": "string", "description": "The concept or term to research"],
                        "kind": [
                            "type": "string",
                            "enum": ["definition", "counterpoint", "example", "metric", "person", "company", "context", "trend"],
                            "description": "What type of research is needed"
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
                "enum": ["definition", "counterpoint", "example", "metric", "person", "company", "context", "trend"],
                "description": "The type of research"
            ],
            "summary": ["type": "string", "description": "Concise factual summary (2-3 sentences)"],
            "how_to_use_in_question": ["type": "string", "description": "How to use this in a follow-up question"],
            "priority": [
                "type": "integer",
                "description": "How important this is (1 = very, 2 = moderate, 3 = nice-to-have)"
            ]
        ],
        "required": ["topic", "kind", "summary", "how_to_use_in_question", "priority"],
        "additionalProperties": false
    ]
}
