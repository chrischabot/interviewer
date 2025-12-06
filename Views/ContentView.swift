import SwiftUI
import SwiftData

// MARK: - Plan Generation Stage

enum PlanGenerationStage: CaseIterable {
    case idle
    case analyzing
    case designing
    case generating
    case finalizing

    var title: String {
        switch self {
        case .idle: return ""
        case .analyzing: return "Analyzing Topic"
        case .designing: return "Designing Structure"
        case .generating: return "Generating Questions"
        case .finalizing: return "Finalizing Plan"
        }
    }

    var description: String {
        switch self {
        case .idle: return ""
        case .analyzing: return "Understanding your topic and context..."
        case .designing: return "Creating research goal and story arc..."
        case .generating: return "Crafting interview questions..."
        case .finalizing: return "Preparing your plan for review..."
        }
    }

    var icon: String {
        switch self {
        case .idle: return "circle"
        case .analyzing: return "magnifyingglass"
        case .designing: return "rectangle.3.group"
        case .generating: return "text.bubble"
        case .finalizing: return "checkmark.circle"
        }
    }

    var progress: Double {
        switch self {
        case .idle: return 0
        case .analyzing: return 0.2
        case .designing: return 0.5
        case .generating: return 0.8
        case .finalizing: return 0.95
        }
    }
}

// MARK: - Plan Generation Overlay

