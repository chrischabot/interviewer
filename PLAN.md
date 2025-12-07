# PLAN.md

Comprehensive implementation plan for a **fully native Swift** macOS 26 "Tahoe" / iOS 26 app that interviews a user on a topic and produces a narrative blog-ready write-up, using **OpenAI for all speech and reasoning** (no web search tooling).

---

## 0. Scope & Audience

This document is intended as a **full specification** for an AI code agent (e.g. Claude Code) and human developers to implement the app end-to-end.

**In scope:**

* **Fully native Swift app** - no backend server required
* macOS 26 Tahoe + iOS/iPadOS 26 (universal app)
* Swift 6+, SwiftUI, Liquid Glass design
* Single source of AI capability: **OpenAI** (Realtime + Chat Completions APIs, structured outputs; no web search tools)
* Voice-first UX: 14-minute default conversations via OpenAI Realtime (with built-in exploration time)
* Multi-agent orchestration running **directly on-device** (Planner, Note-Taker, Researcher, Orchestrator, Analysis, Writer, Follow-Up)
* **Follow-up sessions**: Resume previous conversations with 6-minute deep-dives on unexplored threads
* Anthropic-style interview methodology: **"Interview me to produce a killer essay, not a social-science report."**
* Local data persistence with **SwiftData**
* Secure API key storage via **iOS/macOS Keychain**

**Out of scope:**

* Backend servers (Node.js, Python, etc.) - everything runs natively
* Alternative AI providers (no Apple/Google STT/TTS, no non-OpenAI LLMs)
* Non-Apple platforms
* Multi-user SaaS features

---

## 1. Product Overview

### 1.1 Vision

A **voice-driven thinking partner** for subject-matter experts:

> "Talk for 5–15 minutes about a deep topic (e.g. developer relations strategies, agentic coding). The app interviews you podcast-style, live-researches new threads, keeps track of what matters, and then generates a **strong, coherent narrative** that could ship as a blog post."

### 1.2 Key ideas

* Start from a **clear research goal / angle**, not just a vague topic.
* Use a **rubric** with backbone and follow-up questions (Anthropic Interviewer style).
* Human-in-the-loop plan review before you talk.
* Real-time **multi-agent orchestration** behind a single natural voice.
* Post-interview **analysis** step to clarify the claims before drafting prose.
* Final output: 1–2 **blog-style drafts** with quotable snippets and strong narrative flow.

---

## 2. Requirements

### 2.1 Functional requirements

1. **Topic capture & goal setting**

   * User enters:
     * Topic (single line),
     * Optional free-form context (multi-line),
     * Target duration (5–20 min slider).
   * System infers a **research goal** and proposed **angle**.

2. **Planner & rubric**

   * Planner agent generates:
     * Story arc (sections),
     * Questions (backbone vs follow-up),
     * Rough timing per section.
   * User can:
     * Edit section titles & order,
     * Edit/add/remove questions,
     * Mark "must hit" vs "optional."

3. **Interview session**

   * Start interview:
     * Open **OpenAI Realtime** session (speech-in/speech-out).
   * Timed session:
     * Timer visible (`mm:ss`),
     * Target duration displayed.
   * UX:
     * Large **current question** display.
     * Live transcript (speaker-tagged).
     * Indicators of which **sections** are covered.
     * Agent activity meters at bottom.

4. **Real-time intelligence**

   * Note-Taker tracks:
     * Key ideas, stories, claims,
     * Coverage of each section,
     * Gaps & contradictions to follow up.
   * Researcher:
     * When new concepts arise, provides quick factual context and claim checks from model knowledge (no live web search).
   * Orchestrator:
     * Chooses next question based on plan, notes, research, and time.

5. **Post-interview analysis**

   * Analysis agent:
     * Answers the research goal in bullets.
     * Summarizes key themes and tensions.
     * Picks 3–8 **quotable lines**.

6. **Writer**

   * Writer agent generates:
     * At least one long-form essay draft (~1,200–1,800 words).
     * Three style options: Standard, Punchy, Reflective.
   * Essays written in **first person** as the author's voice (not third-party "one expert says...").
   * For follow-up sessions: combines original + follow-up transcripts into unified narrative.

7. **Follow-up Sessions**

   * From home screen, users can:
     * **Resume** a previous session (analyze for unexplored threads)
     * **Start fresh** with same topic (new plan)
   * Follow-Up Agent analyzes completed sessions and suggests:
     * 3 topics to explore further
     * 2-3 questions per topic
     * Unexplored gaps and areas to strengthen
   * Follow-up interviews are 6 minutes by default.
   * Analysis and Writer agents merge both transcripts for combined output.

8. **Draft management**

   * Show markdown preview in app.
   * Copy to clipboard.
   * Export to `.md` file.
   * Share sheet integration (iOS/macOS).

### 2.2 Non-functional requirements

* **Latency (voice):**
  * Realtime responses should feel conversational (< 500 ms perceived lag after user finishes talking).

* **Resilience:**
  * Graceful handling of:
    * Realtime disconnect / reconnect,
    * Agent failures (continue with simpler logic if an agent fails).

* **Privacy:**
  * All data stored locally on device via SwiftData.
  * API key stored securely in Keychain.
  * Clear indication when microphone is recording.

* **Accessibility:**
  * Support system text size & contrast settings.
  * Respect macOS Tahoe Liquid Glass transparency toggles ("Tinted" vs "Clear", Reduce transparency).
  * VoiceOver support.

### 2.3 Constraints & choices

* **AI stack:**
  * Speech + reasoning: **OpenAI** only (Realtime + Chat Completions; no web search tools).
  * No other AI SDKs.

* **Architecture:**
  * **No backend server** - all agent logic runs on-device via direct OpenAI API calls.
  * API key provided by user, stored in Keychain.

* **Platforms:**
  * macOS 26 Tahoe + iOS/iPadOS 26 (universal Swift app).
  * Shared codebase with platform-specific UI adaptations.

