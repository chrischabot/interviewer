import Foundation
import Testing
@testable import Interviewer

/// Tests to ensure all model properties are properly handled
/// These tests verify that no data is lost when creating, storing, or merging models
@Suite("Property Completeness Tests")
struct PropertyCompletenessTests {

    // MARK: - KeyIdea Properties

    @Test("KeyIdea preserves all properties")
    func keyIdeaPreservesAllProperties() {
        let keyIdea = KeyIdea(
            id: "test-id-123",
            text: "Important insight about startups",
            relatedQuestionIds: ["q1", "q2", "q3"]
        )

        #expect(keyIdea.id == "test-id-123")
        #expect(keyIdea.text == "Important insight about startups")
        #expect(keyIdea.relatedQuestionIds.count == 3)
        #expect(keyIdea.relatedQuestionIds.contains("q1"))
        #expect(keyIdea.relatedQuestionIds.contains("q2"))
        #expect(keyIdea.relatedQuestionIds.contains("q3"))
    }

    @Test("KeyIdea default values work correctly")
    func keyIdeaDefaultValues() {
        let keyIdea = KeyIdea(text: "Simple idea")

        #expect(!keyIdea.id.isEmpty)  // Auto-generated UUID
        #expect(keyIdea.text == "Simple idea")
        #expect(keyIdea.relatedQuestionIds.isEmpty)
    }

    // MARK: - Story Properties

    @Test("Story preserves all properties")
    func storyPreservesAllProperties() {
        let story = Story(
            id: "story-123",
            summary: "Failed startup experience",
            impact: "Led to new methodology",
            timestamp: "2024-01-15T10:30:00Z"
        )

        #expect(story.id == "story-123")
        #expect(story.summary == "Failed startup experience")
        #expect(story.impact == "Led to new methodology")
        #expect(story.timestamp == "2024-01-15T10:30:00Z")
    }

    @Test("Story default values work correctly")
    func storyDefaultValues() {
        let story = Story(summary: "Quick story", impact: "Minor impact")

        #expect(!story.id.isEmpty)
        #expect(story.timestamp == "")  // Empty by default
    }

    // MARK: - Claim Properties

    @Test("Claim preserves all properties")
    func claimPreservesAllProperties() {
        let claim = Claim(
            id: "claim-123",
            text: "Always talk to customers first",
            confidence: "high"
        )

        #expect(claim.id == "claim-123")
        #expect(claim.text == "Always talk to customers first")
        #expect(claim.confidence == "high")
    }

    @Test("Claim default confidence is medium")
    func claimDefaultConfidence() {
        let claim = Claim(text: "Some claim")

        #expect(claim.confidence == "medium")
    }

    // MARK: - Gap Properties

    @Test("Gap preserves all properties")
    func gapPreservesAllProperties() {
        let gap = Gap(
            id: "gap-123",
            description: "Missing team building discussion",
            relatedQuestionIds: ["q6", "q7"],
            suggestedFollowup: "How do you approach hiring?"
        )

        #expect(gap.id == "gap-123")
        #expect(gap.description == "Missing team building discussion")
        #expect(gap.relatedQuestionIds.count == 2)
        #expect(gap.relatedQuestionIds.contains("q6"))
        #expect(gap.suggestedFollowup == "How do you approach hiring?")
    }

    @Test("Gap default values work correctly")
    func gapDefaultValues() {
        let gap = Gap(description: "Some gap")

        #expect(!gap.id.isEmpty)
        #expect(gap.relatedQuestionIds.isEmpty)
        #expect(gap.suggestedFollowup == "")
    }

    // MARK: - Contradiction Properties

    @Test("Contradiction preserves all properties")
    func contradictionPreservesAllProperties() {
        let contradiction = Contradiction(
            id: "contra-123",
            description: "Speed vs thoroughness",
            firstQuote: "Move fast and break things",
            secondQuote: "5 customer conversations before any feature",
            suggestedClarificationQuestion: "How do you balance these approaches?"
        )

        #expect(contradiction.id == "contra-123")
        #expect(contradiction.description == "Speed vs thoroughness")
        #expect(contradiction.firstQuote == "Move fast and break things")
        #expect(contradiction.secondQuote == "5 customer conversations before any feature")
        #expect(contradiction.suggestedClarificationQuestion == "How do you balance these approaches?")
    }

