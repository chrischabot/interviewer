import Foundation

/// Input context for the Orchestrator to make decisions
struct OrchestratorContext {
    let plan: PlanSnapshot
    let transcript: [TranscriptEntry]
    let notes: NotesState
    let research: [ResearchItem]
    let elapsedSeconds: Int
    let targetSeconds: Int
    let askedQuestionIds: Set<String>  // Track which planned questions have been asked
    let recentlyAskedTexts: [String]   // Recent question texts to avoid repetition
    let askedThemes: Set<String>       // Themes already covered to avoid thematic repetition
}

/// Lightweight snapshot of Plan for agent communication (avoids SwiftData in actor)
struct PlanSnapshot: Codable {
    let topic: String
    let researchGoal: String
    let angle: String
    let sections: [SectionSnapshot]

    struct SectionSnapshot: Codable {
        let id: String
        let title: String
        let importance: String
        let questions: [QuestionSnapshot]
    }

    struct QuestionSnapshot: Codable {
        let id: String
        let text: String
        let role: String
        let priority: Int
        let notesForInterviewer: String
    }
}

/// OrchestratorAgent decides the next question based on plan, notes, research, and timing
actor OrchestratorAgent {
    private let llm: LLMClient
    private var modelConfig: LLMModelConfig
    private var lastActivityTime: Date?

    init(client: LLMClient, modelConfig: LLMModelConfig) {
        self.llm = client
        self.modelConfig = modelConfig
    }

    /// Decide the next question to ask
    func decideNextQuestion(context: OrchestratorContext) async throws -> OrchestratorDecision {
        lastActivityTime = Date()

        let progress = Int(Double(context.elapsedSeconds) / Double(context.targetSeconds) * 100)
        AgentLogger.orchestratorThinking(progress: progress, questionsAsked: context.askedQuestionIds.count)

        let userPrompt = buildUserPrompt(from: context)

        let decision: OrchestratorDecision = try await llm.chatStructured(
            messages: [
                Message.system(Self.systemPrompt),
                Message.user(userPrompt)
            ],
            model: modelConfig.insightModel,
            schemaName: "orchestrator_decision_schema",
            schema: Self.jsonSchema,
            maxTokens: nil
        )

        AgentLogger.orchestratorDecided(
            phase: decision.phase,
            source: decision.nextQuestion.source,
            question: decision.nextQuestion.text
        )
        AgentLogger.orchestratorBrief(brief: decision.interviewerBrief)

        return decision
    }

    /// Activity score for UI meters (0-1 based on recency)
    func getActivityScore() -> Double {
        guard let lastActivity = lastActivityTime else { return 0.0 }
        let elapsed = Date().timeIntervalSince(lastActivity)
        return max(0, 1.0 - (elapsed / 30.0))
    }

    // MARK: - Prompt Building

    private func buildUserPrompt(from context: OrchestratorContext) -> String {
        let timeRemaining = context.targetSeconds - context.elapsedSeconds
        let timeProgress = Double(context.elapsedSeconds) / Double(context.targetSeconds)

        // Determine suggested phase based on time
        let suggestedPhase: String
        if timeProgress < 0.15 {
            suggestedPhase = "opening"
        } else if timeProgress > 0.85 {
            suggestedPhase = "wrap_up"
        } else {
            suggestedPhase = "deep_dive"
        }

        // Build transcript summary (last ~10 exchanges)
        let recentTranscript = context.transcript.suffix(20)
        let transcriptText = recentTranscript.map { entry in
            let speaker = entry.speaker == "assistant" ? "Interviewer" : "Expert"
            return "[\(speaker)]: \(entry.text)"
        }.joined(separator: "\n\n")

        // Build plan summary with question coverage - INCLUDE IDs so LLM can return them
        var planSummary = ""
        for section in context.plan.sections {
            let sectionAsked = section.questions.filter { context.askedQuestionIds.contains($0.id) }.count
            let sectionTotal = section.questions.count
            planSummary += """

            ### \(section.title) (section_id: \(section.id)) [\(sectionAsked)/\(sectionTotal) asked, \(section.importance) importance]

            """
            for q in section.questions {
                let status = context.askedQuestionIds.contains(q.id) ? "✓ ASKED" : "○ NOT ASKED"
                // Include question ID so the model can reference it in source_question_id
                planSummary += "  \(status) [id: \(q.id)] [P\(q.priority)] \(q.text)\n"
            }
        }

        // Build recently asked questions to avoid repetition
        var recentlyAskedSummary = ""
        if !context.recentlyAskedTexts.isEmpty {
            recentlyAskedSummary = "**Recently Asked Questions (DO NOT REPEAT OR REPHRASE THESE):**\n"
            for (index, text) in context.recentlyAskedTexts.suffix(5).enumerated() {
                let shortText = String(text.prefix(100))
                recentlyAskedSummary += "\(index + 1). \(shortText)...\n"
            }
        }

        // Build themes already covered to avoid thematic repetition
        var themesSummary = ""
        if !context.askedThemes.isEmpty {
            let themesList = context.askedThemes.sorted().joined(separator: ", ")
            themesSummary = "**Themes Already Covered (AVOID THESE):** \(themesList)\n"
        }

        // Build notes summary
        var notesSummary = ""
        if !context.notes.keyIdeas.isEmpty {
            notesSummary += "**Key Ideas Captured:**\n"
            notesSummary += context.notes.keyIdeas.prefix(5).map { "- \($0.text)" }.joined(separator: "\n")
            notesSummary += "\n\n"
        }
        if !context.notes.gaps.isEmpty {
            notesSummary += "**Gaps to Explore:**\n"
            for gap in context.notes.gaps.prefix(3) {
                notesSummary += "- \(gap.description)\n  → Suggested: \(gap.suggestedFollowup)\n"
            }
            notesSummary += "\n"
        }
        if !context.notes.contradictions.isEmpty {
            notesSummary += "**Contradictions to Clarify:**\n"
            for contradiction in context.notes.contradictions.prefix(2) {
                notesSummary += "- \(contradiction.description)\n"
                notesSummary += "  First: \"\(contradiction.firstQuote)\"\n"
                notesSummary += "  Second: \"\(contradiction.secondQuote)\"\n"
                notesSummary += "  → Suggested: \(contradiction.suggestedClarificationQuestion)\n"
            }
            notesSummary += "\n"
        }
        // Add section coverage quality - critical for knowing which sections need more depth
        if !context.notes.sectionCoverage.isEmpty {
            notesSummary += "**Section Coverage Quality:**\n"
            for coverage in context.notes.sectionCoverage {
                let emoji = switch coverage.coverageQuality {
                case "deep": "✅"
                case "adequate": "🟢"
                case "shallow": "🟡"
                default: "⚪️"
                }
                notesSummary += "- \(emoji) \(coverage.sectionTitle): \(coverage.coverageQuality.uppercased())"
                if !coverage.missingAspects.isEmpty {
                    notesSummary += " (Missing: \(coverage.missingAspects.joined(separator: ", ")))"
                }
                if let followup = coverage.suggestedFollowup, !followup.isEmpty {
                    notesSummary += "\n  → Suggested: \(followup)"
                }
                notesSummary += "\n"
            }
            notesSummary += "\n"
        }

        // Build research summary
        var researchSummary = ""
        if !context.research.isEmpty {
            researchSummary = "**Research Insights Available:**\n"
            for item in context.research.sorted(by: { $0.priority < $1.priority }).prefix(5) {
                researchSummary += "- [\(item.kind)] \(item.topic): \(item.summary)\n"
                researchSummary += "  → How to use: \(item.howToUseInQuestion)\n"
            }
        }

        return """
        ## Interview Status

        **Topic:** \(context.plan.topic)
        **Research Goal:** \(context.plan.researchGoal)
        **Angle:** \(context.plan.angle)

        **Time:** \(formatTime(context.elapsedSeconds)) elapsed / \(formatTime(context.targetSeconds)) total (\(formatTime(timeRemaining)) remaining)
        **Suggested Phase:** \(suggestedPhase)

        ---

        ## Interview Plan (Question Coverage)
        \(planSummary)

        ---

        \(recentlyAskedSummary.isEmpty ? "" : recentlyAskedSummary + "\n")
        \(themesSummary.isEmpty ? "" : themesSummary + "\n---\n")

        ## Notes from Conversation
        \(notesSummary.isEmpty ? "(No significant notes yet)" : notesSummary)

        ---

        ## Research
        \(researchSummary.isEmpty ? "(No research items available)" : researchSummary)

        ---

        ## Recent Transcript
        \(transcriptText.isEmpty ? "(Interview just started)" : transcriptText)

        ---

        Based on all of the above, decide:
        1. What phase are we in? (opening, deep_dive, wrap_up)
        2. What is the best next question to ask?
        3. How should the interviewer approach this question?

        **CRITICAL RULES:**
        - NEVER suggest a question similar to one in "Recently Asked Questions"
        - AVOID questions touching themes listed in "Themes Already Covered"
        - If the expert already answered something, move to a DIFFERENT topic
        - Prioritize P1 questions marked "○ NOT ASKED"
        - Each question should explore a DIFFERENT aspect than previous questions
        - In wrap_up phase, focus on synthesis and closing reflection
        - Do NOT ask the same closing question twice (e.g., "what do you wish people understood")
        """
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - System Prompt

    static let systemPrompt = """
    You are the Orchestrator for a live podcast-style interview. Your job is to decide the next question to ask based on:

    1. **The Interview Plan** - A structured set of sections and questions with priorities
    2. **Notes from the Conversation** - Key ideas, stories, gaps, and contradictions identified
    3. **Research Insights** - Background information that could enrich questions
    4. **Time Remaining** - How much time is left in the interview

    **Your Decision Philosophy:**

    - **Opening Phase** (first ~15% of time): Clarify context and stakes. Ask broad questions that let the expert orient the conversation.

    - **Deep Dive Phase** (middle ~70%): This is where the magic happens. Alternate between:
      - Backbone questions from the plan (ensure must-hit topics are covered)
      - Follow-ups on interesting threads the expert introduced
      - Probing gaps or contradictions
      - Using research insights to ask smarter questions

    - **Wrap Up Phase** (final ~15%): Synthesize and reflect. Ask:
      - "What's the one thing you wish more people understood about X?"
      - "If you could go back and do one thing differently..."
      - "What's the biggest misconception about X?"

    **Question Sources:**
    - `plan` - From the interview plan
    - `gap` - Addressing a gap in coverage
    - `contradiction` - Clarifying a contradiction
    - `research` - Incorporating research insights

    **⚠️ CRITICAL - AVOID REPETITION:**
    - Check the "Recently Asked Questions" list - NEVER ask a similar question
    - If you see a question about "examples" was already asked, don't ask for more examples
    - If you see a question about "industries" was already asked, don't ask about industries again
    - Each new question MUST explore a genuinely DIFFERENT aspect of the topic
    - Variety is key to a good interview - don't circle back to the same themes

    **Guidelines:**
    - Prioritize P1 questions marked "○ NOT ASKED" - these are must-hit
    - NEVER suggest questions marked "✓ ASKED" - those have already been covered
    - When following up, reference what the expert said: "You mentioned X..."
    - Provide a brief for the interviewer on HOW to ask the question (tone, framing)
    - Keep the conversation flowing naturally - don't make it feel like an interrogation
    - If the expert is on a great tangent, suggest letting them continue before redirecting

    **CRITICAL - Question Tracking:**
    - Each question in the plan has a unique `id` shown in brackets like `[id: ABC123]`
    - When you choose a question from the plan, you MUST set `source_question_id` to that exact ID
    - This is how we track coverage - if you don't return the ID, we can't mark it as asked
    - For gap/contradiction/research questions, set `source_question_id` to null
    """

    // MARK: - JSON Schema

    nonisolated(unsafe) static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "phase": [
                "type": "string",
                "enum": ["opening", "deep_dive", "wrap_up"],
                "description": "Current interview phase based on time and content"
            ],
            "next_question": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "The question to ask (can be adapted from plan or newly crafted)"],
                    "target_section_id": ["type": "string", "description": "ID of the section this question relates to"],
                    "source": [
                        "type": "string",
                        "enum": ["plan", "gap", "contradiction", "research"],
                        "description": "What prompted this question"
                    ],
                    "source_question_id": [
                        "type": ["string", "null"],
                        "description": "ID of the original plan question if source is 'plan', null otherwise"
                    ],
                    "expected_answer_seconds": [
                        "type": "integer",
                        "description": "Estimated time for the expert to answer (30-120 seconds typical)"
                    ]
                ],
                "required": ["text", "target_section_id", "source", "source_question_id", "expected_answer_seconds"],
                "additionalProperties": false
            ],
            "interviewer_brief": [
                "type": "string",
                "description": "Guidance for the interviewer on how to ask this question (tone, framing, context to mention)"
            ]
        ],
        "required": ["phase", "next_question", "interviewer_brief"],
        "additionalProperties": false
    ]
}

// MARK: - Plan Snapshot Creation

extension Plan {
    func toSnapshot() -> PlanSnapshot {
        PlanSnapshot(
            topic: topic,
            researchGoal: researchGoal,
            angle: angle,
            sections: sections.sorted(by: { $0.sortOrder < $1.sortOrder }).map { section in
                PlanSnapshot.SectionSnapshot(
                    id: section.id.uuidString,
                    title: section.title,
                    importance: section.importance,
                    questions: section.questions.sorted(by: { $0.sortOrder < $1.sortOrder }).map { question in
                        PlanSnapshot.QuestionSnapshot(
                            id: question.id.uuidString,
                            text: question.text,
                            role: question.role,
                            priority: question.priority,
                            notesForInterviewer: question.notesForInterviewer
                        )
                    }
                )
            }
        )
    }
}
