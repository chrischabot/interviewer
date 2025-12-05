import Foundation

// MARK: - Orchestrator Decision (Agent Output)

struct OrchestratorDecision: Codable, Equatable {
    let phase: String  // "opening" | "deep_dive" | "wrap_up"
    let nextQuestion: NextQuestion
    let interviewerBrief: String
}

struct NextQuestion: Codable, Equatable {
    let text: String
    let targetSectionId: String
    let source: String  // "plan" | "gap" | "contradiction" | "research"
    let expectedAnswerSeconds: Int

    init(
        text: String,
        targetSectionId: String,
        source: String = "plan",
        expectedAnswerSeconds: Int = 60
    ) {
        self.text = text
        self.targetSectionId = targetSectionId
        self.source = source
        self.expectedAnswerSeconds = expectedAnswerSeconds
    }
}

// MARK: - Interview Phase Enum Helper

enum InterviewPhase: String, CaseIterable, Codable {
    case opening
    case deepDive = "deep_dive"
    case wrapUp = "wrap_up"

    var displayName: String {
        switch self {
        case .opening: return "Opening"
        case .deepDive: return "Deep Dive"
        case .wrapUp: return "Wrap Up"
        }
    }

    var description: String {
        switch self {
        case .opening:
            return "Clarifying context and stakes"
        case .deepDive:
            return "Exploring stories and concrete examples"
        case .wrapUp:
            return "Synthesizing and closing reflection"
        }
    }
}

// MARK: - Question Source Enum Helper

enum QuestionSource: String, CaseIterable, Codable {
    case plan
    case gap
    case contradiction
    case research

    var displayName: String {
        switch self {
        case .plan: return "Plan"
        case .gap: return "Gap"
        case .contradiction: return "Contradiction"
        case .research: return "Research"
        }
    }
}
