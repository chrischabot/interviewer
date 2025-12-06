import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Draft Generation Stage

enum DraftGenerationStage: CaseIterable {
    case idle
    case loading
    case generating
    case complete
    case error

    var title: String {
        switch self {
        case .idle: return "Ready"
        case .loading: return "Loading Data"
        case .generating: return "Writing Essay"
        case .complete: return "Draft Ready"
        case .error: return "Error"
        }
    }

    var description: String {
        switch self {
        case .idle: return "Preparing to write your essay..."
        case .loading: return "Loading analysis and transcript..."
        case .generating: return "Crafting your blog post with style..."
        case .complete: return "Your essay is ready!"
        case .error: return "Something went wrong during writing."
        }
    }
}

// MARK: - Draft View

struct DraftView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let sessionId: UUID

    @Query private var sessions: [InterviewSession]

    @State private var stage: DraftGenerationStage = .idle
    @State private var markdownContent: String = ""
    @State private var currentError: AppError?
    @State private var showCopiedFeedback = false

    private var session: InterviewSession? {
        sessions.first { $0.id == sessionId }
    }

    private func log(_ message: String) {
        StructuredLogger.log(component: "DraftView", message: message)
    }

    var body: some View {
        Group {
            if let session {
                draftContent(session)
            } else {
                ContentUnavailableView(
                    "Session Not Found",
                    systemImage: "doc.questionmark",
                    description: Text("The requested session could not be found.")
                )
            }
        }
        .navigationTitle("Draft")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if stage == .complete {
                    Button {
                        copyToClipboard()
                    } label: {
                        Label(showCopiedFeedback ? "Copied!" : "Copy", systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel(showCopiedFeedback ? "Essay copied to clipboard" : "Copy essay to clipboard")
                    .accessibilityHint("Double tap to copy the essay markdown to your clipboard")

                    ShareLink(item: markdownContent) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share essay")
                    .accessibilityHint("Double tap to share the essay")
                }
            }
        }
        .task {
            await loadOrGenerateDraft()
        }
        .errorAlert($currentError) { action in
            switch action {
            case .retry:
                Task { await loadOrGenerateDraft() }
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
    private func draftContent(_ session: InterviewSession) -> some View {
        switch stage {
        case .idle, .loading, .generating:
            processingView
        case .complete:
            completeDraftView(session)
        case .error:
            errorView
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
        .accessibilityLabel("Essay generation in progress")
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

            Text(currentError?.errorDescription ?? "Draft Generation Failed")
                .font(.headline)

            Text(currentError?.recoverySuggestion ?? "Unknown error")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Try Again") {
                    Task { await loadOrGenerateDraft() }
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

    // MARK: - Complete Draft View

    @ViewBuilder
    private func completeDraftView(_ session: InterviewSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Style badge
                HStack {
                    Label(appState.selectedDraftStyle.displayName, systemImage: "paintbrush")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.1), in: Capsule())

                    Spacer()

                    Text(wordCount)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Markdown content with basic rendering
                MarkdownView(content: markdownContent)
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private var wordCount: String {
        let words = markdownContent.split { $0.isWhitespace || $0.isNewline }.count
        let readingMinutes = max(1, words / 200)
        return "\(words) words (\(readingMinutes) min read)"
    }

    private func copyToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = markdownContent
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdownContent, forType: .string)
        #endif

        showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedFeedback = false
        }
    }

    private func loadOrGenerateDraft() async {
        guard let session else { return }

        stage = .loading

        // Check if draft already exists with matching style
        let existingDraft = session.drafts.first { $0.style == appState.selectedDraftStyle.rawValue }
        if let existingDraft, !existingDraft.markdownContent.isEmpty {
            markdownContent = existingDraft.markdownContent
            stage = .complete
            return
        }

        // Need to generate draft
        guard let plan = session.plan else {
            currentError = .notFound(what: "Plan")
            stage = .error
            return
        }

        // Check for analysis
        guard let analysis = appState.currentAnalysis ?? loadAnalysisFromSession(session) else {
            currentError = .notFound(what: "Analysis")
            stage = .error
            return
        }

        stage = .generating

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

            // Check if this is a follow-up session and get previous transcript
            var previousTranscript: [TranscriptEntry]? = nil
            if plan.isFollowUp, let previousSessionId = plan.previousSessionId {
                previousTranscript = await fetchPreviousTranscript(sessionId: previousSessionId)
                if let prev = previousTranscript {
                    log("Found previous transcript with \(prev.count) entries for combined essay")
                } else {
                    log("Follow-up plan but no previous transcript found for session: \(previousSessionId.uuidString)")
                }
            } else if plan.isFollowUp {
                log("Follow-up plan but previousSessionId is nil")
            }

            // Generate draft
            let markdown = try await AgentCoordinator.shared.writeDraft(
                transcript: transcript,
                analysis: analysis,
                plan: plan.toSnapshot(),
                style: appState.selectedDraftStyle,
                previousTranscript: previousTranscript
            )

            // Save to SwiftData
            await MainActor.run {
                let draft = Draft(
                    style: appState.selectedDraftStyle.rawValue,
                    markdownContent: markdown
                )
                draft.session = session
                session.drafts.append(draft)
                do {
                    try modelContext.save()
                } catch {
                    log("Failed to save draft: \(error.localizedDescription)")
                }

                markdownContent = markdown
                stage = .complete
            }
        } catch {
            await MainActor.run {
                currentError = AppError.from(error, context: .draftGeneration)
                stage = .error
            }
        }
    }

    private func loadAnalysisFromSession(_ session: InterviewSession) -> AnalysisSummary? {
        guard let model = session.analysis else { return nil }
        return AnalysisSummary(
            researchGoal: model.researchGoal,
            mainClaims: model.mainClaims,
            themes: model.themes,
            tensions: model.tensions,
            quotes: model.quotes,
            suggestedTitle: model.suggestedTitle,
            suggestedSubtitle: model.suggestedSubtitle
        )
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

// MARK: - Markdown View (Simple Renderer)

struct MarkdownView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parseLines().enumerated()), id: \.offset) { _, element in
                renderElement(element)
            }
        }
    }

    private enum MarkdownElement {
        case h1(String)
        case h2(String)
        case h3(String)
        case blockquote(String)
        case hr
        case paragraph(String)
    }

    private func parseLines() -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        var currentParagraph = ""

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Flush paragraph if needed
            if !currentParagraph.isEmpty && (trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(">") || trimmed == "---") {
                elements.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
                currentParagraph = ""
            }

            if trimmed.isEmpty {
                continue
            } else if trimmed.hasPrefix("# ") {
                elements.append(.h1(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("## ") {
                elements.append(.h2(String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("### ") {
                elements.append(.h3(String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("> ") {
                elements.append(.blockquote(String(trimmed.dropFirst(2))))
            } else if trimmed == "---" {
                elements.append(.hr)
            } else {
                if currentParagraph.isEmpty {
                    currentParagraph = trimmed
                } else {
                    currentParagraph += " " + trimmed
                }
            }
        }

        // Flush remaining paragraph
        if !currentParagraph.isEmpty {
            elements.append(.paragraph(currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return elements
    }

    @ViewBuilder
    private func renderElement(_ element: MarkdownElement) -> some View {
        switch element {
        case .h1(let text):
            Text(text)
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 8)

        case .h2(let text):
            Text(text)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 6)

        case .h3(let text):
            Text(text)
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top, 4)

        case .blockquote(let text):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.blue.opacity(0.5))
                    .frame(width: 3)

                Text(renderInlineFormatting(text))
                    .font(.body)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .padding(.vertical, 8)
            }
            .padding(.vertical, 4)

        case .hr:
            Divider()
                .padding(.vertical, 8)

        case .paragraph(let text):
            Text(renderInlineFormatting(text))
                .font(.body)
        }
    }

    private func renderInlineFormatting(_ text: String) -> AttributedString {
        var result = AttributedString(text)

        // Bold: **text**
        if let boldRange = text.range(of: "\\*\\*(.+?)\\*\\*", options: .regularExpression) {
            let inner = String(text[boldRange]).replacingOccurrences(of: "**", with: "")
            if let attrRange = result.range(of: text[boldRange]) {
                result.replaceSubrange(attrRange, with: AttributedString(inner))
            }
        }

        // Italic: *text* (simple approach)
        if let italicRange = text.range(of: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", options: .regularExpression) {
            let inner = String(text[italicRange]).replacingOccurrences(of: "*", with: "")
            if let attrRange = result.range(of: text[italicRange]) {
                var replacement = AttributedString(inner)
                replacement.inlinePresentationIntent = .emphasized
                result.replaceSubrange(attrRange, with: replacement)
            }
        }

        return result
    }
}
