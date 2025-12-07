import Foundation
import SwiftData

@Model
final class Draft {
    var id: UUID
    var style: String  // "standard" | "punchy" | "reflective"
    var markdownContent: String
    var createdAt: Date

    var session: InterviewSession?

    init(
        id: UUID = UUID(),
        style: String = "standard",
        markdownContent: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.style = style
        self.markdownContent = markdownContent
        self.createdAt = createdAt
    }
}

// MARK: - Draft Style Enum Helper

enum DraftStyle: String, CaseIterable, Codable {
    case standard
    case punchy
    case reflective

    var displayName: String {
        rawValue.capitalized
    }

    var description: String {
        switch self {
        case .standard:
            return "Conversational, surprising, like a Paul Graham essay"
        case .punchy:
            return "Crisp and energetic, ideas land fast"
        case .reflective:
            return "Thoughtful pace, ideas unfold gradually"
        }
    }
}
