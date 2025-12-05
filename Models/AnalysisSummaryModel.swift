import Foundation
import SwiftData

@Model
final class AnalysisSummaryModel {
    var id: UUID
    var researchGoal: String
    var mainClaimsJSON: Data
    var themes: [String]
    var tensions: [String]
    var quotesJSON: Data
    var suggestedTitle: String
    var suggestedSubtitle: String

    init(
        id: UUID = UUID(),
        researchGoal: String = "",
        mainClaims: [MainClaim] = [],
        themes: [String] = [],
        tensions: [String] = [],
        quotes: [Quote] = [],
        suggestedTitle: String = "",
        suggestedSubtitle: String = ""
    ) {
        self.id = id
        self.researchGoal = researchGoal
        self.mainClaimsJSON = (try? JSONEncoder().encode(mainClaims)) ?? Data()
        self.themes = themes
        self.tensions = tensions
        self.quotesJSON = (try? JSONEncoder().encode(quotes)) ?? Data()
        self.suggestedTitle = suggestedTitle
        self.suggestedSubtitle = suggestedSubtitle
    }

    // MARK: - Computed Properties

    var mainClaims: [MainClaim] {
        get { (try? JSONDecoder().decode([MainClaim].self, from: mainClaimsJSON)) ?? [] }
        set { mainClaimsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var quotes: [Quote] {
        get { (try? JSONDecoder().decode([Quote].self, from: quotesJSON)) ?? [] }
        set { quotesJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

// MARK: - Plain Swift Structs for Agent I/O

struct MainClaim: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let evidenceStoryIds: [String]

    init(id: String = UUID().uuidString, text: String, evidenceStoryIds: [String] = []) {
        self.id = id
        self.text = text
        self.evidenceStoryIds = evidenceStoryIds
    }
}

struct Quote: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let role: String  // "origin" | "turning_point" | "opinion"

    init(id: String = UUID().uuidString, text: String, role: String = "opinion") {
        self.id = id
        self.text = text
        self.role = role
    }
}

// MARK: - AnalysisSummary (Plain Struct for Agent Communication)

struct AnalysisSummary: Codable, Equatable {
    let researchGoal: String
    let mainClaims: [MainClaim]
    let themes: [String]
    let tensions: [String]
    let quotes: [Quote]
    let suggestedTitle: String
    let suggestedSubtitle: String

    init(
        researchGoal: String,
        mainClaims: [MainClaim],
        themes: [String],
        tensions: [String],
        quotes: [Quote],
        suggestedTitle: String,
        suggestedSubtitle: String
    ) {
        self.researchGoal = researchGoal
        self.mainClaims = mainClaims
        self.themes = themes
        self.tensions = tensions
        self.quotes = quotes
        self.suggestedTitle = suggestedTitle
        self.suggestedSubtitle = suggestedSubtitle
    }
}

// MARK: - Quote Role Enum Helper

enum QuoteRole: String, CaseIterable, Codable {
    case origin
    case turningPoint = "turning_point"
    case opinion

    var displayName: String {
        switch self {
        case .origin: return "Origin"
        case .turningPoint: return "Turning Point"
        case .opinion: return "Opinion"
        }
    }
}
