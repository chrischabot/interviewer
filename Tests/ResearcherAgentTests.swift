import Foundation
import Testing
@testable import Interviewer

/// Tests for ResearcherAgent topic tracking, refresh logic, and claim verification
@Suite("ResearcherAgent Tests")
struct ResearcherAgentTests {

    // MARK: - Topic Tracking

    @Test("Successfully researched topics are tracked")
    func successfulTopicsTracked() async throws {
        let tracker = ResearchTopicTracker()

        tracker.markAttempted(topic: "Lean Startup")
        tracker.markSuccessful(topic: "Lean Startup")

        #expect(tracker.wasAttempted("lean startup"))  // Case insensitive
        #expect(tracker.wasSuccessful("Lean Startup"))
    }

    @Test("Topics are deduplicated case-insensitively")
    func topicsDeduplicatedCaseInsensitive() async {
        let tracker = ResearchTopicTracker()

        tracker.markAttempted(topic: "AI Native Apps")
        tracker.markAttempted(topic: "ai native apps")
        tracker.markAttempted(topic: "AI NATIVE APPS")

        // Should only count as one topic
        #expect(tracker.attemptedCount == 1)
    }

    // MARK: - Topic Refresh

    @Test("Attempted topics refresh after interval")
    func attemptedTopicsRefresh() async {
        let tracker = ResearchTopicTracker(refreshInterval: 0.1)  // 100ms for testing

        tracker.markAttempted(topic: "Test Topic")
        #expect(tracker.wasAttempted("Test Topic"))

        // Wait for refresh interval
        try? await Task.sleep(for: .milliseconds(150))

        tracker.refreshTopics()

        // Topic should no longer be in attempted set
        #expect(!tracker.wasAttempted("Test Topic"))
    }

    @Test("Successful topics refresh after interval")
    func successfulTopicsRefresh() async {
        let tracker = ResearchTopicTracker(refreshInterval: 0.1)

        tracker.markSuccessful(topic: "Test Topic")
        #expect(tracker.wasSuccessful("Test Topic"))

        try? await Task.sleep(for: .milliseconds(150))

        tracker.refreshTopics()

        // Topic should no longer be in successful set - can be re-researched
        #expect(!tracker.wasSuccessful("Test Topic"))
    }

    @Test("Recent topics are not refreshed")
    func recentTopicsNotRefreshed() async {
        let tracker = ResearchTopicTracker(refreshInterval: 1.0)  // 1 second

        tracker.markSuccessful(topic: "Test Topic")
        tracker.refreshTopics()

        // Should still be tracked (not enough time passed)
        #expect(tracker.wasSuccessful("Test Topic"))
    }

    // MARK: - Filtering Logic

    @Test("Filters out already attempted topics")
    func filtersAttemptedTopics() {
        let tracker = ResearchTopicTracker()
        tracker.markAttempted(topic: "Topic A")

        let candidates = ["Topic A", "Topic B", "Topic C"]
        let filtered = tracker.filterNewTopics(candidates)

        #expect(filtered.count == 2)
        #expect(!filtered.contains("Topic A"))
        #expect(filtered.contains("Topic B"))
        #expect(filtered.contains("Topic C"))
    }

    @Test("Filters out already successful topics")
    func filtersSuccessfulTopics() {
        let tracker = ResearchTopicTracker()
        tracker.markSuccessful(topic: "Topic A")

        let candidates = ["Topic A", "Topic B"]
        let filtered = tracker.filterNewTopics(candidates)

        #expect(filtered.count == 1)
        #expect(filtered.contains("Topic B"))
    }

    @Test("Filters both attempted and successful")
    func filtersBothAttemptedAndSuccessful() {
        let tracker = ResearchTopicTracker()
        tracker.markAttempted(topic: "Attempted Only")
        tracker.markSuccessful(topic: "Successful")

        let candidates = ["Attempted Only", "Successful", "New Topic"]
        let filtered = tracker.filterNewTopics(candidates)

        #expect(filtered.count == 1)
        #expect(filtered.contains("New Topic"))
    }

    // MARK: - Reset

    @Test("Reset clears all tracking")
    func resetClearsAll() {
        let tracker = ResearchTopicTracker()

        tracker.markAttempted(topic: "A")
        tracker.markSuccessful(topic: "B")

        tracker.reset()

        #expect(!tracker.wasAttempted("A"))
        #expect(!tracker.wasSuccessful("B"))
        #expect(tracker.attemptedCount == 0)
    }

    // MARK: - Consecutive Failures

    @Test("Consecutive failures trigger cooldown")
    func consecutiveFailuresCooldown() {
        let tracker = ResearchTopicTracker(maxConsecutiveFailures: 3)

        tracker.recordFailure()
        tracker.recordFailure()
        #expect(!tracker.isInCooldown)

        tracker.recordFailure()
        #expect(tracker.isInCooldown)
    }