    // MARK: - SectionCoverage Properties

    @Test("SectionCoverage preserves all properties")
    func sectionCoveragePreservesAllProperties() {
        let coverage = SectionCoverage(
            id: "customers",
            sectionTitle: "Customer Development",
            coverageQuality: "adequate",
            keyPointsCovered: ["5-conversation rule", "AI vs search pivot"],
            missingAspects: ["Scaling customer feedback", "Hiring"],
            suggestedFollowup: "How does this scale?"
        )

        #expect(coverage.id == "customers")
        #expect(coverage.sectionTitle == "Customer Development")
        #expect(coverage.coverageQuality == "adequate")
        #expect(coverage.keyPointsCovered.count == 2)
        #expect(coverage.keyPointsCovered.contains("5-conversation rule"))
        #expect(coverage.missingAspects.count == 2)
        #expect(coverage.missingAspects.contains("Scaling customer feedback"))
        #expect(coverage.suggestedFollowup == "How does this scale?")
    }

    @Test("SectionCoverage quality scores are correct")
    func sectionCoverageQualityScores() {
        #expect(SectionCoverage(id: "a", sectionTitle: "A", coverageQuality: "none").qualityScore == 0.0)
        #expect(SectionCoverage(id: "b", sectionTitle: "B", coverageQuality: "shallow").qualityScore == 0.3)
        #expect(SectionCoverage(id: "c", sectionTitle: "C", coverageQuality: "adequate").qualityScore == 0.7)
        #expect(SectionCoverage(id: "d", sectionTitle: "D", coverageQuality: "deep").qualityScore == 1.0)
    }

    @Test("SectionCoverage default values work correctly")
    func sectionCoverageDefaultValues() {
        let coverage = SectionCoverage(id: "test", sectionTitle: "Test Section")

        #expect(coverage.coverageQuality == "none")
        #expect(coverage.keyPointsCovered.isEmpty)
        #expect(coverage.missingAspects.isEmpty)
        #expect(coverage.suggestedFollowup == nil)
    }

    // MARK: - QuotableLine Properties

    @Test("QuotableLine preserves all properties")
    func quotableLinePreservesAllProperties() {
        let quote = QuotableLine(
            id: "quote-123",
            text: "We spent 2 years building a product nobody wanted",
            speaker: "expert",
            potentialUse: "hook",
            topic: "failures",
            strength: "exceptional"
        )

        #expect(quote.id == "quote-123")
        #expect(quote.text == "We spent 2 years building a product nobody wanted")
        #expect(quote.speaker == "expert")
        #expect(quote.potentialUse == "hook")
        #expect(quote.topic == "failures")
        #expect(quote.strength == "exceptional")
    }

    @Test("QuotableLine default values work correctly")
    func quotableLineDefaultValues() {
        let quote = QuotableLine(text: "Quick quote", potentialUse: "pull_quote", topic: "test")

        #expect(!quote.id.isEmpty)
        #expect(quote.speaker == "expert")
        #expect(quote.strength == "good")
    }

    // MARK: - ResearchItem Properties

    @Test("ResearchItem preserves all properties")
    func researchItemPreservesAllProperties() {
        let item = ResearchItem(
            id: "research-123",
            topic: "Lean Startup",
            kind: "definition",
            summary: "Build-measure-learn framework",
            howToUseInQuestion: "Compare their approach",
            priority: 1,
            verificationStatus: "verified",
            verificationNote: "Confirmed by multiple sources"
        )

        #expect(item.id == "research-123")
        #expect(item.topic == "Lean Startup")
        #expect(item.kind == "definition")
        #expect(item.summary == "Build-measure-learn framework")
        #expect(item.howToUseInQuestion == "Compare their approach")
        #expect(item.priority == 1)
        #expect(item.verificationStatus == "verified")
        #expect(item.verificationNote == "Confirmed by multiple sources")
    }

