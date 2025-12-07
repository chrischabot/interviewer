import SwiftUI
import SwiftData

// MARK: - Import Stage

enum YouTubeImportStage: Equatable {
    case idle
    case checkingDependencies
    case downloading(progress: Double)
    case downloadComplete(sizeMB: Double)
    case compressing(originalMB: Double)
    case transcribing
    case generatingPlan
    case extractingStyle
    case analyzing
    case complete(sessionId: UUID)
    case error(message: String)

    var title: String {
        switch self {
        case .idle: return "Import from YouTube"
        case .checkingDependencies: return "Checking Dependencies"
        case .downloading: return "Downloading Audio"
        case .downloadComplete: return "Download Complete"
        case .compressing: return "Compressing Audio"
        case .transcribing: return "Transcribing"
        case .generatingPlan: return "Analyzing Content"
        case .extractingStyle: return "Extracting Style"
        case .analyzing: return "Generating Analysis"
        case .complete: return "Import Complete"
        case .error: return "Import Failed"
        }
    }

    var description: String {
        switch self {
        case .idle: return "Paste a YouTube URL to import"
        case .checkingDependencies: return "Checking for yt-dlp and ffmpeg..."
        case .downloading(let progress): return "Downloading audio... \(Int(progress))%"
        case .downloadComplete(let sizeMB): return String(format: "Downloaded %.1f MB", sizeMB)
        case .compressing(let originalMB): return String(format: "File too large (%.0f MB), compressing for Whisper...", originalMB)
        case .transcribing: return "Transcribing audio with Whisper..."
        case .generatingPlan: return "Understanding the content structure..."
        case .extractingStyle: return "Learning your writing voice..."
        case .analyzing: return "Extracting insights and themes..."
        case .complete: return "Ready to view analysis"
        case .error(let message): return message
        }
    }

    var icon: String {
        switch self {
        case .idle: return "play.rectangle"
        case .checkingDependencies: return "gear"
        case .downloading: return "arrow.down.circle"
        case .downloadComplete: return "checkmark.circle"
        case .compressing: return "arrow.triangle.2.circlepath"
        case .transcribing: return "waveform"
        case .generatingPlan: return "doc.text.magnifyingglass"
        case .extractingStyle: return "person.text.rectangle"
        case .analyzing: return "sparkles"
        case .complete: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var isProcessing: Bool {
        switch self {
        case .idle, .complete, .error: return false
        default: return true
        }
    }
}

// MARK: - YouTube Import Sheet

struct YouTubeImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @Query(sort: \InterviewSession.endedAt, order: .reverse) private var allSessions: [InterviewSession]

    @State private var urlInput = ""
    @State private var stage: YouTubeImportStage = .idle
    @State private var completedSessionId: UUID?
    @State private var importTask: Task<Void, Never>?
    @State private var currentTempDirectory: URL?
    @State private var transcriptionStartTime: Date?

    private let youtubeDownloader = YouTubeDownloader.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Icon and stage info
                stageIndicator

                // URL input or progress
                if stage == .idle {
                    urlInputSection
                } else if case .error = stage {
                    errorSection
                } else if case .complete = stage {
                    completionSection
                } else {
                    progressSection
                }

                Spacer()
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Import from YouTube")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelAndCleanup()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                cancelAndCleanup()
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }

    // MARK: - Subviews

    private var stageIndicator: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(stageColor.opacity(0.1))
                    .frame(width: 80, height: 80)

