import Foundation

/// Coordinates all agents and provides a unified interface for the app
actor AgentCoordinator {
    static let shared = AgentCoordinator()

    private let openAIClient: OpenAIClient
    private let plannerAgent: PlannerAgent

    // Agent activity tracking for UI meters
    private var agentActivity: [String: Double] = [:]

    private init() {
        self.openAIClient = OpenAIClient.shared
        self.plannerAgent = PlannerAgent(client: openAIClient)
    }

    // MARK: - Pre-Interview (Phase 2)

    /// Generate an interview plan from user input
    func generatePlan(topic: String, context: String, targetMinutes: Int) async throws -> PlannerResponse {
        updateActivity(agent: "planner", score: 1.0)
        defer { updateActivity(agent: "planner", score: 0.5) }

        return try await plannerAgent.generatePlan(
            topic: topic,
            context: context,
            targetMinutes: targetMinutes
        )
    }

    // MARK: - Activity Tracking

    private func updateActivity(agent: String, score: Double) {
        agentActivity[agent] = score
    }

    func getAgentActivity() -> [String: Double] {
        return agentActivity
    }

    func getActivity(for agent: String) -> Double {
        return agentActivity[agent] ?? 0.0
    }
}

// MARK: - Plan Conversion Helpers

extension PlannerResponse {
    /// Convert PlannerResponse to SwiftData Plan model
    func toPlan(topic: String, targetSeconds: Int) -> Plan {
        let plan = Plan(
            topic: topic,
            researchGoal: researchGoal,
            angle: angle,
            targetSeconds: targetSeconds
        )

        for (index, section) in sections.enumerated() {
            let newSection = Section(
                title: section.title,
                importance: section.importance,
                backbone: true,
                estimatedSeconds: section.estimatedSeconds,
                sortOrder: index
            )

            for (qIndex, question) in section.questions.enumerated() {
                let newQuestion = Question(
                    text: question.text,
                    role: question.role,
                    priority: question.priority,
                    notesForInterviewer: question.notesForInterviewer,
                    sortOrder: qIndex
                )
                newQuestion.section = newSection
                newSection.questions.append(newQuestion)
            }

            newSection.plan = plan
            plan.sections.append(newSection)
        }

        return plan
    }
}
