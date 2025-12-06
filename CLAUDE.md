# CLAUDE.md - Interviewer App

## Overview

A **fully native Swift app** (macOS 26 Tahoe + iOS 26) that interviews users podcast-style on a topic and produces blog-ready narrative essays. Uses **OpenAI exclusively** for all AI capabilities. **No backend server required** - all agents run directly on-device.

**Core Vision**: "Talk for 14 minutes about a deep topic. The app interviews you, live-researches threads, tracks insights, and generates a strong narrative that can ship as a blog post. When there's more to say, resume with a 6-minute follow-up that enriches the original."

**Tagline**: *"You don't know what you know, until you are asked."*

---

## Tone of Voice

### Project Documentation & Copy

When writing prose for this project—README, CLAUDE.md, user-facing copy, marketing—channel the style of an **eloquent old-style journalist**: witty, succinct, to the point, and colorfully descriptive.

**Characteristics:**
- **Narrative over bullet points** when explaining concepts
- **Vivid metaphors** that illuminate rather than obscure (agents as "a symphony," "a maestro before an orchestra")
- **Short, punchy sentences** mixed with longer flowing ones for rhythm
- **Respect for the reader's intelligence**—explain *why* something matters, not just *what* it does
- **A touch of gravitas** when discussing ideas ("The tragedy of expertise is that its possessor often cannot see it clearly enough to share it")
- **Avoid jargon** when plain language serves; use technical terms only when precision demands

The goal: prose that sounds like it was written by someone who genuinely cares about ideas and has thought carefully about how to express them.

### Generated Essays (Writer Agent Output)

The essays produced by the Writer agent are different. They must capture **the interviewee's voice**, not ours.

**Approach:**
- Extract the speaker's natural patterns, cadence, and word choices from their transcript
- Mirror their vocabulary—if they say "gnarly problem" don't write "complex challenge"
- Preserve their sentence rhythms and the way they build arguments
- Keep their characteristic phrases and verbal tics that make them *them*

**The output should be:**
- Well-written and elegantly formatted
- Eloquent and flowing
- Structured with clear narrative arc
- But unmistakably in *their* voice, not a generic polished style

The goal: an essay the interviewee reads and thinks "Yes, that's exactly what I meant—and exactly how I would have said it if I'd had time to write it properly."

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Platform | macOS 26 Tahoe + iOS/iPadOS 26 (universal app) |
| Language | Swift 6+ |
| UI Framework | SwiftUI (Liquid Glass design) |
| Concurrency | Swift Concurrency (actors, `async`/`await`, `AsyncStream`) |
| Audio | `AVAudioEngine` + `AVAudioSession` (iOS) + `CoreAudio` (macOS device selection) |
| Networking | `URLSessionWebSocketTask` (Realtime), `URLSession` (HTTP) |
| AI Provider | **OpenAI only** (Realtime + Chat Completions APIs) |
| Persistence | **SwiftData** (local storage) |
| Security | **Keychain** (API key storage) |

---

## Architecture (No Backend)

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

### Why No Backend?

1. **Simpler** - One Swift codebase, no server to deploy
2. **Lower latency** - Direct API calls to OpenAI
3. **No server costs** - Only pay for OpenAI usage
4. **Better privacy** - Data stays on device (except OpenAI calls)
5. **iOS-native** - Can't ship Node.js/Python with iOS apps

### Data Flow

**Pre-interview:**
```
User Input → PlannerAgent → OpenAI → Plan JSON → SwiftData → PlanEditorView
```

**Live interview:**
```
Mic → RealtimeClient (WebSocket) → OpenAI Realtime → Speaker + Transcripts
                                                          ↓
Every ~10s:  AgentCoordinator.processLiveUpdate()
             ├── NoteTakerAgent (parallel)
             ├── ResearcherAgent (parallel)
             └── OrchestratorAgent (sequential)
                      ↓
             RealtimeClient.updateInstructions()
```

