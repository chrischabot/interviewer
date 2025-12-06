import Foundation
import Testing
@testable import Interviewer

/// Tests for interview phase transitions, timing logic, and phase-specific behavior
@Suite("Phase Transition Tests")
struct PhaseTransitionTests {

    // MARK: - Phase Calculation

    @Test("Opening phase spans first 15% of interview")
    func openingPhaseFirst15Percent() {
        let targetSeconds = 600  // 10 minutes

        // 0% = opening
        #expect(calculatePhase(elapsed: 0, target: targetSeconds) == "opening")

        // 5% = opening
        #expect(calculatePhase(elapsed: 30, target: targetSeconds) == "opening")

        // 10% = opening
        #expect(calculatePhase(elapsed: 60, target: targetSeconds) == "opening")

        // 14.9% = still opening
        #expect(calculatePhase(elapsed: 89, target: targetSeconds) == "opening")
    }

    @Test("Deep dive phase spans 15%-85% of interview")
    func deepDivePhaseMiddle() {
        let targetSeconds = 600

        // 15% = deep_dive starts
        #expect(calculatePhase(elapsed: 90, target: targetSeconds) == "deep_dive")

        // 50% = deep_dive
        #expect(calculatePhase(elapsed: 300, target: targetSeconds) == "deep_dive")

        // 84% = still deep_dive
        #expect(calculatePhase(elapsed: 504, target: targetSeconds) == "deep_dive")
    }

    @Test("Wrap up phase starts at 85%")
    func wrapUpPhaseStarts85Percent() {
        let targetSeconds = 600

        // 85% = wrap_up starts
        #expect(calculatePhase(elapsed: 510, target: targetSeconds) == "wrap_up")

        // 100% = wrap_up
        #expect(calculatePhase(elapsed: 600, target: targetSeconds) == "wrap_up")

        // Over 100% = still wrap_up
        #expect(calculatePhase(elapsed: 700, target: targetSeconds) == "wrap_up")
    }

    @Test("Phase boundaries work for different durations")
    func phaseBoundariesDifferentDurations() {
        // 5 minute interview
        #expect(calculatePhase(elapsed: 44, target: 300) == "opening")
        #expect(calculatePhase(elapsed: 45, target: 300) == "deep_dive")
        #expect(calculatePhase(elapsed: 254, target: 300) == "deep_dive")
        #expect(calculatePhase(elapsed: 255, target: 300) == "wrap_up")

        // 15 minute interview
        #expect(calculatePhase(elapsed: 134, target: 900) == "opening")
        #expect(calculatePhase(elapsed: 135, target: 900) == "deep_dive")
        #expect(calculatePhase(elapsed: 764, target: 900) == "deep_dive")
        #expect(calculatePhase(elapsed: 765, target: 900) == "wrap_up")
    }

    // MARK: - Phase Locking

    @Test("Phase never goes backward")
    func phaseNeverGoesBackward() {
        let tracker = PhaseTracker()

        // Progress forward
        _ = tracker.update(elapsed: 0, target: 600)
        #expect(tracker.currentPhase == "opening")

        _ = tracker.update(elapsed: 100, target: 600)
        #expect(tracker.currentPhase == "deep_dive")

        // Try to go back - should stay at deep_dive
        _ = tracker.update(elapsed: 50, target: 600)
        #expect(tracker.currentPhase == "deep_dive")

        // Progress to wrap_up
        _ = tracker.update(elapsed: 520, target: 600)
        #expect(tracker.currentPhase == "wrap_up")

        // Try to go back - should stay at wrap_up
        _ = tracker.update(elapsed: 100, target: 600)
        #expect(tracker.currentPhase == "wrap_up")
    }

    @Test("Manual phase advancement works")
    func manualPhaseAdvancement() {
        let tracker = PhaseTracker()

        _ = tracker.update(elapsed: 0, target: 600)
        #expect(tracker.currentPhase == "opening")

        // Manually advance to wrap_up (user clicks "wrap up" button)
        tracker.advanceTo("wrap_up")
        #expect(tracker.currentPhase == "wrap_up")

        // Can't go back even manually
        tracker.advanceTo("deep_dive")
        #expect(tracker.currentPhase == "wrap_up")
    }

