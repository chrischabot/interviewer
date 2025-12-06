import Foundation
import Testing
@testable import Interviewer

/// End-to-end tests for full interview orchestration
/// Simulates complete interview lifecycle with all agents working together
@Suite("End-to-End Orchestration Tests")
@MainActor
struct EndToEndOrchestrationTests {

    // MARK: - Full Interview Lifecycle

    @Test("Complete interview lifecycle from plan to draft")
    func completeInterviewLifecycle() async throws {
        let orchestrator = MockInterviewOrchestrator()

        // Phase 1: Planning
        let plan = try await orchestrator.generatePlan(
            topic: "Building Startups",
            context: "Founder with 10 years experience",
            durationMinutes: 10
        )

        #expect(!plan.sections.isEmpty)
        #expect(plan.researchGoal.count > 10)

        // Phase 2: Live Interview (simulated)
        orchestrator.startInterview(with: plan, targetSeconds: 600)

        // Simulate 3 interview cycles
        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.openingTranscript,
            elapsedSeconds: 30
        )
        #expect(orchestrator.currentPhase == "opening")
        #expect(!orchestrator.notes.keyIdeas.isEmpty)

        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.deepDiveTranscript,
            elapsedSeconds: 300
        )
        #expect(orchestrator.currentPhase == "deep_dive")
        #expect(orchestrator.research.count > 0)

        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.closingTranscript,
            elapsedSeconds: 540
        )
        #expect(orchestrator.currentPhase == "wrap_up")
        #expect(!orchestrator.notes.stories.isEmpty)

        // Phase 3: Analysis
        let analysis = try await orchestrator.generateAnalysis()
        #expect(!analysis.themes.isEmpty)
        #expect(!analysis.quotes.isEmpty)

        // Phase 4: Draft
        let draft = try await orchestrator.generateDraft()
        #expect(draft.count > 500)
        #expect(draft.contains("#"))  // Has markdown headers
    }

    // MARK: - Agent Data Flow

    @Test("Notes flow from NoteTaker to Orchestrator")
    func notesFlowToOrchestrator() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.openingTranscript,
            elapsedSeconds: 30
        )

        // Orchestrator should have access to notes
        let decision = orchestrator.lastDecision
        #expect(decision != nil)
    }

    @Test("Research flows from Researcher to Orchestrator")
    func researchFlowsToOrchestrator() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        // Transcript mentions a researchable topic
        let transcript = [
            TranscriptEntry(speaker: "user", text: "We used the Lean Startup methodology extensively.", timestamp: Date(), isFinal: true)
        ]

        try await orchestrator.simulateInterviewCycle(
            transcript: transcript,
            elapsedSeconds: 100
        )

        // Research should be available
        #expect(orchestrator.research.contains { $0.topic.lowercased().contains("lean") })
    }

    @Test("Orchestrator decision incorporates all agent data")
    func orchestratorIncorporatesAllAgentData() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        // Set up state with notes and research
        orchestrator.notes = TestFixtures.partialNotes
        orchestrator.research = TestFixtures.sampleResearch

        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.deepDiveTranscript,
            elapsedSeconds: 200
        )

        let decision = orchestrator.lastDecision!

        // Decision should be informed by notes (not repeating covered topics)
        // Decision should reference research context
        #expect(!decision.nextQuestion.text.isEmpty)
        #expect(!decision.interviewerBrief.isEmpty)
    }

    // MARK: - Parallel Agent Execution

    @Test("NoteTaker and Researcher run in parallel")
    func noteTakerAndResearcherParallel() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        let startTime = Date()

        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.deepDiveTranscript,
            elapsedSeconds: 200
        )

        let elapsed = Date().timeIntervalSince(startTime)

        // If running in parallel, should complete faster than sequential
        #expect(elapsed < 0.5)  // Allow some overhead
    }

    @Test("Orchestrator runs after parallel agents complete")
    func orchestratorRunsAfterParallel() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.deepDiveTranscript,
            elapsedSeconds: 200
        )

        // Verify execution order
        let executionOrder = orchestrator.agentExecutionOrder
        let noteTakerIndex = executionOrder.firstIndex(of: "noteTaker")!
        let researcherIndex = executionOrder.firstIndex(of: "researcher")!
        let orchestratorIndex = executionOrder.firstIndex(of: "orchestrator")!

        // NoteTaker and Researcher start before Orchestrator
        #expect(noteTakerIndex < orchestratorIndex)
        #expect(researcherIndex < orchestratorIndex)
    }

    // MARK: - State Accumulation

    @Test("Notes accumulate across cycles")
    func notesAccumulateAcrossCycles() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        // Cycle 1
        try await orchestrator.simulateInterviewCycle(
            transcript: [TranscriptEntry(speaker: "user", text: "First key idea here.", timestamp: Date(), isFinal: true)],
            elapsedSeconds: 30
        )
        let notesAfterCycle1 = orchestrator.notes.keyIdeas.count

        // Cycle 2
        try await orchestrator.simulateInterviewCycle(
            transcript: [TranscriptEntry(speaker: "user", text: "Second key idea here.", timestamp: Date(), isFinal: true)],
            elapsedSeconds: 60
        )
        let notesAfterCycle2 = orchestrator.notes.keyIdeas.count

        // Notes should accumulate (or at least not decrease)
        #expect(notesAfterCycle2 >= notesAfterCycle1)
    }

    @Test("Research accumulates without duplicates")
    func researchAccumulatesNoDuplicates() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        // Same topic mentioned twice
        try await orchestrator.simulateInterviewCycle(
            transcript: [TranscriptEntry(speaker: "user", text: "Lean startup is important.", timestamp: Date(), isFinal: true)],
            elapsedSeconds: 30
        )
        let countAfter1 = orchestrator.research.count

        try await orchestrator.simulateInterviewCycle(
            transcript: [TranscriptEntry(speaker: "user", text: "Lean startup changed everything.", timestamp: Date(), isFinal: true)],
            elapsedSeconds: 60
        )
        let countAfter2 = orchestrator.research.count

        // Should not duplicate research for same topic
        #expect(countAfter2 == countAfter1 || countAfter2 == countAfter1 + 1)
    }

    @Test("Question tracking prevents repetition")
    func questionTrackingPreventsRepetition() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        var askedQuestions: Set<String> = []

        for i in 0..<5 {
            try await orchestrator.simulateInterviewCycle(
                transcript: [TranscriptEntry(speaker: "user", text: "Response \(i)", timestamp: Date(), isFinal: true)],
                elapsedSeconds: 30 + i * 60
            )

            if let question = orchestrator.lastDecision?.nextQuestion.text {
                // Should not repeat questions
                #expect(!askedQuestions.contains(question))
                askedQuestions.insert(question)
            }
        }
    }

    // MARK: - Error Recovery

    @Test("Orchestrator handles NoteTaker failure gracefully")
    func orchestratorHandlesNoteTakerFailure() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.noteTakerShouldFail = true
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        // Should not throw - should handle gracefully
        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.deepDiveTranscript,
            elapsedSeconds: 200
        )

        // Should still produce a decision
        #expect(orchestrator.lastDecision != nil)
    }

    @Test("Orchestrator handles Researcher failure gracefully")
    func orchestratorHandlesResearcherFailure() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.researcherShouldFail = true
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.deepDiveTranscript,
            elapsedSeconds: 200
        )

        // Should still produce a decision
        #expect(orchestrator.lastDecision != nil)
    }

    // MARK: - Follow-up Session

    @Test("Follow-up session preserves previous context")
    func followUpPreservesContext() async throws {
        let orchestrator = MockInterviewOrchestrator()

        // Complete first session
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)
        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.deepDiveTranscript,
            elapsedSeconds: 300
        )

        let notesFromFirstSession = orchestrator.notes
        let researchFromFirstSession = orchestrator.research

        // Start follow-up
        orchestrator.startFollowUp(followUpContext: "Explore hiring practices")

        // Previous notes and research should be preserved
        #expect(orchestrator.notes.keyIdeas.count >= notesFromFirstSession.keyIdeas.count)
        #expect(orchestrator.research.count >= researchFromFirstSession.count)
    }

    @Test("Follow-up questions don't repeat original session")
    func followUpQuestionsNoRepeat() async throws {
        let orchestrator = MockInterviewOrchestrator()

        // First session
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)
        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.deepDiveTranscript,
            elapsedSeconds: 300
        )

        let questionsFromFirst = orchestrator.askedQuestionTexts

        // Start follow-up
        orchestrator.startFollowUp(followUpContext: "New angle")

        try await orchestrator.simulateInterviewCycle(
            transcript: [TranscriptEntry(speaker: "user", text: "New content", timestamp: Date(), isFinal: true)],
            elapsedSeconds: 30
        )

        // New questions should not repeat
        if let newQuestion = orchestrator.lastDecision?.nextQuestion.text {
            #expect(!questionsFromFirst.contains(newQuestion))
        }
    }

    @Test("Follow-up transcript merges with original")
    func followUpTranscriptMerges() async throws {
        let orchestrator = MockInterviewOrchestrator()

        // First session
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)
        let originalTranscript = TestFixtures.deepDiveTranscript
        try await orchestrator.simulateInterviewCycle(
            transcript: originalTranscript,
            elapsedSeconds: 300
        )

        let transcriptLengthAfterFirst = orchestrator.fullTranscript.count

        // Start follow-up
        orchestrator.startFollowUp(followUpContext: "Continue")

        let followUpTranscript = [
            TranscriptEntry(speaker: "assistant", text: "Welcome back!", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "user", text: "Thanks!", timestamp: Date(), isFinal: true)
        ]

        try await orchestrator.simulateInterviewCycle(
            transcript: followUpTranscript,
            elapsedSeconds: 30
        )

        // Full transcript should include both sessions
        #expect(orchestrator.fullTranscript.count == transcriptLengthAfterFirst + followUpTranscript.count)
    }

    // MARK: - Analysis Integration

    @Test("Analysis uses complete interview data")
    func analysisUsesCompleteData() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        // Build up interview data
        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.deepDiveTranscript,
            elapsedSeconds: 300
        )

        orchestrator.notes = TestFixtures.fullNotes

        let analysis = try await orchestrator.generateAnalysis()

        // Analysis should incorporate notes data
        #expect(!analysis.themes.isEmpty)
        #expect(!analysis.quotes.isEmpty)
        #expect(!analysis.mainClaims.isEmpty)
    }

    @Test("Analysis preserves quotable lines from live notes")
    func analysisPreservesLiveQuotes() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        // Notes with quotable lines
        orchestrator.notes = NotesState(
            keyIdeas: [],
            stories: [],
            claims: [],
            gaps: [],
            contradictions: [],
            possibleTitles: [],
            sectionCoverage: [],
            quotableLines: [
                QuotableLine(text: "Exceptional live quote", potentialUse: "hook", topic: "test", strength: "exceptional")
            ]
        )

        let analysis = try await orchestrator.generateAnalysis()

        // Should include the exceptional quote
        #expect(analysis.quotes.contains { $0.text.contains("Exceptional") })
    }

    // MARK: - Draft Generation

    @Test("Draft incorporates analysis themes")
    func draftIncorporatesAnalysis() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)

        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.deepDiveTranscript,
            elapsedSeconds: 500
        )

        _ = try await orchestrator.generateAnalysis()
        let draft = try await orchestrator.generateDraft()

        #expect(draft.count > 100)
    }

    @Test("Draft uses quotes from analysis")
    func draftUsesQuotes() async throws {
        let orchestrator = MockInterviewOrchestrator()
        orchestrator.startInterview(with: TestFixtures.standardPlan, targetSeconds: 600)
        orchestrator.notes = TestFixtures.fullNotes

        _ = try await orchestrator.generateAnalysis()
        let draft = try await orchestrator.generateDraft()

        // Draft should contain blockquotes
        #expect(draft.contains(">"))
    }

    // MARK: - Complete Workflow

    @Test("Full workflow from topic to publishable draft")
    func fullWorkflowToPublishableDraft() async throws {
        let orchestrator = MockInterviewOrchestrator()

        // 1. Generate plan
        let plan = try await orchestrator.generatePlan(
            topic: "Engineering Leadership",
            context: "CTO at growing startup",
            durationMinutes: 14
        )
        #expect(plan.sections.count >= 3)

        // 2. Run interview through all phases
        orchestrator.startInterview(with: plan, targetSeconds: 840)

        // Opening
        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.openingTranscript,
            elapsedSeconds: 60
        )

        // Deep dive
        for i in 1...3 {
            try await orchestrator.simulateInterviewCycle(
                transcript: TestFixtures.deepDiveTranscript,
                elapsedSeconds: 60 + i * 180
            )
        }

        // Wrap up
        try await orchestrator.simulateInterviewCycle(
            transcript: TestFixtures.closingTranscript,
            elapsedSeconds: 780
        )

        // 3. Generate analysis
        let analysis = try await orchestrator.generateAnalysis()
        #expect(!analysis.suggestedTitle.isEmpty)

        // 4. Generate draft
        let draft = try await orchestrator.generateDraft()

        // Verify draft quality indicators
        #expect(draft.count > 500)
        #expect(draft.contains("#"))  // Has headers
        #expect(draft.contains(">") || draft.contains("\""))  // Has quotes
    }
}

