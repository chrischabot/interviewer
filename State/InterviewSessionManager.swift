import Foundation
import SwiftUI
import Observation

// MARK: - Transcript Entry

struct TranscriptEntry: Identifiable, Equatable {
    let id = UUID()
    let speaker: String  // "user" or "assistant"
    var text: String
    let timestamp: Date
    var isFinal: Bool

    // Include text in equality check so SwiftUI re-renders when text changes
    static func == (lhs: TranscriptEntry, rhs: TranscriptEntry) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.isFinal == rhs.isFinal
    }
}

// MARK: - Interview State

enum InterviewState: Equatable {
    case idle
    case connecting
    case active
    case paused
    case ending
    case ended
}

// MARK: - Interview Session Manager

@MainActor
@Observable
final class InterviewSessionManager: RealtimeClientDelegate, AudioEngineDelegate {
    // State
    var state: InterviewState = .idle
    var transcript: [TranscriptEntry] = []
    var elapsedSeconds: Int = 0
    var targetSeconds: Int = 840  // 14 minutes default
    var currentQuestion: String = ""
    var isUserSpeaking = false
    var isAssistantSpeaking = false
    var errorMessage: String?
    var assistantAudioLevel: CGFloat = 0  // Audio level for visualization (0.0 to 1.0)

    // Plan reference
    var plan: Plan?

    // Agent state (Phase 4)
    var currentNotes: NotesState = .empty
    var researchItems: [ResearchItem] = []
    var latestDecision: OrchestratorDecision?
    var currentPhase: String = "opening"
    var agentActivity: [String: Double] = [:]
    var isProcessingAgents = false

    // Private
    private let realtimeClient = RealtimeClient()
    private let audioEngine = AudioEngine()
    private var timer: Timer?
    private var audioLevelTimer: Timer?
    private var agentTimer: Timer?  // Periodic agent processing
    private var currentAssistantEntry: TranscriptEntry?
    private var pendingAssistantText: String = ""  // Accumulate assistant transcript until audio done
    private var pendingUserText: String = ""  // Accumulate user transcript during speech
    private var lastAssistantAudioAt: Date?  // Track when last AI audio chunk was received
    private let audioBleedGuardSeconds: TimeInterval = 2.0  // Delay after last audio chunk before resuming mic
    var isMicMuted: Bool { isAssistantSpeaking || isInBleedGuardPeriod }  // Exposed for UI

    private var isInBleedGuardPeriod: Bool {
        guard let lastAudioAt = lastAssistantAudioAt else { return false }
        return Date().timeIntervalSince(lastAudioAt) < audioBleedGuardSeconds
    }
    private var hasSentAudioSinceLastResponse = false  // Track if we've sent audio (to avoid empty buffer error)
    private let agentProcessingInterval: TimeInterval = 10.0  // Process agents every 10 seconds
    private var planSnapshot: PlanSnapshot?  // Cached snapshot for agent processing
    private var delegatesConfigured = false
    var hasDetectedClosing = false  // Track if we've seen a closing statement (public for UI)
    private var closingDetectedAt: Date?  // When closing was detected

    // Phrases that indicate the interview is ending
    private let closingPhrases = [
        "thank you for sharing",
        "thanks for sharing",
        "thank you so much for",
        "it was great talking",
        "wonderful talking with you",
        "take care",
        "goodbye",
        "good bye",
        "that's all the time",
        "we're out of time",
        "wrap up our conversation",
        "bring our conversation to a close",
        "final thoughts"
    ]

    init() {
        // Set synchronous delegate immediately
        audioEngine.delegate = self
    }

    private func ensureDelegatesConfigured() async {
        guard !delegatesConfigured else { return }
        await realtimeClient.setDelegate(self)
        delegatesConfigured = true
    }

    // MARK: - Session Control