    @Test("ResearchItem claim verification helpers work")
    func researchItemVerificationHelpers() {
        let verified = ResearchItem(
            topic: "Test",
            kind: "claim_verification",
            summary: "Test",
            howToUseInQuestion: "Test",
            verificationStatus: "verified"
        )

        let contradicted = ResearchItem(
            topic: "Test",
            kind: "claim_verification",
            summary: "Test",
            howToUseInQuestion: "Test",
            verificationStatus: "contradicted"
        )

        let partiallyTrue = ResearchItem(
            topic: "Test",
            kind: "claim_verification",
            summary: "Test",
            howToUseInQuestion: "Test",
            verificationStatus: "partially_true"
        )

        let regular = ResearchItem(
            topic: "Test",
            kind: "definition",
            summary: "Test",
            howToUseInQuestion: "Test"
        )

        #expect(verified.isVerifiedClaim)
        #expect(!verified.isContradictedClaim)

        #expect(!contradicted.isVerifiedClaim)
        #expect(contradicted.isContradictedClaim)

        #expect(!partiallyTrue.isVerifiedClaim)
        #expect(!partiallyTrue.isContradictedClaim)

        #expect(!regular.isVerifiedClaim)
        #expect(!regular.isContradictedClaim)
    }

    // MARK: - NotesState Properties

    @Test("NotesState has all 8 fields")
    func notesStateHasAllFields() {
        let notes = NotesState(
            keyIdeas: [KeyIdea(text: "Idea 1")],
            stories: [Story(summary: "Story 1", impact: "Impact 1")],
            claims: [Claim(text: "Claim 1")],
            gaps: [Gap(description: "Gap 1")],
            contradictions: [Contradiction(description: "Contra 1", firstQuote: "A", secondQuote: "B")],
            possibleTitles: ["Title 1"],
            sectionCoverage: [SectionCoverage(id: "s1", sectionTitle: "Section 1")],
            quotableLines: [QuotableLine(text: "Quote 1", potentialUse: "hook", topic: "test")]
        )

        #expect(notes.keyIdeas.count == 1)
        #expect(notes.stories.count == 1)
        #expect(notes.claims.count == 1)
        #expect(notes.gaps.count == 1)
        #expect(notes.contradictions.count == 1)
        #expect(notes.possibleTitles.count == 1)
        #expect(notes.sectionCoverage.count == 1)
        #expect(notes.quotableLines.count == 1)
    }

    @Test("NotesState.empty is truly empty")
    func notesStateEmptyIsTrulyEmpty() {
        let empty = NotesState.empty

        #expect(empty.keyIdeas.isEmpty)
        #expect(empty.stories.isEmpty)
        #expect(empty.claims.isEmpty)
        #expect(empty.gaps.isEmpty)
        #expect(empty.contradictions.isEmpty)
        #expect(empty.possibleTitles.isEmpty)
        #expect(empty.sectionCoverage.isEmpty)
        #expect(empty.quotableLines.isEmpty)
    }

    @Test("NotesState helper methods work correctly")
    func notesStateHelperMethods() {
        let notes = NotesState(
            sectionCoverage: [
                SectionCoverage(id: "deep", sectionTitle: "Deep", coverageQuality: "deep"),
                SectionCoverage(id: "shallow", sectionTitle: "Shallow", coverageQuality: "shallow"),
                SectionCoverage(id: "none", sectionTitle: "None", coverageQuality: "none")
            ],
            quotableLines: [
                QuotableLine(text: "Exceptional", potentialUse: "hook", topic: "test", strength: "exceptional"),
                QuotableLine(text: "Great", potentialUse: "hook", topic: "test", strength: "great"),
                QuotableLine(text: "Good", potentialUse: "hook", topic: "test", strength: "good")
            ]
        )

        // coverage(for:) helper
        #expect(notes.coverage(for: "deep")?.coverageQuality == "deep")
        #expect(notes.coverage(for: "nonexistent") == nil)

        // underCoveredSections helper
        #expect(notes.underCoveredSections.count == 2)
        #expect(notes.underCoveredSections.contains { $0.id == "shallow" })
        #expect(notes.underCoveredSections.contains { $0.id == "none" })

        // bestQuotes helper
        #expect(notes.bestQuotes.count == 2)
        #expect(notes.bestQuotes.contains { $0.text == "Exceptional" })
        #expect(notes.bestQuotes.contains { $0.text == "Great" })
    }

    // MARK: - JSON Encoding/Decoding Roundtrip