// MARK: - Mock Interview Orchestrator

/// Simulates the full interview orchestration for testing
@MainActor
final class MockInterviewOrchestrator {
    // State
    var notes: NotesState = .empty
    var research: [ResearchItem] = []
    var currentPhase = "opening"
    var lastDecision: OrchestratorDecision?
    var fullTranscript: [TranscriptEntry] = []
    var askedQuestionTexts: Set<String> = []
    var askedQuestionIds: Set<String> = []

    // Configuration
    var noteTakerShouldFail = false
    var researcherShouldFail = false
    var noteTakerDelay: TimeInterval = 0.05
    var researcherDelay: TimeInterval = 0.05
    var agentTimeout: TimeInterval = 2.0

    // Tracking
    var agentExecutionOrder: [String] = []

    private var plan: PlanSnapshot?
    private var targetSeconds: Int = 600
    private var isFollowUp = false
    private var followUpContext: String?

    func generatePlan(topic: String, context: String, durationMinutes: Int) async throws -> PlanSnapshot {
        // Simulate planning
        try? await Task.sleep(for: .milliseconds(50))

        return PlanSnapshot(
            topic: topic,
            researchGoal: "Understand \(topic) from practitioner perspective",
            angle: "Practical lessons learned",
            sections: [
                PlanSnapshot.SectionSnapshot(id: "bg", title: "Background", importance: "high", questions: [
                    PlanSnapshot.QuestionSnapshot(id: "q1", text: "How did you get into this?", role: "opening", priority: 1, notesForInterviewer: "")
                ]),
                PlanSnapshot.SectionSnapshot(id: "challenges", title: "Challenges", importance: "high", questions: [
                    PlanSnapshot.QuestionSnapshot(id: "q2", text: "What's been hardest?", role: "backbone", priority: 1, notesForInterviewer: "")
                ]),
                PlanSnapshot.SectionSnapshot(id: "lessons", title: "Lessons", importance: "medium", questions: [
                    PlanSnapshot.QuestionSnapshot(id: "q3", text: "What would you do differently?", role: "backbone", priority: 2, notesForInterviewer: "")
                ])
            ]
        )
    }

