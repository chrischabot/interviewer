import Foundation

/// Result of processing a live update during interview
struct LiveUpdateResult {
    let notes: NotesState
    let newResearchItems: [ResearchItem]
    let decision: OrchestratorDecision
    let interviewerInstructions: String  // Combined instructions to send to Realtime API
}

/// Coordinates all agents and provides a unified interface for the app
actor AgentCoordinator {
    static let shared = AgentCoordinator()

    private let openAIClient: OpenAIClient

    // Pre-interview agent
    private let plannerAgent: PlannerAgent

    // Live interview agents
    private let noteTakerAgent: NoteTakerAgent
    private let researcherAgent: ResearcherAgent
    private let orchestratorAgent: OrchestratorAgent

    // Post-interview agents
    private let analysisAgent: AnalysisAgent
    private let writerAgent: WriterAgent

    // Accumulated state during interview
    private var accumulatedResearch: [ResearchItem] = []
    private var askedQuestionIds: Set<String> = []
    private var finalNotes: NotesState = .empty

    // Agent activity tracking for UI meters
    private var agentActivity: [String: Double] = [:]

    // Transcript windowing configuration to control prompt size
    private let maxTranscriptEntriesForNotes = 20      // Note-taker gets recent context
    private let maxTranscriptEntriesForResearch = 20   // Researcher needs enough context to identify topics
    private let maxTranscriptEntriesForOrchestrator = 30  // Orchestrator needs more for decisions

    private init() {
        self.openAIClient = OpenAIClient.shared
        self.plannerAgent = PlannerAgent(client: openAIClient)
        self.noteTakerAgent = NoteTakerAgent(client: openAIClient)
        self.researcherAgent = ResearcherAgent(client: openAIClient)
        self.orchestratorAgent = OrchestratorAgent(client: openAIClient)
        self.analysisAgent = AnalysisAgent(client: openAIClient)
        self.writerAgent = WriterAgent(client: openAIClient)
    }

    // MARK: - Session Management

    /// Reset state for a new interview session
    func startNewSession() async {
        AgentLogger.sessionStarted()
        accumulatedResearch = []
        askedQuestionIds = []
        agentActivity = [:]
        finalNotes = .empty

        // Reset agent state
        await researcherAgent.reset()
    }

    /// Store final notes when interview ends (for use in post-processing)
    func storeNotes(_ notes: NotesState) {
        finalNotes = notes
    }

    /// Get the final notes from the session
    func getFinalNotes() -> NotesState {
        finalNotes
    }

    /// Window transcript to a maximum number of recent entries
    /// Returns the most recent entries to control prompt size
    private func windowTranscript(_ transcript: [TranscriptEntry], maxEntries: Int) -> [TranscriptEntry] {
        guard transcript.count > maxEntries else { return transcript }
        return Array(transcript.suffix(maxEntries))
    }

    /// Mark a question as asked (for tracking coverage)
    func markQuestionAsked(_ questionId: String) {
        askedQuestionIds.insert(questionId)
    }

    // MARK: - Pre-Interview (Phase 2)

    /// Generate an interview plan from user input
    func generatePlan(topic: String, context: String, targetMinutes: Int) async throws -> PlannerResponse {
        updateActivity(agent: "planner", score: 1.0)
        defer { updateActivity(agent: "planner", score: 0.5) }

        return try await plannerAgent.generatePlan(
            topic: topic,
            context: context,
            targetMinutes: targetMinutes
        )
    }

    // MARK: - Live Interview (Phase 4)

    /// Process a live update during the interview
    /// Runs NoteTaker and Researcher in parallel, then Orchestrator sequentially
    /// All agents have graceful fallbacks, so this method never throws
    func processLiveUpdate(
        transcript: [TranscriptEntry],
        currentNotes: NotesState,
        plan: PlanSnapshot,
        elapsedSeconds: Int,
        targetSeconds: Int
    ) async -> LiveUpdateResult {
        let progress = Int(Double(elapsedSeconds) / Double(targetSeconds) * 100)

        AgentLogger.liveUpdateStarted(progress: progress, transcriptCount: transcript.count)

        // Update activity indicators
        updateActivity(agent: "notes", score: 1.0)
        updateActivity(agent: "research", score: 1.0)

        AgentLogger.parallelAgentsStarted()

        // Window transcripts for each agent to control prompt size
        let notesTranscript = windowTranscript(transcript, maxEntries: maxTranscriptEntriesForNotes)
        let researchTranscript = windowTranscript(transcript, maxEntries: maxTranscriptEntriesForResearch)

        // Run NoteTaker and Researcher in parallel with graceful failure handling
        async let notesTask = runNoteTakerWithFallback(
            transcript: notesTranscript,
            currentNotes: currentNotes,
            plan: plan
        )
        async let researchTask = runResearcherWithFallback(
            transcript: researchTranscript,
            topic: plan.topic
        )

        // Wait for both to complete - failures return fallback values instead of throwing
        let (updatedNotes, newResearchItems) = await (notesTask, researchTask)

        AgentLogger.parallelAgentsFinished()

        // Update accumulated research
        accumulatedResearch.append(contentsOf: newResearchItems)

        // Update activity indicators
        updateActivity(agent: "notes", score: 0.5)
        updateActivity(agent: "research", score: 0.5)
        updateActivity(agent: "orchestrator", score: 1.0)

        // Window transcript for orchestrator
        let orchestratorTranscript = windowTranscript(transcript, maxEntries: maxTranscriptEntriesForOrchestrator)

        // Now run Orchestrator with the combined results (with fallback on failure)
        let context = OrchestratorContext(
            plan: plan,
            transcript: orchestratorTranscript,
            notes: updatedNotes,
            research: accumulatedResearch,
            elapsedSeconds: elapsedSeconds,
            targetSeconds: targetSeconds,
            askedQuestionIds: askedQuestionIds
        )

        let decision = await runOrchestratorWithFallback(context: context, plan: plan)

        // Mark the question as asked for coverage tracking
        if let questionId = decision.nextQuestion.sourceQuestionId {
            markQuestionAsked(questionId)
            AgentLogger.questionMarkedAsked(questionId: questionId, method: "direct ID")
        } else if decision.nextQuestion.source == "plan" {
            // Fallback: Try to match by question text similarity if LLM didn't return ID
            if let matchedId = findMatchingQuestionId(
                questionText: decision.nextQuestion.text,
                in: plan
            ) {
                markQuestionAsked(matchedId)
                AgentLogger.questionMarkedAsked(questionId: matchedId, method: "text match")
            } else {
                AgentLogger.info(agent: "Coordinator", message: "Plan question suggested but couldn't match ID - coverage tracking may be incomplete")
            }
        }

        updateActivity(agent: "orchestrator", score: 0.5)

        // Build interviewer instructions for Realtime API
        let instructions = buildInterviewerInstructions(
            decision: decision,
            notes: updatedNotes,
            research: newResearchItems
        )

        AgentLogger.liveUpdateComplete(phase: decision.phase, nextQuestion: decision.nextQuestion.text)

        return LiveUpdateResult(
            notes: updatedNotes,
            newResearchItems: newResearchItems,
            decision: decision,
            interviewerInstructions: instructions
        )
    }

    // MARK: - Private Agent Runners with Fallbacks

    /// Run NoteTaker with graceful fallback on failure
    private func runNoteTakerWithFallback(
        transcript: [TranscriptEntry],
        currentNotes: NotesState,
        plan: PlanSnapshot
    ) async -> NotesState {
        do {
            return try await noteTakerAgent.updateNotes(
                transcript: transcript,
                currentNotes: currentNotes,
                plan: plan
            )
        } catch {
            AgentLogger.error(agent: "NoteTaker", message: "Failed with error: \(error.localizedDescription). Using previous notes.")
            // Return current notes unchanged - interview continues with existing insights
            return currentNotes
        }
    }

    /// Run Researcher with graceful fallback on failure
    private func runResearcherWithFallback(
        transcript: [TranscriptEntry],
        topic: String
    ) async -> [ResearchItem] {
        do {
            return try await researcherAgent.research(
                transcript: transcript,
                existingResearch: accumulatedResearch,
                topic: topic
            )
        } catch {
            AgentLogger.error(agent: "Researcher", message: "Failed with error: \(error.localizedDescription). Skipping research this cycle.")
            // Return empty array - interview continues without new research
            return []
        }
    }

    /// Run Orchestrator with graceful fallback on failure
    private func runOrchestratorWithFallback(
        context: OrchestratorContext,
        plan: PlanSnapshot
    ) async -> OrchestratorDecision {
        do {
            return try await orchestratorAgent.decideNextQuestion(context: context)
        } catch {
            AgentLogger.error(agent: "Orchestrator", message: "Failed with error: \(error.localizedDescription). Using fallback decision.")
            // Fallback: Pick the first unasked P1 question from the plan
            return createFallbackDecision(from: plan, context: context)
        }
    }

    /// Create a simple fallback decision when Orchestrator fails
    private func createFallbackDecision(from plan: PlanSnapshot, context: OrchestratorContext) -> OrchestratorDecision {
        // Determine phase based on time
        let progress = Double(context.elapsedSeconds) / Double(context.targetSeconds)
        let phase: String
        if progress < 0.15 {
            phase = "opening"
        } else if progress > 0.85 {
            phase = "wrap_up"
        } else {
            phase = "deep_dive"
        }

        // Find first unasked question, prioritizing P1
        var fallbackQuestion: (text: String, sectionId: String, questionId: String)?

        for priority in 1...3 {
            for section in plan.sections {
                for question in section.questions where question.priority == priority {
                    if !askedQuestionIds.contains(question.id) {
                        fallbackQuestion = (question.text, section.id, question.id)
                        break
                    }
                }
                if fallbackQuestion != nil { break }
            }
            if fallbackQuestion != nil { break }
        }

        // If all questions asked, use a generic wrap-up
        let (questionText, sectionId, questionId) = fallbackQuestion ?? (
            "Is there anything else you'd like to add that we haven't covered?",
            plan.sections.first?.id ?? "",
            ""
        )

        return OrchestratorDecision(
            phase: phase,
            nextQuestion: NextQuestion(
                text: questionText,
                targetSectionId: sectionId,
                source: fallbackQuestion != nil ? "plan" : "gap",
                sourceQuestionId: fallbackQuestion != nil ? questionId : nil,
                expectedAnswerSeconds: 60
            ),
            interviewerBrief: "Ask naturally and listen carefully. (Note: Using fallback due to agent error)"
        )
    }

    // MARK: - Instructions Builder

    private func buildInterviewerInstructions(
        decision: OrchestratorDecision,
        notes: NotesState,
        research: [ResearchItem]
    ) -> String {
        var instructions = """
        ## Current Phase: \(decision.phase.uppercased())

        ## Next Question to Ask
        \(decision.nextQuestion.text)

        ## How to Ask It
        \(decision.interviewerBrief)

        """

        // Add relevant research if available
        let relevantResearch = research.filter { $0.priority <= 2 }
        if !relevantResearch.isEmpty {
            instructions += "\n## Research Context\n"
            for item in relevantResearch {
                instructions += "- **\(item.topic)**: \(item.summary)\n"
            }
        }

        // Add gaps to explore if in deep_dive phase
        if decision.phase == "deep_dive" && !notes.gaps.isEmpty {
            instructions += "\n## Gaps to Explore (if natural)\n"
            for gap in notes.gaps.prefix(2) {
                instructions += "- \(gap.description)\n"
            }
        }

        // Add contradictions if any
        if !notes.contradictions.isEmpty {
            instructions += "\n## Contradictions to Clarify\n"
            for contradiction in notes.contradictions.prefix(1) {
                instructions += "- \(contradiction.description)\n"
            }
        }

        return instructions
    }

    // MARK: - Question Matching

    /// Fallback matching when LLM doesn't return sourceQuestionId
    /// Uses simple text similarity to find the best matching plan question
    private func findMatchingQuestionId(questionText: String, in plan: PlanSnapshot) -> String? {
        let normalizedQuestion = questionText.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var bestMatch: (id: String, score: Double)?

        for section in plan.sections {
            for question in section.questions {
                // Skip already-asked questions
                guard !askedQuestionIds.contains(question.id) else { continue }

                let normalizedPlan = question.text.lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Calculate similarity score
                let score = calculateSimilarity(normalizedQuestion, normalizedPlan)

                if score > 0.6 {  // Threshold for match
                    if bestMatch == nil || score > bestMatch!.score {
                        bestMatch = (question.id, score)
                    }
                }
            }
        }

        return bestMatch?.id
    }

    /// Simple word-based similarity (Jaccard-like)
    private func calculateSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.components(separatedBy: .whitespaces).filter { $0.count > 2 })
        let words2 = Set(text2.components(separatedBy: .whitespaces).filter { $0.count > 2 })

        guard !words1.isEmpty && !words2.isEmpty else { return 0 }

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        return Double(intersection) / Double(union)
    }

    // MARK: - Activity Tracking

    private func updateActivity(agent: String, score: Double) {
        agentActivity[agent] = score
    }

    func getAgentActivity() -> [String: Double] {
        return agentActivity
    }

    func getActivity(for agent: String) -> Double {
        return agentActivity[agent] ?? 0.0
    }

    // MARK: - Post-Interview (Phase 5)

    /// Analyze the completed interview
    func analyzeInterview(
        transcript: [TranscriptEntry],
        notes: NotesState,
        plan: PlanSnapshot
    ) async throws -> AnalysisSummary {
        updateActivity(agent: "analysis", score: 1.0)
        defer { updateActivity(agent: "analysis", score: 0.5) }

        return try await analysisAgent.analyze(
            transcript: transcript,
            notes: notes,
            plan: plan
        )
    }

    /// Generate a draft essay from analysis
    func writeDraft(
        transcript: [TranscriptEntry],
        analysis: AnalysisSummary,
        plan: PlanSnapshot,
        style: DraftStyle
    ) async throws -> String {
        updateActivity(agent: "writer", score: 1.0)
        defer { updateActivity(agent: "writer", score: 0.5) }

        return try await writerAgent.writeDraft(
            transcript: transcript,
            analysis: analysis,
            plan: plan,
            style: style
        )
    }
}

// MARK: - Plan Conversion Helpers

extension PlannerResponse {
    /// Convert PlannerResponse to SwiftData Plan model
    func toPlan(topic: String, targetSeconds: Int) -> Plan {
        let plan = Plan(
            topic: topic,
            researchGoal: researchGoal,
            angle: angle,
            targetSeconds: targetSeconds
        )

        for (index, section) in sections.enumerated() {
            let newSection = Section(
                title: section.title,
                importance: section.importance,
                backbone: true,
                estimatedSeconds: section.estimatedSeconds,
                sortOrder: index
            )

            for (qIndex, question) in section.questions.enumerated() {
                let newQuestion = Question(
                    text: question.text,
                    role: question.role,
                    priority: question.priority,
                    notesForInterviewer: question.notesForInterviewer,
                    sortOrder: qIndex
                )
                newQuestion.section = newSection
                newSection.questions.append(newQuestion)
            }

            newSection.plan = plan
            plan.sections.append(newSection)
        }

        return plan
    }
}
