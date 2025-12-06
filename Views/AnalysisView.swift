import SwiftUI
import SwiftData

// MARK: - Analysis Processing Stage

enum AnalysisStage: CaseIterable {
    case idle
    case loading
    case analyzing
    case complete
    case error

    var title: String {
        switch self {
        case .idle: return "Ready"
        case .loading: return "Loading Data"
        case .analyzing: return "Analyzing Interview"
        case .complete: return "Analysis Complete"
        case .error: return "Error"
        }
    }

    var description: String {
        switch self {
        case .idle: return "Preparing to analyze your interview..."
        case .loading: return "Loading transcript and notes..."
        case .analyzing: return "Extracting insights, themes, and quotable lines..."
        case .complete: return "Your analysis is ready!"
        case .error: return "Something went wrong during analysis."
        }
    }
}

// MARK: - Analysis View

struct AnalysisView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let sessionId: UUID

    @Query private var sessions: [InterviewSession]

    @State private var stage: AnalysisStage = .idle
    @State private var analysis: AnalysisSummary?
    @State private var currentError: AppError?
    @State private var selectedStyle: DraftStyle = .standard

    private var session: InterviewSession? {
        sessions.first { $0.id == sessionId }
    }

    private func log(_ message: String) {
        StructuredLogger.log(component: "AnalysisView", message: message)
    }

    var body: some View {
        Group {
            if let session {
                analysisContent(session)
            } else {
                ContentUnavailableView(
                    "Session Not Found",
                    systemImage: "doc.questionmark",
                    description: Text("The requested session could not be found.")
                )
            }
        }
        .navigationTitle("Analysis")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadOrGenerateAnalysis()
        }
        .errorAlert($currentError) { action in
            switch action {
            case .retry:
                Task { await loadOrGenerateAnalysis() }
            case .openSettings:
                appState.showSettings = true
            case .goBack:
                appState.navigateBack()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private func analysisContent(_ session: InterviewSession) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                switch stage {
                case .idle, .loading, .analyzing:
                    processingView
                case .complete:
                    if let analysis {
                        completeAnalysisView(analysis, session: session)
                    }
                case .error:
                    errorView
                }
            }
            .padding()
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 100, height: 100)

                ProgressView()
                    .scaleEffect(1.5)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(stage.title)
                    .font(.headline)

                Text(stage.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analysis in progress")
        .accessibilityValue("\(stage.title). \(stage.description)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: currentError?.icon ?? "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text(currentError?.errorDescription ?? "Analysis Failed")
                .font(.headline)

            Text(currentError?.recoverySuggestion ?? "Unknown error")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Try Again") {
                    Task { await loadOrGenerateAnalysis() }
                }
                .buttonStyle(.borderedProminent)

                if currentError?.primaryAction == .openSettings {
                    Button("Settings") {
                        appState.showSettings = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
    }

    // MARK: - Complete Analysis View

    @ViewBuilder
    private func completeAnalysisView(_ analysis: AnalysisSummary, session: InterviewSession) -> some View {
        // Title Section
        VStack(alignment: .leading, spacing: 8) {
            Text(analysis.suggestedTitle)
                .font(.title)
                .fontWeight(.bold)

            if !analysis.suggestedSubtitle.isEmpty {
                Text(analysis.suggestedSubtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider()

        // Research Goal Assessment
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Research Goal", systemImage: "target")
                    .font(.headline)

                Text(analysis.researchGoal)
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }

        // Main Claims
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Main Claims", systemImage: "quote.bubble")
                    .font(.headline)

                ForEach(Array(analysis.mainClaims.enumerated()), id: \.element.id) { index, claim in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.headline)
                            .foregroundStyle(.blue)
                            .frame(width: 24)

                        Text(claim.text)
                            .font(.body)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }

        // Themes
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Themes", systemImage: "rectangle.3.group")
                    .font(.headline)

                FlowLayout(spacing: 8) {
                    ForEach(analysis.themes, id: \.self) { theme in
                        Text(theme)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.blue.opacity(0.1), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }

        // Tensions (if any)
        if !analysis.tensions.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Tensions & Nuances", systemImage: "arrow.left.arrow.right")
                        .font(.headline)

                    ForEach(analysis.tensions, id: \.self) { tension in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.orange)

                            Text(tension)
                                .font(.body)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }

        // Quotable Lines
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label("Quotable Lines", systemImage: "text.quote")
                    .font(.headline)

                ForEach(analysis.quotes) { quote in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\"\(quote.text)\"")
                            .font(.body)
                            .italic()

                        HStack {
                            Spacer()
                            Text(quoteRoleLabel(quote.role))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.1), in: Capsule())
                        }
                    }
                    .padding()
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }

        Divider()

        // Generate Draft Section
        GroupBox {
            VStack(spacing: 16) {
                Text("Generate Essay")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Writing Style")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Style", selection: $selectedStyle) {
                        ForEach(DraftStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedStyle.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    navigateToDraft(session: session)
                } label: {
                    Label("Generate Draft", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private func quoteRoleLabel(_ role: String) -> String {
        switch role {
        case "origin": return "Origin Story"
        case "turning_point": return "Turning Point"
        case "opinion": return "Strong Opinion"
        default: return role.capitalized
        }
    }

    private func loadOrGenerateAnalysis() async {
        guard let session else { return }

        stage = .loading

        // Check if analysis already exists
        if let existingAnalysis = session.analysis {
            analysis = AnalysisSummary(
                researchGoal: existingAnalysis.researchGoal,
                mainClaims: existingAnalysis.mainClaims,
                themes: existingAnalysis.themes,
                tensions: existingAnalysis.tensions,
                quotes: existingAnalysis.quotes,
                suggestedTitle: existingAnalysis.suggestedTitle,
                suggestedSubtitle: existingAnalysis.suggestedSubtitle
            )
            stage = .complete
            return
        }

        // Need to generate analysis
        guard let plan = session.plan else {
            currentError = .notFound(what: "Plan")
            stage = .error
            return
        }

        stage = .analyzing

        do {
            // Convert current session transcript to TranscriptEntry format
            var transcript = session.utterances.map { utterance in
                TranscriptEntry(
                    speaker: utterance.speaker,
                    text: utterance.text,
                    timestamp: utterance.timestamp,
                    isFinal: true
                )
            }

            // If this is a follow-up, prepend the original session's transcript
            if plan.isFollowUp, let previousSessionId = plan.previousSessionId {
                if let previousTranscript = await fetchPreviousTranscript(sessionId: previousSessionId) {
                    // Combine: original first, then follow-up
                    transcript = previousTranscript + transcript
                    log("Combined transcripts: \(previousTranscript.count) original + \(session.utterances.count) follow-up entries")
                }
            }

            // Get notes from coordinator, falling back to persisted notes from session
            var notes = await AgentCoordinator.shared.getFinalNotes()
            if notes == .empty, let persistedNotes = session.notesState {
                // Include ALL fields - sectionCoverage and quotableLines are critical for analysis quality
                notes = NotesState(
                    keyIdeas: persistedNotes.keyIdeas,
                    stories: persistedNotes.stories,
                    claims: persistedNotes.claims,
                    gaps: persistedNotes.gaps,
                    contradictions: persistedNotes.contradictions,
                    possibleTitles: persistedNotes.possibleTitles,
                    sectionCoverage: persistedNotes.sectionCoverage,
                    quotableLines: persistedNotes.quotableLines
                )
            }

            // Generate analysis
            let newAnalysis = try await AgentCoordinator.shared.analyzeInterview(
                transcript: transcript,
                notes: notes,
                plan: plan.toSnapshot()
            )

            // Save to SwiftData
            await MainActor.run {
                let model = AnalysisSummaryModel(
                    researchGoal: newAnalysis.researchGoal,
                    mainClaims: newAnalysis.mainClaims,
                    themes: newAnalysis.themes,
                    tensions: newAnalysis.tensions,
                    quotes: newAnalysis.quotes,
                    suggestedTitle: newAnalysis.suggestedTitle,
                    suggestedSubtitle: newAnalysis.suggestedSubtitle
                )
                session.analysis = model
                do {
                    try modelContext.save()
                } catch {
                    log("Failed to save analysis: \(error.localizedDescription)")
                }

                analysis = newAnalysis
                stage = .complete
            }
        } catch {
            await MainActor.run {
                currentError = AppError.from(error, context: .analysisGeneration)
                stage = .error
            }
        }
    }

    private func navigateToDraft(session: InterviewSession) {
        // Store the selected style in AppState or pass it via navigation
        appState.selectedDraftStyle = selectedStyle
        appState.currentAnalysis = analysis
        appState.navigate(to: .draft(sessionId: session.id))
    }

    private func fetchPreviousTranscript(sessionId: UUID) async -> [TranscriptEntry]? {
        // Fetch the previous session from SwiftData
        let descriptor = FetchDescriptor<InterviewSession>(
            predicate: #Predicate { $0.id == sessionId }
        )

        do {
            let sessions = try modelContext.fetch(descriptor)
            guard let previousSession = sessions.first else {
                log("Previous session not found: \(sessionId.uuidString)")
                return nil
            }

            return previousSession.utterances
                .sorted { $0.timestamp < $1.timestamp }
                .map { utterance in
                    TranscriptEntry(
                        speaker: utterance.speaker,
                        text: utterance.text,
                        timestamp: utterance.timestamp,
                        isFinal: true
                    )
                }
        } catch {
            log("Failed to fetch previous session: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth, currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
