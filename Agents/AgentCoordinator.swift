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
    func startNewSession() {
        AgentLogger.sessionStarted()
        accumulatedResearch = []
        askedQuestionIds = []
        agentActivity = [:]
        finalNotes = .empty
    }

    /// Store final notes when interview ends (for use in post-processing)
    func storeNotes(_ notes: NotesState) {
        finalNotes = notes
    }

    /// Get the final notes from the session
    func getFinalNotes() -> NotesState {
        finalNotes
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
    func processLiveUpdate(
        transcript: [TranscriptEntry],
        currentNotes: NotesState,
        plan: PlanSnapshot,
        elapsedSeconds: Int,
        targetSeconds: Int
    ) async throws -> LiveUpdateResult {
        let progress = Int(Double(elapsedSeconds) / Double(targetSeconds) * 100)

        AgentLogger.liveUpdateStarted(progress: progress, transcriptCount: transcript.count)

        // Update activity indicators
        updateActivity(agent: "notes", score: 1.0)
        updateActivity(agent: "research", score: 1.0)

        AgentLogger.parallelAgentsStarted()

        // Run NoteTaker and Researcher in parallel
        async let notesTask = runNoteTaker(
            transcript: transcript,
            currentNotes: currentNotes,
            plan: plan
        )
        async let researchTask = runResearcher(
            transcript: transcript,
            topic: plan.topic
        )

        // Wait for both to complete
        let (updatedNotes, newResearchItems) = try await (notesTask, researchTask)

        AgentLogger.parallelAgentsFinished()

        // Update accumulated research
        accumulatedResearch.append(contentsOf: newResearchItems)

        // Update activity indicators
        updateActivity(agent: "notes", score: 0.5)
        updateActivity(agent: "research", score: 0.5)
        updateActivity(agent: "orchestrator", score: 1.0)

        // Now run Orchestrator with the combined results
        let context = OrchestratorContext(
            plan: plan,
            transcript: transcript,
            notes: updatedNotes,
            research: accumulatedResearch,
            elapsedSeconds: elapsedSeconds,
            targetSeconds: targetSeconds,
            askedQuestionIds: askedQuestionIds
        )

        let decision = try await orchestratorAgent.decideNextQuestion(context: context)

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

    // MARK: - Private Agent Runners

    private func runNoteTaker(
        transcript: [TranscriptEntry],
        currentNotes: NotesState,
        plan: PlanSnapshot
    ) async throws -> NotesState {
        // Create a lightweight Plan-like struct for NoteTaker
        let planForNotes = Plan(
            topic: plan.topic,
            researchGoal: plan.researchGoal,
            angle: plan.angle,
            targetSeconds: 0  // Not needed for notes
        )

        return try await noteTakerAgent.updateNotes(
            transcript: transcript,
            currentNotes: currentNotes,
            plan: planForNotes
        )
    }

    private func runResearcher(
        transcript: [TranscriptEntry],
        topic: String
    ) async throws -> [ResearchItem] {
        return try await researcherAgent.research(
            transcript: transcript,
            existingResearch: accumulatedResearch,
            topic: topic
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
