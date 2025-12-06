import Foundation

// MARK: - Research Item (Agent Output)

struct ResearchItem: Codable, Identifiable, Equatable {
    let id: String
    let topic: String
    let kind: String  // "definition" | "counterpoint" | "example" | "metric" | "claim_verification"
    let summary: String
    let howToUseInQuestion: String
    let priority: Int
    // Claim verification fields (populated when kind = "claim_verification")
    let verificationStatus: String?  // "verified" | "contradicted" | "partially_true" | "unverifiable"
    let verificationNote: String?    // Explanation of verification result

    init(
        id: String = UUID().uuidString,
        topic: String,
        kind: String,
        summary: String,
        howToUseInQuestion: String,
        priority: Int = 2,
        verificationStatus: String? = nil,
        verificationNote: String? = nil
    ) {
        self.id = id
        self.topic = topic
        self.kind = kind
        self.summary = summary
        self.howToUseInQuestion = howToUseInQuestion
        self.priority = priority
        self.verificationStatus = verificationStatus
        self.verificationNote = verificationNote
    }

    /// Whether this is a verified claim that matches what the expert said
    var isVerifiedClaim: Bool {
        kind == "claim_verification" && verificationStatus == "verified"
    }

    /// Whether this contradicts what the expert said
    var isContradictedClaim: Bool {
        kind == "claim_verification" && verificationStatus == "contradicted"
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
    case claimVerification = "claim_verification"

    var displayName: String {
        switch self {
        case .claimVerification:
            return "Claim Verification"
        default:
            return rawValue.capitalized
        }
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
        case .claimVerification:
            return "Verification of a specific claim or statistic"
        }
    }
}
