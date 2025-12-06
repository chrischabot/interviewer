import Foundation
import Testing
@testable import Interviewer

/// Tests for FollowUpAgent and the data flow through follow-up sessions
@Suite("FollowUp Data Flow Tests")
struct FollowUpDataFlowTests {

    // MARK: - NotesSnapshot Completeness

    @Test("NotesSnapshot includes all 8 fields")
    func notesSnapshotIncludesAllFields() {
        let fullNotes = TestFixtures.fullNotes

        let snapshot = NotesSnapshot(
            keyIdeas: fullNotes.keyIdeas.map { $0.text },
            stories: fullNotes.stories.map { $0.summary },
            claims: fullNotes.claims.map { $0.text },
            gaps: fullNotes.gaps.map { GapSnapshot(description: $0.description, suggestedFollowup: $0.suggestedFollowup) },
            contradictions: fullNotes.contradictions.map {
                ContradictionSnapshot(
                    description: $0.description,
                    firstQuote: $0.firstQuote,
                    secondQuote: $0.secondQuote,
                    suggestedClarificationQuestion: $0.suggestedClarificationQuestion
                )
            },
            possibleTitles: fullNotes.possibleTitles,
            sectionCoverage: fullNotes.sectionCoverage.map {
                SectionCoverageSnapshot(
                    sectionId: $0.id,
                    sectionTitle: $0.sectionTitle,
                    coverageQuality: $0.coverageQuality,
                    missingAspects: $0.missingAspects
                )
            },
            quotableLines: fullNotes.quotableLines.map {
                QuotableLineSnapshot(
                    text: $0.text,
                    potentialUse: $0.potentialUse,
                    topic: $0.topic,
                    strength: $0.strength
                )
            }
        )

        // Verify all fields are populated
        #expect(snapshot.keyIdeas.count == fullNotes.keyIdeas.count)
        #expect(snapshot.stories.count == fullNotes.stories.count)
        #expect(snapshot.claims.count == fullNotes.claims.count)
        #expect(snapshot.gaps.count == fullNotes.gaps.count)
        #expect(snapshot.contradictions.count == fullNotes.contradictions.count)
        #expect(snapshot.possibleTitles.count == fullNotes.possibleTitles.count)
        #expect(snapshot.sectionCoverage.count == fullNotes.sectionCoverage.count)
        #expect(snapshot.quotableLines.count == fullNotes.quotableLines.count)
    }

    @Test("GapSnapshot preserves suggested followup")
    func gapSnapshotPreservesFollowup() {
        let gap = Gap(description: "Missing hiring details", suggestedFollowup: "How do you interview candidates?")
        let snapshot = GapSnapshot(description: gap.description, suggestedFollowup: gap.suggestedFollowup)

        #expect(snapshot.description == gap.description)
        #expect(snapshot.suggestedFollowup == gap.suggestedFollowup)
    }

    @Test("ContradictionSnapshot preserves all fields")
    func contradictionSnapshotPreservesFields() {
        let contradiction = Contradiction(
            description: "Speed vs quality",
            firstQuote: "Move fast",
            secondQuote: "Be thorough",
            suggestedClarificationQuestion: "How do you balance these?"
        )

        let snapshot = ContradictionSnapshot(
            description: contradiction.description,
            firstQuote: contradiction.firstQuote,
            secondQuote: contradiction.secondQuote,
            suggestedClarificationQuestion: contradiction.suggestedClarificationQuestion
        )

        #expect(snapshot.description == contradiction.description)
        #expect(snapshot.firstQuote == contradiction.firstQuote)
        #expect(snapshot.secondQuote == contradiction.secondQuote)
        #expect(snapshot.suggestedClarificationQuestion == contradiction.suggestedClarificationQuestion)
    }

    @Test("SectionCoverageSnapshot preserves missing aspects")
    func sectionCoverageSnapshotPreservesMissingAspects() {
        let coverage = SectionCoverage(
            id: "customers",
            sectionTitle: "Customer Development",
            coverageQuality: "shallow",
            missingAspects: ["Specific examples", "Conflicting feedback"]
        )

        let snapshot = SectionCoverageSnapshot(
            sectionId: coverage.id,
            sectionTitle: coverage.sectionTitle,
            coverageQuality: coverage.coverageQuality,
            missingAspects: coverage.missingAspects
        )

        #expect(snapshot.missingAspects.count == 2)
        #expect(snapshot.missingAspects.contains("Specific examples"))
    }

    @Test("QuotableLineSnapshot preserves strength rating")
    func quotableLineSnapshotPreservesStrength() {
        let quote = QuotableLine(
            text: "Test quote",
            potentialUse: "hook",
            topic: "test",
            strength: "exceptional"
        )

        let snapshot = QuotableLineSnapshot(
            text: quote.text,
            potentialUse: quote.potentialUse,
            topic: quote.topic,
            strength: quote.strength
        )

        #expect(snapshot.strength == "exceptional")
        #expect(snapshot.potentialUse == "hook")
    }