* **Design:**
  * Follow **Liquid Glass** design language for panels, sidebars, toolbars.

* **Language:**
  * Swift 6+, SwiftUI, Swift Concurrency (actors, `async`/`await`, AsyncStreams).
  * Follow Swift & SwiftUI coding guidelines documented in `CLAUDE.md`.

* **Persistence:**
  * **SwiftData** for local storage of sessions, plans, transcripts, drafts.
  * Note: Avoid `@Attribute(.unique)` if planning CloudKit sync (not supported).

---

## 3. System Architecture

### 3.1 High-level components (No Backend)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Native Swift App                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      SwiftUI Views                        │   │
│  │   HomeView │ PlanEditorView │ InterviewView │ DraftView   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   AgentCoordinator                        │   │
│  │  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌─────────────┐   │   │
│  │  │ Planner │ │NoteTaker │ │Researcher│ │Orchestrator │   │   │
│  │  └─────────┘ └──────────┘ └──────────┘ └─────────────┘   │   │
│  │  ┌─────────┐ ┌──────────┐                                │   │
│  │  │Analysis │ │  Writer  │  ← All agents are Swift actors │   │
│  │  └─────────┘ └──────────┘                                │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│  ┌────────────┐  ┌───────────────┐  ┌─────────────────────┐     │
│  │AudioEngine │  │ OpenAIClient  │  │  KeychainManager    │     │
│  │(AVAudio)   │  │ (URLSession)  │  │  (API key storage)  │     │
│  └────────────┘  └───────────────┘  └─────────────────────┘     │
│                              │                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                     SwiftData                             │   │
│  │   Sessions │ Plans │ Transcripts │ Notes │ Drafts         │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                          OpenAI                                  │
│  ┌─────────────────────┐  ┌──────────────────────────────────┐  │
│  │    Realtime API     │  │     Chat Completions API         │  │
│  │  (WebSocket voice)  │  │  (Structured Outputs + Tools)    │  │
│  │  STT + TTS + VAD    │  │  All agents use this directly    │  │
│  └─────────────────────┘  └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Why No Backend?

1. **Simpler architecture** - One Swift codebase, no server to deploy/maintain
2. **Lower latency** - Direct API calls, no HTTP roundtrip to your server
3. **Works offline** - Local data always available (just needs OpenAI for AI features)
4. **No server costs** - Only pay for OpenAI API usage
5. **Better privacy** - Data never touches your server, only OpenAI
6. **Native on iOS** - Can't ship Node.js/Python with an iOS app anyway

### 3.3 Data flow overview

**Pre-interview:**
```
User Input → PlannerAgent (via OpenAIClient) → Plan JSON → SwiftData → PlanEditorView
```

**Live interview:**
```
Mic Audio → RealtimeClient (WebSocket) → OpenAI Realtime → Audio + Transcripts
                                                              ↓
Every N seconds:  Transcripts → AgentCoordinator
                                    ├── NoteTakerAgent → Updated NotesState
                                    ├── ResearcherAgent → ResearchItems
                                    └── OrchestratorAgent → NextQuestion
                                              ↓
                              RealtimeClient.updateInstructions()
```

**Post-interview:**
```
Transcript + Notes + Plan → AnalysisAgent → AnalysisSummary → SwiftData
AnalysisSummary + Plan → WriterAgent → Markdown Draft → SwiftData → DraftView
```

---

## 4. Native App Design (macOS 26 + iOS 26)

### 4.1 Tech stack

* **Language & frameworks:**
  * Swift 6+
  * SwiftUI (scene-based app)
  * Swift Concurrency:
    * `actor` for agents and shared state,
    * `AsyncStream` / `AsyncSequence` for streaming events.

* **Audio:**
  * `AVAudioEngine` for mic capture and playback.
  * `AVAudioSession` configuration (iOS only).
  * `CoreAudio` for device selection (macOS only).

* **Networking:**
  * `URLSessionWebSocketTask` for OpenAI Realtime.
  * `URLSession` for OpenAI Chat Completions API.

* **Persistence:**
  * `SwiftData` for all local storage.

* **Security:**
  * `Security.framework` (Keychain) for API key storage.

### 4.2 Top-level structure

* `InterviewerApp` (`@main`)
  * Creates `AppCoordinator` / `RootViewModel`.
  * Configures SwiftData `ModelContainer`.

* Views:
  * `HomeView` – topic / goal / duration.
  * `PlanEditorView` – sections & questions.
  * `InterviewView` – live voice UI.
  * `AnalysisView` – research goal answers & themes.
  * `DraftView` – markdown preview.
  * `SettingsView` – API key management, audio device selection.

### 4.3 Scenes & navigation

* Single window app with `NavigationStack`.
* High-level navigation states:
  * `.home`
  * `.planning(planId)`
  * `.interview(sessionId)`
  * `.analysis(sessionId)`
  * `.draft(sessionId)`
  * `.settings`

### 4.4 State & concurrency

Use **actors** to manage mutable shared state safely across async tasks:

```swift
actor SessionState {
    var id: UUID
    var topic: String
    var researchGoal: String
    var angle: String
    var sections: [Section]
    var transcript: [Utterance]
    var notesState: NotesState
    var researchItems: [ResearchItem]
    var currentQuestion: QuestionRef?
    var elapsedSeconds: Int
    var targetSeconds: Int
    var agentActivity: AgentActivityWindow

    func appendUtterance(_:)
    func updatePlan(_:)
    func applyNotesUpdate(_:)
    func applyResearchUpdate(_:)
    func applyOrchestratorUpdate(_:)
}

@MainActor
@Observable
final class SessionViewModel {
    let sessionState: SessionState
    let agentCoordinator: AgentCoordinator
    let realtimeClient: RealtimeClient
    let audioEngine: AudioEngine

    // Properties automatically observed by SwiftUI (no @Published needed)
}
```

