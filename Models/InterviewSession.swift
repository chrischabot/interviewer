import Foundation
import SwiftData

@Model
final class InterviewSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var elapsedSeconds: Int

    var plan: Plan?

    @Relationship(deleteRule: .cascade, inverse: \Utterance.session)
    var utterances: [Utterance] = []

    @Relationship(deleteRule: .cascade)
    var notesState: NotesStateModel?

    @Relationship(deleteRule: .cascade)
    var analysis: AnalysisSummaryModel?

    @Relationship(deleteRule: .cascade, inverse: \Draft.session)
    var drafts: [Draft] = []

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        elapsedSeconds: Int = 0,
        plan: Plan? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.elapsedSeconds = elapsedSeconds
        self.plan = plan
    }

    var isCompleted: Bool {
        endedAt != nil
    }

    var formattedDuration: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@Model
final class Utterance {
    var id: UUID
    var speaker: String  // "user" | "assistant"
    var text: String
    var timestamp: Date

    var session: InterviewSession?

    init(
        id: UUID = UUID(),
        speaker: String,
        text: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}

// MARK: - Speaker Enum Helper

enum Speaker: String, CaseIterable, Codable {
    case user
    case assistant

    var displayName: String {
        switch self {
        case .user: return "You"
        case .assistant: return "Interviewer"
        }
    }
}
