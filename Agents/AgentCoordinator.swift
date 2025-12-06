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

    private var llmClient: LLMClient
    private var modelConfig: LLMModelConfig
    private var provider: LLMProvider

    // Pre-interview agent
    private var plannerAgent: PlannerAgent

    // Live interview agents
    private var noteTakerAgent: NoteTakerAgent
    private var researcherAgent: ResearcherAgent
    private var orchestratorAgent: OrchestratorAgent

    // Post-interview agents
    private var analysisAgent: AnalysisAgent
    private var writerAgent: WriterAgent
    private var followUpAgent: FollowUpAgent

    // Accumulated state during interview
    private var accumulatedResearch: [ResearchItem] = []
    private var askedQuestionIds: Set<String> = []
    private var finalNotes: NotesState = .empty

    // Track recently asked question TEXTS to prevent similar questions
    private var recentlyAskedQuestionTexts: [String] = []
    private let maxRecentQuestions = 10

    // Track question themes to prevent thematic repetition
    private var askedQuestionThemes: Set<String> = []

    // Agent activity tracking for UI meters
    private var agentActivity: [String: Double] = [:]

    // Transcript change detection to skip redundant processing
    private var lastProcessedTranscriptHash: Int = 0
    private var lastProcessedFinalCount: Int = 0  // Count of final (non-streaming) entries

    // Orchestrator throttling when no content changes
    private var lastOrchestratorRunTime: Date?
    private var lastOrchestratorDecision: OrchestratorDecision?
    private let orchestratorMinIntervalNoContent: TimeInterval = 30  // Min 30s between runs if no new content

    // Phase locking to prevent oscillation after 85%
    private var lockedPhase: String?

    // Transcript windowing configuration to control prompt size
    private let maxTranscriptEntriesForNotes = 20      // Note-taker gets recent context
    private let maxTranscriptEntriesForResearch = 20   // Researcher needs enough context to identify topics
    private let maxTranscriptEntriesForOrchestrator = 30  // Orchestrator needs more for decisions

    private init() {
        self.provider = .openAI
        self.modelConfig = LLMModelResolver.config(for: .openAI)
        let adapter = OpenAIAdapter()
        self.llmClient = adapter
        self.plannerAgent = PlannerAgent(client: adapter, modelConfig: modelConfig)
        self.noteTakerAgent = NoteTakerAgent(client: adapter, modelConfig: modelConfig)
        self.researcherAgent = ResearcherAgent(client: adapter, modelConfig: modelConfig)
        self.orchestratorAgent = OrchestratorAgent(client: adapter, modelConfig: modelConfig)
        self.analysisAgent = AnalysisAgent(client: adapter, modelConfig: modelConfig)
        self.writerAgent = WriterAgent(client: adapter, modelConfig: modelConfig)
        self.followUpAgent = FollowUpAgent(client: adapter, modelConfig: modelConfig)
    }

    func updateLLM(client: LLMClient, modelConfig: LLMModelConfig, provider: LLMProvider) {
        self.llmClient = client
        self.modelConfig = modelConfig
        self.provider = provider
        self.plannerAgent = PlannerAgent(client: client, modelConfig: modelConfig)
        self.noteTakerAgent = NoteTakerAgent(client: client, modelConfig: modelConfig)
        self.researcherAgent = ResearcherAgent(client: client, modelConfig: modelConfig)
        self.orchestratorAgent = OrchestratorAgent(client: client, modelConfig: modelConfig)
        self.analysisAgent = AnalysisAgent(client: client, modelConfig: modelConfig)
        self.writerAgent = WriterAgent(client: client, modelConfig: modelConfig)
        self.followUpAgent = FollowUpAgent(client: client, modelConfig: modelConfig)
    }

    // MARK: - Session Management

    /// Reset state for a new interview session
    func startNewSession() async {
        AgentLogger.sessionStarted()
        accumulatedResearch = []
        askedQuestionIds = []
        recentlyAskedQuestionTexts = []
        askedQuestionThemes = []
        agentActivity = [:]
        finalNotes = .empty
        lastProcessedTranscriptHash = 0
        lastProcessedFinalCount = 0
        lastOrchestratorRunTime = nil
        lastOrchestratorDecision = nil
        lockedPhase = nil

        // Reset agent state
        await researcherAgent.reset()
    }

    /// Start a follow-up session, preserving context from previous session
    /// This ensures the agents know what was already discussed and don't repeat questions
    func startFollowUpSession(
        previousTranscript: [TranscriptEntry],
        previousNotes: NotesState,
        previousPlan: PlanSnapshot
    ) async {
        AgentLogger.sessionStarted()
        AgentLogger.info(agent: "Coordinator", message: "Starting follow-up session with \(previousTranscript.count) previous exchanges")

        // Reset accumulating state but preserve knowledge
        accumulatedResearch = []
        agentActivity = [:]
        lastProcessedTranscriptHash = 0
        lastProcessedFinalCount = 0
        lastOrchestratorRunTime = nil
        lastOrchestratorDecision = nil
        lockedPhase = nil  // Fresh start for follow-up timing

        // Extract questions that were asked in the previous session
        // Look at assistant messages that appear to be questions
        recentlyAskedQuestionTexts = []
        askedQuestionThemes = []

        for entry in previousTranscript where entry.speaker == "assistant" {
            let text = entry.text
            // If it contains a question mark, it's likely a question
            if text.contains("?") {
                recentlyAskedQuestionTexts.append(text)
                // Extract and track themes
                let themes = extractThemes(from: text)
                askedQuestionThemes.formUnion(themes)
            }
        }

        // Keep only recent questions to avoid huge context
        if recentlyAskedQuestionTexts.count > maxRecentQuestions {
            recentlyAskedQuestionTexts = Array(recentlyAskedQuestionTexts.suffix(maxRecentQuestions))
        }

        // Mark questions from previous plan as asked if they were covered
        askedQuestionIds = []
        for section in previousPlan.sections {
            for question in section.questions {
                // Check if this question (or something similar) was asked
                if isQuestionCoveredInTranscript(question.text, transcript: previousTranscript) {
                    askedQuestionIds.insert(question.id)
                }
            }
        }

        // Preserve notes from previous session
        finalNotes = previousNotes

        AgentLogger.info(agent: "Coordinator", message: "Restored \(askedQuestionIds.count) asked questions, \(askedQuestionThemes.count) themes, \(recentlyAskedQuestionTexts.count) recent questions")

        // Reset researcher but it will get context from the follow-up
        await researcherAgent.reset()
    }

    /// Check if a question was covered in the transcript
    private func isQuestionCoveredInTranscript(_ questionText: String, transcript: [TranscriptEntry]) -> Bool {
        let questionWords = normalizeForMatching(questionText)
        guard !questionWords.isEmpty else { return false }

        for entry in transcript where entry.speaker == "assistant" {
            let entryWords = normalizeForMatching(entry.text)
            let similarity = calculateSimilarity(questionWords, entryWords)
            if similarity > 0.4 {
                return true
            }
        }
        return false
    }

    /// Store final notes when interview ends (for use in post-processing)
    func storeNotes(_ notes: NotesState) {
        finalNotes = notes
    }

    func analyzeFollowUp(session: SessionSnapshot, plan: PlanSnapshot) async throws -> FollowUpAnalysis {
        try await followUpAgent.analyzeForFollowUp(session: session, plan: plan)
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

    /// Compute a hash of final transcript entries to detect meaningful changes
    private func computeTranscriptHash(_ transcript: [TranscriptEntry]) -> Int {
        var hasher = Hasher()
        // Only hash final entries - streaming entries change too frequently
        let finalEntries = transcript.filter { $0.isFinal }
        hasher.combine(finalEntries.count)
        for entry in finalEntries.suffix(10) {
            hasher.combine(entry.text)
        }
        return hasher.finalize()
    }

    /// Count final (non-streaming) transcript entries
    private func countFinalEntries(_ transcript: [TranscriptEntry]) -> Int {
        transcript.filter { $0.isFinal }.count
    }

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
        let finalCount = countFinalEntries(transcript)

        AgentLogger.liveUpdateStarted(progress: progress, transcriptCount: finalCount)

        // Check if transcript has meaningfully changed since last processing
        let currentHash = computeTranscriptHash(transcript)
        let hasNewContent = currentHash != lastProcessedTranscriptHash || finalCount > lastProcessedFinalCount

        // Decide whether to run each agent based on content change
        let shouldRunNoteTaker = hasNewContent
        let shouldRunResearcher = hasNewContent
        // Note: Orchestrator always runs as it considers time-based phase decisions

        var updatedNotes = currentNotes
        var newResearchItems: [ResearchItem] = []

        if shouldRunNoteTaker || shouldRunResearcher {
            // Update activity indicators
            updateActivity(agent: "notes", score: shouldRunNoteTaker ? 1.0 : 0.3)
            updateActivity(agent: "research", score: shouldRunResearcher ? 1.0 : 0.3)

            AgentLogger.parallelAgentsStarted()

            // Window transcripts for each agent to control prompt size
            let notesTranscript = windowTranscript(transcript, maxEntries: maxTranscriptEntriesForNotes)
            let researchTranscript = windowTranscript(transcript, maxEntries: maxTranscriptEntriesForResearch)

            if shouldRunNoteTaker && shouldRunResearcher {
                // Run both in parallel
                async let notesTask = runNoteTakerWithFallback(
                    transcript: notesTranscript,
                    currentNotes: currentNotes,
                    plan: plan
                )
                async let researchTask = runResearcherWithFallback(
                    transcript: researchTranscript,
                    topic: plan.topic
                )
                (updatedNotes, newResearchItems) = await (notesTask, researchTask)
            } else if shouldRunNoteTaker {
                updatedNotes = await runNoteTakerWithFallback(
                    transcript: notesTranscript,
                    currentNotes: currentNotes,
                    plan: plan
                )
            } else if shouldRunResearcher {
                newResearchItems = await runResearcherWithFallback(
                    transcript: researchTranscript,
                    topic: plan.topic
                )
            }

            AgentLogger.parallelAgentsFinished()

            // Update accumulated research
            accumulatedResearch.append(contentsOf: newResearchItems)

            // Track that we processed this content
            lastProcessedTranscriptHash = currentHash
            lastProcessedFinalCount = finalCount
        } else {
            AgentLogger.info(agent: "Coordinator", message: "Skipping NoteTaker/Researcher - no new content")
        }

        // Determine if we should run Orchestrator
        // Skip if: no new content AND ran recently AND not at a phase transition point
        let timeSinceLastOrchestrator = lastOrchestratorRunTime.map { Date().timeIntervalSince($0) } ?? .infinity
        let shouldRunOrchestrator = hasNewContent ||
            timeSinceLastOrchestrator >= orchestratorMinIntervalNoContent ||
            lastOrchestratorDecision == nil

        var decision: OrchestratorDecision

        if shouldRunOrchestrator {
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
                askedQuestionIds: askedQuestionIds,
                recentlyAskedTexts: recentlyAskedQuestionTexts,
                askedThemes: askedQuestionThemes
            )

            decision = await runOrchestratorWithFallback(context: context, plan: plan)
            lastOrchestratorRunTime = Date()
            lastOrchestratorDecision = decision

            // Apply phase locking after 85% to prevent oscillation
            let progress = Double(elapsedSeconds) / Double(targetSeconds)
            if progress >= 0.85 {
                if lockedPhase == nil {
                    // Lock to wrap_up phase once we're past 85%
                    lockedPhase = "wrap_up"
                    AgentLogger.info(agent: "Coordinator", message: "Locking phase to wrap_up (85% reached)")
                }
            }

            // Override phase if locked
            if let locked = lockedPhase, decision.phase != locked {
                AgentLogger.info(agent: "Coordinator", message: "Overriding phase from \(decision.phase) to \(locked) (phase locked)")
                decision = OrchestratorDecision(
                    phase: locked,
                    nextQuestion: decision.nextQuestion,
                    interviewerBrief: decision.interviewerBrief
                )
            }

            // Track the question and validate ID before marking
            let questionText = decision.nextQuestion.text
            trackAskedQuestion(questionText)

            if let questionId = decision.nextQuestion.sourceQuestionId {
                // Validate the question ID before marking
                if isValidQuestionId(questionId, in: plan) {
                    if !askedQuestionIds.contains(questionId) {
                        markQuestionAsked(questionId)
                        AgentLogger.questionMarkedAsked(questionId: questionId, method: "direct ID")
                    } else {
                        AgentLogger.info(agent: "Coordinator", message: "Question ID \(questionId.prefix(8))... already marked as asked - skipping duplicate")
                    }
                } else {
                    AgentLogger.info(agent: "Coordinator", message: "Invalid question ID '\(questionId.prefix(20))...' rejected - not in plan")
                }
            } else if decision.nextQuestion.source == "plan" {
                // Fallback: Try to match by question text similarity if LLM didn't return ID
                if let matchedId = findMatchingQuestionId(
                    questionText: questionText,
                    in: plan
                ) {
                    if !askedQuestionIds.contains(matchedId) {
                        markQuestionAsked(matchedId)
                        AgentLogger.questionMarkedAsked(questionId: matchedId, method: "text match")
                    }
                } else {
                    AgentLogger.info(agent: "Coordinator", message: "Plan question suggested but couldn't match ID - coverage tracking may be incomplete")
                }
            }

            updateActivity(agent: "orchestrator", score: 0.5)
        } else {
            // Reuse previous decision
            decision = lastOrchestratorDecision!
            AgentLogger.info(agent: "Coordinator", message: "Reusing previous Orchestrator decision (no new content, \(Int(timeSinceLastOrchestrator))s since last run)")
        }

        // Build interviewer instructions for Realtime API
        // Use accumulated research (not just new items) to give interviewer full context
        let instructions = buildInterviewerInstructions(
            decision: decision,
            notes: updatedNotes,
            research: accumulatedResearch
        )

        AgentLogger.liveUpdateComplete(phase: decision.phase, nextQuestion: decision.nextQuestion.text)

        return LiveUpdateResult(
            notes: updatedNotes,
            newResearchItems: newResearchItems,
            decision: decision,
            interviewerInstructions: instructions
        )
    }

    /// Track question text to prevent similar questions
    private func trackAskedQuestion(_ text: String) {
        recentlyAskedQuestionTexts.append(text)
        // Keep only the most recent questions
        if recentlyAskedQuestionTexts.count > maxRecentQuestions {
            recentlyAskedQuestionTexts.removeFirst()
        }

        // Extract and track themes from this question
        let themes = extractThemes(from: text)
        askedQuestionThemes.formUnion(themes)
    }

    // MARK: - Theme Extraction

    /// Key themes/topics that indicate what a question is about
    private static let themeKeywords: [String: [String]] = [
        "examples": ["example", "examples", "instance", "instances", "case", "cases", "scenario", "scenarios"],
        "industries": ["industry", "industries", "sector", "sectors", "field", "fields", "domain", "domains"],
        "understanding": ["understand", "understanding", "understood", "misconception", "misconceptions", "misunderstand"],
        "challenges": ["challenge", "challenges", "difficult", "difficulty", "struggle", "problem", "obstacle"],
        "advice": ["advice", "recommend", "suggestion", "tips", "guidance", "counsel"],
        "future": ["future", "next", "upcoming", "trend", "trends", "evolving", "evolution"],
        "mistakes": ["mistake", "mistakes", "error", "errors", "wrong", "fail", "failure", "failures"],
        "success": ["success", "successful", "achieve", "achievement", "win", "wins", "victory"],
        "origin": ["start", "started", "begin", "began", "origin", "origins", "first", "initially"],
        "difference": ["different", "difference", "differences", "distinguish", "unique", "versus"],
        "impact": ["impact", "effect", "influence", "affect", "change", "transform"],
        "wish": ["wish", "wished", "hope", "hoped", "want", "wanted", "desire"]
    ]

    /// Extract themes from a question text
    private func extractThemes(from text: String) -> Set<String> {
        let lowercased = text.lowercased()
        var themes: Set<String> = []

        for (theme, keywords) in Self.themeKeywords {
            for keyword in keywords {
                if lowercased.contains(keyword) {
                    themes.insert(theme)
                    break
                }
            }
        }

        return themes
    }

    /// Check if a question's themes overlap too much with already-asked themes
    func hasOverlappingThemes(_ questionText: String, maxOverlap: Int = 2) -> Bool {
        let newThemes = extractThemes(from: questionText)
        let overlap = newThemes.intersection(askedQuestionThemes)
        return overlap.count >= maxOverlap
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
            // Separate claim verifications from regular research
            let claimVerifications = relevantResearch.filter { $0.kind == "claim_verification" }
            let regularResearch = relevantResearch.filter { $0.kind != "claim_verification" }

            if !regularResearch.isEmpty {
                instructions += "\n## Research Context\n"
                for item in regularResearch {
                    instructions += "- **\(item.topic)**: \(item.summary)\n"
                }
            }

            // Surface claim verifications prominently, especially contradictions
            if !claimVerifications.isEmpty {
                instructions += "\n## Fact-Check Notes\n"
                for item in claimVerifications {
                    let status = item.verificationStatus ?? "unverifiable"
                    let emoji = switch status {
                    case "verified": "✅"
                    case "contradicted": "⚠️"
                    case "partially_true": "🟡"
                    default: "❓"
                    }
                    instructions += "- \(emoji) **\(item.topic)**: \(status.uppercased())\n"
                    if let note = item.verificationNote, !note.isEmpty {
                        instructions += "  \(note)\n"
                    }
                    if status == "contradicted" || status == "partially_true" {
                        instructions += "  → \(item.howToUseInQuestion)\n"
                    }
                }
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

    // MARK: - Question ID Validation

    /// Validate that a question ID is legitimate (exists in the plan)
    /// Rejects fake IDs, null strings, empty strings, and IDs not in the plan
    private func isValidQuestionId(_ questionId: String, in plan: PlanSnapshot) -> Bool {
        // Reject obviously invalid IDs
        let trimmed = questionId.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for empty or placeholder values
        if trimmed.isEmpty { return false }
        if trimmed.lowercased() == "null" { return false }
        if trimmed.lowercased().hasPrefix("fake") { return false }
        if trimmed.lowercased().hasPrefix("n/a") { return false }

        // Verify ID actually exists in the plan
        for section in plan.sections {
            for question in section.questions {
                if question.id == questionId {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Question Matching

    // Stop words to filter out for better matching
    private static let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "can", "this", "that", "these", "those",
        "i", "you", "he", "she", "it", "we", "they", "what", "which", "who",
        "when", "where", "why", "how", "all", "each", "every", "both", "few",
        "more", "most", "other", "some", "such", "no", "nor", "not", "only",
        "own", "same", "so", "than", "too", "very", "just", "about", "into",
        "through", "during", "before", "after", "above", "below", "to", "from",
        "up", "down", "in", "out", "on", "off", "over", "under", "again",
        "further", "then", "once", "here", "there", "any", "your", "their"
    ]

    /// Normalize text for better matching - remove punctuation, stop words, lowercase
    private func normalizeForMatching(_ text: String) -> Set<String> {
        let cleaned = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")

        let words = cleaned.components(separatedBy: .whitespaces)
            .filter { $0.count > 2 && !Self.stopWords.contains($0) }

        return Set(words)
    }

    /// Fallback matching when LLM doesn't return sourceQuestionId
    /// Uses improved text similarity to find the best matching plan question
    private func findMatchingQuestionId(questionText: String, in plan: PlanSnapshot) -> String? {
        let normalizedQuestion = normalizeForMatching(questionText)

        guard !normalizedQuestion.isEmpty else { return nil }

        var bestMatch: (id: String, score: Double)?

        for section in plan.sections {
            for question in section.questions {
                // Skip already-asked questions
                guard !askedQuestionIds.contains(question.id) else { continue }

                let normalizedPlan = normalizeForMatching(question.text)

                guard !normalizedPlan.isEmpty else { continue }

                // Calculate similarity score
                let score = calculateSimilarity(normalizedQuestion, normalizedPlan)

                // Lower threshold (0.35) to catch more rephrased questions
                if score > 0.35 {
                    if bestMatch == nil || score > bestMatch!.score {
                        bestMatch = (question.id, score)
                    }
                }
            }
        }

        return bestMatch?.id
    }

    /// Check if a new question is too similar to recently asked questions
    func isQuestionTooSimilar(_ newQuestion: String, threshold: Double = 0.5) -> Bool {
        let normalizedNew = normalizeForMatching(newQuestion)

        for askedText in recentlyAskedQuestionTexts {
            let normalizedAsked = normalizeForMatching(askedText)
            let similarity = calculateSimilarity(normalizedNew, normalizedAsked)
            if similarity > threshold {
                return true
            }
        }
        return false
    }

    /// Jaccard similarity between two word sets
    private func calculateSimilarity(_ words1: Set<String>, _ words2: Set<String>) -> Double {
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
    /// - Parameters:
    ///   - transcript: Current session transcript
    ///   - analysis: Analysis summary
    ///   - plan: The interview plan
    ///   - style: Writing style
    ///   - previousTranscript: Optional transcript from previous session (for follow-ups)
    func writeDraft(
        transcript: [TranscriptEntry],
        analysis: AnalysisSummary,
        plan: PlanSnapshot,
        style: DraftStyle,
        previousTranscript: [TranscriptEntry]? = nil
    ) async throws -> String {
        updateActivity(agent: "writer", score: 1.0)
        defer { updateActivity(agent: "writer", score: 0.5) }

        return try await writerAgent.writeDraft(
            transcript: transcript,
            analysis: analysis,
            plan: plan,
            style: style,
            previousTranscript: previousTranscript
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
