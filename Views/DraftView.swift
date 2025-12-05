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
    @State private var errorMessage: String?
    @State private var showCopiedFeedback = false

    private var session: InterviewSession? {
        sessions.first { $0.id == sessionId }
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

                    ShareLink(item: markdownContent) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            await loadOrGenerateDraft()
        }
        .alert("Draft Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Retry") {
                Task { await loadOrGenerateDraft() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
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

            Text("Draft Generation Failed")
                .font(.headline)

            Text(errorMessage ?? "Unknown error")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await loadOrGenerateDraft() }
            }
            .buttonStyle(.borderedProminent)
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
            errorMessage = "No plan associated with this session"
            stage = .error
            return
        }

        // Check for analysis
        guard let analysis = appState.currentAnalysis ?? loadAnalysisFromSession(session) else {
            errorMessage = "No analysis available. Please run analysis first."
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

            // Generate draft
            let markdown = try await AgentCoordinator.shared.writeDraft(
                transcript: transcript,
                analysis: analysis,
                plan: plan.toSnapshot(),
                style: appState.selectedDraftStyle
            )

            // Save to SwiftData
            await MainActor.run {
                let draft = Draft(
                    style: appState.selectedDraftStyle.rawValue,
                    markdownContent: markdown
                )
                draft.session = session
                session.drafts.append(draft)
                try? modelContext.save()

                markdownContent = markdown
                stage = .complete
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
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