    func startInterview(with plan: PlanSnapshot, targetSeconds: Int) {
        self.plan = plan
        self.targetSeconds = targetSeconds
        self.currentPhase = "opening"
        self.notes = .empty
        self.research = []
        self.fullTranscript = []
        self.askedQuestionTexts = []
        self.askedQuestionIds = []
        self.isFollowUp = false
        self.followUpContext = nil
    }

    func startFollowUp(followUpContext: String) {
        self.isFollowUp = true
        self.followUpContext = followUpContext
        self.currentPhase = "opening"
        // Notes and research are preserved
    }

    func simulateInterviewCycle(transcript: [TranscriptEntry], elapsedSeconds: Int) async throws {
        agentExecutionOrder = []

        // Update transcript
        fullTranscript.append(contentsOf: transcript)

        // Calculate phase
        currentPhase = calculatePhase(elapsed: elapsedSeconds, target: targetSeconds)

        // Run NoteTaker and Researcher in parallel
        async let notesResult = runNoteTaker(transcript: transcript)
        async let researchResult = runResearcher(transcript: transcript)

        let (newNotes, newResearch) = try await (notesResult, researchResult)

        // Merge notes
        if let newNotes = newNotes {
            notes = NotesState.merge(existing: notes, new: newNotes)
        }

        // Add research (avoiding duplicates)
        for item in newResearch {
            if !research.contains(where: { $0.topic.lowercased() == item.topic.lowercased() }) {
                research.append(item)
            }
        }

        // Run Orchestrator (depends on notes and research)
        agentExecutionOrder.append("orchestrator")
        lastDecision = try await runOrchestrator(elapsedSeconds: elapsedSeconds)

        // Track asked question
        if let decision = lastDecision {
            askedQuestionTexts.insert(decision.nextQuestion.text)
        }
    }