    @Test("Success resets consecutive failures")
    func successResetsFailures() {
        let tracker = ResearchTopicTracker(maxConsecutiveFailures: 3)

        tracker.recordFailure()
        tracker.recordFailure()
        tracker.recordSuccess()

        #expect(!tracker.isInCooldown)

        // Should need 3 more failures to trigger cooldown
        tracker.recordFailure()
        tracker.recordFailure()
        #expect(!tracker.isInCooldown)

        tracker.recordFailure()
        #expect(tracker.isInCooldown)
    }

    // MARK: - Claim Verification

    @Test("Claim verification items have correct fields")
    func claimVerificationFields() {
        let item = ResearchItem(
            topic: "90% of startups fail",
            kind: "claim_verification",
            summary: "Statistics vary by source and timeframe",
            howToUseInQuestion: "Ask about their view on failure rates",
            priority: 1,
            verificationStatus: "partially_true",
            verificationNote: "Actual rate is 70-75% within 10 years"
        )

        #expect(item.kind == "claim_verification")
        #expect(item.verificationStatus == "partially_true")
        #expect(item.verificationNote?.contains("70-75%") == true)
    }

    @Test("isVerifiedClaim helper works correctly")
    func isVerifiedClaimHelper() {
        let verified = ResearchItem(
            topic: "Test",
            kind: "claim_verification",
            summary: "Verified",
            howToUseInQuestion: "Use it",
            verificationStatus: "verified"
        )

        let contradicted = ResearchItem(
            topic: "Test",
            kind: "claim_verification",
            summary: "Wrong",
            howToUseInQuestion: "Clarify",
            verificationStatus: "contradicted"
        )

        let regular = ResearchItem(
            topic: "Test",
            kind: "definition",
            summary: "Definition",
            howToUseInQuestion: "Reference"
        )

        #expect(verified.isVerifiedClaim)
        #expect(!verified.isContradictedClaim)

        #expect(!contradicted.isVerifiedClaim)
        #expect(contradicted.isContradictedClaim)

        #expect(!regular.isVerifiedClaim)
        #expect(!regular.isContradictedClaim)
    }

    // MARK: - Research Item Kind

    @Test("All research kinds have display names")
    func researchKindsHaveDisplayNames() {
        for kind in ResearchItemKind.allCases {
            #expect(!kind.displayName.isEmpty)
        }
    }

    @Test("Claim verification kind has correct raw value")
    func claimVerificationKindRawValue() {
        #expect(ResearchItemKind.claimVerification.rawValue == "claim_verification")
    }
}

// MARK: - ResearchTopicTracker (Test Helper)

/// A simplified tracker for testing the topic tracking logic
/// This mirrors the tracking behavior in ResearcherAgent
class ResearchTopicTracker {
    private var attemptedTopics: Set<String> = []
    private var successfulTopics: Set<String> = []
    private var attemptedAt: [String: Date] = [:]
    private var successfulAt: [String: Date] = [:]
    private var consecutiveFailures = 0

    let refreshInterval: TimeInterval
    let maxConsecutiveFailures: Int

    init(refreshInterval: TimeInterval = 300, maxConsecutiveFailures: Int = 5) {
        self.refreshInterval = refreshInterval
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }

    var attemptedCount: Int { attemptedTopics.count }

    var isInCooldown: Bool {
        consecutiveFailures >= maxConsecutiveFailures
    }

    func markAttempted(topic: String) {
        let key = topic.lowercased()
        attemptedTopics.insert(key)
        attemptedAt[key] = Date()
    }

    func markSuccessful(topic: String) {
        let key = topic.lowercased()
        successfulTopics.insert(key)
        successfulAt[key] = Date()
    }

    func wasAttempted(_ topic: String) -> Bool {
        attemptedTopics.contains(topic.lowercased())
    }

    func wasSuccessful(_ topic: String) -> Bool {
        successfulTopics.contains(topic.lowercased())
    }

    func refreshTopics() {
        let now = Date()

        attemptedTopics = attemptedTopics.filter { key in
            guard let time = attemptedAt[key] else { return false }
            return now.timeIntervalSince(time) < refreshInterval
        }

        successfulTopics = successfulTopics.filter { key in
            guard let time = successfulAt[key] else { return false }
            return now.timeIntervalSince(time) < refreshInterval
        }
    }

    func filterNewTopics(_ candidates: [String]) -> [String] {
        candidates.filter { topic in
            let key = topic.lowercased()
            return !attemptedTopics.contains(key) && !successfulTopics.contains(key)
        }
    }

    func recordFailure() {
        consecutiveFailures += 1
    }

    func recordSuccess() {
        consecutiveFailures = 0
    }

    func reset() {
        attemptedTopics = []
        successfulTopics = []
        attemptedAt = [:]
        successfulAt = [:]
        consecutiveFailures = 0
    }
}
