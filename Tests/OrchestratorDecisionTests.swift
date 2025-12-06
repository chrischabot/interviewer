import Foundation
import Testing
@testable import Interviewer

@Suite("OrchestratorDecision Tests")
struct OrchestratorDecisionTests {

    // MARK: - InterviewPhase

    @Test("InterviewPhase display names")
    func phaseDisplayNames() {
        #expect(InterviewPhase.opening.displayName == "Opening")
        #expect(InterviewPhase.deepDive.displayName == "Deep Dive")
        #expect(InterviewPhase.wrapUp.displayName == "Wrap Up")
    }

    @Test("InterviewPhase raw values")
    func phaseRawValues() {
        #expect(InterviewPhase.opening.rawValue == "opening")
        #expect(InterviewPhase.deepDive.rawValue == "deep_dive")
        #expect(InterviewPhase.wrapUp.rawValue == "wrap_up")
    }

    @Test("InterviewPhase descriptions")
    func phaseDescriptions() {
        #expect(InterviewPhase.opening.description.contains("context"))
        #expect(InterviewPhase.deepDive.description.contains("Stories") || InterviewPhase.deepDive.description.contains("examples"))
        #expect(InterviewPhase.wrapUp.description.contains("Synthesizing") || InterviewPhase.wrapUp.description.contains("reflection"))
    }

    // MARK: - QuestionSource

    @Test("QuestionSource display names")
    func sourceDisplayNames() {
        #expect(QuestionSource.plan.displayName == "Plan")
        #expect(QuestionSource.gap.displayName == "Gap")
        #expect(QuestionSource.contradiction.displayName == "Contradiction")
        #expect(QuestionSource.research.displayName == "Research")
    }

    // MARK: - NextQuestion

    @Test("NextQuestion initialization with defaults")
    func nextQuestionDefaults() {
        let question = NextQuestion(
            text: "Test question?",
            targetSectionId: "section-1"
        )

        #expect(question.text == "Test question?")
        #expect(question.targetSectionId == "section-1")
        #expect(question.source == "plan")
        #expect(question.sourceQuestionId == nil)
        #expect(question.expectedAnswerSeconds == 60)
    }

    @Test("NextQuestion initialization with all parameters")
    func nextQuestionFullInit() {
        let question = NextQuestion(
            text: "Follow-up question?",
            targetSectionId: "section-2",
            source: "gap",
            sourceQuestionId: "q-123",
            expectedAnswerSeconds: 90
        )

        #expect(question.text == "Follow-up question?")
        #expect(question.source == "gap")
        #expect(question.sourceQuestionId == "q-123")
        #expect(question.expectedAnswerSeconds == 90)
    }

    // MARK: - OrchestratorDecision Codable

    @Test("OrchestratorDecision JSON encoding and decoding")
    func codable() throws {
        let decision = OrchestratorDecision(
            phase: "deep_dive",
            nextQuestion: NextQuestion(
                text: "What challenges did you face?",
                targetSectionId: "challenges",
                source: "plan",
                sourceQuestionId: "q-456"
            ),
            interviewerBrief: "Ask with empathy, listen for specific examples"
        )

        // Model uses explicit CodingKeys for snake_case, so use default encoder/decoder
        let data = try JSONEncoder().encode(decision)
        let decoded = try JSONDecoder().decode(OrchestratorDecision.self, from: data)

        #expect(decoded.phase == "deep_dive")
        #expect(decoded.nextQuestion.text == "What challenges did you face?")
        #expect(decoded.interviewerBrief.contains("empathy"))
    }
}