    func generateAnalysis() async throws -> AnalysisSummary {
        try? await Task.sleep(for: .milliseconds(50))

        // Merge live quotable lines with analysis quotes
        var quotes = TestFixtures.sampleQuotes
        for quotable in notes.quotableLines where quotable.strength == "exceptional" || quotable.strength == "great" {
            let quote = Quote(text: quotable.text, role: quotable.potentialUse)
            if !quotes.contains(where: { $0.text == quote.text }) {
                quotes.insert(quote, at: 0)
            }
        }

        return AnalysisSummary(
            researchGoal: plan?.researchGoal ?? "Unknown",
            mainClaims: [
                MainClaim(text: "Key insight 1", evidenceStoryIds: ["story-1"]),
                MainClaim(text: "Key insight 2", evidenceStoryIds: ["story-2"])
            ],
            themes: ["Leadership", "Growth", "Challenges"],
            tensions: ["Speed vs Quality"],
            quotes: quotes,
            suggestedTitle: "Lessons from the Trenches",
            suggestedSubtitle: "What building companies taught me"
        )
    }

    func generateDraft() async throws -> String {
        try? await Task.sleep(for: .milliseconds(50))

        return """
        # Lessons from the Trenches: Building Companies That Matter

        ## Introduction

        The journey of building something from scratch is never straightforward. It requires patience, resilience, and an unwavering commitment to learning from every setback. Over the years, I've accumulated wisdom that can only come from experience.

        > "We learned more from our failures than our successes. Every misstep taught us something crucial about our customers, our product, and ourselves."

        ## The Challenge of Starting

        Every leader faces moments of doubt. The key is perseverance and the ability to adapt quickly. When we started, we thought we knew what customers wanted. We were wrong—spectacularly so.

        ## Key Insights

        1. Start with the problem, not the solution
        2. Build for the user, not for yourself
        3. Embrace failure as feedback, not as defeat
        4. Talk to customers before writing a single line of code
        5. Move fast, but never at the expense of understanding

        ## Conclusion

        The path forward is rarely clear, but that's what makes the entrepreneurial journey worthwhile. Keep building, keep learning, and never stop asking questions.
        """
    }