**Post-interview:**
```
Transcript + Notes → AnalysisAgent → AnalysisSummary
AnalysisSummary → WriterAgent → Markdown Draft → DraftView
```

---

## Multi-Agent System

Seven specialized agents, all **Swift actors** calling OpenAI Chat Completions API directly:

| Agent | Purpose | When |
|-------|---------|------|
| **Planner** | Generate interview rubric (research goal, angle, sections, questions) | Pre-interview |
| **Note-Taker** | Track key ideas, stories, claims, gaps, contradictions | Live |
| **Researcher** | Web search for new concepts (OpenAI web_search tool) | Live |
| **Orchestrator** | Choose next question based on plan, notes, time | Live |
| **Analysis** | Extract claims, themes, tensions, quotable lines | Post-interview |
| **Writer** | Generate first-person blog-style narrative essay | Post-interview |
| **Follow-Up** | Analyze completed sessions, suggest 3 topics for continuation | Resume flow |

### Agent Execution Pattern

```swift
actor AgentCoordinator {
    private let plannerAgent: PlannerAgent
    private let noteTakerAgent: NoteTakerAgent
    private let researcherAgent: ResearcherAgent
    private let orchestratorAgent: OrchestratorAgent
    private let analysisAgent: AnalysisAgent
    private let writerAgent: WriterAgent

    // Live interview: Note-Taker and Researcher run in parallel
    func processLiveUpdate(...) async throws {
        async let notes = noteTakerAgent.updateNotes(...)
        async let research = researcherAgent.research(...)
        let (updatedNotes, items) = try await (notes, research)

        // Orchestrator runs after, using both results
        let decision = try await orchestratorAgent.decideNextQuestion(...)
    }
}
```

### Agent Design Philosophy

- Start from a **research goal**, not just a topic
- Encode **hypotheses** to probe or challenge
- Balance **consistency** (backbone questions) with **flexibility** (follow-up tangents)
- Prefer questions that elicit **stories, failures, trade-offs, strong opinions**
- Produce **killer essays**, not social-science reports

---

## Key Data Models (SwiftData)

### Plan
```swift
@Model final class Plan {
    @Attribute(.unique) var id: UUID
    var topic: String
    var researchGoal: String
    var angle: String
    var targetSeconds: Int  // Default: 840 (14 minutes)

    // Follow-up support
    var isFollowUp: Bool = false
    var previousSessionId: UUID?  // The session this continues
    var followUpContext: String = ""  // Selected topics/questions

    @Relationship(deleteRule: .cascade) var sections: [Section]
}

@Model final class Section {
    var id: UUID
    var title: String
    var importance: String  // "high" | "medium" | "low"
    var backbone: Bool
    @Relationship(deleteRule: .cascade) var questions: [Question]
}

@Model final class Question {
    var id: UUID
    var text: String
    var role: String  // "backbone" | "followup"
    var priority: Int  // 1 = must-hit
}
```

### Interview Session
```swift
@Model final class InterviewSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var elapsedSeconds: Int
    var plan: Plan?
    @Relationship(deleteRule: .cascade) var utterances: [Utterance]
    @Relationship(deleteRule: .cascade) var notesState: NotesStateModel?
    @Relationship(deleteRule: .cascade) var analysis: AnalysisSummaryModel?
    @Relationship(deleteRule: .cascade) var drafts: [Draft]
}
```

### Notes (Agent I/O Structs)
```swift
struct NotesState: Codable {
    var keyIdeas: [KeyIdea]
    var stories: [Story]
    var claims: [Claim]
    var gaps: [Gap]
    var contradictions: [Contradiction]
    var possibleTitles: [String]
}

struct OrchestratorDecision: Codable {
    let phase: String  // "opening" | "deep_dive" | "wrap_up"
    let nextQuestion: NextQuestion
    let interviewerBrief: String
}

struct AnalysisSummary: Codable {
    let researchGoal: String
    let mainClaims: [MainClaim]
    let themes: [String]
    let tensions: [String]
    let quotes: [Quote]
    let suggestedTitle: String
}
```

