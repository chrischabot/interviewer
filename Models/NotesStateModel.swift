import Foundation
import SwiftData

@Model
final class NotesStateModel {
    var id: UUID

    // Store complex nested data as JSON
    var keyIdeasJSON: Data
    var storiesJSON: Data
    var claimsJSON: Data
    var gapsJSON: Data
    var contradictionsJSON: Data
    // New fields with default empty array JSON for migration compatibility
    var sectionCoverageJSON: Data = Data("[]".utf8)
    var quotableLinesJSON: Data = Data("[]".utf8)
    var possibleTitles: [String]

    init(
        id: UUID = UUID(),
        keyIdeas: [KeyIdea] = [],
        stories: [Story] = [],
        claims: [Claim] = [],
        gaps: [Gap] = [],
        contradictions: [Contradiction] = [],
        sectionCoverage: [SectionCoverage] = [],
        quotableLines: [QuotableLine] = [],
        possibleTitles: [String] = []
    ) {
        self.id = id
        self.keyIdeasJSON = (try? JSONEncoder().encode(keyIdeas)) ?? Data()
        self.storiesJSON = (try? JSONEncoder().encode(stories)) ?? Data()
        self.claimsJSON = (try? JSONEncoder().encode(claims)) ?? Data()
        self.gapsJSON = (try? JSONEncoder().encode(gaps)) ?? Data()
        self.contradictionsJSON = (try? JSONEncoder().encode(contradictions)) ?? Data()
        self.sectionCoverageJSON = (try? JSONEncoder().encode(sectionCoverage)) ?? Data()
        self.quotableLinesJSON = (try? JSONEncoder().encode(quotableLines)) ?? Data()
        self.possibleTitles = possibleTitles
    }

    // MARK: - Computed Properties