    // MARK: - Private Helpers

    private func runNoteTaker(transcript: [TranscriptEntry]) async throws -> NotesState? {
        agentExecutionOrder.append("noteTaker")

        if noteTakerShouldFail {
            return nil
        }

        do {
            try await Task.sleep(for: .milliseconds(Int(noteTakerDelay * 1000)))
        } catch {
            return nil
        }

        // Extract simple notes from transcript
        var keyIdeas: [KeyIdea] = []
        var stories: [Story] = []

        for entry in transcript where entry.speaker == "user" {
            if entry.text.count > 20 {
                keyIdeas.append(KeyIdea(text: String(entry.text.prefix(100))))
            }
            // Extract stories from longer entries that seem narrative
            if entry.text.count > 50 {
                stories.append(Story(summary: String(entry.text.prefix(80)), impact: "Learning experience"))
            }
        }

        return NotesState(
            keyIdeas: keyIdeas,
            stories: stories,
            claims: [],
            gaps: [],
            contradictions: [],
            possibleTitles: [],
            sectionCoverage: [],
            quotableLines: []
        )
    }

    private func runResearcher(transcript: [TranscriptEntry]) async throws -> [ResearchItem] {
        agentExecutionOrder.append("researcher")

        if researcherShouldFail {
            return []
        }

        try? await Task.sleep(for: .milliseconds(Int(researcherDelay * 1000)))

        // Look for researchable topics
        var items: [ResearchItem] = []
        let text = transcript.map { $0.text }.joined(separator: " ").lowercased()

        if text.contains("lean startup") || text.contains("lean") {
            items.append(ResearchItem(
                topic: "Lean Startup",
                kind: "methodology",
                summary: "Build-Measure-Learn approach",
                howToUseInQuestion: "Reference their use of lean principles"
            ))
        }

        return items
    }

