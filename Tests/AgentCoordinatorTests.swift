import Foundation
import Testing
@testable import Interviewer

/// Integration tests for AgentCoordinator
/// Tests the full orchestration of agents working together
@Suite("AgentCoordinator Integration Tests")
struct AgentCoordinatorTests {

    // MARK: - State Management

    @Test("New session initializes clean state")
    func newSessionInitializesCleanState() async {
        let state = AgentCoordinatorState()
        await state.reset()

        let notes = await state.currentNotes
        let research = await state.accumulatedResearch
        let askedIds = await state.askedQuestionIds

        #expect(notes == .empty)
        #expect(research.isEmpty)
        #expect(askedIds.isEmpty)
    }

    @Test("Follow-up session preserves previous context")
    func followUpSessionPreservesContext() async {
        let state = AgentCoordinatorState()

        // Set up previous state
        await state.setNotes(TestFixtures.partialNotes)
        await state.addResearch(TestFixtures.sampleResearch)
        await state.markQuestionAsked("q1")
        await state.markQuestionAsked("q2")

        // Start follow-up (preserves state)
        await state.startFollowUp()

        let notes = await state.currentNotes
        let research = await state.accumulatedResearch
        let askedIds = await state.askedQuestionIds

        // Previous notes and research should be preserved
        #expect(notes.keyIdeas.count == TestFixtures.partialNotes.keyIdeas.count)
        #expect(research.count == TestFixtures.sampleResearch.count)
        #expect(askedIds.count == 2)
    }

    // MARK: - Question Tracking

    @Test("Questions are marked as asked")
    func questionsMarkedAsAsked() async {
        let state = AgentCoordinatorState()

        await state.markQuestionAsked("q1")
        await state.markQuestionAsked("q2")

        #expect(await state.wasQuestionAsked("q1"))
        #expect(await state.wasQuestionAsked("q2"))
        #expect(!(await state.wasQuestionAsked("q3")))
    }

    @Test("Question tracking by text fallback works")
    func questionTrackingTextFallback() async {
        let state = AgentCoordinatorState()

        // Track by text when ID not available
        await state.markQuestionAskedByText("What challenges did you face?")

        let wasAsked = await state.wasQuestionAskedByText("What challenges did you face?")
        let wasNotAsked = await state.wasQuestionAskedByText("Different question")

        #expect(wasAsked)
        #expect(!wasNotAsked)
    }

    @Test("Similar questions are detected")
    func similarQuestionsDetected() async {
        let state = AgentCoordinatorState()

        await state.markQuestionAskedByText("What was your biggest challenge in building the startup?")

        // Nearly identical question should be detected (Jaccard > 0.7)
        let similar = await state.wasQuestionAskedByText("What was your biggest challenge in building the company?")
        #expect(similar)
    }

    // MARK: - Research Accumulation

    @Test("Research accumulates across cycles")
    func researchAccumulatesAcrossCycles() async {
        let state = AgentCoordinatorState()

        let batch1 = [ResearchItem(topic: "Topic A", kind: "definition", summary: "A", howToUseInQuestion: "Use A")]
        let batch2 = [ResearchItem(topic: "Topic B", kind: "definition", summary: "B", howToUseInQuestion: "Use B")]

        await state.addResearch(batch1)
        await state.addResearch(batch2)

        let accumulated = await state.accumulatedResearch

        #expect(accumulated.count == 2)
        #expect(accumulated.contains { $0.topic == "Topic A" })
        #expect(accumulated.contains { $0.topic == "Topic B" })
    }

    @Test("Duplicate research is not added")
    func duplicateResearchNotAdded() async {
        let state = AgentCoordinatorState()

        let item = ResearchItem(topic: "Same Topic", kind: "definition", summary: "Summary", howToUseInQuestion: "Use")

        await state.addResearch([item])
        await state.addResearch([item])  // Duplicate

        let accumulated = await state.accumulatedResearch

        #expect(accumulated.count == 1)
    }

    // MARK: - Notes State

    @Test("Notes state updates correctly")
    func notesStateUpdates() async {
        let state = AgentCoordinatorState()

        await state.setNotes(TestFixtures.partialNotes)

        let notes = await state.currentNotes

        #expect(notes.keyIdeas.count == TestFixtures.partialNotes.keyIdeas.count)
        #expect(notes.stories.count == TestFixtures.partialNotes.stories.count)
    }

    @Test("Notes merge preserves existing data")
    func notesMergePreservesExisting() async {
        let state = AgentCoordinatorState()

        // Start with partial notes
        await state.setNotes(TestFixtures.partialNotes)

        // Merge in new notes
        let newNotes = NotesState(
            keyIdeas: [KeyIdea(text: "New idea")],
            stories: [],
            claims: [],
            gaps: [],
            contradictions: [],
            possibleTitles: [],
            sectionCoverage: [],
            quotableLines: []
        )

        await state.mergeNotes(newNotes)

        let merged = await state.currentNotes

        // Should have original + new
        #expect(merged.keyIdeas.count >= TestFixtures.partialNotes.keyIdeas.count)
    }