    var keyIdeas: [KeyIdea] {
        get { (try? JSONDecoder().decode([KeyIdea].self, from: keyIdeasJSON)) ?? [] }
        set { keyIdeasJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var stories: [Story] {
        get { (try? JSONDecoder().decode([Story].self, from: storiesJSON)) ?? [] }
        set { storiesJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var claims: [Claim] {
        get { (try? JSONDecoder().decode([Claim].self, from: claimsJSON)) ?? [] }
        set { claimsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var gaps: [Gap] {
        get { (try? JSONDecoder().decode([Gap].self, from: gapsJSON)) ?? [] }
        set { gapsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var contradictions: [Contradiction] {
        get { (try? JSONDecoder().decode([Contradiction].self, from: contradictionsJSON)) ?? [] }
        set { contradictionsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var sectionCoverage: [SectionCoverage] {
        get { (try? JSONDecoder().decode([SectionCoverage].self, from: sectionCoverageJSON)) ?? [] }
        set { sectionCoverageJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var quotableLines: [QuotableLine] {
        get { (try? JSONDecoder().decode([QuotableLine].self, from: quotableLinesJSON)) ?? [] }
        set { quotableLinesJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Convert to plain NotesState struct for agent communication
    func toNotesState() -> NotesState {
        NotesState(
            keyIdeas: keyIdeas,
            stories: stories,
            claims: claims,
            gaps: gaps,
            contradictions: contradictions,
            possibleTitles: possibleTitles,
            sectionCoverage: sectionCoverage,
            quotableLines: quotableLines
        )
    }
}

// MARK: - Plain Swift Structs for Agent I/O

struct KeyIdea: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let relatedQuestionIds: [String]

    init(id: String = UUID().uuidString, text: String, relatedQuestionIds: [String] = []) {
        self.id = id
        self.text = text
        self.relatedQuestionIds = relatedQuestionIds
    }
}

struct Story: Codable, Identifiable, Equatable {
    let id: String
    let summary: String
    let impact: String
    let timestamp: String

    init(id: String = UUID().uuidString, summary: String, impact: String, timestamp: String = "") {
        self.id = id
        self.summary = summary
        self.impact = impact
        self.timestamp = timestamp
    }
}

struct Claim: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let confidence: String  // "low" | "medium" | "high"

    init(id: String = UUID().uuidString, text: String, confidence: String = "medium") {
        self.id = id
        self.text = text
        self.confidence = confidence
    }
}

struct Gap: Codable, Identifiable, Equatable {
    let id: String
    let description: String
    let relatedQuestionIds: [String]
    let suggestedFollowup: String

    init(id: String = UUID().uuidString, description: String, relatedQuestionIds: [String] = [], suggestedFollowup: String = "") {
        self.id = id
        self.description = description
        self.relatedQuestionIds = relatedQuestionIds
        self.suggestedFollowup = suggestedFollowup
    }
}

struct Contradiction: Codable, Identifiable, Equatable {
    let id: String
    let description: String
    let firstQuote: String
    let secondQuote: String
    let suggestedClarificationQuestion: String

    init(id: String = UUID().uuidString, description: String, firstQuote: String, secondQuote: String, suggestedClarificationQuestion: String = "") {
        self.id = id
        self.description = description
        self.firstQuote = firstQuote
        self.secondQuote = secondQuote
        self.suggestedClarificationQuestion = suggestedClarificationQuestion
    }
}

// MARK: - Section Coverage (Quality Tracking)

/// Tracks how well a section has been covered, not just whether questions were asked
struct SectionCoverage: Codable, Identifiable, Equatable {
    let id: String  // Matches section ID from plan
    let sectionTitle: String
    let coverageQuality: String  // "none" | "shallow" | "adequate" | "deep"
    let keyPointsCovered: [String]  // Main points addressed in this section
    let missingAspects: [String]  // Important aspects not yet explored
    let suggestedFollowup: String?  // If coverage is shallow, a suggested question

    init(
        id: String,
        sectionTitle: String,
        coverageQuality: String = "none",
        keyPointsCovered: [String] = [],
        missingAspects: [String] = [],
        suggestedFollowup: String? = nil
    ) {
        self.id = id
        self.sectionTitle = sectionTitle
        self.coverageQuality = coverageQuality
        self.keyPointsCovered = keyPointsCovered
        self.missingAspects = missingAspects
        self.suggestedFollowup = suggestedFollowup
    }

    /// Numeric score for sorting/comparison (0.0 to 1.0)
    var qualityScore: Double {
        switch coverageQuality {
        case "deep": return 1.0
        case "adequate": return 0.7
        case "shallow": return 0.3
        default: return 0.0
        }
    }
}

// MARK: - Quotable Lines (Live Capture)

/// Memorable quotes captured during the live interview
struct QuotableLine: Codable, Identifiable, Equatable {
    let id: String
    let text: String  // The exact quote
    let speaker: String  // Usually "expert"
    let potentialUse: String  // "hook" | "section_header" | "pull_quote" | "conclusion" | "tweet"
    let topic: String  // What this quote is about
    let strength: String  // "good" | "great" | "exceptional"

    init(
        id: String = UUID().uuidString,
        text: String,
        speaker: String = "expert",
        potentialUse: String,
        topic: String,
        strength: String = "good"
    ) {
        self.id = id
        self.text = text
        self.speaker = speaker
        self.potentialUse = potentialUse
        self.topic = topic
        self.strength = strength
    }
}

// MARK: - NotesState (Plain Struct for Agent Communication)

struct NotesState: Codable, Equatable {
    var keyIdeas: [KeyIdea]
    var stories: [Story]
    var claims: [Claim]
    var gaps: [Gap]
    var contradictions: [Contradiction]
    var possibleTitles: [String]
    var sectionCoverage: [SectionCoverage]  // NEW: Quality tracking per section
    var quotableLines: [QuotableLine]  // NEW: Memorable quotes captured live

    init(
        keyIdeas: [KeyIdea] = [],
        stories: [Story] = [],
        claims: [Claim] = [],
        gaps: [Gap] = [],
        contradictions: [Contradiction] = [],
        possibleTitles: [String] = [],
        sectionCoverage: [SectionCoverage] = [],
        quotableLines: [QuotableLine] = []
    ) {
        self.keyIdeas = keyIdeas
        self.stories = stories
        self.claims = claims
        self.gaps = gaps
        self.contradictions = contradictions
        self.possibleTitles = possibleTitles
        self.sectionCoverage = sectionCoverage
        self.quotableLines = quotableLines
    }

    static let empty = NotesState()

    /// Get coverage for a specific section
    func coverage(for sectionId: String) -> SectionCoverage? {
        sectionCoverage.first { $0.id == sectionId }
    }

    /// Get sections that need more attention (shallow or no coverage)
    var underCoveredSections: [SectionCoverage] {
        sectionCoverage.filter { $0.qualityScore < 0.5 }
    }

    /// Get the best quotable lines (great or exceptional)
    var bestQuotes: [QuotableLine] {
        quotableLines.filter { $0.strength == "great" || $0.strength == "exceptional" }
    }

    /// Build a markdown-formatted summary of the notes for use in agent prompts
    func buildSummary() -> String {
        var parts: [String] = []

        if !keyIdeas.isEmpty {
            parts.append("**Key Ideas:**\n" + keyIdeas.map { "- \($0.text)" }.joined(separator: "\n"))
        }

        if !stories.isEmpty {
            parts.append("**Stories:**\n" + stories.map { "- \($0.summary) (Impact: \($0.impact))" }.joined(separator: "\n"))
        }

        if !claims.isEmpty {
            parts.append("**Claims:**\n" + claims.map { "- \($0.text) [confidence: \($0.confidence)]" }.joined(separator: "\n"))
        }

        if !gaps.isEmpty {
            parts.append("**Gaps:**\n" + gaps.map { "- \($0.description)" }.joined(separator: "\n"))
        }

        if !contradictions.isEmpty {
            parts.append("**Contradictions:**\n" + contradictions.map { "- \($0.description)" }.joined(separator: "\n"))
        }

        if !sectionCoverage.isEmpty {
            let coverageSummary = sectionCoverage.map { section in
                let quality = section.coverageQuality.uppercased()
                let points = section.keyPointsCovered.isEmpty ? "" : " (\(section.keyPointsCovered.joined(separator: ", ")))"
                return "- \(section.sectionTitle): \(quality)\(points)"
            }.joined(separator: "\n")
            parts.append("**Section Coverage:**\n" + coverageSummary)
        }

        if !quotableLines.isEmpty {
            let quotesSummary = quotableLines.prefix(5).map { quote in
                return "- \"\(quote.text)\" [\(quote.potentialUse), \(quote.strength)]"
            }.joined(separator: "\n")
            parts.append("**Quotable Lines:**\n" + quotesSummary)
        }

        if !possibleTitles.isEmpty {
            parts.append("**Possible Titles:**\n" + possibleTitles.map { "- \($0)" }.joined(separator: "\n"))
        }

        return parts.isEmpty ? "(No notes yet)" : parts.joined(separator: "\n\n")
    }
}
