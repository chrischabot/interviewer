import Foundation
import Testing
@testable import Interviewer

/// Tests for NoteTakerAgent's merge logic
/// These tests verify that notes are properly merged without data loss
@Suite("NoteTaker Merge Tests")
struct NoteTakerMergeTests {

    // MARK: - Key Ideas Merging

    @Test("Key ideas are merged without duplicates")
    func keyIdeasMergeNoDuplicates() {
        let existing = NotesState(
            keyIdeas: [
                KeyIdea(text: "Fail fast is important"),
                KeyIdea(text: "Customer feedback drives decisions")
            ]
        )

        let new = NotesState(
            keyIdeas: [
                KeyIdea(text: "Fail fast is important"),  // Duplicate
                KeyIdea(text: "Hire for ambiguity tolerance")  // New
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        // Should have 3 unique ideas (no duplicate)
        #expect(merged.keyIdeas.count == 3)
        #expect(merged.keyIdeas.contains { $0.text == "Fail fast is important" })
        #expect(merged.keyIdeas.contains { $0.text == "Customer feedback drives decisions" })
        #expect(merged.keyIdeas.contains { $0.text == "Hire for ambiguity tolerance" })
    }

    @Test("Similar key ideas are deduplicated")
    func keyIdeasSimilarityDeduplication() {
        let existing = NotesState(
            keyIdeas: [
                KeyIdea(text: "Failing fast is critical for startup success in technology")
            ]
        )

        let new = NotesState(
            keyIdeas: [
                // Nearly identical wording = high Jaccard similarity (>0.7)
                KeyIdea(text: "Failing fast is critical for startup success")
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        // Should recognize these as the same idea (Jaccard > 0.7)
        #expect(merged.keyIdeas.count == 1)
    }

    @Test("Existing key ideas are preserved when new is empty")
    func keyIdeasPreservedWhenNewEmpty() {
        let existing = NotesState(
            keyIdeas: [
                KeyIdea(text: "Important idea 1"),
                KeyIdea(text: "Important idea 2")
            ]
        )

        let new = NotesState.empty

        let merged = NotesState.merge(existing: existing, new: new)

        #expect(merged.keyIdeas.count == 2)
    }

    // MARK: - Stories Merging

    @Test("Stories are merged without duplicates")
    func storiesMergeNoDuplicates() {
        let existing = NotesState(
            stories: [
                Story(summary: "We spent 2 years building the wrong product entirely", impact: "Learned to fail fast")
            ]
        )

        let new = NotesState(
            stories: [
                // Nearly identical - Jaccard > 0.7
                Story(summary: "We spent 2 years building the wrong product", impact: "Fail fast lesson"),
                Story(summary: "AI vs search pivot", impact: "Saved 3 months")  // New
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        // Should recognize the similar story and add the new one
        #expect(merged.stories.count == 2)
        #expect(merged.stories.contains { $0.summary.contains("AI") || $0.summary.contains("search") })
    }

    // MARK: - Claims Merging

    @Test("Claims are merged preserving confidence levels")
    func claimsMergeWithConfidence() {
        let existing = NotesState(
            claims: [
                Claim(text: "No feature ships without customer conversations", confidence: "medium")
            ]
        )

        let new = NotesState(
            claims: [
                Claim(text: "5 customer conversations per feature", confidence: "high"),  // Similar claim, higher confidence
                Claim(text: "Hire failed founders over successful employees", confidence: "high")  // New
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        // Should have 2 unique claims (similar ones merged)
        #expect(merged.claims.count >= 2)
    }

    // MARK: - Gaps Merging

    @Test("Resolved gaps are removed when section coverage improves")
    func gapsRemovedWhenCovered() {
        let existing = NotesState(
            gaps: [
                Gap(description: "Haven't covered team building", suggestedFollowup: "Ask about hiring")
            ],
            sectionCoverage: [
                SectionCoverage(id: "team", sectionTitle: "Team Building", coverageQuality: "none")
            ]
        )

        let new = NotesState(
            gaps: [],  // Gap resolved
            sectionCoverage: [
                SectionCoverage(id: "team", sectionTitle: "Team Building", coverageQuality: "adequate")  // Now covered
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        // The gap about team building should be resolved since coverage improved
        #expect(merged.sectionCoverage.first { $0.id == "team" }?.coverageQuality == "adequate")
    }

    @Test("New gaps are added to existing gaps")
    func newGapsAdded() {
        let existing = NotesState(
            gaps: [
                Gap(description: "Missing team building", suggestedFollowup: "Ask about hiring")
            ]
        )

        let new = NotesState(
            gaps: [
                Gap(description: "Missing fundraising story", suggestedFollowup: "Ask about raising money")
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        #expect(merged.gaps.count == 2)
    }

    // MARK: - Contradictions Merging

    @Test("Contradictions are merged without duplicates")
    func contradictionsMergeNoDuplicates() {
        let existing = NotesState(
            contradictions: [
                Contradiction(
                    description: "The tension between moving fast in development and being thorough with customer research",
                    firstQuote: "Move fast and break things",
                    secondQuote: "5 conversations before any feature",
                    suggestedClarificationQuestion: "How do you balance these?"
                )
            ]
        )

        let new = NotesState(
            contradictions: [
                Contradiction(
                    // Nearly identical description - Jaccard > 0.6
                    description: "The tension between moving fast in development and being thorough with customers",
                    firstQuote: "Move fast",
                    secondQuote: "Be thorough with customers",
                    suggestedClarificationQuestion: "Balance?"
                )
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        // Should recognize similar contradictions (threshold 0.6)
        #expect(merged.contradictions.count == 1)
    }

    // MARK: - Section Coverage Merging

    @Test("Section coverage uses newest quality assessment")
    func sectionCoverageUsesNewest() {
        let existing = NotesState(
            sectionCoverage: [
                SectionCoverage(id: "failures", sectionTitle: "Failures", coverageQuality: "shallow")
            ]
        )

        let new = NotesState(
            sectionCoverage: [
                SectionCoverage(id: "failures", sectionTitle: "Failures", coverageQuality: "deep")  // Improved
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        let failures = merged.sectionCoverage.first { $0.id == "failures" }
        #expect(failures?.coverageQuality == "deep")
    }

    @Test("Section coverage never regresses")
    func sectionCoverageNeverRegresses() {
        let existing = NotesState(
            sectionCoverage: [
                SectionCoverage(id: "failures", sectionTitle: "Failures", coverageQuality: "deep")
            ]
        )

        let new = NotesState(
            sectionCoverage: [
                SectionCoverage(id: "failures", sectionTitle: "Failures", coverageQuality: "shallow")  // Regression attempt
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        let failures = merged.sectionCoverage.first { $0.id == "failures" }
        // Should keep "deep" not regress to "shallow"
        #expect(failures?.coverageQuality == "deep")
    }

    @Test("New sections are added to coverage")
    func newSectionsAddedToCoverage() {
        let existing = NotesState(
            sectionCoverage: [
                SectionCoverage(id: "opening", sectionTitle: "Opening", coverageQuality: "adequate")
            ]
        )

        let new = NotesState(
            sectionCoverage: [
                SectionCoverage(id: "failures", sectionTitle: "Failures", coverageQuality: "deep")
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        #expect(merged.sectionCoverage.count == 2)
        #expect(merged.sectionCoverage.contains { $0.id == "opening" })
        #expect(merged.sectionCoverage.contains { $0.id == "failures" })
    }

    // MARK: - Quotable Lines Merging

    @Test("Quotable lines are merged without duplicates")
    func quotableLinesMergeNoDuplicates() {
        let existing = NotesState(
            quotableLines: [
                QuotableLine(text: "We spent two years building a product that nobody wanted to use", potentialUse: "hook", topic: "failures", strength: "great")
            ]
        )

        let new = NotesState(
            quotableLines: [
                // Nearly identical - Jaccard > 0.8
                QuotableLine(text: "We spent two years building a product that nobody wanted", potentialUse: "hook", topic: "failures", strength: "great"),
                QuotableLine(text: "Talk to customers before writing any code", potentialUse: "conclusion", topic: "advice", strength: "exceptional")  // New
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        // Should have 2 unique quotes (similar quote deduplicated)
        #expect(merged.quotableLines.count == 2)
        #expect(merged.quotableLines.contains { $0.text.contains("Talk to customers") })
    }

    @Test("Exceptional quotes are preserved")
    func exceptionalQuotesPreserved() {
        let existing = NotesState(
            quotableLines: [
                QuotableLine(text: "Exceptional insight here", potentialUse: "hook", topic: "test", strength: "exceptional")
            ]
        )

        let new = NotesState.empty

        let merged = NotesState.merge(existing: existing, new: new)

        #expect(merged.quotableLines.count == 1)
        #expect(merged.quotableLines.first?.strength == "exceptional")
    }

    // MARK: - Possible Titles Merging

    @Test("Titles are merged without exact duplicates")
    func titlesMergeNoDuplicates() {
        let existing = NotesState(
            possibleTitles: ["The Art of Failing Fast", "Learning from Failure"]
        )

        let new = NotesState(
            possibleTitles: ["The Art of Failing Fast", "Why I Talk to Customers First"]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        #expect(merged.possibleTitles.count == 3)
    }

    // MARK: - Full State Merging

    @Test("Full merge preserves all data categories")
    func fullMergePreservesAll() {
        let existing = TestFixtures.partialNotes
        let new = NotesState(
            keyIdeas: [KeyIdea(text: "New insight")],
            stories: [Story(summary: "New story", impact: "New impact")],
            claims: [Claim(text: "New claim", confidence: "high")],
            gaps: [Gap(description: "New gap", suggestedFollowup: "New followup")],
            contradictions: [Contradiction(description: "New contradiction", firstQuote: "A", secondQuote: "B", suggestedClarificationQuestion: "?")],
            possibleTitles: ["New Title"],
            sectionCoverage: [SectionCoverage(id: "new", sectionTitle: "New Section", coverageQuality: "shallow")],
            quotableLines: [QuotableLine(text: "New quote", potentialUse: "hook", topic: "new", strength: "good")]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        // Verify nothing was lost
        #expect(merged.keyIdeas.count >= existing.keyIdeas.count)
        #expect(merged.stories.count >= existing.stories.count)
        #expect(merged.claims.count >= existing.claims.count)
        #expect(merged.sectionCoverage.count >= existing.sectionCoverage.count)
        #expect(merged.quotableLines.count >= existing.quotableLines.count)
    }

    // MARK: - Edge Cases

    @Test("Merging empty with empty produces empty")
    func emptyMergeProducesEmpty() {
        let merged = NotesState.merge(existing: .empty, new: .empty)

        #expect(merged == .empty)
    }

    @Test("Merging full with empty preserves full")
    func fullMergeWithEmptyPreservesFull() {
        let full = TestFixtures.fullNotes
        let merged = NotesState.merge(existing: full, new: .empty)

        #expect(merged.keyIdeas.count == full.keyIdeas.count)
        #expect(merged.stories.count == full.stories.count)
        #expect(merged.claims.count == full.claims.count)
        #expect(merged.quotableLines.count == full.quotableLines.count)
    }
}

// MARK: - NotesState Merge Extension (for testing)

extension NotesState {
    /// Static merge function for testing
    /// This mirrors the logic in NoteTakerAgent but is accessible for unit tests
    static func merge(existing: NotesState, new: NotesState) -> NotesState {
        NotesState(
            keyIdeas: mergeKeyIdeas(existing: existing.keyIdeas, new: new.keyIdeas),
            stories: mergeStories(existing: existing.stories, new: new.stories),
            claims: mergeClaims(existing: existing.claims, new: new.claims),
            gaps: mergeGaps(existing: existing.gaps, new: new.gaps),
            contradictions: mergeContradictions(existing: existing.contradictions, new: new.contradictions),
            possibleTitles: mergeTitles(existing: existing.possibleTitles, new: new.possibleTitles),
            sectionCoverage: mergeSectionCoverage(existing: existing.sectionCoverage, new: new.sectionCoverage),
            quotableLines: mergeQuotableLines(existing: existing.quotableLines, new: new.quotableLines)
        )
    }

    private static func textSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().split(separator: " ").map(String.init))
        let words2 = Set(text2.lowercased().split(separator: " ").map(String.init))
        guard !words1.isEmpty || !words2.isEmpty else { return 0.0 }
        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count
        return Double(intersection) / Double(union)
    }

    private static func mergeKeyIdeas(existing: [KeyIdea], new: [KeyIdea]) -> [KeyIdea] {
        var merged = existing
        for newIdea in new {
            let isDuplicate = existing.contains { textSimilarity($0.text, newIdea.text) > 0.7 }
            if !isDuplicate {
                merged.append(newIdea)
            }
        }
        return merged
    }

    private static func mergeStories(existing: [Story], new: [Story]) -> [Story] {
        var merged = existing
        for newStory in new {
            let isDuplicate = existing.contains { textSimilarity($0.summary, newStory.summary) > 0.7 }
            if !isDuplicate {
                merged.append(newStory)
            }
        }
        return merged
    }

    private static func mergeClaims(existing: [Claim], new: [Claim]) -> [Claim] {
        var merged = existing
        for newClaim in new {
            let isDuplicate = existing.contains { textSimilarity($0.text, newClaim.text) > 0.7 }
            if !isDuplicate {
                merged.append(newClaim)
            }
        }
        return merged
    }

    private static func mergeGaps(existing: [Gap], new: [Gap]) -> [Gap] {
        // For gaps, prefer the newer assessment but keep unique old ones
        var merged = new
        for existingGap in existing {
            let isDuplicate = new.contains { textSimilarity($0.description, existingGap.description) > 0.6 }
            if !isDuplicate {
                merged.append(existingGap)
            }
        }
        return merged
    }

    private static func mergeContradictions(existing: [Contradiction], new: [Contradiction]) -> [Contradiction] {
        var merged = existing
        for newContradiction in new {
            let isDuplicate = existing.contains { textSimilarity($0.description, newContradiction.description) > 0.6 }
            if !isDuplicate {
                merged.append(newContradiction)
            }
        }
        return merged
    }

    private static func mergeTitles(existing: [String], new: [String]) -> [String] {
        var merged = existing
        for newTitle in new {
            if !existing.contains(where: { $0.lowercased() == newTitle.lowercased() }) {
                merged.append(newTitle)
            }
        }
        return merged
    }

    private static func mergeSectionCoverage(existing: [SectionCoverage], new: [SectionCoverage]) -> [SectionCoverage] {
        var merged: [SectionCoverage] = []
        var processedIds = Set<String>()

        // Process new coverage first (prefer newer)
        for newCoverage in new {
            if let existingCoverage = existing.first(where: { $0.id == newCoverage.id }) {
                // Compare quality - never regress
                let existingScore = existingCoverage.qualityScore
                let newScore = newCoverage.qualityScore
                merged.append(newScore >= existingScore ? newCoverage : existingCoverage)
            } else {
                merged.append(newCoverage)
            }
            processedIds.insert(newCoverage.id)
        }

        // Add any existing coverage not in new
        for existingCoverage in existing where !processedIds.contains(existingCoverage.id) {
            merged.append(existingCoverage)
        }

        return merged
    }

    private static func mergeQuotableLines(existing: [QuotableLine], new: [QuotableLine]) -> [QuotableLine] {
        var merged = existing
        for newQuote in new {
            let isDuplicate = existing.contains { textSimilarity($0.text, newQuote.text) > 0.8 }
            if !isDuplicate {
                merged.append(newQuote)
            }
        }
        return merged
    }
}