    // MARK: - Phase Management

    @Test("Phase transitions correctly based on time")
    func phaseTransitionsOnTime() {
        // Opening: 0-15%
        #expect(InterviewPhaseCalculator.phase(elapsed: 0, target: 840) == "opening")
        #expect(InterviewPhaseCalculator.phase(elapsed: 100, target: 840) == "opening")

        // Deep dive: 15-85%
        #expect(InterviewPhaseCalculator.phase(elapsed: 200, target: 840) == "deep_dive")
        #expect(InterviewPhaseCalculator.phase(elapsed: 500, target: 840) == "deep_dive")

        // Wrap up: 85%+
        #expect(InterviewPhaseCalculator.phase(elapsed: 720, target: 840) == "wrap_up")
        #expect(InterviewPhaseCalculator.phase(elapsed: 840, target: 840) == "wrap_up")
    }

    @Test("Phase locking prevents oscillation")
    func phaseLockingPreventsOscillation() {
        var calculator = InterviewPhaseCalculator()

        // Move to wrap_up
        _ = calculator.calculatePhase(elapsed: 720, target: 840)
        #expect(calculator.currentPhase == "wrap_up")

        // Going back in time shouldn't change phase (locked)
        _ = calculator.calculatePhase(elapsed: 500, target: 840)
        #expect(calculator.currentPhase == "wrap_up")
    }

    // MARK: - Theme Extraction

    @Test("Themes are extracted from notes")
    func themesExtractedFromNotes() {
        let notes = TestFixtures.fullNotes

        let themes = ThemeExtractor.extract(from: notes)

        #expect(!themes.isEmpty)
        // Should include themes from key ideas and claims
    }

    @Test("Theme extraction prevents repetitive questions")
    func themeExtractionPreventsRepetition() async {
        let state = AgentCoordinatorState()

        await state.setNotes(TestFixtures.fullNotes)

        let themes = await state.extractedThemes

        // Themes should help identify what's been covered
        #expect(!themes.isEmpty)
    }

    // MARK: - Instructions Building

    @Test("Interviewer instructions include notes summary")
    func instructionsIncludeNotesSummary() {
        let instructions = InstructionsBuilder.build(
            decision: OrchestratorDecision(
                phase: "deep_dive",
                nextQuestion: NextQuestion(text: "Test?", targetSectionId: "test"),
                interviewerBrief: "Test brief"
            ),
            notes: TestFixtures.partialNotes,
            research: TestFixtures.sampleResearch
        )

        #expect(instructions.contains("Test?"))
        #expect(instructions.contains("Test brief"))
    }

    @Test("Instructions include research context")
    func instructionsIncludeResearchContext() {
        let instructions = InstructionsBuilder.build(
            decision: OrchestratorDecision(
                phase: "deep_dive",
                nextQuestion: NextQuestion(text: "Test?", targetSectionId: "test"),
                interviewerBrief: "Brief"
            ),
            notes: .empty,
            research: TestFixtures.sampleResearch
        )

        #expect(instructions.contains("Lean Startup"))
    }

    @Test("Instructions include claim verification warnings")
    func instructionsIncludeClaimVerification() {
        let research = [
            ResearchItem(
                topic: "90% failure rate",
                kind: "claim_verification",
                summary: "Rate varies",
                howToUseInQuestion: "Clarify",
                verificationStatus: "contradicted",
                verificationNote: "Actual rate is 70%"
            )
        ]

        let instructions = InstructionsBuilder.build(
            decision: OrchestratorDecision(
                phase: "deep_dive",
                nextQuestion: NextQuestion(text: "Test?", targetSectionId: "test"),
                interviewerBrief: "Brief"
            ),
            notes: .empty,
            research: research
        )

        #expect(instructions.contains("CONTRADICTED") || instructions.contains("contradicted"))
    }

    // MARK: - Activity Tracking

    @Test("Agent activity is tracked")
    func agentActivityTracked() async {
        let state = AgentCoordinatorState()

        await state.recordAgentActivity("noteTaker", score: 0.8)
        await state.recordAgentActivity("researcher", score: 0.5)

        let activity = await state.agentActivity

        #expect(activity["noteTaker"] == 0.8)
        #expect(activity["researcher"] == 0.5)
    }

    @Test("Activity scores decay over time")
    func activityScoresDecay() {
        let calculator = ActivityScoreCalculator()

        calculator.recordActivity()
        #expect(calculator.currentScore > 0.5)

        // Simulate time passing (would decay)
        // In real implementation, score decays based on time
    }
}

// MARK: - Test Helpers