**Concurrency pattern:**
* UI work on `@MainActor`.
* Network/audio events processed on background tasks.
* Access to `SessionState` is always `await`ed.
* Each agent is an `actor` for thread-safe state.

### 4.5 Audio pipeline

**Capture → Realtime:**

* Configure `AVAudioEngine`:
  * Input node with `installTap(onBus:bufferSize:format:)`.
  * Use linear PCM (mono, 16-bit, 24kHz) to match OpenAI Realtime audio format.
* For each buffer:
  * Convert to byte array (resample if needed).
  * Wrap in Realtime `input_audio_buffer.append` event as per API.
* Use Realtime's **turn detection / VAD** (server side) so you don't have to manually segment user speech.

**iOS-specific:**
```swift
// Configure AVAudioSession for iOS
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
try session.setActive(true)
```

**Realtime → playback:**

* Realtime events include:
  * Audio deltas (`response.audio.delta`),
  * Text transcripts.
* `RealtimeClient`:
  * Converts audio chunks to `AVAudioPCMBuffer`.
  * Schedules them on an `AVAudioPlayerNode` attached to the same `AVAudioEngine` output.
* Maintain small audio queue to avoid underruns.

### 4.6 Echo Cancellation & Audio Feedback Prevention

**CRITICAL**: The OpenAI Realtime API with server-side VAD can pick up its own audio output through the microphone, causing the AI to respond to itself. This is a **common problem** documented in the OpenAI developer community.

**Multi-Layer Protection Strategy:**

1. **Apple Voice Processing (Primary Defense)**
   ```swift
   // Enable before engine.start()
   try inputNode.setVoiceProcessingEnabled(true)
   inputNode.isVoiceProcessingAGCEnabled = true
   ```
   This enables Apple's hardware-tuned:
   - Acoustic Echo Cancellation (AEC)
   - Noise suppression
   - Automatic Gain Control (AGC)
   - De-reverberation

2. **Voice Isolation Mode (User-Enabled)**
   - Users can enable "Voice Isolation" in Control Center/System Settings
   - Requires voice processing to be enabled first
   - Aggressively filters everything except the speaker's voice
   - **Cannot be set programmatically** - user must enable manually

3. **Mic Muting During AI Speech**
   ```swift
   var isMicMuted: Bool { isAssistantSpeaking || isInBleedGuardPeriod }

   private var isInBleedGuardPeriod: Bool {
       guard let lastAudioAt = lastAssistantAudioAt else { return false }
       return Date().timeIntervalSince(lastAudioAt) < audioBleedGuardSeconds // 2.0s
   }
   ```
   - Stop sending audio to server while AI is speaking
   - Continue muting for 2 seconds after last audio chunk (guard period)
   - Show yellow indicator in UI when mic is muted

4. **Server Audio Buffer Clearing**
   ```swift
   // When AI starts speaking, clear the server's audio buffer
   if !wasAlreadySpeaking {
       try? await realtimeClient.clearAudioBuffer()
   }
   ```
   Send `input_audio_buffer.clear` event when AI starts speaking to prevent stale audio from triggering responses.

5. **Extended Silence Detection**
   ```swift
   turnDetection: .serverVAD(
       threshold: 0.5,
       prefixPaddingMs: 300,
       silenceDurationMs: 3000,  // 3 seconds of silence before AI responds
       createResponse: true
   )
   ```
   Require 3 seconds of silence after user stops speaking before AI responds.

**UI Indicators:**
- Yellow circle + "Mic Off" - when mic is muted (AI speaking or guard period)
- Green circle + "Listening..." - when mic is active and user is speaking
- Green circle + "Ready" - when mic is active and ready for speech