---

## Client Architecture

### Navigation States
```swift
enum NavigationState {
    case home
    case planning(planId: UUID)
    case interview(planId: UUID)
    case analysis(sessionId: UUID)
    case draft(sessionId: UUID)
    case followUp(sessionId: UUID)  // Resume flow
    case settings
}
```

### Views
- `HomeView` - Topic/goal/duration input, recent conversations with resume/fresh icons
- `PlanEditorView` - Edit sections & questions
- `InterviewView` - Live voice UI with timer, transcript, agent meters
- `AnalysisView` - Research goal answers, themes, quotes
- `DraftView` - Markdown preview, 4 style options, export
- `FollowUpView` - Analyze previous session, select topics for 6-min follow-up
- `SettingsView` - API key management, audio device selection

### State Management
```swift
actor SessionState {
    var id: UUID
    var transcript: [Utterance]
    var notesState: NotesState
    var currentQuestion: QuestionRef?
    var elapsedSeconds: Int
    var agentActivity: AgentActivityWindow
}

@MainActor
class SessionViewModel: ObservableObject {
    let sessionState: SessionState
    let agentCoordinator: AgentCoordinator
    let realtimeClient: RealtimeClient
    let audioEngine: AudioEngine
    // @Published properties for SwiftUI
}
```

---

## OpenAI Integration

### OpenAIClient Actor
```swift
actor OpenAIClient {
    private let apiKey: String

    // Chat Completions with Structured Outputs
    func chatCompletion(
        messages: [Message],
        model: String = "gpt-4o",
        responseFormat: JSONSchema?,
        tools: [Tool]? = nil
    ) async throws -> ChatCompletionResponse
}
```

### Structured Outputs
All agents use `strict: true` for guaranteed JSON schema adherence:
```swift
responseFormat: JSONSchema(name: "plan_schema", strict: true, schema: ...)
```

### Web Search (Research Agent)
```swift
let tools = [Tool(type: "web_search", webSearch: WebSearchConfig(searchContextSize: "medium"))]
```

### Realtime API (Voice)
```swift
actor RealtimeClient {
    func connect(model: String = "gpt-4o-realtime-preview") async throws
    func sendAudio(_ audioData: Data) async throws
    func updateInstructions(_ instructions: String) async throws
}
```

---

## Audio Pipeline

### Capture (Mic → Realtime)
1. `AVAudioEngine` input node with `installTap`
2. Format: Linear PCM, mono, 16-bit, 16-24kHz
3. Convert to base64, send as `input_audio_buffer.append`
4. Realtime's server-side VAD handles turn detection

### iOS Audio Session
```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
try session.setActive(true)
```

### Playback (Realtime → Speaker)
1. Receive `response.audio.delta` events
2. Decode base64 to `AVAudioPCMBuffer`
3. Schedule on `AVAudioPlayerNode`

### Echo Cancellation & Feedback Prevention

The app uses a multi-layer strategy to prevent the microphone from picking up AI speech output:

#### Layer 1: Apple Voice Processing (Primary)
```swift
// Enable BEFORE engine.start()
try inputNode.setVoiceProcessingEnabled(true)
inputNode.isVoiceProcessingAGCEnabled = true  // Automatic gain control
```
- Hardware-tuned AEC (Acoustic Echo Cancellation)
- Noise suppression
- Automatic gain control
- **User Tip**: Enable "Voice Isolation" in Control Center for maximum quality

#### Layer 2: Server Buffer Clearing
When AI starts speaking, clear any stale audio in OpenAI's buffer:
```swift
// On first audio chunk from AI
try await realtimeClient.clearAudioBuffer()  // "input_audio_buffer.clear"
```