    @Test("Phase can be forced only forward")
    func phaseForceOnlyForward() {
        let tracker = PhaseTracker()

        tracker.advanceTo("deep_dive")
        #expect(tracker.currentPhase == "deep_dive")

        tracker.advanceTo("opening")  // Can't go back
        #expect(tracker.currentPhase == "deep_dive")

        tracker.advanceTo("wrap_up")
        #expect(tracker.currentPhase == "wrap_up")
    }

    // MARK: - Phase Transition Events

    @Test("Phase change triggers callback")
    func phaseChangeTriggerCallback() {
        let tracker = PhaseTracker()
        var transitions: [(String, String)] = []

        tracker.onPhaseChange = { from, to in
            transitions.append((from, to))
        }

        _ = tracker.update(elapsed: 0, target: 600)  // Initial - no callback
        _ = tracker.update(elapsed: 100, target: 600)  // opening -> deep_dive
        _ = tracker.update(elapsed: 520, target: 600)  // deep_dive -> wrap_up

        #expect(transitions.count == 2)
        #expect(transitions[0] == ("opening", "deep_dive"))
        #expect(transitions[1] == ("deep_dive", "wrap_up"))
    }

    @Test("No callback when phase stays same")
    func noCallbackWhenPhaseSame() {
        let tracker = PhaseTracker()
        var callCount = 0

        tracker.onPhaseChange = { _, _ in
            callCount += 1
        }

        _ = tracker.update(elapsed: 0, target: 600)
        _ = tracker.update(elapsed: 10, target: 600)
        _ = tracker.update(elapsed: 20, target: 600)
        _ = tracker.update(elapsed: 30, target: 600)

        // All in opening phase - no transitions
        #expect(callCount == 0)
    }

    // MARK: - Phase-Specific Question Filtering

    @Test("Opening phase only shows opening questions")
    func openingPhaseOnlyOpeningQuestions() {
        let questions = TestFixtures.sampleQuestions

        let filtered = filterQuestionsForPhase(questions, phase: "opening")

        #expect(filtered.allSatisfy { $0.role == "opening" || $0.priority == 1 })
    }

    @Test("Deep dive phase shows all non-closing questions")
    func deepDiveShowsAllNonClosing() {
        let questions = TestFixtures.sampleQuestions

        let filtered = filterQuestionsForPhase(questions, phase: "deep_dive")

        #expect(filtered.contains { $0.role == "backbone" })
        #expect(filtered.contains { $0.role == "followup" })
        #expect(!filtered.contains { $0.role == "closing" })
    }

    @Test("Wrap up phase includes closing questions")
    func wrapUpIncludesClosing() {
        let questions = TestFixtures.sampleQuestions

        let filtered = filterQuestionsForPhase(questions, phase: "wrap_up")

        #expect(filtered.contains { $0.role == "closing" })
    }

    // MARK: - Time Remaining Calculations

    @Test("Time remaining is calculated correctly")
    func timeRemainingCalculatedCorrectly() {
        #expect(timeRemaining(elapsed: 0, target: 600) == 600)
        #expect(timeRemaining(elapsed: 300, target: 600) == 300)
        #expect(timeRemaining(elapsed: 600, target: 600) == 0)
        #expect(timeRemaining(elapsed: 700, target: 600) == 0)  // Can't be negative
    }

    @Test("Time until phase change is correct")
    func timeUntilPhaseChange() {
        // Opening -> deep_dive at 15%
        #expect(calculateTimeUntilPhaseChange(elapsed: 0, target: 600, currentPhase: "opening") == 90)
        #expect(calculateTimeUntilPhaseChange(elapsed: 50, target: 600, currentPhase: "opening") == 40)

        // Deep_dive -> wrap_up at 85%
        #expect(calculateTimeUntilPhaseChange(elapsed: 90, target: 600, currentPhase: "deep_dive") == 420)

        // Wrap_up - no more transitions
        #expect(calculateTimeUntilPhaseChange(elapsed: 510, target: 600, currentPhase: "wrap_up") == nil)
    }