                if stage.isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: stage.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(stageColor)
                }
            }

            VStack(spacing: 8) {
                Text(stage.title)
                    .font(.headline)

                Text(stage.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var stageColor: Color {
        switch stage {
        case .error: return .red
        case .complete: return .green
        default: return .blue
        }
    }

    private var urlInputSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                TextField("https://www.youtube.com/watch?v=...", text: $urlInput)
                    .textFieldStyle(.plain)
                    .font(.body)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif

                Button {
                    pasteFromClipboard()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Paste from clipboard")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 500)

            Button {
                startImport()
            } label: {
                Label("Import", systemImage: "arrow.down.circle")
                    .font(.headline)
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .disabled(urlInput.isEmpty || !YouTubeDownloader.shared.isValidYouTubeURL(urlInput))

            Text("Requires yt-dlp and ffmpeg installed via Homebrew")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 16) {
            if case .downloading(let progress) = stage {
                ProgressView(value: progress / 100)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
            }

            if case .transcribing = stage, let startTime = transcriptionStartTime {
                // Show elapsed timer during transcription
                TimelineView(.periodic(from: startTime, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(startTime)
                    let minutes = Int(elapsed) / 60
                    let seconds = Int(elapsed) % 60
                    Text(String(format: "Elapsed: %d:%02d", minutes, seconds))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Text(transcriptionHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var transcriptionHint: String {
        if case .transcribing = stage {
            return "Transcription can take 2-3 minutes for long videos..."
        }
        return "This may take a few minutes..."
    }

    private var errorSection: some View {
        VStack(spacing: 16) {
            if case .error(let message) = stage {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: 400)

                if message.contains("yt-dlp") {
                    VStack(spacing: 8) {
                        Text("Install with Homebrew:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("brew install yt-dlp ffmpeg")
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(.rect(cornerRadius: 8))
                    }
                }
            }

            Button("Try Again") {
                stage = .idle
            }
            .buttonStyle(.bordered)
        }
    }

    private var completionSection: some View {
        VStack(spacing: 16) {
            Text("Your video has been imported and analyzed.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                if let sessionId = completedSessionId {
                    dismiss()
                    appState.navigate(to: .analysis(sessionId: sessionId))
                }
            } label: {
                Label("View Analysis", systemImage: "arrow.right")
                    .font(.headline)
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        #if os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            urlInput = string
        }
        #else
        if let string = UIPasteboard.general.string {
            urlInput = string
        }
        #endif
    }

    private func startImport() {
        importTask = Task {
            await performImport()
        }
    }

    private func cancelAndCleanup() {
        // Cancel any running import task
        importTask?.cancel()
        importTask = nil

        // Clean up temp directory if we have one
        if let tempDir = currentTempDirectory {
            StructuredLogger.log(component: "YouTube Import", message: "Cleaning up cancelled import...")
            try? FileManager.default.removeItem(at: tempDir)
            currentTempDirectory = nil
        }

        // Kill any orphaned ffmpeg processes for our temp dirs
        // This is a best-effort cleanup
        let script = "pkill -f 'ffmpeg.*youtube_import' 2>/dev/null || true"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func performImport() async {
        let log = { (message: String) in
            StructuredLogger.log(component: "YouTube Import", message: message)
        }

        log("Starting import from: \(urlInput)")

        do {
            // Stage 1: Check dependencies
            await MainActor.run { stage = .checkingDependencies }
            log("Checking for yt-dlp and ffmpeg...")
            let deps = await youtubeDownloader.checkDependencies()

            if !deps.ytDlp {
                log("ERROR: yt-dlp not found")
                await MainActor.run { stage = .error(message: "yt-dlp not found. Install with: brew install yt-dlp") }
                return
            }
            if !deps.ffmpeg {
                log("ERROR: ffmpeg not found")
                await MainActor.run { stage = .error(message: "ffmpeg not found. Install with: brew install ffmpeg") }
                return
            }
            log("Dependencies OK: yt-dlp ✓, ffmpeg ✓")

            // Stage 2: Download audio
            log("Starting audio download...")
            var audioURL: URL?
            var lastLoggedPercent: Int = -10
            for try await progress in youtubeDownloader.downloadAudio(from: urlInput) {
                await MainActor.run {
                    switch progress {
                    case .checking:
                        stage = .checkingDependencies
                    case .downloading(let percent, let speed):
                        stage = .downloading(progress: percent)
                        // Log every 10% to avoid spam
                        let percentInt = Int(percent)
                        if percentInt >= lastLoggedPercent + 10 {
                            let speedStr = speed ?? "unknown"
                            log("Downloading: \(percentInt)% at \(speedStr)")
                            lastLoggedPercent = percentInt
                        }
                    case .extractingAudio:
                        stage = .downloading(progress: 99)
                        log("Extracting audio with ffmpeg...")
                    case .complete(let url):
                        audioURL = url
                        currentTempDirectory = url.deletingLastPathComponent()
                        log("Download complete: \(url.lastPathComponent)")
                    }
                }
            }

            guard var audioURL else {
                log("ERROR: No audio file produced")
                await MainActor.run { stage = .error(message: "Failed to download audio") }
                return
            }

            // Get file size for logging
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0
            let fileSizeMB = Double(fileSize) / 1_000_000
            log("Audio file ready: \(String(format: "%.1f", fileSizeMB)) MB")

            // Show download complete status
            await MainActor.run { stage = .downloadComplete(sizeMB: fileSizeMB) }

            // Compress if over 25MB (Whisper API limit)
            if fileSize > YouTubeDownloader.maxWhisperFileSize {
                await MainActor.run { stage = .compressing(originalMB: fileSizeMB) }
            }
            audioURL = try await youtubeDownloader.compressIfNeeded(audioURL: audioURL)

            // Stage 3: Transcribe with Whisper
            await MainActor.run {
                stage = .transcribing
                transcriptionStartTime = Date()
            }
            log("Sending to Whisper API for transcription...")
            let whisperResponse = try await OpenAIClient.shared.transcribeAudio(fileURL: audioURL)

            let durationStr = whisperResponse.duration.map { String(format: "%.0f", $0) + "s" } ?? "unknown"
            let wordCount = whisperResponse.text.split(separator: " ").count
            log("Transcription complete: \(wordCount) words, \(durationStr) duration")
            if let language = whisperResponse.language {
                log("Detected language: \(language)")
            }

            // Clean up the audio file
            youtubeDownloader.cleanup(audioURL: audioURL)
            log("Cleaned up temporary audio file")

            // Convert to transcript entries (speaker is "user" since it's the video creator talking)
            let transcript: [TranscriptEntry]
            if let segments = whisperResponse.segments {
                transcript = segments.map { segment in
                    TranscriptEntry(
                        speaker: "user",
                        text: segment.text.trimmingCharacters(in: .whitespaces),
                        timestamp: Date(timeIntervalSince1970: segment.start),
                        isFinal: true
                    )
                }
                log("Parsed \(segments.count) transcript segments")
            } else {
                // Fallback: single entry with full text
                transcript = [TranscriptEntry(
                    speaker: "user",
                    text: whisperResponse.text,
                    timestamp: Date(),
                    isFinal: true
                )]
                log("Using single transcript block (no segments)")
            }

            // Stage 4: Generate reverse plan
            await MainActor.run { stage = .generatingPlan }
            log("Generating interview plan from content...")
            let reversePlan = try await AgentCoordinator.shared.generateReversePlan(from: whisperResponse.text)
            log("Plan generated: \"\(reversePlan.topic)\" with \(reversePlan.sections.count) sections")
            log("Angle: \(reversePlan.angle)")

            // Stage 5: Extract style from past sessions
            await MainActor.run { stage = .extractingStyle }
            let styleInput = await buildStyleInput()
            log("Extracting voice style from \(styleInput.totalSamples) samples...")
            let styleGuide = try await AgentCoordinator.shared.extractVoiceStyle(from: styleInput)
            if styleGuide.hasContent {
                log("Style guide extracted: \(styleGuide.bullets.count) voice characteristics")
            } else {
                log("No past sessions for style extraction")
            }

            // Stage 6: Generate analysis
            await MainActor.run { stage = .analyzing }
            log("Running analysis agent...")
            let planSnapshot = reversePlan.toSnapshot()
            let analysis = try await AgentCoordinator.shared.analyzeInterview(
                transcript: transcript,
                notes: .empty,
                plan: planSnapshot
            )
            log("Analysis complete: \(analysis.mainClaims.count) claims, \(analysis.themes.count) themes, \(analysis.quotes.count) quotes")
            log("Suggested title: \"\(analysis.suggestedTitle)\"")

            // Create and save session
            await MainActor.run {
                log("Saving session to database...")
                let plan = reversePlan.toPlan()
                modelContext.insert(plan)

                let session = InterviewSession(
                    startedAt: Date(),
                    endedAt: Date(),
                    elapsedSeconds: Int(whisperResponse.duration ?? 0),
                    plan: plan,
                    sessionType: .imported,
                    sourceURL: urlInput
                )

                // Add utterances
                for entry in transcript {
                    let utterance = Utterance(
                        speaker: entry.speaker,
                        text: entry.text,
                        timestamp: entry.timestamp
                    )
                    utterance.session = session
                    session.utterances.append(utterance)
                }

                // Add analysis
                let analysisModel = AnalysisSummaryModel(
                    researchGoal: analysis.researchGoal,
                    suggestedTitle: analysis.suggestedTitle,
                    suggestedSubtitle: analysis.suggestedSubtitle
                )
                analysisModel.mainClaims = analysis.mainClaims
                analysisModel.themes = analysis.themes
                analysisModel.tensions = analysis.tensions
                analysisModel.quotes = analysis.quotes
                session.analysis = analysisModel

                modelContext.insert(session)

                do {
                    try modelContext.save()
                    completedSessionId = session.id
                    stage = .complete(sessionId: session.id)

                    // Store style guide for later use in writing
                    appState.importedStyleGuide = styleGuide

                    log("Import complete! Session ID: \(session.id)")
                } catch {
                    log("ERROR: Failed to save session: \(error.localizedDescription)")
                    stage = .error(message: "Failed to save session: \(error.localizedDescription)")
                }
            }

        } catch {
            log("ERROR: \(error.localizedDescription)")
            await MainActor.run {
                stage = .error(message: error.localizedDescription)
            }
        }
    }

    private func buildStyleInput() async -> StyleExtractionInput {
        // Get completed sessions with interviews (not imports)
        let completedSessions = allSessions.filter { session in
            session.isCompleted && !session.isImported
        }

        var draftExcerpts: [String] = []
        var quotableLines: [String] = []
        var userUtterances: [String] = []

        // Collect draft excerpts (up to 3, truncated)
        for session in completedSessions.prefix(5) {
            if let draft = session.drafts.first {
                let truncated = String(draft.markdownContent.prefix(8000))
                draftExcerpts.append(truncated)
            }
            if draftExcerpts.count >= 3 { break }
        }

        // Collect quotable lines from notes
        for session in completedSessions {
            guard let notes = session.notesState else { continue }
            for quote in notes.quotableLines where quote.strength != "good" {
                quotableLines.append(quote.text)
            }
        }
        quotableLines = Array(quotableLines.prefix(20))

        // Collect user utterances
        for session in completedSessions {
            for utterance in session.utterances where utterance.speaker == "user" {
                let wordCount = utterance.text.split(separator: " ").count
                if wordCount >= 10 {
                    userUtterances.append(utterance.text)
                }
            }
        }
        userUtterances = Array(userUtterances.prefix(30))

        return StyleExtractionInput(
            draftExcerpts: draftExcerpts,
            quotableLines: quotableLines,
            userUtterances: userUtterances
        )
    }
}

#Preview {
    YouTubeImportSheet()
        .environment(AppState.shared)
}