#### Layer 3: Mic Muting During AI Speech
- Stop sending audio while `isAssistantSpeaking = true`
- Add 2-second "bleed guard" after last AI audio chunk
- UI shows yellow indicator when mic is muted

#### Layer 4: Extended Silence Detection
- VAD configured with `silenceDurationMs: 3000` (3 seconds)
- AI waits for clear pause before responding
- Manual trigger button as fallback

#### Alternative Solutions (Not Implemented)
- **Krisp SDK**: Commercial ML-based noise cancellation
- **WebRTC**: Battle-tested but complex integration
- **AECAudioStream**: Swift package for VoiceProcessingIO

### macOS Voice Processing Multi-Channel Fix

**Problem**: When `setVoiceProcessingEnabled(true)` is called on macOS, the input node may return a multi-channel format (commonly 5 channels) instead of the expected stereo or mono. This caused the audio converter to fail silently, resulting in no audio being sent to the API.

**Root Cause**: Apple's voice processing uses a multi-channel format internally for echo cancellation and noise suppression. The first channel (channel 0) contains the processed voice data.

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

    // Copy just channel 0
    for i in 0..<Int(buffer.frameLength) {
        monoData[0][i] = floatData[0][i]
    }

    return monoBuffer
}
```

**Usage in tap callback**:
```swift
// If multi-channel (voice processing), extract channel 0 first
let monoBuffer: AVAudioPCMBuffer
if buffer.format.channelCount > 1 {
    monoBuffer = self.extractChannel0(from: buffer) ?? buffer
} else {
    monoBuffer = buffer
}

// Then resample to 24kHz and convert to PCM16
let audioData = self.resampleAndConvert(monoBuffer, ...)
```

### Audio Device Management (macOS)

The app allows users to select input/output audio devices on macOS via Settings.

#### AudioDeviceManager
```swift
@MainActor
@Observable
final class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    var inputDevices: [AudioDevice] = []
    var outputDevices: [AudioDevice] = []
    var selectedInputDeviceID: String?
    var selectedOutputDeviceID: String?
}
```

#### Device Enumeration (CoreAudio)
Uses `AudioObjectGetPropertyData` with:
- `kAudioHardwarePropertyDevices` to enumerate all devices
- `kAudioDevicePropertyDeviceNameCFString` for device names
- `kAudioDevicePropertyDeviceUID` for persistent device IDs
- `kAudioDevicePropertyStreams` to check input/output capability

#### Setting System Default Device
When user selects a device, set it as the system default:
```swift
private func setInputDevice(uid: String) {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var deviceID = device.audioObjectID
    AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        UInt32(MemoryLayout<AudioObjectID>.size),
        &deviceID
    )
}
```

**Note**: AVAudioEngine automatically uses the system default device, so setting the system default is sufficient.

#### CoreAudio CFString Memory Management
Use `Unmanaged<CFString>?` instead of direct CFString variables:
```swift
// Correct approach
var nameRef: Unmanaged<CFString>?
var dataSize = UInt32(MemoryLayout<CFString?>.size)

status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &nameRef)