    // MARK: - Previous Session Summary

    @Test("Previous session summary includes key ideas")
    func previousSummarIncludesKeyIdeas() {
        let summary = PreviousSessionSummaryBuilder.build(from: TestFixtures.fullNotes)

        #expect(summary.contains("Key ideas"))
        #expect(summary.contains("Fail fast"))
    }

    @Test("Previous session summary includes stories")
    func previousSummaryIncludesStories() {
        let summary = PreviousSessionSummaryBuilder.build(from: TestFixtures.fullNotes)

        #expect(summary.contains("Stories"))
    }

    @Test("Previous session summary includes claims")
    func previousSummaryIncludesClaims() {
        let summary = PreviousSessionSummaryBuilder.build(from: TestFixtures.fullNotes)

        #expect(summary.contains("Claims") || summary.contains("opinions"))
    }

    @Test("Previous session summary includes section coverage")
    func previousSummaryIncludesSectionCoverage() {
        let summary = PreviousSessionSummaryBuilder.build(from: TestFixtures.fullNotes)

        #expect(summary.contains("Sections covered") || summary.contains("coverage"))
    }

    @Test("Empty notes produce empty summary")
    func emptyNotesProduceEmptySummary() {
        let summary = PreviousSessionSummaryBuilder.build(from: .empty)

        #expect(summary.isEmpty)
    }

    // MARK: - Transcript Merging

    @Test("Transcripts are merged for follow-up analysis")
    func transcriptsMergedForFollowUp() {
        let original = TestFixtures.shortTranscript
        let followUp = [
            TranscriptEntry(speaker: "assistant", text: "Welcome back!", timestamp: Date(), isFinal: true),
            TranscriptEntry(speaker: "user", text: "Thanks for having me again.", timestamp: Date(), isFinal: true)
        ]

        let merged = original + followUp

        #expect(merged.count == original.count + followUp.count)
        #expect(merged.first?.text == original.first?.text)
        #expect(merged.last?.text == followUp.last?.text)
    }

    @Test("Merged transcript preserves speaker labels")
    func mergedTranscriptPreservesSpeakers() {
        let original = TestFixtures.shortTranscript
        let followUp = TestFixtures.shortTranscript

        let merged = original + followUp

        let assistantCount = merged.filter { $0.speaker == "assistant" }.count
        let userCount = merged.filter { $0.speaker == "user" }.count

        #expect(assistantCount == original.filter { $0.speaker == "assistant" }.count * 2)
        #expect(userCount == original.filter { $0.speaker == "user" }.count * 2)
    }

    // MARK: - Follow-up Plan Generation

    @Test("Follow-up plan data includes follow-up context")
    func followUpPlanIncludesContext() {
        // Test follow-up data structure (separate from PlanSnapshot which is for agent communication)
        let followUpData = FollowUpPlanData(
            basePlan: TestFixtures.standardPlan,
            isFollowUp: true,
            followUpContext: "Explore hiring practices in more depth",
            targetSeconds: 360
        )

        #expect(followUpData.isFollowUp)
        #expect(followUpData.followUpContext.contains("hiring"))
        #expect(followUpData.basePlan.topic == "Building Startups")
    }

    @Test("Follow-up instructions include previous summary")
    func followUpInstructionsIncludeSummary() {
        let previousSummary = "Discussed failure, customer feedback"
        let followUpTopics = "Explore hiring practices"

        let instructions = FollowUpInstructionsBuilder.build(
            previousSummary: previousSummary,
            followUpTopics: followUpTopics
        )

        #expect(instructions.contains("FOLLOW-UP"))
        #expect(instructions.contains("DO NOT REPEAT") || instructions.contains("already covered"))
        #expect(instructions.contains(previousSummary))
        #expect(instructions.contains(followUpTopics))
    }

    // MARK: - Analysis with Quotable Lines

    @Test("Analysis merges live quotes with extracted quotes")
    func analysisMergesLiveQuotes() {
        let liveQuotes = [
            QuotableLine(text: "Live quote 1", potentialUse: "hook", topic: "test", strength: "exceptional"),
            QuotableLine(text: "Live quote 2", potentialUse: "pull_quote", topic: "test", strength: "great")
        ]

        let extractedQuotes = [
            Quote(text: "Extracted quote 1", role: "opinion"),
            Quote(text: "Extracted quote 2", role: "origin")
        ]

        let merged = QuoteMerger.merge(liveQuotes: liveQuotes, extractedQuotes: extractedQuotes)

        // Should have all quotes (no exact duplicates)
        #expect(merged.count == 4)
    }

    @Test("Duplicate quotes are deduplicated during merge")
    func duplicateQuotesDeduplicatedDuringMerge() {
        let liveQuotes = [
            QuotableLine(text: "Same quote text here", potentialUse: "hook", topic: "test", strength: "exceptional")
        ]

        let extractedQuotes = [
            Quote(text: "Same quote text here", role: "opinion")  // Duplicate
        ]

        let merged = QuoteMerger.merge(liveQuotes: liveQuotes, extractedQuotes: extractedQuotes)

        #expect(merged.count == 1)
    }