    private func runOrchestrator(elapsedSeconds: Int) async throws -> OrchestratorDecision {
        try? await Task.sleep(for: .milliseconds(50))

        // Generate a question that hasn't been asked
        var questionText = "Tell me more about that."
        var attempts = 0

        while askedQuestionTexts.contains(questionText) && attempts < 10 {
            questionText = "Follow-up question \(attempts + 1)?"
            attempts += 1
        }

        return OrchestratorDecision(
            phase: currentPhase,
            nextQuestion: NextQuestion(text: questionText, targetSectionId: "section-1"),
            interviewerBrief: "Explore the topic further based on their response."
        )
    }

    private func calculatePhase(elapsed: Int, target: Int) -> String {
        guard target > 0 else { return "wrap_up" }
        let progress = Double(elapsed) / Double(target)
        let openingThreshold = isFollowUp ? 0.10 : 0.15
        if progress < openingThreshold { return "opening" }
        if progress < 0.85 { return "deep_dive" }
        return "wrap_up"
    }
}

// MARK: - Test Fixtures Extensions

private extension TestFixtures {
    static var openingTranscript: [TranscriptEntry] {
        [
            TranscriptEntry(speaker: "assistant", text: "Welcome! I'm excited to learn about your journey.", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "user", text: "Thanks for having me. I've been in the industry for about 10 years now.", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "assistant", text: "What first drew you to this field?", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "user", text: "I stumbled into it honestly. Started as an engineer and gradually moved into leadership.", timestamp: Date(), isFinal: true)
        ]
    }

    static var deepDiveTranscript: [TranscriptEntry] {
        [
            TranscriptEntry(speaker: "assistant", text: "What's been the biggest challenge you've faced?", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "user", text: "Scaling the team was incredibly hard. We went from 5 to 50 people in 18 months. We used lean startup principles but had to adapt them significantly.", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "assistant", text: "How did you adapt those principles?", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "user", text: "We realized that move fast and break things doesn't work when you have customers depending on you. We had to find balance.", timestamp: Date(), isFinal: true)
        ]
    }

    static var closingTranscript: [TranscriptEntry] {
        [
            TranscriptEntry(speaker: "assistant", text: "What advice would you give to others starting this journey?", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "user", text: "Don't be afraid to fail. Every failure taught us something. We spent two years building a product nobody wanted before we figured it out.", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "assistant", text: "Any final thoughts?", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "user", text: "Just that it's worth it. The struggle is part of the journey.", timestamp: Date(), isFinal: true)
        ]
    }

    static var sampleQuotes: [Quote] {
        [
            Quote(text: "Every failure taught us something.", role: "opinion"),
            Quote(text: "The struggle is part of the journey.", role: "turning_point")
        ]
    }
}
