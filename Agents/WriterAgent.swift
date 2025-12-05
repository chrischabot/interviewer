import Foundation

/// Response structure from the Writer agent
struct WriterResponse: Codable {
    let markdown: String
    let wordCount: Int
    let estimatedReadingMinutes: Int

    enum CodingKeys: String, CodingKey {
        case markdown
        case wordCount = "word_count"
        case estimatedReadingMinutes = "estimated_reading_minutes"
    }
}

/// WriterAgent generates blog-style narrative essays from interview analysis
actor WriterAgent {
    private let client: OpenAIClient
    private var lastActivityTime: Date?

    init(client: OpenAIClient = .shared) {
        self.client = client
    }

    /// Generate a blog post draft from analysis
    func writeDraft(
        transcript: [TranscriptEntry],
        analysis: AnalysisSummary,
        plan: PlanSnapshot,
        style: DraftStyle = .standard
    ) async throws -> String {
        lastActivityTime = Date()

        AgentLogger.writerStarted(style: style.displayName)

        // Build full transcript for reference
        let transcriptText = transcript.map { entry in
            let speaker = entry.speaker == "assistant" ? "Interviewer" : "Expert"
            return "[\(speaker)]: \(entry.text)"
        }.joined(separator: "\n\n")

        // Build analysis summary
        let analysisSummary = buildAnalysisSummary(analysis)

        let userPrompt = """
        ## Interview Context

        **Topic:** \(plan.topic)
        **Research Goal:** \(plan.researchGoal)
        **Angle:** \(plan.angle)

        ## Analysis Summary
        \(analysisSummary)

        ## Full Transcript (for exact quotes)
        \(transcriptText)

        ---

        Write a compelling blog post essay based on this interview.

        **Style:** \(style.rawValue)
        \(styleGuidance(for: style))

        **Requirements:**

        1. **Use the suggested title** "\(analysis.suggestedTitle)" (or improve it)
        2. **Open with a hook** - A surprising insight, a vivid scene, or a provocative question
        3. **Weave in direct quotes** - Use the expert's actual words (from the transcript)
        4. **Structure around main claims** - Each major point should have supporting stories/evidence
        5. **Acknowledge tensions** - Where the expert showed nuance, reflect that
        6. **End with a call to action or reflection** - Leave the reader thinking

        Output the essay as clean markdown with:
        - # for the main title
        - ## for section headers
        - > for pull quotes
        - *italics* for emphasis
        - --- for section breaks if needed

        Target length: 1200-2000 words (adjust based on content richness)
        """

        let response = try await client.chatCompletion(
            messages: [
                Message.system(systemPrompt(for: style)),
                Message.user(userPrompt)
            ],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "writer_schema", schema: Self.jsonSchema)
        )

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            AgentLogger.error(agent: "Writer", message: "Invalid response from API")
            throw OpenAIError.invalidResponse
        }

        let writerResponse = try JSONDecoder().decode(WriterResponse.self, from: data)

        AgentLogger.writerComplete(wordCount: writerResponse.wordCount, readingTime: writerResponse.estimatedReadingMinutes)

        return writerResponse.markdown
    }

    /// Activity score for UI meters (0-1 based on recency)
    func getActivityScore() -> Double {
        guard let lastActivity = lastActivityTime else { return 0.0 }
        let elapsed = Date().timeIntervalSince(lastActivity)
        return max(0, 1.0 - (elapsed / 30.0))
    }

    // MARK: - Helpers

    private func buildAnalysisSummary(_ analysis: AnalysisSummary) -> String {
        var parts: [String] = []

        parts.append("**Research Goal Assessment:**\n\(analysis.researchGoal)")

        parts.append("**Main Claims:**\n" + analysis.mainClaims.enumerated().map { i, claim in
            "\(i + 1). \(claim.text)"
        }.joined(separator: "\n"))

        parts.append("**Themes:**\n" + analysis.themes.map { "- \($0)" }.joined(separator: "\n"))

        if !analysis.tensions.isEmpty {
            parts.append("**Tensions/Nuances:**\n" + analysis.tensions.map { "- \($0)" }.joined(separator: "\n"))
        }

        parts.append("**Key Quotes:**\n" + analysis.quotes.map { quote in
            "> \"\(quote.text)\" [\(quote.role)]"
        }.joined(separator: "\n"))

        parts.append("**Suggested Title:** \(analysis.suggestedTitle)")
        if !analysis.suggestedSubtitle.isEmpty {
            parts.append("**Subtitle:** \(analysis.suggestedSubtitle)")
        }

        return parts.joined(separator: "\n\n")
    }

    private func styleGuidance(for style: DraftStyle) -> String {
        switch style {
        case .standard:
            return """
            - Balanced narrative with clear structure
            - Mix of exposition and quotes
            - Professional but accessible tone
            - Medium-length paragraphs
            """
        case .punchy:
            return """
            - Direct and energetic
            - Short paragraphs, punchy sentences
            - Bold statements up front
            - More quotes, less exposition
            - Conversational, slightly provocative
            """
        case .reflective:
            return """
            - Thoughtful and introspective
            - Explore nuances and trade-offs
            - Longer, more considered paragraphs
            - Room for the reader to think
            - Acknowledge complexity
            """
        }
    }

    private func systemPrompt(for style: DraftStyle) -> String {
        let basePrompt = """
        You are an expert essay writer specializing in interview-based content. Your job is to transform a raw interview transcript and analysis into a compelling, readable blog post.

        **Your Writing Philosophy:**

        1. **Start strong** - The first paragraph should hook the reader. Don't waste it on "In this interview, we talked about..."

        2. **Show, don't tell** - Instead of "John is passionate about testing," write "John leans forward, his voice rising. 'Every time I see an untested function, I imagine a user somewhere hitting that bug.'"

        3. **Use the expert's voice** - Direct quotes are gold. They bring authenticity and personality.

        4. **Create narrative arc** - Even an informational essay should have flow: setup → development → insight → conclusion.

        5. **Cut the fluff** - Every sentence should earn its place. No filler, no padding.

        6. **End with resonance** - The conclusion should either call the reader to action or leave them with something to think about.
        """

        switch style {
        case .standard:
            return basePrompt + """

            **Standard Style Notes:**
            - Clear, professional prose
            - Balanced use of quotes and exposition
            - Well-organized sections
            - Accessible to a general audience
            """
        case .punchy:
            return basePrompt + """

            **Punchy Style Notes:**
            - Short sentences. Short paragraphs.
            - Lead with the strongest point
            - Be slightly provocative
            - Use more quotes, fewer transitions
            - Write like you're talking to a smart friend
            """
        case .reflective:
            return basePrompt + """

            **Reflective Style Notes:**
            - Take time to explore ideas
            - Acknowledge complexity and nuance
            - Let insights develop gradually
            - Use thoughtful transitions
            - Leave room for the reader to draw conclusions
            """
        }
    }

    // MARK: - JSON Schema

    nonisolated(unsafe) static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "markdown": [
                "type": "string",
                "description": "The complete essay in markdown format"
            ],
            "word_count": [
                "type": "integer",
                "description": "Approximate word count of the essay"
            ],
            "estimated_reading_minutes": [
                "type": "integer",
                "description": "Estimated reading time in minutes"
            ]
        ],
        "required": ["markdown", "word_count", "estimated_reading_minutes"],
        "additionalProperties": false
    ]
}
