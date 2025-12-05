import Foundation
import SwiftData

@Model
final class Plan {
    @Attribute(.unique) var id: UUID
    var topic: String
    var researchGoal: String
    var angle: String
    var targetSeconds: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Section.plan)
    var sections: [Section] = []

    init(
        id: UUID = UUID(),
        topic: String,
        researchGoal: String,
        angle: String,
        targetSeconds: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.topic = topic
        self.researchGoal = researchGoal
        self.angle = angle
        self.targetSeconds = targetSeconds
        self.createdAt = createdAt
    }
}

@Model
final class Section {
    var id: UUID
    var title: String
    var importance: String  // "high" | "medium" | "low"
    var backbone: Bool
    var estimatedSeconds: Int
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \Question.section)
    var questions: [Question] = []

    var plan: Plan?

    init(
        id: UUID = UUID(),
        title: String,
        importance: String = "medium",
        backbone: Bool = true,
        estimatedSeconds: Int = 120,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.importance = importance
        self.backbone = backbone
        self.estimatedSeconds = estimatedSeconds
        self.sortOrder = sortOrder
    }
}

@Model
final class Question {
    var id: UUID
    var text: String
    var role: String  // "backbone" | "followup"
    var priority: Int  // 1 = must-hit, 2, 3
    var notesForInterviewer: String
    var sortOrder: Int

    var section: Section?

    init(
        id: UUID = UUID(),
        text: String,
        role: String = "backbone",
        priority: Int = 1,
        notesForInterviewer: String = "",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.text = text
        self.role = role
        self.priority = priority
        self.notesForInterviewer = notesForInterviewer
        self.sortOrder = sortOrder
    }
}

// MARK: - Importance Enum Helper

enum SectionImportance: String, CaseIterable, Codable {
    case high
    case medium
    case low

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Question Role Enum Helper

enum QuestionRole: String, CaseIterable, Codable {
    case backbone
    case followup

    var displayName: String {
        switch self {
        case .backbone: return "Backbone"
        case .followup: return "Follow-up"
        }
    }
}
