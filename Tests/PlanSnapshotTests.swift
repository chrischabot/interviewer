import Foundation
import Testing
@testable import Interviewer

@Suite("PlanSnapshot Tests")
struct PlanSnapshotTests {

    // MARK: - Helper

    func createTestPlanSnapshot() -> PlanSnapshot {
        PlanSnapshot(
            topic: "Software Architecture",
            researchGoal: "Understand trade-offs in microservices",
            angle: "Practical lessons from failures",
            sections: [
                PlanSnapshot.SectionSnapshot(
                    id: "section-1",
                    title: "Background",
                    importance: "high",
                    questions: [
                        PlanSnapshot.QuestionSnapshot(
                            id: "q-1",
                            text: "How did you get into architecture?",
                            role: "backbone",
                            priority: 1,
                            notesForInterviewer: "Listen for turning points"
                        ),
                        PlanSnapshot.QuestionSnapshot(
                            id: "q-2",
                            text: "What's your current role?",
                            role: "followup",
                            priority: 2,
                            notesForInterviewer: ""
                        )
                    ]
                ),
                PlanSnapshot.SectionSnapshot(
                    id: "section-2",
                    title: "Challenges",
                    importance: "high",
                    questions: [
                        PlanSnapshot.QuestionSnapshot(
                            id: "q-3",
                            text: "Tell me about a major failure",
                            role: "backbone",
                            priority: 1,
                            notesForInterviewer: "This is gold - get specifics"
                        )
                    ]
                )
            ]
        )
    }

    // MARK: - Structure Tests

    @Test("PlanSnapshot contains correct topic and goal")
    func topicAndGoal() {
        let plan = createTestPlanSnapshot()

        #expect(plan.topic == "Software Architecture")
        #expect(plan.researchGoal == "Understand trade-offs in microservices")
        #expect(plan.angle == "Practical lessons from failures")
    }

    @Test("PlanSnapshot contains correct sections")
    func sections() {
        let plan = createTestPlanSnapshot()

        #expect(plan.sections.count == 2)
        #expect(plan.sections[0].title == "Background")
        #expect(plan.sections[1].title == "Challenges")
    }

    @Test("PlanSnapshot sections contain questions")
    func questions() {
        let plan = createTestPlanSnapshot()

        #expect(plan.sections[0].questions.count == 2)
        #expect(plan.sections[1].questions.count == 1)
        #expect(plan.sections[0].questions[0].priority == 1)
    }

    // MARK: - Codable Tests

    @Test("PlanSnapshot JSON roundtrip")
    func codable() throws {
        let plan = createTestPlanSnapshot()

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(PlanSnapshot.self, from: data)

        #expect(decoded.topic == plan.topic)
        #expect(decoded.sections.count == plan.sections.count)
        #expect(decoded.sections[0].questions.count == plan.sections[0].questions.count)
    }

    // MARK: - Question Priority

    @Test("Questions have correct priorities")
    func questionPriorities() {
        let plan = createTestPlanSnapshot()

        let allQuestions = plan.sections.flatMap { $0.questions }
        let p1Questions = allQuestions.filter { $0.priority == 1 }
        let p2Questions = allQuestions.filter { $0.priority == 2 }

        #expect(p1Questions.count == 2)  // Two P1 questions
        #expect(p2Questions.count == 1)  // One P2 question
    }

    @Test("Question roles are correct")
    func questionRoles() {
        let plan = createTestPlanSnapshot()

        let allQuestions = plan.sections.flatMap { $0.questions }
        let backboneQuestions = allQuestions.filter { $0.role == "backbone" }
        let followupQuestions = allQuestions.filter { $0.role == "followup" }

        #expect(backboneQuestions.count == 2)
        #expect(followupQuestions.count == 1)
    }
}