guard status == noErr, let name = nameRef?.takeUnretainedValue() else { return nil }
return name as String
```

#### Device Change Notifications
Listen for device connect/disconnect:
```swift
AudioObjectAddPropertyListenerBlock(
    AudioObjectID(kAudioObjectSystemObject),
    &propertyAddress,  // kAudioHardwarePropertyDevices
    DispatchQueue.main
) { _, _ in
    Task { @MainActor in
        self.refreshDevices()
    }
}
```

---

## API Key Security

### Keychain Storage
```swift
actor KeychainManager {
    func saveAPIKey(_ key: String) throws  // kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    func retrieveAPIKey() throws -> String?
    func deleteAPIKey() throws
}
```

### Best Practices
- Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (no iCloud backup)
- Never log API keys
- Validate key on entry with test API call
- Optional biometric protection (Face ID / Touch ID)

---

## UX Flow

### 1. First Launch
- Check Keychain for API key
- If missing → SettingsView to enter OpenAI API key
- Validate → Save to Keychain → HomeView

### 2. Topic Capture (HomeView)
- Enter topic, optional context
- Set duration (default 14 min, range 5-20)
- "Generate interview plan"
- Recent conversations show resume/fresh icons

### 3. Plan Review (PlanEditorView)
- Edit research goal & angle
- Reorder sections, edit questions
- Mark must-hit vs optional
- "Approve plan"

### 4. Live Interview (InterviewView)
- Timer (mm:ss), current question display
- Live speaker-tagged transcript with auto-scroll
- Section coverage indicators
- Agent activity meters (bottom bar)
- **Exploration time**: Built-in flexibility for whimsical discovery
- **Closing detection**: AI closing phrase → stop audio → blue "Next" button

### 5. Analysis (AnalysisView)
- Main claims, themes, tensions
- Quotable lines
- Adjust title
- For follow-ups: analyzes combined transcript

### 6. Draft (DraftView)
- Markdown preview
- 4 style options: Standard, Punchy, Reflective, Zinsser
- Copy / Export / Share

### 7. Follow-Up (FollowUpView)
- Resume icon on HomeView → navigate here
- Follow-Up Agent analyzes previous session
- Shows 3 suggested topics with questions
- User selects topics → 6-minute follow-up interview
- Combined analysis and essay generation

---

## Cross-Platform (macOS + iOS)

### Shared Code (~90%)
- All SwiftData models
- All agents (actors)
- OpenAIClient, RealtimeClient, KeychainManager
- Business logic

### Platform-Specific
| Feature | macOS | iOS |
|---------|-------|-----|
| Audio session | Not needed | `AVAudioSession` required |
| Audio devices | CoreAudio device selection | `AVAudioSession` route selection |
| Window mgmt | Multi-window | Single window |
| Menu bar | Native menus | None |
| Share | `NSSharingServicePicker` | `UIActivityViewController` |

### Conditional Compilation
```swift
#if os(iOS)
// iOS-specific
#elseif os(macOS)
// macOS-specific
#endif
```

---

## Liquid Glass Design

- Blur + translucency for sidebars/toolbars
- Elevated center panel with higher contrast
- Respect system toggles: `Reduce transparency`, `Tinted` vs `Clear`
- Follow 26.x spacing, corner radii, toolbar styling

---

## Agent Activity UI

Bottom bar with horizontal meters:
- Planner (pre-interview)
- Notes, Research, Orchestrator (live)
- Writer (post-interview)

Each shows `recentActivityScore` (0-1), animated pulse when > 0.7.

---

## Non-Functional Requirements

| Requirement | Target |
|-------------|--------|
| Voice latency | < 500ms perceived lag |
| Resilience | Graceful disconnect/reconnect, agent fallbacks |
| Privacy | Local data only (SwiftData), Keychain for API key |
| Accessibility | VoiceOver, Dynamic Type, contrast settings |

---

## Implementation Phases

1. **Core Infrastructure**: Keychain, OpenAIClient, SwiftData models, SettingsView
2. **Planner + UI**: PlannerAgent, HomeView, PlanEditorView
3. **Realtime Voice**: RealtimeClient, AudioEngine, InterviewView
4. **Multi-Agent**: Note-Taker, Researcher, Orchestrator, AgentCoordinator
5. **Analysis + Writer**: AnalysisAgent, WriterAgent, AnalysisView, DraftView
6. **Polish**: Liquid Glass, error handling, accessibility, testing

---

## Project Structure

```
Interviewer/
├── App/
│   ├── InterviewerApp.swift          # @main, SwiftData container
│   └── AppCoordinator.swift          # Navigation state
├── Views/
│   ├── HomeView.swift
│   ├── PlanEditorView.swift
│   ├── InterviewView.swift
│   ├── AnalysisView.swift
│   ├── DraftView.swift
│   ├── FollowUpView.swift
│   └── SettingsView.swift
├── Models/                            # SwiftData @Model classes
│   ├── Plan.swift
│   ├── Section.swift
│   ├── Question.swift
│   ├── InterviewSession.swift
│   ├── Utterance.swift
│   ├── NotesStateModel.swift
│   ├── AnalysisSummaryModel.swift
│   └── Draft.swift
├── Agents/                            # Swift actors
│   ├── AgentCoordinator.swift
│   ├── PlannerAgent.swift
│   ├── NoteTakerAgent.swift
│   ├── ResearcherAgent.swift
│   ├── OrchestratorAgent.swift
│   ├── AnalysisAgent.swift
│   ├── WriterAgent.swift
│   └── FollowUpAgent.swift
├── Networking/
│   ├── OpenAIClient.swift            # Chat Completions API
│   ├── RealtimeClient.swift          # WebSocket to Realtime API
│   ├── AudioEngine.swift             # AVAudioEngine wrapper (capture + playback)
│   └── AudioDeviceManager.swift      # CoreAudio device enumeration (macOS)
├── Security/
│   └── KeychainManager.swift         # API key storage
├── State/
│   ├── SessionState.swift            # Actor for live session
│   └── SessionViewModel.swift        # @MainActor ObservableObject
└── Prompts/
    └── AgentPrompts.swift            # System prompts for all agents