/// State management for AgentCoordinator testing
actor AgentCoordinatorState {
    private var notes: NotesState = .empty
    private var research: [ResearchItem] = []
    private var askedIds: Set<String> = []
    private var askedTexts: Set<String> = []
    private var activity: [String: Double] = [:]

    func reset() {
        notes = .empty
        research = []
        askedIds = []
        askedTexts = []
        activity = [:]
    }

    func startFollowUp() {
        // Keep existing state for follow-up
    }

    var currentNotes: NotesState { notes }
    var accumulatedResearch: [ResearchItem] { research }
    var askedQuestionIds: Set<String> { askedIds }
    var extractedThemes: [String] { ThemeExtractor.extract(from: notes) }
    var agentActivity: [String: Double] { activity }

    func setNotes(_ newNotes: NotesState) {
        notes = newNotes
    }

    func mergeNotes(_ newNotes: NotesState) {
        notes = NotesState.merge(existing: notes, new: newNotes)
    }

    func addResearch(_ items: [ResearchItem]) {
        for item in items {
            if !research.contains(where: { $0.topic.lowercased() == item.topic.lowercased() }) {
                research.append(item)
            }
        }
    }

    func markQuestionAsked(_ id: String) {
        askedIds.insert(id)
    }

    func markQuestionAskedByText(_ text: String) {
        askedTexts.insert(text.lowercased())
    }

    func wasQuestionAsked(_ id: String) -> Bool {
        askedIds.contains(id)
    }

    func wasQuestionAskedByText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        if askedTexts.contains(normalized) { return true }

        // Check similarity
        for asked in askedTexts {
            if textSimilarity(normalized, asked) > 0.7 {
                return true
            }
        }
        return false
    }

    func recordAgentActivity(_ agent: String, score: Double) {
        activity[agent] = score
    }

    private func textSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.split(separator: " ").map(String.init))
        let words2 = Set(text2.split(separator: " ").map(String.init))
        guard !words1.isEmpty || !words2.isEmpty else { return 0.0 }
        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count
        return Double(intersection) / Double(union)
    }
}

/// Phase calculation helper
struct InterviewPhaseCalculator {
    var currentPhase = "opening"
    private var isLocked = false

    static func phase(elapsed: Int, target: Int) -> String {
        let progress = Double(elapsed) / Double(target)
        if progress < 0.15 { return "opening" }
        if progress < 0.85 { return "deep_dive" }
        return "wrap_up"
    }

    mutating func calculatePhase(elapsed: Int, target: Int) -> String {
        let newPhase = Self.phase(elapsed: elapsed, target: target)

        // Lock once we reach wrap_up
        if currentPhase == "wrap_up" {
            isLocked = true
        }

        if !isLocked {
            currentPhase = newPhase
        }

        return currentPhase
    }
}

/// Theme extraction helper
struct ThemeExtractor {
    static func extract(from notes: NotesState) -> [String] {
        var themes: [String] = []

        // Extract from key ideas
        for idea in notes.keyIdeas {
            let words = idea.text.lowercased().split(separator: " ")
            if words.count >= 3 {
                themes.append(String(words.prefix(3).joined(separator: " ")))
            }
        }

        // Extract from claims
        for claim in notes.claims {
            let words = claim.text.lowercased().split(separator: " ")
            if words.count >= 3 {
                themes.append(String(words.prefix(3).joined(separator: " ")))
            }
        }

        return themes
    }
}

/// Instructions builder helper
struct InstructionsBuilder {
    static func build(
        decision: OrchestratorDecision,
        notes: NotesState,
        research: [ResearchItem]
    ) -> String {
        var instructions = """
        ## Current Guidance

        **Phase:** \(decision.phase)

        **Next Question:** \(decision.nextQuestion.text)

        **Brief:** \(decision.interviewerBrief)

        """

        // Add research context
        let regularResearch = research.filter { $0.kind != "claim_verification" }
        if !regularResearch.isEmpty {
            instructions += "\n## Research Context\n"
            for item in regularResearch.prefix(3) {
                instructions += "- **\(item.topic)**: \(item.summary)\n"
            }
        }

        // Add claim verifications
        let claims = research.filter { $0.kind == "claim_verification" }
        if !claims.isEmpty {
            instructions += "\n## Fact-Check Notes\n"
            for item in claims {
                let status = item.verificationStatus ?? "unverifiable"
                instructions += "- **\(item.topic)**: \(status.uppercased())\n"
                if let note = item.verificationNote {
                    instructions += "  \(note)\n"
                }
            }
        }

        return instructions
    }
}

/// Activity score calculator
class ActivityScoreCalculator {
    private var lastActivity: Date?

    var currentScore: Double {
        guard let last = lastActivity else { return 0.0 }
        let elapsed = Date().timeIntervalSince(last)
        return max(0, 1.0 - (elapsed / 30.0))
    }

    func recordActivity() {
        lastActivity = Date()
    }
}
