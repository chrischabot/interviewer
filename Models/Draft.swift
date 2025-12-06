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
    case zinsser

    var displayName: String {
        switch self {
        case .zinsser:
            return "Zinsser"
        default:
            return rawValue.capitalized
        }
    }

    var description: String {
        switch self {
        case .standard:
            return "Balanced narrative with clear structure"
        case .punchy:
            return "Direct, energetic, shorter paragraphs"
        case .reflective:
            return "Thoughtful, introspective, more nuanced"
        case .zinsser:
            return "Clean, clear nonfiction (On Writing Well)"
        }
    }
}
