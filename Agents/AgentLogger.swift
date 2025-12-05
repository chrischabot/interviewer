import Foundation
import os.log

/// Human-readable logging for the agent system
/// Shows the "conversation" between agents at a high level
enum AgentLogger {

    // MARK: - Simple Print

    static func log(_ message: String) {
        let time = formatTime()
        print("[\(time)] \(message)")
    }

    // MARK: - Coordinator Messages

    static func sessionStarted() {
        log("🎬 Starting new interview session")
    }

    static func liveUpdateStarted(progress: Int, transcriptCount: Int) {
        log("🎛️ Processing update (\(progress)% through interview, \(transcriptCount) exchanges so far)")
    }

    static func parallelAgentsStarted() {
        log("   ↳ NoteTaker and Researcher working in parallel...")
    }

    static func parallelAgentsFinished() {
        log("   ↳ Both finished, asking Orchestrator what to do next")
    }

    static func liveUpdateComplete(phase: String, nextQuestion: String) {
        let shortQuestion = String(nextQuestion.prefix(60))
        log("✅ Update complete — now in \(phase) phase")
        log("   ↳ Next: \"\(shortQuestion)...\"")
    }

    // MARK: - Planner Messages

    static func plannerStarted(topic: String, duration: Int) {
        log("📋 Planner designing interview for \"\(topic)\" (\(duration) min)")
    }

    static func plannerComplete(sections: Int, questions: Int, angle: String) {
        log("📋 Planner done — \(sections) sections, \(questions) questions")
        log("   ↳ Angle: \"\(angle)\"")
    }

    // MARK: - NoteTaker Messages

    static func noteTakerStarted(transcriptCount: Int) {
        log("📝 NoteTaker reviewing \(transcriptCount) exchanges for insights...")
    }

    static func noteTakerFound(ideas: [String], stories: [String], claims: [String], gaps: [String]) {
        var parts: [String] = []

        if !ideas.isEmpty {
            let preview = ideas.prefix(3).joined(separator: ", ")
            parts.append("\(ideas.count) idea\(ideas.count == 1 ? "" : "s") (\(preview))")
        }
        if !stories.isEmpty {
            let preview = stories.prefix(2).joined(separator: ", ")
            parts.append("\(stories.count) stor\(stories.count == 1 ? "y" : "ies") (\(preview))")
        }
        if !claims.isEmpty {
            let preview = claims.prefix(2).joined(separator: ", ")
            parts.append("\(claims.count) claim\(claims.count == 1 ? "" : "s") (\(preview))")
        }
        if !gaps.isEmpty {
            parts.append("\(gaps.count) gap\(gaps.count == 1 ? "" : "s") to explore")
        }

        if parts.isEmpty {
            log("📝 NoteTaker found nothing new this round")
        } else {
            log("📝 NoteTaker found: \(parts.joined(separator: ", "))")
        }
    }

    // MARK: - Researcher Messages

    static func researcherStarted() {
        log("🔍 Researcher scanning for concepts to look up...")
    }

    static func researcherIdentifiedTopics(_ topics: [String]) {
        if topics.isEmpty {
            log("🔍 Researcher: nothing new to look up")
        } else {
            log("🔍 Researcher wants to look up: \(topics.joined(separator: ", "))")
        }
    }

    static func researcherLookingUp(topic: String, reason: String) {
        log("   ↳ Researching \"\(topic)\" (\(reason))")
    }

    static func researcherFound(topic: String, summary: String) {
        let shortSummary = String(summary.prefix(80))
        log("   ↳ Found: \(shortSummary)...")
    }

    static func researcherComplete(count: Int) {
        if count == 0 {
            log("🔍 Researcher done — no new findings")
        } else {
            log("🔍 Researcher done — \(count) new piece\(count == 1 ? "" : "s") of context")
        }
    }

    // MARK: - Orchestrator Messages

    static func orchestratorThinking(progress: Int, questionsAsked: Int) {
        log("🎯 Orchestrator deciding next move (\(progress)% done, \(questionsAsked) questions asked)")
    }

    static func orchestratorDecided(phase: String, source: String, question: String) {
        let shortQuestion = String(question.prefix(70))

        let sourceDesc: String
        switch source {
        case "plan": sourceDesc = "from the plan"
        case "gap": sourceDesc = "to fill a gap"
        case "contradiction": sourceDesc = "to clarify a contradiction"
        case "research": sourceDesc = "based on research"
        default: sourceDesc = source
        }

        log("🎯 Orchestrator says: ask about \"\(shortQuestion)...\"")
        log("   ↳ Phase: \(phase), Reason: \(sourceDesc)")
    }

    static func orchestratorBrief(brief: String) {
        let shortBrief = String(brief.prefix(100))
        log("   ↳ Tip for interviewer: \(shortBrief)...")
    }

    // MARK: - Analysis Messages

    static func analysisStarted(wordCount: Int) {
        log("🔬 Analyst reviewing full interview (~\(wordCount) words)...")
    }

    static func analysisComplete(claims: Int, themes: [String], quotes: Int, title: String) {
        log("🔬 Analyst done!")
        log("   ↳ Found \(claims) main claims, \(quotes) quotable lines")
        log("   ↳ Themes: \(themes.joined(separator: ", "))")
        log("   ↳ Suggested title: \"\(title)\"")
    }

    // MARK: - Writer Messages

    static func writerStarted(style: String) {
        log("✍️ Writer crafting essay (style: \(style))...")
    }

    static func writerComplete(wordCount: Int, readingTime: Int) {
        log("✍️ Writer done — \(wordCount) words, ~\(readingTime) min read")
    }

    // MARK: - Error Messages

    static func error(agent: String, message: String) {
        log("❌ \(agent) error: \(message)")
    }

    // MARK: - Helpers

    private static func formatTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
