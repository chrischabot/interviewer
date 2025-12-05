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

    var body: some View {
        ZStack {
            // Background blur
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            // Content card
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
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 20)
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
    @State private var isGenerating = false
    @State private var generationStage: PlanGenerationStage = .idle
    @State private var errorMessage: String?
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
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
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
                    Button {
                        appState.navigate(to: .planning(planId: plan.id))
                    } label: {
                        HStack {
                            Text(plan.topic)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            Text(plan.createdAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 500)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }

    // MARK: - Actions

    private func generatePlan() {
        isGenerating = true
        generationStage = .analyzing
        errorMessage = nil
        isInputFocused = false

        Task {
            do {
                // Stage 1: Analyzing topic
                try await Task.sleep(for: .milliseconds(300))
                await MainActor.run { generationStage = .designing }

                // Stage 2: Designing structure (API call happens here)
                let response = try await AgentCoordinator.shared.generatePlan(
                    topic: topic,
                    context: "",
                    targetMinutes: 10
                )

                // Stage 3: Generating questions
                await MainActor.run { generationStage = .generating }
                try await Task.sleep(for: .milliseconds(200))

                // Convert response to SwiftData model
                let plan = response.toPlan(
                    topic: topic,
                    targetSeconds: 10 * 60
                )

                // Stage 4: Finalizing
                await MainActor.run { generationStage = .finalizing }
                try await Task.sleep(for: .milliseconds(200))

                // Save to SwiftData
                await MainActor.run {
                    modelContext.insert(plan)
                    try? modelContext.save()

                    // Navigate to plan editor
                    appState.navigate(to: .planning(planId: plan.id))

                    // Clear form
                    topic = ""
                    isGenerating = false
                    generationStage = .idle
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
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
        try? modelContext.save()
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
    @State private var sessionManager = InterviewSessionManager()
    @State private var showEndConfirmation = false
    @State private var savedSessionId: UUID?

    private var plan: Plan? {
        plans.first { $0.id == planId }
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
                    Button("End") {
                        showEndConfirmation = true
                    }
                    .foregroundStyle(.red)
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
        .alert("Error", isPresented: .init(
            get: { sessionManager.errorMessage != nil },
            set: { if !$0 { sessionManager.errorMessage = nil } }
        )) {
            Button("OK") { sessionManager.errorMessage = nil }
        } message: {
            Text(sessionManager.errorMessage ?? "An unknown error occurred")
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
                    await sessionManager.startSession(plan: plan)
                }
            }
        }
    }

    // MARK: - Timer Header

    private var timerHeader: some View {
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
        }
        .padding()
        .background(.bar)
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
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: sessionManager.transcript.count) { _, _ in
                    if let lastEntry = sessionManager.transcript.filter({ $0.speaker == "assistant" }).last {
                        withAnimation {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: sessionManager.transcript.last?.text) { _, _ in
                    // Also scroll when text updates (streaming)
                    if let lastEntry = sessionManager.transcript.filter({ $0.speaker == "assistant" }).last {
                        withAnimation {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Controls
            interviewControls
        }
    }

    private var interviewControls: some View {
        HStack(spacing: 16) {
            // Status indicator - Yellow when mic is muted, Green when listening
            HStack(spacing: 8) {
                Circle()
                    .fill(sessionManager.isMicMuted ? Color.yellow : Color.green)
                    .frame(width: 10, height: 10)
                Text(sessionManager.isMicMuted ? "Mic Off" : (sessionManager.isUserSpeaking ? "Listening..." : "Ready"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

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
        .padding()
        .background(.bar)
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

        // Save notes state
        let notesModel = NotesStateModel()
        notesModel.keyIdeas = sessionManager.currentNotes.keyIdeas
        notesModel.stories = sessionManager.currentNotes.stories
        notesModel.claims = sessionManager.currentNotes.claims
        notesModel.gaps = sessionManager.currentNotes.gaps
        notesModel.contradictions = sessionManager.currentNotes.contradictions
        notesModel.possibleTitles = sessionManager.currentNotes.possibleTitles
        session.notesState = notesModel

        await MainActor.run {
            modelContext.insert(session)
            try? modelContext.save()
            savedSessionId = session.id
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