    func startSession(plan: Plan, previousSession: InterviewSession? = nil) async {
        // Ensure delegates are configured before starting
        await ensureDelegatesConfigured()

        NSLog("[InterviewSession] 🎬 Starting session for plan: %@", plan.topic)

        self.plan = plan
        self.targetSeconds = plan.targetSeconds
        self.transcript = []
        self.elapsedSeconds = 0
        self.errorMessage = nil
        self.isAssistantSpeaking = true  // AI will start speaking immediately with greeting
        self.isUserSpeaking = false
        self.lastAssistantAudioAt = Date()  // Pretend we just received audio to block mic initially
        self.pendingAssistantText = ""
        self.pendingUserText = ""
        self.hasDetectedClosing = false
        self.closingDetectedAt = nil

        // Reset agent state
        self.currentNotes = .empty
        self.researchItems = []
        self.latestDecision = nil
        self.currentPhase = "opening"
        self.agentActivity = [:]
        self.isProcessingAgents = false
        self.planSnapshot = plan.toSnapshot()

        // Initialize agent coordinator - preserve context if this is a follow-up
        if plan.isFollowUp, let previousSession = previousSession {
            NSLog("[InterviewSession] 📚 Loading context from previous session with %d utterances", previousSession.utterances.count)

            // Convert utterances to transcript entries
            let previousTranscript = previousSession.utterances.map { utterance in
                TranscriptEntry(
                    speaker: utterance.speaker,
                    text: utterance.text,
                    timestamp: utterance.timestamp,
                    isFinal: true
                )
            }

            // Get previous notes
            let previousNotes = previousSession.notesState?.toNotesState() ?? .empty

            // Get the original plan snapshot (if available)
            let previousPlanSnapshot = previousSession.plan?.toSnapshot() ?? plan.toSnapshot()

            await AgentCoordinator.shared.startFollowUpSession(
                previousTranscript: previousTranscript,
                previousNotes: previousNotes,
                previousPlan: previousPlanSnapshot
            )
        } else {
            await AgentCoordinator.shared.startNewSession()
        }

        state = .connecting

        do {
            // Setup audio engine
            NSLog("[InterviewSession] 🎤 Setting up audio engine...")
            try audioEngine.setup()
            NSLog("[InterviewSession] ✓ Audio engine setup complete")

            // Build instructions from plan
            let instructions = buildInstructions(from: plan)
            NSLog("[InterviewSession] 📝 Instructions built (length: %d)", instructions.count)

            // Connect to Realtime API
            NSLog("[InterviewSession] 🔌 Connecting to Realtime API...")
            try await realtimeClient.connect(instructions: instructions)
            NSLog("[InterviewSession] ✓ Connected to Realtime API")

            // Start audio capture
            NSLog("[InterviewSession] 🎙️ Starting audio capture...")
            try await audioEngine.startCapturing()
            NSLog("[InterviewSession] ✓ Audio capture started")

            // Start timer
            startTimer()

            // Set initial question
            if let firstSection = plan.sections.sorted(by: { $0.sortOrder < $1.sortOrder }).first,
               let firstQuestion = firstSection.questions.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
                currentQuestion = firstQuestion.text
            }

            state = .active
            NSLog("[InterviewSession] ✅ Session is now active!")
        } catch {
            NSLog("[InterviewSession] ❌ Error starting session: %@", String(describing: error))
            // Clean up any partially started resources
            stopTimer()
            audioEngine.shutdown()
            errorMessage = error.localizedDescription
            state = .idle
        }
    }

    func pauseSession() async {
        guard state == .active else { return }

        audioEngine.stopCapturing()
        stopTimer()
        state = .paused
    }

    func resumeSession() async {
        guard state == .paused else { return }

        do {
            try await audioEngine.startCapturing()
            startTimer()
            state = .active
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func endSession() async {
        state = .ending

        stopTimer()
        audioEngine.shutdown()  // Fully stop audio engine when ending (not just pausing)
        await realtimeClient.disconnect()

        state = .ended
    }

    func triggerResponse() async {
        // Only commit and respond if we've actually sent audio
        guard hasSentAudioSinceLastResponse else {
            NSLog("[InterviewSession] ⚠️ No audio sent since last response, skipping commit")
            return
        }

        do {
            // Commit buffer and trigger response (since create_response is false)
            try await realtimeClient.commitAndRespond()
            hasSentAudioSinceLastResponse = false  // Reset for next round
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }

        // Audio level polling timer (60fps for smooth animation)
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.assistantAudioLevel = self.audioEngine.audioLevel
            }
        }

        // Agent processing timer (every 10 seconds)
        agentTimer = Timer.scheduledTimer(withTimeInterval: agentProcessingInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.processAgentUpdate()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        agentTimer?.invalidate()
        agentTimer = nil
        assistantAudioLevel = 0
    }

    // MARK: - Agent Processing

    private func processAgentUpdate() async {
        // Skip if not active or already processing
        guard state == .active, !isProcessingAgents else { return }

        // Skip if no transcript yet (nothing to analyze)
        guard !transcript.isEmpty else { return }

        // Need plan snapshot
        guard let snapshot = planSnapshot else { return }

        isProcessingAgents = true
        NSLog("[InterviewSession] 🤖 Starting agent processing cycle...")

        // Process live update - this never throws due to graceful fallbacks
        let result = await AgentCoordinator.shared.processLiveUpdate(
            transcript: transcript,
            currentNotes: currentNotes,
            plan: snapshot,
            elapsedSeconds: elapsedSeconds,
            targetSeconds: targetSeconds
        )

        // Update state with results
        currentNotes = result.notes
        researchItems.append(contentsOf: result.newResearchItems)
        latestDecision = result.decision
        currentPhase = result.decision.phase
        currentQuestion = result.decision.nextQuestion.text

        // Update agent activity from coordinator
        agentActivity = await AgentCoordinator.shared.getAgentActivity()

        // Update Realtime API instructions with new guidance
        // This can still fail (network issues), but we handle gracefully
        do {
            try await realtimeClient.updateInstructions(result.interviewerInstructions)
        } catch {
            NSLog("[InterviewSession] ⚠️ Failed to update Realtime instructions: %@", error.localizedDescription)
            // Interview continues with existing instructions
        }

        NSLog("[InterviewSession] ✅ Agent processing complete - Phase: %@, Next Q: %@",
              result.decision.phase,
              String(result.decision.nextQuestion.text.prefix(50)))

        isProcessingAgents = false
    }

    // MARK: - Instructions Builder

    private func buildInstructions(from plan: Plan) -> String {
        var sectionsText = ""
        for section in plan.sections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            sectionsText += "\n\n### \(section.title)\n"
            for question in section.questions.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let marker = question.role == "backbone" ? "**[MUST ASK]**" : "[follow-up]"
                sectionsText += "- \(marker) \(question.text)\n"
                if !question.notesForInterviewer.isEmpty {
                    sectionsText += "  _Note: \(question.notesForInterviewer)_\n"
                }
            }
        }

        // Build follow-up context if this is a continuation
        var followUpSection = ""
        if plan.isFollowUp && !plan.followUpContext.isEmpty {
            followUpSection = """

            **IMPORTANT: This is a FOLLOW-UP conversation.**

            You already spoke with this person in a previous session. This is a continuation to explore new angles and add depth.

            **Topics to explore in this follow-up:**
            \(plan.followUpContext)

            **Follow-up style:**
            - Reference that you spoke before ("Last time we talked about...")
            - Don't repeat ground already covered
            - Go deeper on new angles
            - Help them add richness to their eventual essay

            """
        }

        let openingInstruction = plan.isFollowUp
            ? "Start by warmly welcoming them back and briefly mention you're picking up where you left off. Then dive into the first follow-up topic."
            : "Start by warmly greeting them in English and asking about the topic. Keep it natural and conversational."

        return """
        You are an expert podcast-style interviewer talking with a single expert.

        **IMPORTANT: Always speak and respond in English, regardless of any other language you may hear.**
        \(followUpSection)
        **Research Goal:** \(plan.researchGoal)

        **Angle:** \(plan.angle)

        **Topic:** \(plan.topic)

        **Interview Sections:**
        \(sectionsText)

        **Your Role:**
        - Help them talk their way into a strong essay about this topic
        - Surface stories, failures, turning points
        - Clarify their opinions and trade-offs
        - Connect their experiences to the research goal and angle

        **Conversation Style:**
        - Warm, concise, curious
        - Ask one clear question at a time
        - Use short natural phrases
        - When they give a long answer, briefly mirror what you heard ("So it sounds like…") and then ask a focused follow-up

        **Time Budget:** \(plan.targetSeconds / 60) minutes total
        - First 2-3 minutes: establish context and stakes
        - Middle: dive deep into stories and concrete examples
        - Last 2 minutes: synthesize and ask for closing reflection

        **Exploration Time:**
        You have built-in flexibility for whimsical discovery. When an unexpected but fascinating thread emerges—a surprising connection, an intriguing tangent, a story begging to be told—follow it. These detours often yield the richest material.

        Don't force exploration if nothing sparks. But when the conversation wants to meander somewhere interesting, let it breathe. The best essays come from conversations that found unexpected corners.

        \(openingInstruction)
        """
    }

    // MARK: - Time Display

    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedTargetTime: String {
        let minutes = targetSeconds / 60
        let seconds = targetSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedCountdownTime: String {
        let remaining = targetSeconds - elapsedSeconds
        if remaining >= 0 {
            let minutes = remaining / 60
            let seconds = remaining % 60
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            let overtime = -remaining
            let minutes = overtime / 60
            let seconds = overtime % 60
            return String(format: "-%02d:%02d", minutes, seconds)
        }
    }

    var timeProgress: Double {
        guard targetSeconds > 0 else { return 0 }
        return min(1.0, Double(elapsedSeconds) / Double(targetSeconds))
    }

    var isOvertime: Bool {
        elapsedSeconds > targetSeconds
    }

    // MARK: - RealtimeClientDelegate

    nonisolated func realtimeClientDidConnect(_ client: RealtimeClient) async {
        // Connection established
    }

    nonisolated func realtimeClientDidDisconnect(_ client: RealtimeClient, error: Error?) async {
        await MainActor.run {
            // Only set error if it's a real error (not expected disconnection)
            if let error = error {
                // Don't show error if we're ending normally
                if self.state != .ending && self.state != .ended && !self.hasDetectedClosing {
                    self.errorMessage = error.localizedDescription
                }
            }
            // Only reset to idle if we were active and it's an unexpected disconnect
            // Don't overwrite .ending or .ended states
            if self.state == .active && !self.hasDetectedClosing {
                self.state = .idle
            }
        }
    }

    nonisolated func realtimeClient(_ client: RealtimeClient, didReceiveAudio data: Data) async {
        // Check if this is the start of AI speaking (first audio chunk)
        let wasAlreadySpeaking = await MainActor.run {
            let was = self.isAssistantSpeaking
            self.isAssistantSpeaking = true
            self.lastAssistantAudioAt = Date()  // Track when each audio chunk arrives
            return was
        }

        // Clear the audio buffer when AI starts speaking to prevent stale audio from triggering responses
        if !wasAlreadySpeaking {
            NSLog("[InterviewSession] 🔇 AI started speaking, clearing audio buffer")
            try? await realtimeClient.clearAudioBuffer()
        }

        do {
            try audioEngine.playAudio(data)
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    nonisolated func realtimeClient(_ client: RealtimeClient, didReceiveTranscript text: String, isFinal: Bool, speaker: String) async {
        await MainActor.run {
            if speaker == "assistant" {
                if isFinal {
                    // Final transcript - mark the current entry as final
                    NSLog("[Session] ✅ Final assistant transcript received, length: %d", text.count)

                    // Update the current streaming entry to final, or create one if needed
                    if let index = self.transcript.lastIndex(where: { $0.speaker == "assistant" && !$0.isFinal }) {
                        var updatedEntry = self.transcript[index]
                        updatedEntry.text = text  // Use final text from server
                        updatedEntry.isFinal = true
                        self.transcript[index] = updatedEntry
                    } else if !text.isEmpty {
                        let entry = TranscriptEntry(speaker: speaker, text: text, timestamp: Date(), isFinal: true)
                        self.transcript.append(entry)
                    }

                    // Reset speaking state
                    self.pendingAssistantText = ""
                    self.isAssistantSpeaking = false

                    // Check for closing statement
                    self.checkForClosingStatement(text)
                } else {
                    // Delta - stream text as it comes in
                    self.pendingAssistantText += text

                    // Update or create streaming entry
                    if let index = self.transcript.lastIndex(where: { $0.speaker == "assistant" && !$0.isFinal }) {
                        var updatedEntry = self.transcript[index]
                        updatedEntry.text = self.pendingAssistantText
                        self.transcript[index] = updatedEntry
                    } else {
                        let entry = TranscriptEntry(speaker: speaker, text: self.pendingAssistantText, timestamp: Date(), isFinal: false)
                        self.transcript.append(entry)
                    }
                }
            } else if speaker == "user" {
                // Capture user speech for agents and analysis
                if isFinal {
                    NSLog("[Session] 🎤 Final user transcript received, length: %d", text.count)

                    // Update the current streaming entry to final, or create one if needed
                    if let index = self.transcript.lastIndex(where: { $0.speaker == "user" && !$0.isFinal }) {
                        var updatedEntry = self.transcript[index]
                        updatedEntry.text = text
                        updatedEntry.isFinal = true
                        self.transcript[index] = updatedEntry
                    } else if !text.isEmpty {
                        let entry = TranscriptEntry(speaker: speaker, text: text, timestamp: Date(), isFinal: true)
                        self.transcript.append(entry)
                    }

                    // Update user speaking state
                    self.pendingUserText = ""
                    self.isUserSpeaking = false
                } else {
                    // Delta - stream text as it comes in
                    self.pendingUserText += text
                    self.isUserSpeaking = true

                    // Update or create streaming entry
                    if let index = self.transcript.lastIndex(where: { $0.speaker == "user" && !$0.isFinal }) {
                        var updatedEntry = self.transcript[index]
                        updatedEntry.text = self.pendingUserText
                        self.transcript[index] = updatedEntry
                    } else {
                        let entry = TranscriptEntry(speaker: speaker, text: self.pendingUserText, timestamp: Date(), isFinal: false)
                        self.transcript.append(entry)
                    }
                }
            }
        }
    }

    nonisolated func realtimeClient(_ client: RealtimeClient, didReceiveError error: Error) async {
        await MainActor.run {
            self.errorMessage = error.localizedDescription
        }
    }

    nonisolated func realtimeClient(_ client: RealtimeClient, didDetectSpeechStart: Bool) async {
        await MainActor.run {
            self.isUserSpeaking = true
        }
    }

    nonisolated func realtimeClient(_ client: RealtimeClient, didDetectSpeechEnd: Bool) async {
        await MainActor.run {
            self.isUserSpeaking = false
        }
    }

    // MARK: - AudioEngineDelegate

    nonisolated func audioEngine(_ engine: AudioEngine, didCaptureAudio data: Data) async {
        // Skip sending audio while assistant is speaking (or recently stopped) to prevent audio bleed
        // (microphone picking up speaker output)
        let shouldSkip = await MainActor.run { () -> Bool in
            // Don't send audio if session is ending or ended
            if self.state == .ending || self.state == .ended || self.state == .idle {
                return true
            }
            // Don't send audio if we've detected a closing statement (interview is about to end)
            if self.hasDetectedClosing {
                return true
            }
            if self.isAssistantSpeaking {
                return true
            }
            // Also skip for a short period after last audio chunk (audio still playing from buffer)
            if let lastAudioAt = self.lastAssistantAudioAt {
                let elapsed = Date().timeIntervalSince(lastAudioAt)
                if elapsed < self.audioBleedGuardSeconds {
                    return true
                }
            }
            return false
        }

        if shouldSkip {
            return
        }

        do {
            try await realtimeClient.sendAudio(data)
            await MainActor.run {
                self.hasSentAudioSinceLastResponse = true
            }
        } catch {
            // Only show error if session is still active (not ending/ended)
            let isStillActive = await MainActor.run { self.state == .active }
            if isStillActive {
                NSLog("[AudioCapture] ❌ Failed to send audio: %@", error.localizedDescription)
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    nonisolated func audioEngineDidStartCapturing(_ engine: AudioEngine) async {
        // Capture started
    }

    nonisolated func audioEngineDidStopCapturing(_ engine: AudioEngine) async {
        // Capture stopped
    }

    // MARK: - Closing Detection

    private func checkForClosingStatement(_ text: String) {
        // Only check if we're in wrap_up phase or past target time
        let shouldCheck = currentPhase == "wrap_up" || elapsedSeconds >= targetSeconds - 60

        guard shouldCheck else { return }
        guard !hasDetectedClosing else { return }  // Already detected

        let lowerText = text.lowercased()

        for phrase in closingPhrases {
            if lowerText.contains(phrase) {
                NSLog("[InterviewSession] 🏁 Detected closing phrase: \"%@\"", phrase)
                hasDetectedClosing = true
                closingDetectedAt = Date()

                // Immediately stop audio and connection - no more input/output
                Task {
                    await self.stopAudioAndConnection()
                }
                break
            }
        }
    }

    /// Stop audio capture and realtime connection immediately (called when closing detected)
    private func stopAudioAndConnection() async {
        NSLog("[InterviewSession] 🛑 Stopping audio and connection after closing")
        NSLog("[InterviewSession] 📊 Transcript contains %d entries before stopping", transcript.count)

        // Stop all audio
        audioEngine.stopCapturing()
        audioEngine.stopPlayback()

        // Disconnect from realtime API
        await realtimeClient.disconnect()

        // Stop all timers
        stopTimer()

        // Update state
        isAssistantSpeaking = false
        isUserSpeaking = false

        // CRITICAL: Set state to .ended so the UI shows the ended screen and data gets saved
        // This triggers the onChange handler in InterviewView that calls saveSessionAfterAutoEnd()
        state = .ended
        NSLog("[InterviewSession] ✅ Session state set to .ended - ready for data save")
    }
}

// MARK: - RealtimeClient Extension

extension RealtimeClient {
    func setDelegate(_ delegate: RealtimeClientDelegate?) async {
        self.delegate = delegate
    }
}