**Resources:**
- [WWDC 2019: What's New in AVAudioEngine](https://developer.apple.com/videos/play/wwdc2019/510/)
- [WWDC 2023: What's new in voice processing](https://developer.apple.com/videos/play/wwdc2023/10235/)
- [OpenAI Realtime API Feedback Loop Discussion](https://community.openai.com/t/realtime-api-feedback-loop/976737)

### 4.6.1 macOS Voice Processing Multi-Channel Fix

**Problem Discovered**: When `setVoiceProcessingEnabled(true)` is called on macOS, the input node returns a multi-channel format (commonly 5 channels) instead of standard mono/stereo. This causes the audio converter to fail silently, resulting in no audio being sent to the API.

**Root Cause**: Apple's voice processing uses an internal multi-channel format for echo cancellation and noise suppression. The actual voice data is in channel 0.

**Solution**: Extract channel 0 from multi-channel buffers before conversion:
```swift
private func extractChannel0(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let floatData = buffer.floatChannelData else { return nil }

    guard let monoFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: buffer.format.sampleRate,
        channels: 1,
        interleaved: false
    ) else { return nil }

    guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength) else {
        return nil
    }

    monoBuffer.frameLength = buffer.frameLength
    guard let monoData = monoBuffer.floatChannelData else { return nil }

    for i in 0..<Int(buffer.frameLength) {
        monoData[0][i] = floatData[0][i]
    }

    return monoBuffer
}

// In tap callback:
let monoBuffer: AVAudioPCMBuffer
if buffer.format.channelCount > 1 {
    monoBuffer = self.extractChannel0(from: buffer) ?? buffer
} else {
    monoBuffer = buffer
}
```

**Key Insight**: Always check `buffer.format.channelCount` before assuming the format matches your expectations when voice processing is enabled.

### 4.6.2 Audio Device Selection (macOS)

On macOS, users can select input/output audio devices from Settings.

**Implementation Pattern**:
```swift
@MainActor
@Observable
final class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    var inputDevices: [AudioDevice] = []
    var outputDevices: [AudioDevice] = []
    var selectedInputDeviceID: String?  // Device UID
    var selectedOutputDeviceID: String?
}
```

**CoreAudio Device Enumeration**:
```swift
// Get all devices
var propertyAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, ...)

// For each device, check if it has input/output streams
propertyAddress.mSelector = kAudioDevicePropertyStreams
propertyAddress.mScope = kAudioDevicePropertyScopeInput  // or ScopeOutput
```

**Setting System Default Device**:
```swift
// AVAudioEngine automatically uses system defaults
// So we just set the system default
var propertyAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectSetPropertyData(kAudioObjectSystemObject, &propertyAddress, ...)
```

**CoreAudio CFString Memory Pattern**:
```swift
// WRONG - causes memory warnings
var name: CFString = "" as CFString
AudioObjectGetPropertyData(..., &name)

// CORRECT - use Unmanaged
var nameRef: Unmanaged<CFString>?
AudioObjectGetPropertyData(..., &nameRef)
guard let name = nameRef?.takeUnretainedValue() else { return nil }
```

**Device Change Notifications**:
```swift
AudioObjectAddPropertyListenerBlock(
    kAudioObjectSystemObject,
    &propertyAddress,  // kAudioHardwarePropertyDevices
    DispatchQueue.main
) { _, _ in
    Task { @MainActor in self.refreshDevices() }
}
```

### 4.7 Liquid Glass design integration

* Use **Liquid Glass-styled** components for main panels:
  * Blur + translucency for sidebars and toolbars.
  * Elevated content in the center panel with higher contrast.
* Respect system toggles:
  * If user enables `Reduce transparency` or selects `Tinted` Liquid Glass style in Tahoe 26.1+, reduce blur radius and increase surface opacity.
* Adopt cross-platform 26.x design cues (spacing, corner radii, updated toolbar look).

### 4.7 Agent activity meters UI

* Bottom bar with horizontal meters:
  * Planner (pre-interview only),
  * Notes,
  * Research,
  * Orchestrator,
  * Writer (post-interview).
* For each agent:
  * Maintain `recentActivityScore` in `AgentActivityWindow` (0–1 based on calls in last 30s).
  * Visual: `Capsule` filled proportional to score, with subtle animated pulsation when > 0.7.

---

## 5. OpenAI Integration (Direct from App)

### 5.1 OpenAIClient actor

All API calls go through a single `OpenAIClient` actor:

```swift
actor OpenAIClient {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // Chat Completions with Structured Outputs (for all agents)
    func chatCompletion(
        messages: [Message],
        model: String = "gpt-4o",
        responseFormat: JSONSchema?,
        tools: [Tool]? = nil
    ) async throws -> ChatCompletionResponse

    // Streaming for long responses
    func streamChatCompletion(
        messages: [Message]
    ) -> AsyncStream<String>
}
```

### 5.2 Structured Outputs

All agents use OpenAI's **Structured Outputs** feature for guaranteed JSON schema adherence:

```swift
let response = try await openAIClient.chatCompletion(
    messages: [
        Message(role: "system", content: plannerSystemPrompt),
        Message(role: "user", content: "Topic: \(topic)\nContext: \(context)")
    ],
    model: "gpt-4o",
    responseFormat: JSONSchema(
        name: "plan_schema",
        strict: true,  // Guarantees 100% schema adherence
        schema: planJSONSchema
    )
)
```

### 5.3 Realtime API (WebSocket)

```swift
actor RealtimeClient {
    private var webSocket: URLSessionWebSocketTask?
    private let apiKey: String

    func connect(model: String = "gpt-4o-realtime-preview") async throws {
        let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        webSocket = URLSession.shared.webSocketTask(with: request)
        webSocket?.resume()
        startReceiving()
    }

    func sendAudio(_ audioData: Data) async throws {
        let event = RealtimeEvent.inputAudioBufferAppend(audio: audioData.base64EncodedString())
        try await send(event)
    }

    func updateInstructions(_ instructions: String) async throws {
        let event = RealtimeEvent.sessionUpdate(instructions: instructions)
        try await send(event)
    }
}
```

---

## 6. Data Models

All models defined in Swift, persisted with SwiftData.

### 6.1 Plan

```swift
@Model
final class Plan {
    var id: UUID  // Note: @Attribute(.unique) removed for CloudKit compatibility
    var topic: String
    var researchGoal: String
    var angle: String
    var targetSeconds: Int  // Default: 840 (14 minutes)
    var createdAt: Date

    // Follow-up support
    var isFollowUp: Bool = false
    var previousSessionId: UUID?  // The session this is a follow-up to
    var followUpContext: String = ""  // Selected topics and questions

    @Relationship(deleteRule: .cascade) var sections: [Section]

    init(topic: String, researchGoal: String, angle: String, targetSeconds: Int,
         isFollowUp: Bool = false, previousSessionId: UUID? = nil, followUpContext: String = "") {
        self.id = UUID()
        self.topic = topic
        self.researchGoal = researchGoal
        self.angle = angle
        self.targetSeconds = targetSeconds
        self.createdAt = Date()
        self.isFollowUp = isFollowUp
        self.previousSessionId = previousSessionId
        self.followUpContext = followUpContext
        self.sections = []
    }
}

@Model
final class Section {
    var id: UUID
    var title: String
    var importance: String  // "high" | "medium" | "low"
    var backbone: Bool
    var estimatedSeconds: Int
    var sortOrder: Int

    @Relationship(deleteRule: .cascade) var questions: [Question]
    var plan: Plan?
}

@Model
final class Question {
    var id: UUID
    var text: String
    var role: String  // "backbone" | "followup"
    var priority: Int  // 1 = must-hit, 2, 3
    var notesForInterviewer: String
    var sortOrder: Int

    var section: Section?
}
```

### 6.2 Interview Session

```swift
@Model
final class InterviewSession {
    var id: UUID  // Note: @Attribute(.unique) removed for CloudKit compatibility
    var startedAt: Date
    var endedAt: Date?
    var elapsedSeconds: Int

    var plan: Plan?
    @Relationship(deleteRule: .cascade) var utterances: [Utterance]
    @Relationship(deleteRule: .cascade) var notesState: NotesStateModel?
    @Relationship(deleteRule: .cascade) var analysis: AnalysisSummaryModel?
    @Relationship(deleteRule: .cascade) var drafts: [Draft]
}

@Model
final class Utterance {
    var id: UUID
    var speaker: String  // "user" | "assistant"
    var text: String
    var timestamp: Date

    var session: InterviewSession?
}
```

### 6.3 Notes State

```swift
@Model
final class NotesStateModel {
    var id: UUID

    // Store complex nested data as JSON
    var keyIdeasJSON: Data
    var storiesJSON: Data
    var claimsJSON: Data
    var gapsJSON: Data
    var contradictionsJSON: Data
    var possibleTitles: [String]

    var session: InterviewSession?

    // Computed properties decode JSON to Swift structs
    var keyIdeas: [KeyIdea] { get }
    var stories: [Story] { get }
    var claims: [Claim] { get }
    var gaps: [Gap] { get }
    var contradictions: [Contradiction] { get }
}

// Plain Swift structs for agent I/O (Codable)
struct KeyIdea: Codable, Identifiable {
    let id: String
    let text: String
    let relatedQuestionIds: [String]
}

struct Story: Codable, Identifiable {
    let id: String
    let summary: String
    let impact: String
    let timestamp: String
}

struct Claim: Codable, Identifiable {
    let id: String
    let text: String
    let confidence: String  // "low" | "medium" | "high"
}

struct Gap: Codable, Identifiable {
    let id: String
    let description: String
    let relatedQuestionIds: [String]
    let suggestedFollowup: String
}

struct Contradiction: Codable, Identifiable {
    let id: String
    let description: String
    let firstQuote: String
    let secondQuote: String
    let suggestedClarificationQuestion: String
}
```

### 6.4 Research Items

```swift
struct ResearchItem: Codable, Identifiable {
    let id: String
    let topic: String
    let kind: String  // "definition" | "counterpoint" | "example" | "metric"
    let summary: String
    let howToUseInQuestion: String
    let priority: Int
}
```

### 6.5 Orchestrator Decision

```swift
struct OrchestratorDecision: Codable {
    let phase: String  // "opening" | "deep_dive" | "wrap_up"
    let nextQuestion: NextQuestion
    let interviewerBrief: String
}

struct NextQuestion: Codable {
    let text: String
    let targetSectionId: String
    let source: String  // "plan" | "gap" | "contradiction" | "research"
    let expectedAnswerSeconds: Int
}
```

### 6.6 Analysis Summary

```swift
@Model
final class AnalysisSummaryModel {
    var id: UUID
    var researchGoal: String
    var mainClaimsJSON: Data
    var themes: [String]
    var tensions: [String]
    var quotesJSON: Data
    var suggestedTitle: String
    var suggestedSubtitle: String

    var session: InterviewSession?
}

struct MainClaim: Codable, Identifiable {
    let id: String
    let text: String
    let evidenceStoryIds: [String]
}

struct Quote: Codable, Identifiable {
    let id: String
    let text: String
    let role: String  // "origin" | "turning_point" | "opinion"
}
```

### 6.7 Draft

```swift
@Model
final class Draft {
    var id: UUID
    var style: String  // "standard" | "punchy" | "reflective"
    var markdownContent: String
    var createdAt: Date

    var session: InterviewSession?
}

enum DraftStyle: String, CaseIterable {
    case standard   // Conversational, surprising, like a Paul Graham essay
    case punchy     // Crisp and energetic, ideas land fast
    case reflective // Thoughtful pace, ideas unfold gradually
}
```

---

## 7. Multi-Agent Design

All agents are **Swift actors** that call OpenAI Chat Completions API directly.

### 7.1 Agent Architecture

```swift
actor AgentCoordinator {
    private let openAIClient: OpenAIClient

    private let plannerAgent: PlannerAgent
    private let noteTakerAgent: NoteTakerAgent
    private let researcherAgent: ResearcherAgent
    private let orchestratorAgent: OrchestratorAgent
    private let analysisAgent: AnalysisAgent
    private let writerAgent: WriterAgent

    // Activity scores accessed via async methods (actors don't use @Published)
    private var agentActivity: [String: Double] = [:]

    func getAgentActivity() -> [String: Double] { agentActivity }

    init(apiKey: String) {
        let client = OpenAIClient(apiKey: apiKey)
        self.openAIClient = client
        self.plannerAgent = PlannerAgent(client: client)
        self.noteTakerAgent = NoteTakerAgent(client: client)
        self.researcherAgent = ResearcherAgent(client: client)
        self.orchestratorAgent = OrchestratorAgent(client: client)
        self.analysisAgent = AnalysisAgent(client: client)
        self.writerAgent = WriterAgent(client: client)
    }

    // Pre-interview
    func generatePlan(topic: String, context: String, targetMinutes: Int) async throws -> Plan

    // Live interview (called every N seconds)
    func processLiveUpdate(
        newUtterances: [Utterance],
        plan: Plan,
        currentNotes: NotesState,
        elapsedSeconds: Int,
        targetSeconds: Int
    ) async throws -> (NotesState, [ResearchItem], OrchestratorDecision)

    // Post-interview
    func generateAnalysis(transcript: [Utterance], notes: NotesState, plan: Plan) async throws -> AnalysisSummary
    func generateDraft(analysis: AnalysisSummary, plan: Plan, style: String) async throws -> String
}
```

### 7.2 Individual Agent Pattern

Each agent follows the same pattern:

```swift
actor PlannerAgent {
    private let client: OpenAIClient
    private var lastActivityTime: Date?

    init(client: OpenAIClient) {
        self.client = client
    }

    func generatePlan(topic: String, context: String, targetMinutes: Int) async throws -> Plan {
        lastActivityTime = Date()

        let response = try await client.chatCompletion(
            messages: [
                Message(role: "system", content: Self.systemPrompt),
                Message(role: "user", content: "Topic: \(topic)\nContext: \(context)\nTarget minutes: \(targetMinutes)")
            ],
            model: "gpt-4o",
            responseFormat: Self.jsonSchema
        )

        return try JSONDecoder().decode(Plan.self, from: response.content.data(using: .utf8)!)
    }

    func getActivityScore() -> Double {
        guard let lastActivity = lastActivityTime else { return 0.0 }
        let elapsed = Date().timeIntervalSince(lastActivity)
        return max(0, 1.0 - (elapsed / 30.0))
    }

    static let systemPrompt = """
    You are a senior narrative designer and interviewer...
    """

    static let jsonSchema: JSONSchema = ...
}
```

### 7.3 Parallel Agent Execution

During live interview, Note-Taker and Researcher run in parallel:

```swift
func processLiveUpdate(...) async throws -> (...) {
    // Run Note-Taker and Researcher in parallel
    async let notesTask = noteTakerAgent.updateNotes(
        newUtterances: newUtterances,
        plan: plan,
        currentNotes: currentNotes
    )

    async let researchTask = researcherAgent.research(
        newUtterances: newUtterances,
        plan: plan
    )

    let (updatedNotes, researchItems) = try await (notesTask, researchTask)

    // Orchestrator runs after, using results from both
    let decision = try await orchestratorAgent.decideNextQuestion(
        plan: plan,
        notes: updatedNotes,
        research: researchItems,
        elapsedSeconds: elapsedSeconds,
        targetSeconds: targetSeconds
    )

    return (updatedNotes, researchItems, decision)
}
```

### 7.4 Agent Purposes

| Agent | Purpose |
|-------|---------|
| **Planner** | Turn topic + context into research goal, angle, sections + questions |
| **Note-Taker** | Maintain NotesState: key ideas, stories, claims, gaps, contradictions |
| **Researcher** | Web search for new concepts, produce ResearchItems |
| **Orchestrator** | Choose next question based on plan, notes, research, time |
| **Analysis** | Post-hoc: answer research goal, extract claims, themes, quotes |
| **Writer** | Turn AnalysisSummary + plan into blog-style narrative (first-person voice) |
| **Follow-Up** | Analyze completed sessions, suggest 3 topics with questions for continuation |

---

## 8. Prompts (System messages)

### 8.1 Planner system prompt

> You are a **senior narrative designer and interviewer**.
> Your job is to design interview rubrics that help a subject-matter expert talk their way into a **killer essay**, not a social-science report.
>
> The user will provide:
> – A topic they want to talk about.
> – Optional free-form notes or constraints.
> – A target duration in minutes.
>
> Your output is a **plan** for a voice interview that:
> – Has a clearly articulated **research goal** (what this piece is trying to understand or argue).
> – Proposes a sharp **angle** (why this will be interesting to read).
> – Is structured as 3–6 **sections** that feel like a good story arc.
> – Contains both **backbone questions** that must be hit and more flexible **follow-up questions** for tangents.
> – Fits roughly within the time budget.
>
> **Anthropic-style learnings to incorporate:**
> – Start from a **research goal**: what we're trying to learn or clarify, not just the topic.
> – Encode **hypotheses** or expectations where relevant, so the interviewer knows what to probe or challenge.
> – Maintain a balance between **consistency** (backbone questions) and **flexibility** (room for tangents).
> – Assume a **human-in-the-loop review**: your plan will be shown in a UI where the expert can edit.
> – Prefer questions that elicit **stories, failures, trade-offs, and strong opinions**.

### 8.2 Realtime interviewer instructions

Set as `session.instructions` for Realtime:

> You are an **expert podcast-style interviewer** talking with a single expert.
>
> **Goal:** Help them talk their way into a strong essay about the provided topic.
> – Surface stories, failures, turning points.
> – Clarify their opinions and trade-offs.
> – Connect their experiences to the inferred research goal and angle.
>
> Conversation style:
> – Warm, concise, curious.
> – Ask **one clear question at a time**.
> – Use short natural phrases.
> – When they give a long answer, briefly **mirror** what you heard ("So it sounds like…") and then ask a focused follow-up.
>
> You may receive periodic **internal guidance** from the orchestration system:
> – These come as system messages containing JSON with keys like `phase`, `nextQuestion`, and `interviewerBrief`.
> – **Never** read this JSON verbatim or mention it exists.
> – Treat it as a suggestion for what to ask next.
>
> Pacing rules:
> – Respect the time budget: {{target_minutes}} minutes.
> – First 2–3 minutes: clarify context and stakes.
> – Middle: dive deep into stories and concrete examples.
> – Last 2–3 minutes: synthesize and ask for closing reflection.

### 8.3 Note-Taker prompt

> You are a **real-time note-taker and gap-finder** for a voice interview.
>
> On each call you receive:
> – A slice of the latest transcript (1–10 turns, speaker-tagged).
> – The current plan (sections + questions).
> – The previous NotesState JSON.
>
> Your tasks:
> – Update concise notes, stories, and claims.
> – Track **which sections and backbone questions have been meaningfully addressed**.
> – Identify **gaps** (important questions not yet answered).
> – Identify potential **contradictions or tensions**.
>
> Keep the state compact. Do not rewrite the transcript.
> For each new gap or contradiction, propose **one** suggested follow-up question.

### 8.4 Research agent prompt

> You are a **live research assistant** supporting an interview.
>
> The input describes:
> – The main topic and research goal.
> – A brief summary of what the speaker has said.
> – A list of **new phrases or concepts** that seem important.
>
> For each high-importance concept:
> – Provide concise, factual context or claim checks from your knowledge (no live web search).
> – Produce **short, accurate summaries** (2–3 sentences each); be explicit when uncertain.
> – Suggest 1–2 **questions the interviewer could ask**.
>
> Prioritize clarity over breadth.

### 8.5 Orchestrator prompt

> You are the **interview conductor**.
>
> You receive:
> – The original plan (sections, questions, importance).
> – The latest NotesState (coverage, gaps, contradictions).
> – Any new research_items from the Research agent.
> – The elapsed and target time.
>
> Your tasks:
> 1. Decide which **phase** we are in: `"opening" | "deep_dive" | "wrap_up"`.
> 2. Choose the **single best next question**, considering section importance, gaps, contradictions, research, and time.
> 3. Provide a short `interviewerBrief` explaining what to listen for.
>
> The `text` field must be exactly what the interviewer should say out loud.

### 8.6 Analysis agent prompt

> You are an **analysis partner** helping turn an interview into clear claims and insights.
>
> Input:
> – The original plan (including research_goal and angle).
> – The final NotesState.
> – The full transcript (speaker-tagged).
>
> Your tasks:
> 1. Answer the **research_goal** using the interviewee's perspective.
> 2. Extract 3–7 **main claims**.
> 3. Identify 3–6 **themes** that recur.
> 4. Identify 1–3 **tensions or contradictions** worth highlighting.
> 5. Select 3–8 **quotable lines** (short, vivid quotes).
> 6. Propose a title and subtitle.

### 8.7 Writer agent prompt

> First-person essay for educated readers. Sentence complexity: 8/10. Compound and complex sentences with subordinate clauses—20-35 words typical. Ideas unfold WITHIN sentences via "and," "but," "because," "which," "while." Paragraphs: 4-6 sentences developing one idea fully.
>
> Use the author's words from the transcript. One example per point. Trust readers.
>
> **Banned:** sentences under 12 words (except 2-3 per essay), single-sentence paragraphs (max 1), bullets, blockquotes, "Here's the thing," "That's the key," signposting, AI-speak, em dashes.
>
> **Style options:**
> – Standard: Conversational rhythm, ideas that surprise, warmth without saccharine.
> – Punchy: Crisp sentences, ideas land fast, energy without hype.
> – Reflective: Slower pace, ideas unfold, room for nuance and complexity.
>
> Output: First-person essay with Markdown formatting. Length as required by the content.

### 8.8 Follow-Up agent prompt

> You are an **interview analyst** reviewing a completed session to identify opportunities for a meaningful follow-up conversation.
>
> Input:
> – The original plan (topic, research goal, angle).
> – The session transcript.
> – Any notes captured during the session.
>
> Focus on finding:
> – **Unexplored threads** – Topics mentioned but not fully explored.
> – **Gaps in the story** – Missing context, unexplained decisions, skipped details.
> – **Areas to deepen** – Points that deserve more examples or elaboration.
> – **New angles** – Fresh perspectives that emerged but weren't pursued.
>
> Output: 3 compelling follow-up topics, each with 2-3 specific questions.

---

## 9. API Key Security

### 9.1 Keychain Storage

```swift
actor KeychainManager {
    private let service = "com.yourapp.interviewer"
    private let account = "openai_api_key"

    func saveAPIKey(_ key: String) throws {
        let data = key.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)  // Remove existing
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func retrieveAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

### 9.2 Security Best Practices

* Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` - key doesn't backup to iCloud
* Never log API keys
* Allow users to view (masked) and delete their key
* Optionally add biometric protection (Face ID / Touch ID)

---

## 10. UX Flows

### 10.1 First Launch / Settings

1. User opens app → Check for API key in Keychain
2. If no key → Show **SettingsView** with prompt to enter OpenAI API key
3. User pastes key → Validate with test API call → Save to Keychain
4. Navigate to **HomeView**

### 10.2 Pre-interview

1. User on **HomeView**:
   * Enters topic
   * (Optional) Adds context
   * Sets target duration (slider)
   * Clicks "Generate interview plan"

2. App calls `agentCoordinator.generatePlan()`:
   * Shows loading indicator with Planner agent activity

3. Plan returns → **PlanEditorView**:
   * Shows: Topic, Research goal & angle (editable), Sections, Questions
   * User edits until satisfied
   * Clicks "Approve plan" → Save to SwiftData

### 10.3 Live interview

1. On "Start interview":
   * App creates `InterviewSession` in SwiftData
   * Opens Realtime WebSocket connection
   * Starts audio capture
   * Starts timer

2. Live call:
   * User speaks → Audio to Realtime → Response audio plays
   * Transcripts accumulate
   * Every ~10 seconds (or on turn end):
     * Call `agentCoordinator.processLiveUpdate()`
     * Update UI (section coverage, gaps)
     * Call `realtimeClient.updateInstructions()` with next question

3. **Exploration time**: 14-minute default includes flexibility for whimsical discovery. When unexpected but fascinating threads emerge, follow them.

4. **Closing detection**: When AI says closing phrase ("thank you for sharing..."):
   * Immediately stop audio capture and Realtime connection
   * Red "End" button becomes blue "Next" button
   * User clicks "Next" → save session → navigate to Analysis

5. Manual end: User can click "End" at any time (with confirmation dialog)

### 10.4 Post-interview

1. App gathers final data:
   * Full transcript
   * Final notes
   * Plan

2. Call `agentCoordinator.generateAnalysis()`:
   * Show **AnalysisView**:
     * Research goal + main claims
     * Themes, tensions, selected quotes
   * User can adjust title or mark favorite quotes
   * Save to SwiftData

3. Call `agentCoordinator.generateDraft()`:
   * Show **DraftView** with markdown preview
   * User can:
     * Copy to clipboard
     * Export to `.md` file
     * Share (iOS share sheet / macOS share)
     * Select from 3 styles (Standard, Punchy, Reflective)

### 10.5 Follow-up Sessions

1. From **HomeView**, user sees recent conversations with two icons:
   * **Resume** (arrow.clockwise) → Continue with follow-up
   * **Fresh** (plus.circle) → Start new session with same topic

2. On "Resume":
   * Navigate to **FollowUpView**
   * Follow-Up Agent analyzes previous session
   * Shows 3 suggested topics with questions

3. User selects topics → "Start 6-Minute Follow-Up":
   * Creates new Plan with `isFollowUp = true` and `previousSessionId`
   * Navigates to InterviewView
   * Interviewer references previous conversation

4. Post-interview:
   * Analysis combines both transcripts
   * Writer weaves both conversations into unified narrative
   * Essay reflects the full depth of combined sessions

---

## 11. Cross-Platform Considerations

### 11.1 Shared Code (~90%)

* All models (SwiftData)
* All agents (actors)
* OpenAIClient, RealtimeClient
* KeychainManager
* Business logic

### 11.2 Platform-Specific

| Feature | macOS | iOS |
|---------|-------|-----|
| Audio session | Not needed | `AVAudioSession` required |
| Audio devices | CoreAudio device selection | `AVAudioSession` route selection |
| Window management | Multi-window support | Single window |
| Menu bar | Native menus | No menu bar |
| Keyboard shortcuts | Essential | Optional |
| Share | `NSSharingServicePicker` | `UIActivityViewController` |

### 11.3 Conditional Compilation

```swift
#if os(iOS)
import UIKit
// iOS-specific code
#elseif os(macOS)
import AppKit
// macOS-specific code
#endif
```

---

## 12. Implementation Phases

### Phase 1 – Core Infrastructure

* Create multiplatform SwiftUI app
* Implement `KeychainManager`
* Implement `OpenAIClient` actor
* Set up SwiftData models
* Build `SettingsView` for API key entry
* Test Chat Completions API

### Phase 2 – Planner Agent + UI

* Implement `PlannerAgent`
* Build `HomeView` and `PlanEditorView`
* Test plan generation end-to-end
* Persist plans to SwiftData

### Phase 3 – Realtime Voice

* Implement `RealtimeClient` (WebSocket)
* Build `AudioEngine` (AVAudioEngine)
* Create `InterviewView` with live transcript
* Test voice conversation flow

### Phase 4 – Multi-Agent Orchestration

* Implement Note-Taker, Researcher, Orchestrator agents
* Build `AgentCoordinator` for parallel execution
* Add live updates during interview
* Build agent activity UI meters
* Update Realtime instructions dynamically

### Phase 5 – Analysis + Writer

* Implement Analysis and Writer agents
* Build `AnalysisView` and `DraftView`
* Add export functionality (clipboard, file, share)
* Polish markdown preview

### Phase 6 – Polish + Testing

* Liquid Glass design refinement
* Error handling and resilience
* Accessibility features
* Unit and integration tests
* End-to-end testing

---

## 13. Testing Strategy

The project includes a comprehensive test suite with **158 tests across 10 test suites**, verifying agent orchestration without requiring live API calls.

### Test Suite Overview

| Suite | Tests | Focus |
|-------|-------|-------|
| AgentCoordinator Integration | 18 | State management, question tracking, phase management |
| End-to-End Orchestration | 18 | Full interview lifecycle, parallel execution, error handling |
| FollowUp Data Flow | 18 | Session context, transcript merging, quote deduplication |
| NoteTaker Merge | 17 | Jaccard similarity deduplication, accumulation |
| NotesState | 7 | Helper methods, coverage tracking |
| OrchestratorDecision | 7 | Phase enums, JSON roundtrip |
| Phase Transition | 22 | Phase boundaries (15%/85%), callbacks, locking |
| PlanSnapshot | 6 | Structure validation, serialization |
| Property Completeness | 30 | All model properties, merge appends (not overwrites) |
| ResearcherAgent | 15 | Topic tracking, deduplication, cooldown |

### Test Architecture

```
Tests/
├── Mocks/
│   └── MockOpenAIClient.swift        # Deterministic responses by schema name
├── AgentCoordinatorTests.swift
├── NoteTakerMergeTests.swift
├── ResearcherAgentTests.swift
├── FollowUpDataFlowTests.swift
├── PhaseTransitionTests.swift
├── EndToEndOrchestrationTests.swift
├── PropertyCompletenessTests.swift
├── NotesStateTests.swift
├── OrchestratorDecisionTests.swift
└── PlanSnapshotTests.swift
```

### Key Test Patterns

* **Mock Client**: `MockOpenAIClient` returns fixture data based on `responseFormat.schemaName`, enabling deterministic testing
* **Jaccard Similarity**: Tests verify deduplication thresholds (0.7 for ideas, 0.6 for contradictions, 0.8 for quotes)
* **Parallel Execution**: Tests confirm NoteTaker and Researcher run concurrently, with Orchestrator sequential after both
* **Phase Locking**: Tests verify phase transitions only move forward and lock at wrap_up
* **Merge Behavior**: Tests ensure `NotesState.merge` appends data rather than overwriting

### Running Tests

```bash
# Run all agent tests
xcodebuild test -scheme Interviewer -destination 'platform=macOS' \
    -only-testing:InterviewerTests

# Run specific suite
xcodebuild test -scheme Interviewer -destination 'platform=macOS' \
    -only-testing:InterviewerTests/PhaseTransitionTests
```

---

## 14. Logging & Telemetry

* **Local logging only** (no remote telemetry by default)
* Log:
  * Realtime connection events
  * Audio errors
  * API failures (without PII)
  * Agent invocation times

---

## 15. Future Extensions

* **iCloud sync** - Sync sessions across devices
* **Multi-session analytics** - "How your views evolved over time"
* **Custom voice selection** - Choose Realtime voice
* **Style fine-tuning** - Learn user's writing style from past posts
* **Collaboration** - Share plans and drafts with team members

---

This PLAN.md contains the architectural choices, data models, prompts, and implementation details needed for a fully native Swift app (no backend) that runs on macOS 26 Tahoe and iOS 26, using SwiftUI with Liquid Glass design, Swift actors/async streams, SwiftData for persistence, and OpenAI's Realtime + Chat Completions APIs as the sole AI stack.
