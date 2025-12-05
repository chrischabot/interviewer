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
    var possibleTitles: [String]

    init(
        id: UUID = UUID(),
        keyIdeas: [KeyIdea] = [],
        stories: [Story] = [],
        claims: [Claim] = [],
        gaps: [Gap] = [],
        contradictions: [Contradiction] = [],
        possibleTitles: [String] = []
    ) {
        self.id = id
        self.keyIdeasJSON = (try? JSONEncoder().encode(keyIdeas)) ?? Data()
        self.storiesJSON = (try? JSONEncoder().encode(stories)) ?? Data()
        self.claimsJSON = (try? JSONEncoder().encode(claims)) ?? Data()
        self.gapsJSON = (try? JSONEncoder().encode(gaps)) ?? Data()
        self.contradictionsJSON = (try? JSONEncoder().encode(contradictions)) ?? Data()
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

// MARK: - NotesState (Plain Struct for Agent Communication)

struct NotesState: Codable, Equatable {
    var keyIdeas: [KeyIdea]
    var stories: [Story]
    var claims: [Claim]
    var gaps: [Gap]
    var contradictions: [Contradiction]
    var possibleTitles: [String]

    init(
        keyIdeas: [KeyIdea] = [],
        stories: [Story] = [],
        claims: [Claim] = [],
        gaps: [Gap] = [],
        contradictions: [Contradiction] = [],
        possibleTitles: [String] = []
    ) {
        self.keyIdeas = keyIdeas
        self.stories = stories
        self.claims = claims
        self.gaps = gaps
        self.contradictions = contradictions
        self.possibleTitles = possibleTitles
    }

    static let empty = NotesState()
}
