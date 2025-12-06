import SwiftUI
import SwiftData

// MARK: - Follow-Up View

struct FollowUpView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let sessionId: UUID

    @Query private var sessions: [InterviewSession]

    @State private var isAnalyzing = true
    @State private var analysis: FollowUpAnalysis?
    @State private var selectedTopics: Set<String> = []
    @State private var currentError: AppError?
    @State private var isGeneratingPlan = false

    private var session: InterviewSession? {
        sessions.first { $0.id == sessionId }
    }

    var body: some View {
        Group {
            if let session {
                followUpContent(session)
            } else {
                ContentUnavailableView(
                    "Session Not Found",
                    systemImage: "doc.questionmark",
                    description: Text("The requested session could not be found.")
                )
            }
        }
        .navigationTitle("Continue Conversation")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await analyzeSession()
        }
        .errorAlert($currentError) { action in
            switch action {
            case .retry:
                Task { await analyzeSession() }
            case .goBack:
                appState.navigateBack()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private func followUpContent(_ session: InterviewSession) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                if isAnalyzing {
                    analyzingView
                } else if let analysis {
                    analysisResultView(analysis, session: session)
                }
            }
            .padding()
        }
    }

    // MARK: - Analyzing View

    private var analyzingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 100, height: 100)

                ProgressView()
                    .scaleEffect(1.5)
            }

            VStack(spacing: 8) {
                Text("Analyzing Previous Conversation")
                    .font(.headline)

                Text("Finding unexplored threads and opportunities...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    // MARK: - Analysis Result View

    @ViewBuilder
    private func analysisResultView(_ analysis: FollowUpAnalysis, session: InterviewSession) -> some View {
        // Header
        VStack(alignment: .leading, spacing: 8) {
            Label("Continue the Conversation", systemImage: "bubble.left.and.bubble.right")
                .font(.title2)
                .fontWeight(.bold)

            Text(analysis.summary)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider()

        // Topic Selection
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose topics to explore")
                .font(.headline)

            Text("Select one or more areas to dive deeper. A 6-minute follow-up will be generated.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(analysis.suggestedTopics) { topic in
                TopicCard(
                    topic: topic,
                    isSelected: selectedTopics.contains(topic.id),
                    onToggle: {
                        if selectedTopics.contains(topic.id) {
                            selectedTopics.remove(topic.id)
                        } else {
                            selectedTopics.insert(topic.id)
                        }
                    }
                )
            }
        }

        // Gaps and Areas to Strengthen (collapsed)
        if !analysis.unexploredGaps.isEmpty || !analysis.strengthenAreas.isEmpty {
            DisclosureGroup("Additional Insights") {
                VStack(alignment: .leading, spacing: 12) {
                    if !analysis.unexploredGaps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unexplored Threads")
                                .font(.subheadline.weight(.medium))
                            ForEach(analysis.unexploredGaps, id: \.self) { gap in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(gap)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !analysis.strengthenAreas.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Could Use More Depth")
                                .font(.subheadline.weight(.medium))
                            ForEach(analysis.strengthenAreas, id: \.self) { area in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "plus.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(area)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding()
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        }

        Spacer(minLength: 24)

        // Start Follow-Up Button
        Button {
            Task {
                await startFollowUp(session: session, analysis: analysis)
            }
        } label: {
            HStack {
                if isGeneratingPlan {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "mic.fill")
                }
                Text(isGeneratingPlan ? "Preparing..." : "Start 6-Minute Follow-Up")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(selectedTopics.isEmpty || isGeneratingPlan)
    }

    // MARK: - Actions

    private func analyzeSession() async {
        guard let session, let plan = session.plan else {
            currentError = .notFound(what: "Session or Plan")
            return
        }

        isAnalyzing = true

        // Create thread-safe snapshot from SwiftData model
        let sessionSnapshot = SessionSnapshot(
            id: session.id,
            utterances: session.utterances.map { utterance in
                UtteranceSnapshot(
                    speaker: utterance.speaker,
                    text: utterance.text,
                    timestamp: utterance.timestamp
                )
            },
            notes: session.notesState.map { notes in
                NotesSnapshot(
                    keyIdeas: notes.keyIdeas.map { $0.text },
                    stories: notes.stories.map { $0.summary },
                    claims: notes.claims.map { $0.text },
                    gaps: notes.gaps.map { gap in
                        GapSnapshot(
                            description: gap.description,
                            suggestedFollowup: gap.suggestedFollowup
                        )
                    },
                    contradictions: notes.contradictions.map { contradiction in
                        ContradictionSnapshot(
                            description: contradiction.description,
                            firstQuote: contradiction.firstQuote,
                            secondQuote: contradiction.secondQuote,
                            suggestedClarificationQuestion: contradiction.suggestedClarificationQuestion
                        )
                    },
                    possibleTitles: notes.possibleTitles,
                    sectionCoverage: notes.sectionCoverage.map { coverage in
                        SectionCoverageSnapshot(
                            sectionId: coverage.id,
                            sectionTitle: coverage.sectionTitle,
                            coverageQuality: coverage.coverageQuality,
                            missingAspects: coverage.missingAspects
                        )
                    },
                    quotableLines: notes.quotableLines.map { quote in
                        QuotableLineSnapshot(
                            text: quote.text,
                            potentialUse: quote.potentialUse,
                            topic: quote.topic,
                            strength: quote.strength
                        )
                    }
                )
            }
        )
        let planSnapshot = plan.toSnapshot()

        do {
            let result = try await AgentCoordinator.shared.analyzeFollowUp(
                session: sessionSnapshot,
                plan: planSnapshot
            )

            await MainActor.run {
                analysis = result
                // Pre-select first topic
                if let firstTopic = result.suggestedTopics.first {
                    selectedTopics.insert(firstTopic.id)
                }
                isAnalyzing = false
            }
        } catch {
            await MainActor.run {
                currentError = AppError.from(error, context: .analysisGeneration)
                isAnalyzing = false
            }
        }
    }

    private func startFollowUp(session: InterviewSession, analysis: FollowUpAnalysis) async {
        guard let originalPlan = session.plan else { return }

        isGeneratingPlan = true

        // Get selected topics
        let topics = analysis.suggestedTopics.filter { selectedTopics.contains($0.id) }

        // Build follow-up context
        let contextParts = topics.map { topic in
            """
            **\(topic.title):** \(topic.description)
            Questions:
            \(topic.questions.map { "- \($0)" }.joined(separator: "\n"))
            """
        }
        let followUpContext = contextParts.joined(separator: "\n\n")

        // Create a new follow-up plan
        let followUpPlan = Plan(
            topic: originalPlan.topic + " (Follow-up)",
            researchGoal: "Deepen and expand on: " + topics.map { $0.title }.joined(separator: ", "),
            angle: originalPlan.angle,
            targetSeconds: 360,  // 6 minutes
            isFollowUp: true,
            previousSessionId: session.id,
            followUpContext: followUpContext
        )

        // Create sections from selected topics
        for (index, topic) in topics.enumerated() {
            let section = Section(
                title: topic.title,
                importance: "high",
                backbone: true,
                estimatedSeconds: 360 / topics.count,
                sortOrder: index
            )

            for (qIndex, questionText) in topic.questions.enumerated() {
                let question = Question(
                    text: questionText,
                    role: qIndex == 0 ? "backbone" : "followup",
                    priority: qIndex + 1,
                    sortOrder: qIndex
                )
                question.section = section
                section.questions.append(question)
            }

            section.plan = followUpPlan
            followUpPlan.sections.append(section)
        }

        // Save to SwiftData
        await MainActor.run {
            modelContext.insert(followUpPlan)
            do {
                try modelContext.save()
            } catch {
                StructuredLogger.log(component: "FollowUpView", message: "Failed to save follow-up plan: \(error.localizedDescription)")
            }

            isGeneratingPlan = false

            // Navigate to interview
            appState.navigate(to: .interview(planId: followUpPlan.id))
        }
    }
}

// MARK: - Topic Card

struct TopicCard: View {
    let topic: FollowUpTopic
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(topic.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(topic.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    // Preview of questions
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(topic.questions.prefix(2), id: \.self) { question in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(question)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