    // MARK: - Phase Progress

    @Test("Progress percentage is calculated correctly")
    func progressPercentageCalculated() {
        #expect(progressPercentage(elapsed: 0, target: 600) == 0.0)
        #expect(progressPercentage(elapsed: 300, target: 600) == 0.5)
        #expect(progressPercentage(elapsed: 600, target: 600) == 1.0)
        #expect(progressPercentage(elapsed: 700, target: 600) == 1.0)  // Capped at 100%
    }

    @Test("Phase progress within current phase")
    func phaseProgressWithinPhase() {
        // Opening phase: 0-15%
        #expect(phaseProgress(elapsed: 0, target: 600, phase: "opening") == 0.0)
        #expect(phaseProgress(elapsed: 45, target: 600, phase: "opening") == 0.5)
        #expect(phaseProgress(elapsed: 89, target: 600, phase: "opening") > 0.9)

        // Deep dive: 15-85% (70% of total time)
        #expect(phaseProgress(elapsed: 90, target: 600, phase: "deep_dive") == 0.0)
        #expect(phaseProgress(elapsed: 300, target: 600, phase: "deep_dive") == 0.5)
        #expect(phaseProgress(elapsed: 509, target: 600, phase: "deep_dive") > 0.9)
    }

    // MARK: - Edge Cases

    @Test("Zero duration interview")
    func zeroDurationInterview() {
        // Should handle gracefully
        let phase = calculatePhase(elapsed: 0, target: 0)
        #expect(phase == "wrap_up" || phase == "opening")  // Either is acceptable
    }

    @Test("Negative elapsed time treated as zero")
    func negativeElapsedTreatedAsZero() {
        let phase = calculatePhase(elapsed: -100, target: 600)
        #expect(phase == "opening")
    }

    @Test("Very long interview maintains phases")
    func veryLongInterviewMaintainsPhases() {
        let targetSeconds = 3600  // 1 hour

        #expect(calculatePhase(elapsed: 539, target: targetSeconds) == "opening")
        #expect(calculatePhase(elapsed: 540, target: targetSeconds) == "deep_dive")
        #expect(calculatePhase(elapsed: 3059, target: targetSeconds) == "deep_dive")
        #expect(calculatePhase(elapsed: 3060, target: targetSeconds) == "wrap_up")
    }

    // MARK: - Follow-up Session Phase Reset

    @Test("Follow-up session starts in opening phase")
    func followUpStartsInOpening() {
        let tracker = PhaseTracker()

        // Original session went to wrap_up
        _ = tracker.update(elapsed: 520, target: 600)
        #expect(tracker.currentPhase == "wrap_up")

        // Start follow-up - should reset
        tracker.resetForFollowUp()
        #expect(tracker.currentPhase == "opening")
    }

    @Test("Follow-up opening phase is shorter")
    func followUpOpeningIsShorter() {
        // Follow-ups have 10% opening (re-establishing rapport briefly)
        #expect(calculatePhase(elapsed: 29, target: 300, isFollowUp: true) == "opening")
        #expect(calculatePhase(elapsed: 30, target: 300, isFollowUp: true) == "deep_dive")
    }
}

// MARK: - Test Helpers

/// Calculate phase based on elapsed time and target
private func calculatePhase(elapsed: Int, target: Int, isFollowUp: Bool = false) -> String {
    guard target > 0 else { return "wrap_up" }

    let safeElapsed = max(0, elapsed)
    let progress = Double(safeElapsed) / Double(target)

    let openingThreshold = isFollowUp ? 0.10 : 0.15
    let wrapUpThreshold = 0.85

    if progress < openingThreshold { return "opening" }
    if progress < wrapUpThreshold { return "deep_dive" }
    return "wrap_up"
}

/// Phase tracker with locking behavior
class PhaseTracker {
    private(set) var currentPhase = "opening"
    var onPhaseChange: ((String, String) -> Void)?

