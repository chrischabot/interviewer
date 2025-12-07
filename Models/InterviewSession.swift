import Foundation
import SwiftData

// MARK: - Session Type

enum SessionType: String, Codable, CaseIterable {
    case interviewed  // Live voice interview
    case imported     // YouTube/external content

    var displayName: String {
        switch self {
        case .interviewed: return "Interview"
        case .imported: return "Import"
        }
    }

    var icon: String {
        switch self {
        case .interviewed: return "mic.fill"
        case .imported: return "play.rectangle.fill"
        }
    }
}

// MARK: - Interview Session Model

@Model
final class InterviewSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var elapsedSeconds: Int

    /// Type of session: interviewed (live) or imported (YouTube, etc.)
    var sessionType: String = SessionType.interviewed.rawValue

    /// Source URL for imported content (YouTube URL, etc.)
    var sourceURL: String?

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
        plan: Plan? = nil,
        sessionType: SessionType = .interviewed,
        sourceURL: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.elapsedSeconds = elapsedSeconds
        self.plan = plan
        self.sessionType = sessionType.rawValue
        self.sourceURL = sourceURL
    }

    var isCompleted: Bool {
        endedAt != nil
    }

    var isImported: Bool {
        sessionType == SessionType.imported.rawValue
    }

    var type: SessionType {
        SessionType(rawValue: sessionType) ?? .interviewed
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
