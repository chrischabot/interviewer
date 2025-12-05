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
    private let client: OpenAIClient
    private var lastActivityTime: Date?

    init(client: OpenAIClient = .shared) {
        self.client = client
    }

    /// Decide the next question to ask
    func decideNextQuestion(context: OrchestratorContext) async throws -> OrchestratorDecision {
        lastActivityTime = Date()

        let progress = Int(Double(context.elapsedSeconds) / Double(context.targetSeconds) * 100)
        AgentLogger.orchestratorThinking(progress: progress, questionsAsked: context.askedQuestionIds.count)

        let userPrompt = buildUserPrompt(from: context)

        let response = try await client.chatCompletion(
            messages: [
                Message.system(Self.systemPrompt),
                Message.user(userPrompt)
            ],
            model: "gpt-4o",
            responseFormat: .jsonSchema(name: "orchestrator_decision_schema", schema: Self.jsonSchema)
        )

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            AgentLogger.error(agent: "Orchestrator", message: "Invalid response from API")
            throw OpenAIError.invalidResponse
        }

        let decision = try JSONDecoder().decode(OrchestratorDecision.self, from: data)

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

        // Build plan summary with question coverage
        var planSummary = ""
        for section in context.plan.sections {
            let sectionAsked = section.questions.filter { context.askedQuestionIds.contains($0.id) }.count
            let sectionTotal = section.questions.count
            planSummary += """

            ### \(section.title) [\(sectionAsked)/\(sectionTotal) asked, \(section.importance) importance]

            """
            for q in section.questions {
                let status = context.askedQuestionIds.contains(q.id) ? "✓" : "○"
                planSummary += "  \(status) [P\(q.priority)] \(q.text)\n"
            }
        }

        // Build notes summary
        var notesSummary = ""
        if !context.notes.keyIdeas.isEmpty {
            notesSummary += "**Key Ideas Captured:**\n"
            notesSummary += context.notes.keyIdeas.map { "- \($0.text)" }.joined(separator: "\n")
            notesSummary += "\n\n"
        }
        if !context.notes.gaps.isEmpty {
            notesSummary += "**Gaps to Explore:**\n"
            for gap in context.notes.gaps {
                notesSummary += "- \(gap.description)\n  → Suggested: \(gap.suggestedFollowup)\n"
            }
            notesSummary += "\n"
        }
        if !context.notes.contradictions.isEmpty {
            notesSummary += "**Contradictions to Clarify:**\n"
            for contradiction in context.notes.contradictions {
                notesSummary += "- \(contradiction.description)\n"
                notesSummary += "  First: \"\(contradiction.firstQuote)\"\n"
                notesSummary += "  Second: \"\(contradiction.secondQuote)\"\n"
                notesSummary += "  → Suggested: \(contradiction.suggestedClarificationQuestion)\n"
            }
            notesSummary += "\n"
        }

        // Build research summary
        var researchSummary = ""
        if !context.research.isEmpty {
            researchSummary = "**Research Insights Available:**\n"
            for item in context.research.sorted(by: { $0.priority < $1.priority }) {
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

        Consider:
        - Prioritize P1 (must-hit) questions if they haven't been asked
        - If the expert mentioned something interesting, follow up on it
        - If there's a gap or contradiction, address it
        - If research provides a useful insight, incorporate it
        - In wrap_up phase, focus on synthesis and closing reflection
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

    **Guidelines:**
    - Prioritize P1 questions - these are must-hit
    - Don't ask questions that have already been answered
    - When following up, reference what the expert said: "You mentioned X..."
    - Provide a brief for the interviewer on HOW to ask the question (tone, framing)
    - Keep the conversation flowing naturally - don't make it feel like an interrogation
    - If the expert is on a great tangent, suggest letting them continue before redirecting
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
                    "expected_answer_seconds": [
                        "type": "integer",
                        "description": "Estimated time for the expert to answer (30-120 seconds typical)"
                    ]
                ],
                "required": ["text", "target_section_id", "source", "expected_answer_seconds"],
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

