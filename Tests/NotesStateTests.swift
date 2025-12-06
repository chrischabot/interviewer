import Foundation
import Testing
@testable import Interviewer

@Suite("NotesState Tests")
struct NotesStateTests {

    // MARK: - Empty State

    @Test("Empty NotesState initializes correctly")
    func emptyState() {
        let notes = NotesState.empty

        #expect(notes.keyIdeas.isEmpty)
        #expect(notes.stories.isEmpty)
        #expect(notes.claims.isEmpty)
        #expect(notes.gaps.isEmpty)
        #expect(notes.contradictions.isEmpty)
        #expect(notes.sectionCoverage.isEmpty)
        #expect(notes.quotableLines.isEmpty)
        #expect(notes.possibleTitles.isEmpty)
    }

    // MARK: - Section Coverage

    @Test("SectionCoverage quality score calculation")
    func sectionCoverageQualityScore() {
        let deep = SectionCoverage(id: "1", sectionTitle: "Test", coverageQuality: "deep")
        let adequate = SectionCoverage(id: "2", sectionTitle: "Test", coverageQuality: "adequate")
        let shallow = SectionCoverage(id: "3", sectionTitle: "Test", coverageQuality: "shallow")
        let none = SectionCoverage(id: "4", sectionTitle: "Test", coverageQuality: "none")

        #expect(deep.qualityScore == 1.0)
        #expect(adequate.qualityScore == 0.7)
        #expect(shallow.qualityScore == 0.3)
        #expect(none.qualityScore == 0.0)
    }

    @Test("NotesState identifies under-covered sections")
    func underCoveredSections() {
        let notes = NotesState(
            sectionCoverage: [
                SectionCoverage(id: "1", sectionTitle: "Deep", coverageQuality: "deep"),
                SectionCoverage(id: "2", sectionTitle: "Shallow", coverageQuality: "shallow"),
                SectionCoverage(id: "3", sectionTitle: "None", coverageQuality: "none"),
                SectionCoverage(id: "4", sectionTitle: "Adequate", coverageQuality: "adequate")
            ]
        )

        let underCovered = notes.underCoveredSections

        #expect(underCovered.count == 2)
        #expect(underCovered.contains { $0.id == "2" })
        #expect(underCovered.contains { $0.id == "3" })
    }

    @Test("NotesState finds coverage for specific section")
    func coverageForSection() {
        let notes = NotesState(
            sectionCoverage: [
                SectionCoverage(id: "abc", sectionTitle: "Test Section", coverageQuality: "deep")
            ]
        )

        let found = notes.coverage(for: "abc")
        let notFound = notes.coverage(for: "xyz")

        #expect(found != nil)
        #expect(found?.sectionTitle == "Test Section")
        #expect(notFound == nil)
    }

    // MARK: - Quotable Lines

    @Test("NotesState filters best quotes")
    func bestQuotes() {
        let notes = NotesState(
            quotableLines: [
                QuotableLine(text: "Good quote", potentialUse: "pull_quote", topic: "Test", strength: "good"),
                QuotableLine(text: "Great quote", potentialUse: "hook", topic: "Test", strength: "great"),
                QuotableLine(text: "Exceptional quote", potentialUse: "conclusion", topic: "Test", strength: "exceptional"),
                QuotableLine(text: "Another good", potentialUse: "tweet", topic: "Test", strength: "good")
            ]
        )

        let best = notes.bestQuotes

        #expect(best.count == 2)
        #expect(best.contains { $0.text == "Great quote" })
        #expect(best.contains { $0.text == "Exceptional quote" })
    }

    // MARK: - Build Summary

    @Test("BuildSummary produces formatted output")
    func buildSummary() {
        let notes = NotesState(
            keyIdeas: [KeyIdea(text: "Key insight about testing")],
            stories: [Story(summary: "Testing story", impact: "High impact")],
            claims: [Claim(text: "Testing is important", confidence: "high")],
            possibleTitles: ["The Art of Testing"]
        )

        let summary = notes.buildSummary()

        #expect(summary.contains("Key Ideas"))
        #expect(summary.contains("Key insight about testing"))
        #expect(summary.contains("Stories"))
        #expect(summary.contains("Testing story"))
        #expect(summary.contains("Claims"))
        #expect(summary.contains("Possible Titles"))
    }

    @Test("BuildSummary handles empty notes")
    func buildSummaryEmpty() {
        let notes = NotesState.empty
        let summary = notes.buildSummary()

        #expect(summary == "(No notes yet)")
    }
}
