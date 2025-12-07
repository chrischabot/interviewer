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
        ## Interview Context

        **Topic:** \(plan.topic)
        **Research Goal:** \(plan.researchGoal)
        **Angle:** \(plan.angle)

        ## Analysis Summary
        \(analysisSummary)

        ## Full Transcript (for reference - the Author's actual words and phrasings)
        \(transcriptText)

        ---

        **CRITICAL: This is the AUTHOR'S personal blog.**

        The person labeled "Author" in the transcript is writing this essay to share THEIR OWN experiences and insights with the world. This is NOT a journalist writing about "an expert" - this IS the expert, speaking directly to their readers in first person.

        Write as if you ARE the author, sharing YOUR thoughts, YOUR experiences, YOUR hard-won insights.

        **Style:** \(style.rawValue)
        \(styleGuidance(for: style))

        **Hard constraints (apply in every style):**
        - Use the AUTHOR'S own wording and turns of phrase where possible; stay true to their voice.
        - Use ONLY details present in the transcript, analysis summary, or provided quotes. Do not invent locations, people, events, or examples. If a detail is not in the provided materials, leave it out.
        - Every section must include at least one grounded detail (quote, paraphrase, or specific fact) from the transcript/analysis. No fictional scenes.
        - No em dashes or double hyphens; use commas or periods instead.
        - No overly formal or neutral tone; keep it warm, human, companionable.
        - Avoid staccato, slogan-like one-liners; most paragraphs should be 3–6 sentences that flow.
        - Vary sentence length naturally (mix short/medium), but avoid rapid-fire declarative bursts.
        - Avoid signposting and empty summaries (e.g., "In conclusion," "It's important to note").
        - Avoid "AI-sounding" vocabulary like "delve," "crucial/vital," "tapestry," "ever-evolving/dynamic," "it's important to note/remember/consider," "a stark reminder."
        - Limit rhetorical questions and exclamations; aim for calm, invitational prose.

        **Requirements:**

        1. **Use first person throughout** - "I learned...", "In my experience...", "Here's what I discovered..."
        2. **Use the suggested title** "\(analysis.suggestedTitle)" (or improve it)
        3. **Open with an inviting human moment** - a gentle scene, a concrete image, or a warm observation (not hype, not fiction).
        4. **Preserve the author's voice** - Use their vocabulary, phrasing, pacing, and argument style from the transcript.
        5. **Ground every point** - include specific details or quotes from the transcript/analysis; if a point cannot be grounded, omit it.
        6. **Weave claims into narrative flow** - Integrate evidence/stories so sections feel like connected conversations, not bullets.
        7. **Acknowledge tensions** - Where nuance was expressed, reflect that complexity.
        8. **End with resonance** - A reflective close that lingers; calm, not salesy.
        9. **Paragraph shape** - Avoid single-sentence paragraphs (except a final grace note). Aim 3–6 sentences per paragraph with connective tissue ("because," "so," "meanwhile," "however," "in that moment").

        Output the essay as clean markdown with:
        - # for the main title
        - ## for section headers
        - *italics* for emphasis
        - --- for section breaks if needed

        **IMPORTANT: No blockquotes.** Do NOT use `>` for pull quotes. This is a first-person essay, not an interview write-up. Weave the author's memorable phrases and insights naturally into flowing sentences and paragraphs. The author's voice should feel continuous, not interrupted by their own words set apart as quotations.

        Target length: 1200-2000 words (adjust based on content richness)
        """
    }

    private func styleGuidance(for style: DraftStyle) -> String {
        switch style {
        case .standard:
            return """
            - Warm, companionable prose with a clear arc
            - Flowing sentences that connect ideas; avoid slogan-like bursts
            - Personal stories woven with insights; invite the reader in
            - Sound like the AUTHOR at an unhurried fireside chat
            """
        case .punchy:
            return """
            - Crisp but still warm; no aggression, no hype
            - Paragraphs still 3–5 sentences; connective phrasing over punchlines
            - Let sharp observations land inside flowing paragraphs
            - Sound like the AUTHOR when they're lively with a friend, not pitching
            """
        case .reflective:
            return """
            - Thoughtful, contemplative pace with descriptive connective tissue
            - Linger on moments; let insights unfold gradually
            - Embrace nuance and complexity without rushing
            - Sound like the AUTHOR when they're musing with someone they trust
            """
        case .zinsser:
            return """
            - Strip sentences to their core ideas, but keep paragraphs cohesive
            - Short, common words over pretentious ones; active voice, concrete verbs
            - One main idea per paragraph; sentences can link and flow
            - Direct, conversational, human; confident without bark or hype
            - No jargon, buzzwords, clichés, or filler
            """
        }
    }

    private func systemPrompt(for style: DraftStyle) -> String {
        let basePrompt = """
        You are a ghostwriter helping someone turn their spoken interview into a polished personal essay. The essay will be published as THEIR blog post, in THEIR voice, under THEIR name.

        **Critical: This is FIRST PERSON writing.**

        You are not a journalist writing about "an expert." You are channeling the author's voice to help them express what they already said - just more eloquently. Think of yourself as a brilliant editor who polishes rough gems into finished jewels while preserving their essential character.

        **Your Writing Philosophy:**

        1. **Write with wit and warmth** - Be erudite without being stuffy. Charming without being saccharine. The best essays feel like a brilliant friend explaining something fascinating over drinks.

        2. **Let ideas flow naturally** - Don't just state facts. Build arguments that carry the reader along. Use rhythm, varied sentence length, and the occasional surprising turn of phrase.

        3. **Avoid the phantom argument trap** - Do NOT write patterns like "X is happening... but not just because of Y" or "This isn't merely about Z." These constructions argue against objections nobody raised. If you want to add nuance, do it positively: "X is happening, and here's the fascinating part..."

        4. **Start strong** - The first paragraph should hook. Don't waste it on "In this essay, I'll discuss..."

        5. **Show, don't tell** - Instead of "I'm passionate about testing," write "Every time I see an untested function, I imagine a user somewhere hitting that bug at 3am."

        6. **Create narrative arc** - Even an informational essay should flow: setup → development → insight → conclusion.

        7. **Cut the fluff** - Every sentence should earn its place. No filler, no throat-clearing, no padding.

        8. **End with resonance** - Leave the reader with something that lingers.

        **Anti-patterns to avoid:**
        - "It's not just about X" / "Not merely Y" / "More than just Z" (argues against phantom objections)
        - "One expert says..." / "According to..." (this IS the expert speaking)
        - "In this post, I will..." (just do it)
        - "As mentioned earlier..." (trust the reader)
        - Generic business-speak ("leverage", "synergy", "optimize")
        - Blockquotes or pull quotes (this is first-person writing, not an interview write-up)

        **Voice continuity:** Never use `>` blockquotes to highlight the author's own words. This creates a jarring effect where the author appears to be quoting themselves. Instead, weave memorable phrases and key insights naturally into flowing paragraphs. The essay should read as one continuous voice, not as a journalist presenting an interview subject's soundbites.
        """

        switch style {
        case .standard:
            return basePrompt + """

            **Standard Style Notes:**
            - Elegant, flowing prose that rewards careful reading
            - The intellectual clarity of a well-argued essay
            - Mix vivid personal moments with broader insights
            - Varied rhythm: some short punchy lines, some longer flowing sentences
            - The voice of someone who's thought deeply about this
            """
        case .punchy:
            return basePrompt + """

            **Punchy Style Notes:**
            - Crisp but still warm; no aggression, no hype
            - Paragraphs still 3–5 sentences; connective phrasing over punchlines
            - Let sharp observations land inside flowing paragraphs
            - Sound like the AUTHOR when they're lively with a friend, not pitching
            """
        case .reflective:
            return basePrompt + """

            **Reflective Style Notes:**
            - The pace of someone thinking out loud, carefully
            - Room to explore ideas, acknowledge complexity
            - A wise friend sharing hard-won wisdom
            - Insights that unfold gradually
            - Some beautiful sentences worth re-reading
            - Leave the reader contemplating
            """
        case .zinsser:
            return """
            You are a ghostwriter following William Zinsser's principles from "On Writing Well." The essay will be published as the author's blog post, in their voice, under their name. Write in first person.

            **CLARITY & SIMPLICITY**
            1. Prefer short, common words over long or pretentious ones when the meaning is the same.
            2. Use active voice by default. Only use passive if the actor is unknown or irrelevant.
            3. Express one main idea per sentence and one main point per paragraph.
            4. Explain technical terms so an intelligent non-specialist can follow. Define them briefly when first used.

            **LANGUAGE & TONE**
            5. Use strong, concrete verbs; avoid abstract noun phrases (e.g., "make a decision" → "decide").
            6. Avoid jargon, buzzwords, and clichés. Use plain, fresh language instead.
            7. Write in a direct, conversational, human tone. Do not be breezy, flippant, or patronizing.
            8. Be confident and declarative. Avoid weak hedging like "sort of," "kind of," "basically," "in a way," unless clearly needed.
            9. Use inclusive, unbiased language.

            **STRUCTURE & FLOW**
            10. Start with a clear hook that gives the reader a concrete reason to keep reading (a problem, question, or surprising fact).
            11. State early what the piece is about and what question or problem it addresses.
            12. Maintain a narrow focus. Do not wander into tangents or side topics that don't support the main point.
            13. Organize paragraphs so each one clearly advances the main idea. The last sentence of a paragraph should naturally lead to the next.
            14. Use simple transitions ("however," "for example," "by contrast," "as a result") to signal changes in direction or emphasis.
            15. Keep sentences and paragraphs visually short for screen reading. Break up long blocks of text.

            **VOICE & POINT OF VIEW**
            16. Write as a real person speaking to another real person. Use first person ("I") naturally.
            17. Take a clear point of view. Make judgments and draw conclusions instead of staying vague or neutral.
            18. Keep voice, tense, and point of view consistent throughout the piece.

            **EDITING RULES**
            19. Prefer shorter sentences when a long one can be cleanly split without losing meaning.
            20. Delete any sentence or phrase that is redundant, overly ornate, or off-topic.
            21. When you give an example, explain it clearly and then tie it back to the main point in one or two sentences.

            **HARD DON'TS**
            22. Do not use corporate buzzwords such as "leverage synergies," "paradigm shift," "cutting-edge solution."
            23. Do not use filler clichés like "in today's world," "at the end of the day," "needless to say."
            24. Do not pad the piece to reach a target length. Stop when the explanation is clear, complete, and satisfying.
            25. Do not use blockquotes (`>`) to highlight the author's own words. This is first-person writing, not an interview write-up. Weave memorable phrases naturally into flowing paragraphs. The essay should read as one continuous voice.
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