```

---

## Development Patterns & Lessons Learned

### SwiftData + Actors
When passing SwiftData `@Model` objects to actor methods, create **snapshot structs** first:
```swift
// DON'T: Pass @Model directly to actor (causes data race warnings)
let result = try await agent.analyze(session: session)

// DO: Create Sendable snapshot, then pass
let snapshot = SessionSnapshot(id: session.id, utterances: ...)
let result = try await agent.analyze(session: snapshot)
```

### SwiftData Predicates
Capture values before predicates—don't reference external objects:
```swift
// DON'T: Reference external object in predicate
#Predicate { $0.plan?.id == plan.id }

// DO: Capture the value first
let planId = plan.id
#Predicate { $0.plan?.id == planId }
```

### Follow-Up Session Merging
When analyzing or writing for follow-up sessions, **always combine transcripts**:
```swift
if plan.isFollowUp, let previousSessionId = plan.previousSessionId {
    let previousTranscript = await fetchPreviousTranscript(sessionId: previousSessionId)
    transcript = previousTranscript + currentTranscript
}
```

### Closing Detection Flow
When AI says closing phrase:
1. Immediately stop audio capture and Realtime connection
2. Don't wait—stop everything to prevent phantom responses
3. Change UI from red "End" to blue "Next" button
4. User controls when to proceed to Analysis

### Writer Agent Voice
Essays are **first-person ghostwriting**, not third-party journalism:
- ❌ "One expert reminds us..." / "According to the interviewee..."
- ✅ "I learned..." / "In my experience..." / "Here's what I discovered..."

Avoid phantom argument patterns:
- ❌ "It's not just about X" / "More than merely Y"
- ✅ State positively what something IS, not what it's NOT

### Default Durations
- Standard interview: **14 minutes** (includes exploration time)
- Follow-up interview: **6 minutes** (focused deep-dive)

### Agent Processing Optimization
The coordinator implements smart skip logic to reduce API costs:
- **No-content skip**: When no new transcript content, NoteTaker and Researcher are skipped
- **Decision reuse**: When Orchestrator ran recently (~30s) with no new content, previous decision is reused
- **Phase locking**: Once wrap_up phase (85%) is reached, phase cannot regress

---

## Test Suite

The project includes **158 tests across 10 test suites** verifying agent orchestration without live API calls:

| Suite | Focus |
|-------|-------|
| AgentCoordinator Integration | State, question tracking, phases |
| End-to-End Orchestration | Full lifecycle, parallel execution |
| FollowUp Data Flow | Context preservation, transcript merging |
| NoteTaker Merge | Jaccard similarity deduplication |
| Phase Transition | Boundaries, callbacks, phase locking |
| Property Completeness | All model properties, merge behavior |

### Running Tests
```bash
xcodebuild test -scheme Interviewer -destination 'platform=macOS' \
    -only-testing:InterviewerTests
