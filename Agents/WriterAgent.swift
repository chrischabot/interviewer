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
    private let llm: LLMClient
    private var modelConfig: LLMModelConfig
    private var lastActivityTime: Date?

    init(client: LLMClient, modelConfig: LLMModelConfig) {
        self.llm = client
        self.modelConfig = modelConfig
    }

    /// Generate a blog post draft from analysis
    /// - Parameters:
    ///   - transcript: Current session transcript
    ///   - analysis: Analysis summary
    ///   - plan: The interview plan
    ///   - style: Writing style
    ///   - previousTranscript: Optional transcript from a previous session (for follow-ups)
    func writeDraft(
        transcript: [TranscriptEntry],
        analysis: AnalysisSummary,
        plan: PlanSnapshot,
        style: DraftStyle = .standard,
        previousTranscript: [TranscriptEntry]? = nil
    ) async throws -> String {
        lastActivityTime = Date()

        AgentLogger.writerStarted(style: style.displayName)

        let userPrompt = buildUserPrompt(
            transcript: transcript,
            previousTranscript: previousTranscript,
            analysis: analysis,
            plan: plan,
            style: style
        )

        let writerResponse: WriterResponse = try await llm.chatStructured(
            messages: [
                Message.system(systemPrompt(for: style)),
                Message.user(userPrompt)
            ],
            model: modelConfig.insightModel,
            schemaName: "writer_schema",
            schema: Self.jsonSchema,
            maxTokens: nil
        )

        AgentLogger.writerComplete(wordCount: writerResponse.wordCount, readingTime: writerResponse.estimatedReadingMinutes)

        return writerResponse.markdown
    }

    /// Stream a blog post draft from analysis, yielding markdown chunks as they arrive
    /// - Parameters:
    ///   - transcript: Current session transcript
    ///   - analysis: Analysis summary
    ///   - plan: The interview plan
    ///   - style: Writing style
    ///   - previousTranscript: Optional transcript from a previous session (for follow-ups)
    func writeDraftStreaming(
        transcript: [TranscriptEntry],
        analysis: AnalysisSummary,
        plan: PlanSnapshot,
        style: DraftStyle = .standard,
        previousTranscript: [TranscriptEntry]? = nil
    ) -> AsyncThrowingStream<String, Error> {
        lastActivityTime = Date()

        AgentLogger.writerStarted(style: style.displayName)

        let userPrompt = buildUserPrompt(
            transcript: transcript,
            previousTranscript: previousTranscript,
            analysis: analysis,
            plan: plan,
            style: style
        )

        return llm.chatTextStreaming(
            messages: [
                Message.system(systemPrompt(for: style)),
                Message.user(userPrompt)
            ],
            model: modelConfig.insightModel,
            maxTokens: nil
        )
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

    private func buildUserPrompt(
        transcript: [TranscriptEntry],
        previousTranscript: [TranscriptEntry]?,
        analysis: AnalysisSummary,
        plan: PlanSnapshot,
        style: DraftStyle
    ) -> String {
        // Build full transcript for reference
        var transcriptText = ""

        if let previous = previousTranscript, !previous.isEmpty {
            let previousText = previous.map { entry in
                let speaker = entry.speaker == "assistant" ? "Interviewer" : "Author"
                return "[\(speaker)]: \(entry.text)"
            }.joined(separator: "\n\n")

            transcriptText = """
            ### Original Conversation
            \(previousText)

            ---

            ### Follow-Up Conversation
            """
        }

        let currentText = transcript.map { entry in
            let speaker = entry.speaker == "assistant" ? "Interviewer" : "Author"
            return "[\(speaker)]: \(entry.text)"
        }.joined(separator: "\n\n")

        transcriptText += currentText

        // Build analysis summary
        let analysisSummary = buildAnalysisSummary(analysis)

        return """
        **Topic:** \(plan.topic)
        **Angle:** \(plan.angle)
        **Suggested title:** \(analysis.suggestedTitle)

        ## Analysis
        \(analysisSummary)

        ## Transcript
        \(transcriptText)

        ---

        Write a first-person essay for the author's blog. Use their words and phrasings. Only include details from the transcript—invent nothing.

        Output clean markdown: # title, ## sections, *italics* for emphasis. Be as long as the ideas require—no padding.
        """
    }

    private func styleGuidance(for style: DraftStyle) -> String {
        switch style {
        case .standard:
            return "Conversational rhythm, ideas that surprise, warmth without saccharine."
        case .punchy:
            return "Crisp sentences, ideas land fast, energy without hype."
        case .reflective:
            return "Slower pace, ideas unfold, room for nuance and complexity."
        }
    }

    private func systemPrompt(for style: DraftStyle) -> String {
        """
        You ghostwrite first-person essays in the style of Paul Graham or Derek Sivers—conversational, surprising, ruthlessly edited.

        Write for smart readers. Stop explaining the moment they'd get it. One example is enough—never give three when one makes the point. Trust their intelligence to draw implications.

        Simple words. Sentences that flow into each other. Single-sentence paragraphs are rare punctuation (2-3 per essay max), not a rhythm. No bullet points—weave lists into prose.

        Never open by announcing the topic. Start with something surprising or concrete that hooks.

        Use the author's own words from the transcript. This is THEIR voice, first person throughout. Polish their rough gems—don't replace them with generic prose.

        No blockquotes. No "It's not just about X." No signposting. No AI-speak (delve, crucial, tapestry, ever-evolving). No em dashes.

        Style: \(styleGuidance(for: style))
        """
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
