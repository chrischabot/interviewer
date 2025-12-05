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
    @State private var errorMessage: String?
    @State private var selectedStyle: DraftStyle = .standard

    private var session: InterviewSession? {
        sessions.first { $0.id == sessionId }
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
        .alert("Analysis Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Retry") {
                Task { await loadOrGenerateAnalysis() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
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
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Analysis Failed")
                .font(.headline)

            Text(errorMessage ?? "Unknown error")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await loadOrGenerateAnalysis() }
            }
            .buttonStyle(.borderedProminent)
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
            errorMessage = "No plan associated with this session"
            stage = .error
            return
        }

        stage = .analyzing

        do {
            // Convert transcript to TranscriptEntry format
            let transcript = session.utterances.map { utterance in
                TranscriptEntry(
                    speaker: utterance.speaker,
                    text: utterance.text,
                    timestamp: utterance.timestamp,
                    isFinal: true
                )
            }

            // Get notes from coordinator or create empty
            let notes = await AgentCoordinator.shared.getFinalNotes()

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
                try? modelContext.save()

                analysis = newAnalysis
                stage = .complete
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
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