    @Test("Similar quotes are deduplicated")
    func similarQuotesDeduplicatedDuringMerge() {
        let liveQuotes = [
            QuotableLine(text: "We spent two years building a product nobody wanted", potentialUse: "hook", topic: "failures", strength: "exceptional")
        ]

        let extractedQuotes = [
            Quote(text: "We spent 2 years building a product nobody wanted", role: "origin")  // Very similar
        ]

        let merged = QuoteMerger.merge(liveQuotes: liveQuotes, extractedQuotes: extractedQuotes)

        // Should recognize as same quote
        #expect(merged.count == 1)
    }

    @Test("Exceptional live quotes appear first")
    func exceptionalLiveQuotesFirst() {
        let liveQuotes = [
            QuotableLine(text: "Exceptional quote", potentialUse: "hook", topic: "test", strength: "exceptional")
        ]

        let extractedQuotes = [
            Quote(text: "Regular extracted quote", role: "opinion")
        ]

        let merged = QuoteMerger.merge(liveQuotes: liveQuotes, extractedQuotes: extractedQuotes)

        // Exceptional should be first
        #expect(merged.first?.text == "Exceptional quote")
    }
}

// MARK: - Test Helpers

/// Builder for previous session summary
struct PreviousSessionSummaryBuilder {
    static func build(from notes: NotesState) -> String {
        var parts: [String] = []

        if !notes.keyIdeas.isEmpty {
            let ideas = notes.keyIdeas.prefix(5).map { "- \($0.text)" }.joined(separator: "\n")
            parts.append("**Key ideas discussed:**\n\(ideas)")
        }

        if !notes.stories.isEmpty {
            let stories = notes.stories.prefix(3).map { "- \($0.summary)" }.joined(separator: "\n")
            parts.append("**Stories shared:**\n\(stories)")
        }

        if !notes.claims.isEmpty {
            let claims = notes.claims.prefix(4).map { "- \($0.text)" }.joined(separator: "\n")
            parts.append("**Claims/opinions expressed:**\n\(claims)")
        }

        if !notes.sectionCoverage.isEmpty {
            let covered = notes.sectionCoverage
                .filter { $0.coverageQuality != "none" }
                .map { "\($0.sectionTitle) (\($0.coverageQuality))" }
                .joined(separator: ", ")
            if !covered.isEmpty {
                parts.append("**Sections covered:** \(covered)")
            }
        }

        return parts.joined(separator: "\n\n")
    }
}

/// Builder for follow-up instructions
struct FollowUpInstructionsBuilder {
    static func build(previousSummary: String, followUpTopics: String) -> String {
        let summarySection = previousSummary.isEmpty ? "" : """

        **What was already covered (DO NOT REPEAT):**
        \(previousSummary)

        """

        return """
        **IMPORTANT: This is a FOLLOW-UP conversation.**

        You already spoke with this person in a previous session.
        \(summarySection)
        **Topics to explore:**
        \(followUpTopics)

        **Style:**
        - Reference previous conversation
        - Don't repeat ground already covered
        - Go deeper on new angles
        """
    }
}

/// Merger for live and extracted quotes
struct QuoteMerger {
    static func merge(liveQuotes: [QuotableLine], extractedQuotes: [Quote]) -> [Quote] {
        var result: [Quote] = []

        // Add exceptional/great live quotes first
        let goodLiveQuotes = liveQuotes.filter {
            $0.strength == "exceptional" || $0.strength == "great"
        }

        for liveQuote in goodLiveQuotes {
            let role = mapPotentialUseToRole(liveQuote.potentialUse)
            result.append(Quote(text: liveQuote.text, role: role))
        }

        // Add extracted quotes that aren't duplicates
        for extracted in extractedQuotes {
            let isDuplicate = result.contains { quote in
                textSimilarity(quote.text, extracted.text) > 0.7
            }
            if !isDuplicate {
                result.append(extracted)
            }
        }

        return result
    }

    private static func mapPotentialUseToRole(_ use: String) -> String {
        switch use {
        case "hook", "tweet": return "opinion"
        case "section_header": return "turning_point"
        default: return "opinion"
        }
    }

    private static func textSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().split(separator: " ").map(String.init))
        let words2 = Set(text2.lowercased().split(separator: " ").map(String.init))
        guard !words1.isEmpty || !words2.isEmpty else { return 0.0 }
        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count
        return Double(intersection) / Double(union)
    }
}

/// Follow-up plan data container for testing
/// This wraps a base plan with follow-up context information
struct FollowUpPlanData {
    let basePlan: PlanSnapshot
    let isFollowUp: Bool
    let followUpContext: String
    let targetSeconds: Int
}