struct PlanGenerationOverlay: View {
    let stage: PlanGenerationStage

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GlassOverlay {
            GlassPanel(cornerRadius: 20, padding: 32) {
                VStack(spacing: 24) {
                    // Animated icon
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.1))
                            .frame(width: 80, height: 80)

                        Image(systemName: stage.icon)
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    .accessibilityHidden(true)

                    // Stage info
                    VStack(spacing: 8) {
                        Text(stage.title)
                            .font(.headline)

                        Text(stage.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Progress bar
                    VStack(spacing: 8) {
                        ProgressView(value: stage.progress)
                            .progressViewStyle(.linear)
                            .tint(.blue)

                        // Stage indicators
                        HStack(spacing: 0) {
                            ForEach(Array(PlanGenerationStage.allCases.dropFirst().enumerated()), id: \.offset) { index, s in
                                Circle()
                                    .fill(stageCompleted(s) ? Color.blue : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)

                                if index < 3 {
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(width: 200)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Generating interview plan")
            .accessibilityValue("\(stage.title). \(stage.description). \(Int(stage.progress * 100)) percent complete")
            .accessibilityAddTraits(.updatesFrequently)
        }
        .animation(.easeInOut(duration: 0.3), value: stage)
    }

    private func stageCompleted(_ s: PlanGenerationStage) -> Bool {
        s.progress <= stage.progress
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var appState = appState

        NavigationStack(path: $appState.navigationPath) {
            HomeView()
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .home:
                        HomeView()
                    case .planning(let planId):
                        PlanEditorView(planId: planId)
                    case .interview(let planId):
                        InterviewView(planId: planId)
                    case .analysis(let sessionId):
                        AnalysisView(sessionId: sessionId)
                    case .draft(let sessionId):
                        DraftView(sessionId: sessionId)
                    case .followUp(let sessionId):
                        FollowUpView(sessionId: sessionId)
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .sheet(isPresented: $appState.showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            if appState.hasAPIKey {
                                Button("Done") {
                                    appState.showSettings = false
                                }
                            }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
        }
        .overlay {
            if appState.isCheckingAPIKey {
                ProgressView("Checking API key...")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Plan.createdAt, order: .reverse) private var recentPlans: [Plan]

    @State private var topic = ""
    @State private var context = ""
    @State private var durationMinutes: Double = 14
    @State private var showAdvancedOptions = false
    @State private var isGenerating = false
    @State private var generationStage: PlanGenerationStage = .idle
    @State private var currentError: AppError?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Main input area - centered
            VStack(spacing: 32) {
                // Prompt
                Text("What do you want to talk about?")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                // Input box
                HStack(spacing: 12) {
                    TextField("Enter a topic...", text: $topic, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                        .disabled(isGenerating)
                        .onSubmit {
                            if !topic.isEmpty && appState.hasAPIKey && !isGenerating {
                                generatePlan()
                            }
                        }

                    // Send button
                    Button {
                        generatePlan()
                    } label: {
                        Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(canSubmit ? Color.accentColor : Color.gray.opacity(0.3))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .accessibilityLabel(isGenerating ? "Stop generating" : "Generate interview plan")
                    .accessibilityHint(canSubmit ? "Double tap to generate an interview plan for this topic" : "Enter a topic first")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.primary.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                )
                .frame(maxWidth: 600)

                // Advanced options toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAdvancedOptions.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Options")
                            .font(.caption)
                        Image(systemName: showAdvancedOptions ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                // Advanced options
                if showAdvancedOptions {
                    VStack(spacing: 16) {
                        // Duration slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Duration")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(durationMinutes)) minutes")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.primary)
                            }

                            Slider(value: $durationMinutes, in: 5...20, step: 1)
                                .tint(.accentColor)
                                .accessibilityLabel("Interview duration")
                                .accessibilityValue("\(Int(durationMinutes)) minutes")
                        }

                        // Context field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Additional context (optional)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            TextField("e.g., Focus on technical challenges, my experience is in...", text: $context, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.callout)
                                .lineLimit(2...4)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.primary.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                        )
                                )
                        }
                    }
                    .frame(maxWidth: 600)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Recent plans - compact footer
            if !recentPlans.isEmpty {
                recentPlansFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.showSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .errorAlert($currentError) { action in
            switch action {
            case .retry:
                generatePlan()
            case .openSettings:
                appState.showSettings = true
            default:
                break
            }
        }
        .overlay {
            if isGenerating {
                PlanGenerationOverlay(stage: generationStage)
            }
        }
    }

    private var canSubmit: Bool {
        !topic.isEmpty && appState.hasAPIKey && !isGenerating
    }

    private var recentPlansFooter: some View {
        VStack(spacing: 16) {
            Text("Recent conversations")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(recentPlans.prefix(5)) { plan in
                    RecentConversationRow(
                        plan: plan,
                        hasCompletedSession: hasCompletedSession(for: plan),
                        onResume: {
                            startFollowUp(for: plan)
                        },
                        onAnalysis: {
                            goToAnalysis(for: plan)
                        },
                        onFresh: {
                            appState.navigate(to: .planning(planId: plan.id))
                        }
                    )
                }
            }
            .frame(maxWidth: 500)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }

    private func hasCompletedSession(for plan: Plan) -> Bool {
        let planId = plan.id
        let descriptor = FetchDescriptor<InterviewSession>(
            predicate: #Predicate { session in
                session.plan?.id == planId && session.endedAt != nil
            }
        )
        do {
            let sessions = try modelContext.fetch(descriptor)
            return !sessions.isEmpty
        } catch {
            return false
        }
    }

    private func startFollowUp(for plan: Plan) {
        // Find the most recent completed session for this plan
        let planId = plan.id
        let descriptor = FetchDescriptor<InterviewSession>(
            predicate: #Predicate { session in
                session.plan?.id == planId && session.endedAt != nil
            },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )

        do {
            let sessions = try modelContext.fetch(descriptor)
            if let lastSession = sessions.first {
                // Navigate to follow-up flow
                appState.navigate(to: .followUp(sessionId: lastSession.id))
            } else {
                // No completed session, just go to planning
                appState.navigate(to: .planning(planId: plan.id))
            }
        } catch {
            StructuredLogger.log(component: "HomeView", message: "Failed to fetch sessions: \(error.localizedDescription)")
            appState.navigate(to: .planning(planId: plan.id))
        }
    }

    private func goToAnalysis(for plan: Plan) {
        // Find the most recent completed session for this plan and go to analysis
        let planId = plan.id
        let descriptor = FetchDescriptor<InterviewSession>(
            predicate: #Predicate { session in
                session.plan?.id == planId && session.endedAt != nil
            },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )

        do {
            let sessions = try modelContext.fetch(descriptor)
            if let lastSession = sessions.first {
                appState.navigate(to: .analysis(sessionId: lastSession.id))
            }
        } catch {
            StructuredLogger.log(component: "HomeView", message: "Failed to fetch sessions for analysis: \(error.localizedDescription)")
        }
    }

    // MARK: - Actions

    private func generatePlan() {
        isGenerating = true
        generationStage = .analyzing
        currentError = nil
        isInputFocused = false

        Task {
            do {
                // Stage 1: Analyzing topic
                try await Task.sleep(for: .milliseconds(300))
                await MainActor.run { generationStage = .designing }

                // Stage 2: Designing structure (API call happens here)
                let targetMinutes = Int(durationMinutes)
                let response = try await AgentCoordinator.shared.generatePlan(
                    topic: topic,
                    context: context,
                    targetMinutes: targetMinutes
                )

                // Stage 3: Generating questions
                await MainActor.run { generationStage = .generating }
                try await Task.sleep(for: .milliseconds(200))

                // Convert response to SwiftData model
                let plan = response.toPlan(
                    topic: topic,
                    targetSeconds: targetMinutes * 60
                )

                // Stage 4: Finalizing
                await MainActor.run { generationStage = .finalizing }
                try await Task.sleep(for: .milliseconds(200))

                // Save to SwiftData
                await MainActor.run {
                    modelContext.insert(plan)
                    do {
                        try modelContext.save()
                    } catch {
                        StructuredLogger.log(component: "HomeView", message: "Failed to save plan: \(error.localizedDescription)")
                    }

                    // Navigate to plan editor
                    appState.navigate(to: .planning(planId: plan.id))

                    // Clear form
                    topic = ""
                    context = ""
                    durationMinutes = 14
                    showAdvancedOptions = false
                    isGenerating = false
                    generationStage = .idle
                }
            } catch {
                await MainActor.run {
                    currentError = AppError.from(error, context: .planGeneration)
                    isGenerating = false
                    generationStage = .idle
                }
            }
        }
    }
}

// MARK: - Row Views

struct SessionRowView: View {
    let session: InterviewSession

    var body: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.plan?.topic ?? "Untitled Session")
                        .font(.headline)

                    Text(session.startedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.formattedDuration)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if session.isCompleted {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("In Progress", systemImage: "circle.dashed")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct PlanRowView: View {
    let plan: Plan
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.topic)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(plan.researchGoal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(plan.sections.count) sections")
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Text(plan.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plan Editor View

struct PlanEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let planId: UUID

    @Query private var plans: [Plan]

    private var plan: Plan? {
        plans.first { $0.id == planId }
    }

    var body: some View {
        Group {
            if let plan {
                planContent(plan)
            } else {
                ContentUnavailableView(
                    "Plan Not Found",
                    systemImage: "doc.questionmark",
                    description: Text("The requested plan could not be found.")
                )
            }
        }
        .navigationTitle("Edit Plan")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func planContent(_ plan: Plan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Topic Header
                topicHeader(plan)

                // Research Goal
                EditableFieldSection(
                    label: "Research Goal",
                    icon: "target",
                    text: Binding(
                        get: { plan.researchGoal },
                        set: { plan.researchGoal = $0 }
                    )
                )

                // Angle
                EditableFieldSection(
                    label: "Angle",
                    icon: "lightbulb",
                    text: Binding(
                        get: { plan.angle },
                        set: { plan.angle = $0 }
                    )
                )

                // Time Budget
                timeBudgetSection(plan)

                // Sections
                sectionsSection(plan)

                // Action Buttons
                actionButtons(plan)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Start Interview") {
                    startInterview(plan)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Sections

    private func topicHeader(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Topic")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(plan.topic)
                .font(.title2)
                .fontWeight(.bold)
        }
    }

    private func timeBudgetSection(_ plan: Plan) -> some View {
        GroupBox {
            HStack {
                Label("Total Time", systemImage: "clock")
                    .font(.headline)

                Spacer()

                Text("\(plan.targetSeconds / 60) min")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func sectionsSection(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interview Sections")
                .font(.title3)
                .fontWeight(.semibold)

            ForEach(plan.sections.sorted(by: { $0.sortOrder < $1.sortOrder })) { section in
                SectionEditorView(section: section)
            }
        }
    }

    private func actionButtons(_ plan: Plan) -> some View {
        HStack {
            Button(role: .destructive) {
                deletePlan(plan)
            } label: {
                Label("Delete Plan", systemImage: "trash")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.top, 20)
    }

    // MARK: - Actions

    private func startInterview(_ plan: Plan) {
        appState.navigate(to: .interview(planId: plan.id))
    }

    private func deletePlan(_ plan: Plan) {
        modelContext.delete(plan)
        do {
            try modelContext.save()
        } catch {
            StructuredLogger.log(component: "PlanEditorView", message: "Failed to delete plan: \(error.localizedDescription)")
        }
        appState.navigateBack()
    }
}

// MARK: - Editable Field Section

struct EditableFieldSection: View {
    let label: String
    let icon: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(label, systemImage: icon)
                    .font(.headline)

                TextField(label, text: $text, axis: .vertical)
                    .lineLimit(2...6)
                    .padding(4)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(isFocused ? Color.accentColor : Color.primary.opacity(0.08))
                            .frame(height: 1)
                            .padding(.horizontal, 4)
                    }
                    .focused($isFocused)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Section Editor

struct SectionEditorView: View {
    @Bindable var section: Section

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Section Header with controls
                HStack(spacing: 12) {
                    // Editable title
                    EditableSectionTitle(text: $section.title)

                    Spacer()

                    // Importance toggle (cycles on tap)
                    ImportanceToggle(importance: $section.importance)

                    // Time stepper
                    TimeStepper(seconds: $section.estimatedSeconds)
                }

                // Questions
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(section.questions.sorted(by: { $0.sortOrder < $1.sortOrder })) { question in
                        QuestionRowView(question: question)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Editable Section Title

struct EditableSectionTitle: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Section title", text: $text)
            .font(.headline)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isFocused ? Color.accentColor : Color.primary.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 2)
            }
            .focused($isFocused)
    }
}

// MARK: - Importance Toggle

struct ImportanceToggle: View {
    @Binding var importance: String

    private var color: Color {
        switch importance {
        case "high": return .red
        case "medium": return .orange
        default: return .gray
        }
    }

    var body: some View {
        Button {
            cycleImportance()
        } label: {
            Text(importance.capitalized)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func cycleImportance() {
        switch importance {
        case "low": importance = "medium"
        case "medium": importance = "high"
        default: importance = "low"
        }
    }
}

// MARK: - Time Stepper

struct TimeStepper: View {
    @Binding var seconds: Int

    private var minutes: Int {
        seconds / 60
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if seconds > 60 {
                    seconds -= 60
                }
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text("\(minutes)m")
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(minWidth: 28)

            Button {
                seconds += 60
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Question Row

struct QuestionRowView: View {
    @Bindable var question: Question
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Role indicator dot
            Circle()
                .fill(question.role == "backbone" ? Color.blue : Color.gray.opacity(0.4))
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            // Editable question text
            VStack(alignment: .leading, spacing: 4) {
                TextField("Question", text: $question.text, axis: .vertical)
                    .font(.subheadline)
                    .focused($isFocused)

                if !question.notesForInterviewer.isEmpty {
                    Text(question.notesForInterviewer)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
        .padding(.leading, 4)
    }
}

// MARK: - Interview View

struct InterviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let planId: UUID

    @Query private var plans: [Plan]
    @Query private var sessions: [InterviewSession]
    @State private var sessionManager = InterviewSessionManager()
    @State private var showEndConfirmation = false
    @State private var savedSessionId: UUID?

    private var plan: Plan? {
        plans.first { $0.id == planId }
    }

    /// Find the previous session if this is a follow-up plan
    private var previousSession: InterviewSession? {
        guard let plan, plan.isFollowUp, let previousId = plan.previousSessionId else {
            return nil
        }
        return sessions.first { $0.id == previousId }
    }

    var body: some View {
        Group {
            if let plan {
                interviewContent(plan)
            } else {
                ContentUnavailableView(
                    "Plan Not Found",
                    systemImage: "doc.questionmark",
                    description: Text("The requested plan could not be found.")
                )
            }
        }
        .navigationTitle("Interview")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(sessionManager.state == .active || sessionManager.state == .paused)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if sessionManager.state == .active || sessionManager.state == .paused {
                    if sessionManager.hasDetectedClosing {
                        // Interview naturally concluded - show Next button
                        Button {
                            Task {
                                await endAndSaveSession()
                            }
                        } label: {
                            Label("Next", systemImage: "arrow.right")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        // Still active - show End button
                        Button("End") {
                            showEndConfirmation = true
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .confirmationDialog("End Interview?", isPresented: $showEndConfirmation) {
            Button("End Interview", role: .destructive) {
                Task {
                    await endAndSaveSession()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end the interview session. You can review the transcript afterwards.")
        }
        .errorAlert(Binding(
            get: { sessionManager.errorMessage.map { AppError.from(GenericError(message: $0), context: .interviewConnection) } },
            set: { if $0 == nil { sessionManager.errorMessage = nil } }
        )) { action in
            switch action {
            case .retry, .reconnect:
                if let plan {
                    Task {
                        await sessionManager.startSession(plan: plan)
                    }
                }
            case .openSettings:
                appState.showSettings = true
            default:
                break
            }
        }
    }

    @ViewBuilder
    private func interviewContent(_ plan: Plan) -> some View {
        VStack(spacing: 0) {
            // Timer header
            timerHeader

            Divider()

            // Main content
            switch sessionManager.state {
            case .idle, .connecting:
                connectingScreen
            case .active, .paused:
                activeInterviewView
            case .ending:
                endingScreen
            case .ended:
                endedScreen
            }
        }
        .onAppear {
            // Auto-start session when view appears
            if sessionManager.state == .idle {
                Task {
                    // Pass previous session for follow-ups to preserve context
                    await sessionManager.startSession(plan: plan, previousSession: previousSession)
                }
            }
        }
        .onChange(of: sessionManager.state) { oldState, newState in
            // Handle auto-end: when state changes from active to ended (not via manual end button)
            if oldState == .active && newState == .ended && savedSessionId == nil {
                Task {
                    await saveSessionAfterAutoEnd()
                }
            }
        }
    }

    private func saveSessionAfterAutoEnd() async {
        // Save session to SwiftData after auto-end
        guard let plan else { return }

        let session = InterviewSession(
            startedAt: Date().addingTimeInterval(-Double(sessionManager.elapsedSeconds)),
            endedAt: Date(),
            elapsedSeconds: sessionManager.elapsedSeconds,
            plan: plan
        )

        // Save transcript as utterances
        for entry in sessionManager.transcript {
            let utterance = Utterance(
                speaker: entry.speaker,
                text: entry.text,
                timestamp: entry.timestamp
            )
            utterance.session = session
            session.utterances.append(utterance)
        }

        // Save notes state (including sectionCoverage and quotableLines for analysis)
        let notesModel = NotesStateModel()
        notesModel.keyIdeas = sessionManager.currentNotes.keyIdeas
        notesModel.stories = sessionManager.currentNotes.stories
        notesModel.claims = sessionManager.currentNotes.claims
        notesModel.gaps = sessionManager.currentNotes.gaps
        notesModel.contradictions = sessionManager.currentNotes.contradictions
        notesModel.possibleTitles = sessionManager.currentNotes.possibleTitles
        notesModel.sectionCoverage = sessionManager.currentNotes.sectionCoverage
        notesModel.quotableLines = sessionManager.currentNotes.quotableLines
        session.notesState = notesModel

        await MainActor.run {
            modelContext.insert(session)
            do {
                try modelContext.save()
            } catch {
                StructuredLogger.log(component: "InterviewView", message: "Failed to save session: \(error.localizedDescription)")
            }
            savedSessionId = session.id
        }
    }

    // MARK: - Timer Header

    private var timerHeader: some View {
        GlassToolbar {
            HStack(spacing: 12) {
                // Voice orb - shows AI state
                VoiceOrbView(
                    audioLevel: sessionManager.assistantAudioLevel,
                    isActive: sessionManager.isAssistantSpeaking,
                    isListening: sessionManager.isUserSpeaking
                )

                // Topic title
                if let topic = plan?.topic {
                    Text(topic)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                // Countdown timer
                Text(sessionManager.formattedCountdownTime)
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(sessionManager.isOvertime ? .red : .primary)
                    .accessibilityLabel("Time remaining")
                    .accessibilityValue(sessionManager.isOvertime ? "Overtime by \(sessionManager.formattedCountdownTime)" : "\(sessionManager.formattedCountdownTime) remaining")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interview status")
    }

    // MARK: - Connecting Screen

    private var connectingScreen: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Connecting...")
                .font(.headline)

            Text("Setting up your interview session")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Active Interview

    private var activeInterviewView: some View {
        VStack(spacing: 0) {
            // Transcript - only show assistant entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(sessionManager.transcript.filter { $0.speaker == "assistant" }) { entry in
                            InterviewerTextBox(entry: entry)
                                .id(entry.id)
                        }

                        // Invisible anchor at the bottom for reliable scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("transcript-bottom-anchor")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: sessionManager.transcript.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: sessionManager.transcript.last?.text) { _, _ in
                    // Also scroll when text updates (streaming)
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            // Controls
            interviewControls
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("transcript-bottom-anchor", anchor: .bottom)
            }
        }
    }

    private var interviewControls: some View {
        GlassToolbar {
            HStack(spacing: 16) {
                // Status indicator - Yellow when mic is muted, Green when listening
                HStack(spacing: 8) {
                    Circle()
                        .fill(sessionManager.isMicMuted ? Color.yellow : Color.green)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(sessionManager.isMicMuted ? "Mic Off" : (sessionManager.isUserSpeaking ? "Listening..." : "Ready"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Microphone status")
                .accessibilityValue(sessionManager.isMicMuted ? "Microphone is muted" : (sessionManager.isUserSpeaking ? "Listening to you" : "Ready to listen"))

                Spacer()

                // Pause/Resume button
                Button {
                    Task {
                        if sessionManager.state == .active {
                            await sessionManager.pauseSession()
                        } else {
                            await sessionManager.resumeSession()
                        }
                    }
                } label: {
                    Image(systemName: sessionManager.state == .paused ? "play.fill" : "pause.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Ending Screen

    private var endingScreen: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Ending Session...")
                .font(.headline)

            Spacer()
        }
    }

    // MARK: - Ended Screen

    private var endedScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Interview Complete")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                Text("Duration: \(sessionManager.formattedElapsedTime)")
                Text("\(sessionManager.transcript.count) exchanges")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let sessionId = savedSessionId {
                Button {
                    // Store notes in coordinator before navigating
                    Task {
                        await AgentCoordinator.shared.storeNotes(sessionManager.currentNotes)
                    }
                    appState.navigate(to: .analysis(sessionId: sessionId))
                } label: {
                    Label("Continue to Analysis", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Back to Plan") {
                    appState.navigateBack()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Session Management

    private func endAndSaveSession() async {
        await sessionManager.endSession()

        // Save session to SwiftData
        guard let plan else { return }

        let session = InterviewSession(
            startedAt: Date().addingTimeInterval(-Double(sessionManager.elapsedSeconds)),
            endedAt: Date(),
            elapsedSeconds: sessionManager.elapsedSeconds,
            plan: plan
        )

        // Save transcript as utterances
        for entry in sessionManager.transcript {
            let utterance = Utterance(
                speaker: entry.speaker,
                text: entry.text,
                timestamp: entry.timestamp
            )
            utterance.session = session
            session.utterances.append(utterance)
        }

        // Save notes state (including sectionCoverage and quotableLines for analysis)
        let notesModel = NotesStateModel()
        notesModel.keyIdeas = sessionManager.currentNotes.keyIdeas
        notesModel.stories = sessionManager.currentNotes.stories
        notesModel.claims = sessionManager.currentNotes.claims
        notesModel.gaps = sessionManager.currentNotes.gaps
        notesModel.contradictions = sessionManager.currentNotes.contradictions
        notesModel.possibleTitles = sessionManager.currentNotes.possibleTitles
        notesModel.sectionCoverage = sessionManager.currentNotes.sectionCoverage
        notesModel.quotableLines = sessionManager.currentNotes.quotableLines
        session.notesState = notesModel

        await MainActor.run {
            modelContext.insert(session)
            do {
                try modelContext.save()
            } catch {
                StructuredLogger.log(component: "InterviewView", message: "Failed to save session: \(error.localizedDescription)")
            }
            savedSessionId = session.id

            // Store notes and navigate to analysis
            Task {
                await AgentCoordinator.shared.storeNotes(sessionManager.currentNotes)
            }
            appState.navigate(to: .analysis(sessionId: session.id))
        }
    }
}

// MARK: - Interviewer Text Box

struct InterviewerTextBox: View {
    let entry: TranscriptEntry

    var body: some View {
        Text(entry.text)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            )
            .opacity(entry.isFinal ? 1.0 : 0.8)
    }
}

// MARK: - Speaking Indicator

struct SpeakingIndicator: View {
    let speaker: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .opacity(isActive ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever()
                        .delay(Double(i) * 0.15),
                        value: isActive
                    )
            }

            Text(speaker)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1), in: Capsule())
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    let isOvertime: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 4)

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    isOvertime ? Color.red : Color.blue,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if isOvertime {
                Image(systemName: "exclamationmark")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
        }
    }
}


// MARK: - Recent Conversation Row

struct RecentConversationRow: View {
    let plan: Plan
    let hasCompletedSession: Bool
    let onResume: () -> Void
    let onAnalysis: () -> Void
    let onFresh: () -> Void

    var body: some View {
        HStack {
            Text(plan.topic)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            // Follow-up button - continue the conversation
            Button {
                onResume()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue conversation")
            .accessibilityHint("Pick up where you left off with follow-up questions")
            .disabled(!hasCompletedSession)
            .opacity(hasCompletedSession ? 1.0 : 0.3)

            // Analysis button - jump to analysis view
            Button {
                onAnalysis()
            } label: {
                Image(systemName: "doc.richtext")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View analysis")
            .accessibilityHint("Jump to the analysis screen with key points, tensions, and writing style selection")
            .disabled(!hasCompletedSession)
            .opacity(hasCompletedSession ? 1.0 : 0.3)

            // New conversation button - view/edit the plan and start fresh
            Button {
                onFresh()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start new conversation")
            .accessibilityHint("Open the interview plan to start a fresh conversation")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

#Preview {
    ContentView()
        .environment(AppState.shared)
        .modelContainer(for: [
            Plan.self,
            Section.self,
            Question.self,
            InterviewSession.self,
            Utterance.self,
            NotesStateModel.self,
            AnalysisSummaryModel.self,
            Draft.self
        ], inMemory: true)
}
