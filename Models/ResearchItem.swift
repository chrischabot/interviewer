import Foundation

// MARK: - Research Item (Agent Output)

struct ResearchItem: Codable, Identifiable, Equatable {
    let id: String
    let topic: String
    let kind: String  // "definition" | "counterpoint" | "example" | "metric"
    let summary: String
    let howToUseInQuestion: String
    let priority: Int

    init(
        id: String = UUID().uuidString,
        topic: String,
        kind: String,
        summary: String,
        howToUseInQuestion: String,
        priority: Int = 2
    ) {
        self.id = id
        self.topic = topic
        self.kind = kind
        self.summary = summary
        self.howToUseInQuestion = howToUseInQuestion
        self.priority = priority
    }
}

// MARK: - Research Item Kind Enum Helper

enum ResearchItemKind: String, CaseIterable, Codable {
    case definition
    case counterpoint
    case example
    case metric
    case person
    case company
    case context
    case trend

    var displayName: String {
        rawValue.capitalized
    }

    var description: String {
        switch self {
        case .definition:
            return "Definition or explanation of a concept"
        case .counterpoint:
            return "Alternative viewpoint or challenge"
        case .example:
            return "Real-world example or case study"
        case .metric:
            return "Data point or statistic"
        case .person:
            return "Notable person or expert in the field"
        case .company:
            return "Company or organization reference"
        case .context:
            return "Background context or historical information"
        case .trend:
            return "Current trend or emerging pattern"
        }
    }
}