    private let phaseOrder = ["opening", "deep_dive", "wrap_up"]

    func update(elapsed: Int, target: Int) -> String {
        let newPhase = calculatePhase(elapsed: elapsed, target: target)

        // Only advance, never go backward
        if phaseIndex(newPhase) > phaseIndex(currentPhase) {
            let oldPhase = currentPhase
            currentPhase = newPhase
            onPhaseChange?(oldPhase, newPhase)
        }

        return currentPhase
    }

    func advanceTo(_ phase: String) {
        if phaseIndex(phase) > phaseIndex(currentPhase) {
            let oldPhase = currentPhase
            currentPhase = phase
            onPhaseChange?(oldPhase, phase)
        }
    }

    func resetForFollowUp() {
        currentPhase = "opening"
    }

    private func phaseIndex(_ phase: String) -> Int {
        phaseOrder.firstIndex(of: phase) ?? 0
    }

    private func calculatePhase(elapsed: Int, target: Int) -> String {
        guard target > 0 else { return "wrap_up" }

        let progress = Double(max(0, elapsed)) / Double(target)

        if progress < 0.15 { return "opening" }
        if progress < 0.85 { return "deep_dive" }
        return "wrap_up"
    }
}

/// Filter questions by phase
private func filterQuestionsForPhase(_ questions: [TestQuestion], phase: String) -> [TestQuestion] {
    switch phase {
    case "opening":
        return questions.filter { $0.role == "opening" || $0.priority == 1 }
    case "deep_dive":
        return questions.filter { $0.role != "closing" }
    case "wrap_up":
        return questions
    default:
        return questions
    }
}

/// Time calculations
private func timeRemaining(elapsed: Int, target: Int) -> Int {
    max(0, target - elapsed)
}

private func calculateTimeUntilPhaseChange(elapsed: Int, target: Int, currentPhase: String) -> Int? {
    switch currentPhase {
    case "opening":
        return max(0, Int(Double(target) * 0.15) - elapsed)
    case "deep_dive":
        return max(0, Int(Double(target) * 0.85) - elapsed)
    case "wrap_up":
        return nil  // No more transitions
    default:
        return nil
    }
}

private func progressPercentage(elapsed: Int, target: Int) -> Double {
    guard target > 0 else { return 1.0 }
    return min(1.0, Double(max(0, elapsed)) / Double(target))
}

private func phaseProgress(elapsed: Int, target: Int, phase: String) -> Double {
    guard target > 0 else { return 1.0 }

    let progress = Double(max(0, elapsed)) / Double(target)

    switch phase {
    case "opening":
        return min(1.0, progress / 0.15)
    case "deep_dive":
        let phaseStart = 0.15
        let phaseEnd = 0.85
        let phaseLength = phaseEnd - phaseStart
        return min(1.0, max(0, (progress - phaseStart) / phaseLength))
    case "wrap_up":
        let phaseStart = 0.85
        let phaseLength = 0.15
        return min(1.0, max(0, (progress - phaseStart) / phaseLength))
    default:
        return 0.0
    }
}

/// Test question struct
struct TestQuestion {
    let text: String
    let role: String
    let priority: Int
}

// MARK: - Test Fixtures Extension

private extension TestFixtures {
    static var sampleQuestions: [TestQuestion] {
        [
            TestQuestion(text: "Tell me about yourself", role: "opening", priority: 1),
            TestQuestion(text: "What's your background?", role: "opening", priority: 1),
            TestQuestion(text: "What led you to this path?", role: "backbone", priority: 1),
            TestQuestion(text: "Can you tell me more?", role: "followup", priority: 2),
            TestQuestion(text: "How did that feel?", role: "followup", priority: 3),
            TestQuestion(text: "What patterns do you see?", role: "backbone", priority: 2),
            TestQuestion(text: "What would you tell others?", role: "closing", priority: 1),
            TestQuestion(text: "Anything else to add?", role: "closing", priority: 2)
        ]
    }
}