    @Test("KeyIdea survives JSON roundtrip")
    func keyIdeaJsonRoundtrip() throws {
        let original = KeyIdea(
            id: "test-id",
            text: "Test idea",
            relatedQuestionIds: ["q1", "q2"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyIdea.self, from: data)

        #expect(decoded == original)
    }

    @Test("Story survives JSON roundtrip")
    func storyJsonRoundtrip() throws {
        let original = Story(
            id: "story-id",
            summary: "Test story",
            impact: "Test impact",
            timestamp: "2024-01-15"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Story.self, from: data)

        #expect(decoded == original)
    }

    @Test("SectionCoverage survives JSON roundtrip")
    func sectionCoverageJsonRoundtrip() throws {
        let original = SectionCoverage(
            id: "test-section",
            sectionTitle: "Test Section",
            coverageQuality: "adequate",
            keyPointsCovered: ["Point 1", "Point 2"],
            missingAspects: ["Missing 1"],
            suggestedFollowup: "Follow up question"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SectionCoverage.self, from: data)

        #expect(decoded == original)
    }

    @Test("QuotableLine survives JSON roundtrip")
    func quotableLineJsonRoundtrip() throws {
        let original = QuotableLine(
            id: "quote-id",
            text: "Test quote",
            speaker: "expert",
            potentialUse: "hook",
            topic: "test",
            strength: "exceptional"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuotableLine.self, from: data)

        #expect(decoded == original)
    }

    @Test("NotesState survives JSON roundtrip")
    func notesStateJsonRoundtrip() throws {
        let original = TestFixtures.fullNotes

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotesState.self, from: data)

        #expect(decoded == original)
    }

    @Test("ResearchItem survives JSON roundtrip")
    func researchItemJsonRoundtrip() throws {
        let original = ResearchItem(
            id: "research-id",
            topic: "Test Topic",
            kind: "claim_verification",
            summary: "Test summary",
            howToUseInQuestion: "Use it",
            priority: 1,
            verificationStatus: "partially_true",
            verificationNote: "Note"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ResearchItem.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - Merge Always Appends (Never Overwrites)

    @Test("Merge appends keyIdeas, doesn't overwrite")
    func mergeAppendsKeyIdeas() {
        let existing = NotesState(
            keyIdeas: [
                KeyIdea(id: "id-1", text: "Existing idea 1"),
                KeyIdea(id: "id-2", text: "Existing idea 2")
            ]
        )

        let new = NotesState(
            keyIdeas: [
                KeyIdea(id: "id-3", text: "New idea 3")
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        // All 3 should be present
        #expect(merged.keyIdeas.count == 3)
        #expect(merged.keyIdeas.contains { $0.id == "id-1" })
        #expect(merged.keyIdeas.contains { $0.id == "id-2" })
        #expect(merged.keyIdeas.contains { $0.id == "id-3" })
    }

    @Test("Merge appends stories, doesn't overwrite")
    func mergeAppendsStories() {
        let existing = NotesState(
            stories: [
                Story(id: "s1", summary: "Story 1", impact: "Impact 1")
            ]
        )

        let new = NotesState(
            stories: [
                Story(id: "s2", summary: "Story 2", impact: "Impact 2")
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        #expect(merged.stories.count == 2)
        #expect(merged.stories.contains { $0.id == "s1" })
        #expect(merged.stories.contains { $0.id == "s2" })
    }

    @Test("Merge appends claims, doesn't overwrite")
    func mergeAppendsClaims() {
        let existing = NotesState(
            claims: [Claim(id: "c1", text: "Claim 1")]
        )

        let new = NotesState(
            claims: [Claim(id: "c2", text: "Claim 2")]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        #expect(merged.claims.count == 2)
    }

    @Test("Merge appends quotableLines, doesn't overwrite")
    func mergeAppendsQuotableLines() {
        let existing = NotesState(
            quotableLines: [
                QuotableLine(id: "q1", text: "Quote 1", potentialUse: "hook", topic: "t1")
            ]
        )

        let new = NotesState(
            quotableLines: [
                QuotableLine(id: "q2", text: "Quote 2", potentialUse: "conclusion", topic: "t2")
            ]
        )

        let merged = NotesState.merge(existing: existing, new: new)

        #expect(merged.quotableLines.count == 2)
        #expect(merged.quotableLines.contains { $0.id == "q1" })
        #expect(merged.quotableLines.contains { $0.id == "q2" })
    }

    @Test("Merge appends sectionCoverage for new sections")
    func mergeAppendsSectionCoverage() {
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
}