```

See `AGENT_ORCHESTRATION.md` for detailed test documentation.

---

## Constraints

- **Single AI provider**: OpenAI only (no Apple/Google STT/TTS)
- **No backend**: Everything runs natively in Swift
- **Platforms**: macOS 26 + iOS 26 (universal app)
- **User-provided API key**: Stored in Keychain

---

## Swift & SwiftUI Coding Guidelines

Follow these guidelines to ensure modern, safe API usage aligned with Apple best practices.

### Core Requirements

- Target iOS/macOS 26.0 or later
- Swift 6.2 or later with modern Swift concurrency
- SwiftUI backed by `@Observable` classes for shared data
- Do not introduce third-party frameworks without asking first
- Avoid UIKit unless requested

### Swift Instructions

- Always mark `@Observable` classes with `@MainActor`
- Assume strict Swift concurrency rules are being applied
- Prefer Swift-native alternatives to Foundation methods (e.g., `replacing(_:with:)` over `replacingOccurrences(of:with:)`)
- Prefer modern Foundation API (e.g., `URL.documentsDirectory`, `appending(path:)`)
- Never use C-style number formatting like `String(format:)`; use `Text(..., format: .number.precision(...))` instead
- Prefer static member lookup (`.circle` over `Circle()`, `.borderedProminent` over `BorderedProminentButtonStyle()`)
- Never use `DispatchQueue.main.async()`; use modern Swift concurrency instead
- Filter text with `localizedStandardContains()` over `contains()` for user input
- Avoid force unwraps and force `try` unless unrecoverable

### SwiftUI Instructions

- Use `foregroundStyle()` instead of `foregroundColor()`
- Use `clipShape(.rect(cornerRadius:))` instead of `cornerRadius()`
- Use the `Tab` API instead of `tabItem()`
- Use `@Observable` classes, never `ObservableObject`
- Use `onChange()` with two parameters or none; never the one-parameter variant
- Use `Button` over `onTapGesture()` unless you need tap location or count
- Use `Task.sleep(for:)` over `Task.sleep(nanoseconds:)`
- Never use `UIScreen.main.bounds`; prefer `GeometryReader` or `containerRelativeFrame()`
- Extract views into separate `View` structs, not computed properties
- Use Dynamic Type; don't force specific font sizes
- Use `NavigationStack` with `navigationDestination(for:)`, never `NavigationView`
- For image buttons, always include text: `Button("Label", systemImage: "icon", action:)`
- Use `bold()` over `fontWeight(.bold)`
- Avoid `GeometryReader` when `containerRelativeFrame()` or `visualEffect()` works
- Use `ForEach(x.enumerated(), id: \.element.id)` without converting to array
- Use `.scrollIndicators(.hidden)` over `showsIndicators: false`
- Avoid `AnyView` unless absolutely required
- Avoid hard-coded padding/spacing values unless requested
- Avoid UIKit colors in SwiftUI code

### SwiftData Instructions (CloudKit)

If using CloudKit sync:
- Never use `@Attribute(.unique)`
- Model properties must have default values or be optional
- All relationships must be optional

### Project Structure

- Use consistent folder layout by app features
- Follow strict naming conventions for types, properties, methods
- Break types into separate Swift files
- Write unit tests for core logic; UI tests only when unit tests aren't possible
- Add code comments and documentation as needed
- Never commit secrets or API keys to the repository

### PR Guidelines

- Ensure SwiftLint returns no warnings or errors before committing
