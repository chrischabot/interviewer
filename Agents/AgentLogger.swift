import Foundation

/// Human-readable logging for the agent system using the shared structured format.
enum AgentLogger {

    // MARK: - Coordinator Messages

    static func sessionStarted() {
        log(component: "Coordinator", "Starting new interview session")
    }

    static func liveUpdateStarted(progress: Int, transcriptCount: Int) {
        log(component: "Coordinator", "Processing update (\(progress)% through interview, \(transcriptCount) final exchanges)")
    }

    static func parallelAgentsStarted() {
        log(component: "Coordinator", "NoteTaker and Researcher working in parallel...")
    }

    static func parallelAgentsFinished() {
        log(component: "Coordinator", "Both finished, asking Orchestrator what to do next")
    }

    static func agentsSkipped(reason: String) {
        log(component: "Coordinator", "Agents skipped: \(reason)")
    }

    static func liveUpdateComplete(phase: String, nextQuestion: String) {
        let shortQuestion = String(nextQuestion.prefix(60))
        log(component: "Coordinator", "Update complete — now in \(phase) phase")
        log(component: "Coordinator", "Next: \"\(shortQuestion)...\"")
    }

    static func contentChangeDetected(hasNewContent: Bool, hashChanged: Bool, countChanged: Bool) {
        guard hasNewContent else { return }

        var reasons: [String] = []
        if hashChanged { reasons.append("content changed") }
        if countChanged { reasons.append("new entries") }
        log(component: "Coordinator", "Content change detected: \(reasons.joined(separator: ", "))")
    }

    // MARK: - Planner Messages

    static func plannerStarted(topic: String, duration: Int) {
        log(component: "Planner Agent", "Designing interview for \"\(topic)\" (\(duration) min)")
    }

    static func plannerComplete(sections: Int, questions: Int, angle: String) {
        log(component: "Planner Agent", "Planner complete — \(sections) sections, \(questions) questions")
        log(component: "Planner Agent", "Angle: \"\(angle)\"")
    }

    // MARK: - NoteTaker Messages

    static func noteTakerStarted(transcriptCount: Int) {
        log(component: "NoteTaker Agent", "Reviewing \(transcriptCount) exchanges for insights...")
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
            log(component: "NoteTaker Agent", "Found nothing new this round")
        } else {
            log(component: "NoteTaker Agent", "Found: \(parts.joined(separator: ", "))")
        }
    }

    // MARK: - Researcher Messages

    static func researcherStarted() {
        log(component: "Researcher Agent", "Scanning for concepts to look up...")
    }

    static func researcherSkipped(reason: String) {
        log(component: "Researcher Agent", "Skipped: \(reason)")
    }

    static func researcherIdentifiedTopics(_ topics: [String]) {
        if topics.isEmpty {
            log(component: "Researcher Agent", "Nothing new to look up")
        } else {
            log(component: "Researcher Agent", "Wants to look up: \(topics.joined(separator: ", "))")
        }
    }

    static func researcherLookingUp(topic: String, reason: String) {
        log(component: "Researcher Agent", "Researching \"\(topic)\" (\(reason))")
    }

    static func researcherFound(topic: String, summary: String) {
        let shortSummary = String(summary.prefix(80))
        log(component: "Researcher Agent", "Found: \(shortSummary)...")
    }

    static func researcherError(topic: String, error: String) {
        log(component: "Researcher Agent", "Research failed for \"\(topic)\": \(error)")
    }

    static func researcherComplete(count: Int) {
        if count == 0 {
            log(component: "Researcher Agent", "Done — no new findings")
        } else {
            log(component: "Researcher Agent", "Done — \(count) new piece\(count == 1 ? "" : "s") of context")
        }
    }

    // MARK: - Orchestrator Messages

    static func orchestratorThinking(progress: Int, questionsAsked: Int) {
        log(component: "Orchestrator Agent", "Deciding next move (\(progress)% done, \(questionsAsked) questions asked)")
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

        log(component: "Orchestrator Agent", "Ask about \"\(shortQuestion)...\"")
        log(component: "Orchestrator Agent", "Phase: \(phase), Reason: \(sourceDesc)")
    }

    static func orchestratorBrief(brief: String) {
        let shortBrief = String(brief.prefix(100))
        log(component: "Orchestrator Agent", "Tip for interviewer: \(shortBrief)...")
    }

    // MARK: - Analysis Messages

    static func analysisStarted(wordCount: Int) {
        log(component: "Analysis Agent", "Reviewing full interview (~\(wordCount) words)...")
    }

    static func analysisComplete(claims: Int, themes: [String], quotes: Int, title: String) {
        log(component: "Analysis Agent", "Analysis complete")
        log(component: "Analysis Agent", "Found \(claims) main claims, \(quotes) quotable lines")
        log(component: "Analysis Agent", "Themes: \(themes.joined(separator: ", "))")
        log(component: "Analysis Agent", "Suggested title: \"\(title)\"")
    }

    // MARK: - Writer Messages

    static func writerStarted(style: String) {
        log(component: "Writer Agent", "Crafting essay (style: \(style))...")
    }

    static func writerComplete(wordCount: Int, readingTime: Int) {
        log(component: "Writer Agent", "Complete — \(wordCount) words, ~\(readingTime) min read")
    }

    // MARK: - Error Messages

    static func error(agent: String, message: String) {
        log(component: "\(agent) Agent", "Error: \(message)")
    }

    // MARK: - Info Messages

    static func info(agent: String, message: String) {
        log(component: agent, message)
    }

    // MARK: - Question Tracking

    static func questionMarkedAsked(questionId: String, method: String) {
        log(component: "Coordinator", "Question marked as asked (id: \(questionId.prefix(8))..., method: \(method))")
    }

    // MARK: - Helpers

    private static func log(component: String, _ message: String) {
        StructuredLogger.log(component: component, message: message)
    }
}
