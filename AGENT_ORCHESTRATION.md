# Agent Orchestration System

The Interviewer app employs a multi-agent architecture where six specialized AI agents collaborate to conduct interviews, gather insights, and produce narrative essays. This document describes how these agents work, communicate, and coordinate throughout the interview lifecycle.

---

## Table of Contents

1. [Philosophy](#philosophy)
2. [Agent Overview](#agent-overview)
3. [The Three Phases](#the-three-phases)
4. [Data Structures](#data-structures)
5. [Live Interview Orchestration](#live-interview-orchestration)
6. [Question Coverage Tracking](#question-coverage-tracking)
7. [Information Flow](#information-flow)
8. [Agent Communication Patterns](#agent-communication-patterns)
9. [Transcript Windowing](#transcript-windowing)
10. [State Management](#state-management)

---

## Philosophy

The agent system is built on several core principles:

**Research-Goal Driven**: Every interview starts with a *research goal*—not just a topic. The goal defines what we're trying to understand or argue. All agents orient their work around answering this goal.

**Narrative Over Report**: The system is designed to produce "killer essays," not social-science reports. Agents prioritize stories, strong opinions, trade-offs, and failures over dry facts.

**Balance Consistency with Flexibility**: The plan provides *backbone questions* that must be asked, but the system adapts in real-time to follow interesting tangents, fill gaps, and probe contradictions.

**Skeptical Verification**: The Researcher agent doesn't just find supporting information—it actively fact-checks claims and looks for counterpoints.

---

## Agent Overview

### Pre-Interview Agent

| Agent | Purpose | Inputs | Outputs |
|-------|---------|--------|---------|
| **Planner** | Design the interview rubric | Topic, context, duration | Research goal, angle, sections with questions |

### Live Interview Agents

| Agent | Purpose | Inputs | Outputs |
|-------|---------|--------|---------|
| **NoteTaker** | Extract insights in real-time | Transcript, current notes, plan | Updated notes (ideas, stories, claims, gaps, contradictions) |
| **Researcher** | Fact-check and gather context | Transcript, existing research | New research items (definitions, counterpoints, metrics) |
| **Orchestrator** | Decide the next question | Plan, notes, research, timing | Next question, phase, interviewer brief |

### Post-Interview Agents

| Agent | Purpose | Inputs | Outputs |
|-------|---------|--------|---------|
| **Analysis** | Extract essay-ready insights | Full transcript, notes, plan | Main claims, themes, tensions, quotes, title |
| **Writer** | Generate the narrative essay | Transcript, analysis, plan, style | Markdown essay |

---

## The Three Phases

The Orchestrator divides the interview into three phases based on elapsed time:

### Opening Phase (First ~15% of time)

**Goal**: Clarify context and stakes. Let the expert orient the conversation.

**Question Types**:
- Broad, open-ended questions
- "Set the stage" questions
- Questions that establish the expert's credibility and perspective

**Orchestrator Behavior**:
- Prefers backbone questions from the plan
- Avoids deep-dive follow-ups
- Focuses on P1 (must-hit) opening questions

### Deep Dive Phase (Middle ~70% of time)

**Goal**: This is where the magic happens. Extract stories, probe nuances, and follow interesting threads.

**Question Types**:
- Backbone questions from the plan (ensuring coverage)
- Follow-ups on interesting tangents the expert introduced
- Gap-filling questions from NoteTaker
- Contradiction-clarifying questions
- Research-informed questions

**Orchestrator Behavior**:
- Alternates between plan questions and organic follow-ups
- Uses research insights to ask smarter questions
- Probes gaps and contradictions identified by NoteTaker
- References what the expert said: "You mentioned X..."

### Wrap-Up Phase (Final ~15% of time)

**Goal**: Synthesize and reflect. Capture quotable closing thoughts.

**Question Types**:
- "What's the one thing you wish more people understood about X?"
- "If you could go back and do one thing differently..."
- "What's the biggest misconception about X?"
- Synthesis questions that tie threads together

**Orchestrator Behavior**:
- Deprioritizes new backbone questions
- Focuses on reflection and summary
- Ensures the conversation has a satisfying close

---

## Data Structures

### PlanSnapshot

A lightweight, Codable representation of the interview plan that agents can safely pass between actors (avoiding SwiftData threading issues).

```swift
struct PlanSnapshot {
    let topic: String
    let researchGoal: String
    let angle: String
    let sections: [SectionSnapshot]

    struct SectionSnapshot {
        let id: String
        let title: String
        let importance: String  // "high" | "medium" | "low"
        let questions: [QuestionSnapshot]
    }

    struct QuestionSnapshot {
        let id: String          // UUID for tracking
        let text: String
        let role: String        // "backbone" | "followup"
        let priority: Int       // 1 = must-hit, 2 = important, 3 = nice-to-have
        let notesForInterviewer: String
    }
}
```

### NotesState

Accumulated insights from the interview, updated by NoteTaker each cycle.

```swift
struct NotesState {
    var keyIdeas: [KeyIdea]           // Core insights and "aha moments"
    var stories: [Story]               // Concrete anecdotes with impact
    var claims: [Claim]                // Strong opinions with confidence levels
    var gaps: [Gap]                    // Topics touched but not explored
    var contradictions: [Contradiction] // Conflicting statements to clarify
    var sectionCoverage: [SectionCoverage]  // Quality tracking per section
    var quotableLines: [QuotableLine]  // Memorable quotes captured live
    var possibleTitles: [String]       // Emerging essay title candidates
}
```

#### SectionCoverage Structure
```swift
struct SectionCoverage {
    let id: String              // Matches section ID from plan
    let sectionTitle: String
    let coverageQuality: String // "none" | "shallow" | "adequate" | "deep"
    let keyPointsCovered: [String]
    let missingAspects: [String]
    let suggestedFollowup: String?
}
```

Coverage quality levels:
- **none**: Section hasn't been touched
- **shallow**: Mentioned briefly but no substance
- **adequate**: Main points covered but room for more
- **deep**: Thoroughly explored with examples and nuance

#### QuotableLine Structure
```swift
struct QuotableLine {
    let text: String           // The exact quote from the expert
    let speaker: String        // Usually "expert"
    let potentialUse: String   // "hook" | "section_header" | "pull_quote" | "conclusion" | "tweet"
    let topic: String          // What this quote is about
    let strength: String       // "good" | "great" | "exceptional"
}
```

#### Gap Structure
```swift
struct Gap {
    let description: String        // What was touched but not explored
    let suggestedFollowup: String  // A question to fill this gap
}
```

#### Contradiction Structure
```swift
struct Contradiction {
    let description: String
    let firstQuote: String         // The initial statement
    let secondQuote: String        // The conflicting statement
    let suggestedClarificationQuestion: String
}
```

### OrchestratorDecision

The output of each Orchestrator cycle, guiding the next question.

```swift
struct OrchestratorDecision {
    let phase: String              // "opening" | "deep_dive" | "wrap_up"
    let nextQuestion: NextQuestion
    let interviewerBrief: String   // How to ask the question
}

struct NextQuestion {
    let text: String               // The question to ask
    let targetSectionId: String    // Which section this relates to
    let source: String             // "plan" | "gap" | "contradiction" | "research"
    let sourceQuestionId: String?  // ID if from plan, nil otherwise
    let expectedAnswerSeconds: Int // Estimated response time
}
```

### ResearchItem

Context gathered by the Researcher agent.

```swift
struct ResearchItem {
    let topic: String
    let kind: String               // "definition" | "counterpoint" | "example" | "metric" | etc.
    let summary: String            // 2-3 sentence summary
    let howToUseInQuestion: String // How the interviewer can use this
    let priority: Int              // 1 = very important, 2 = moderate, 3 = nice-to-have
}
```

---

## Live Interview Orchestration

### The Update Cycle

Every ~10 seconds during the interview, the `AgentCoordinator` runs a live update cycle:

```
┌─────────────────────────────────────────────────────────────────┐
│                     processLiveUpdate()                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────┐     ┌──────────────┐                          │
│   │  NoteTaker  │     │  Researcher  │    ← Run in PARALLEL     │
│   │             │     │              │                          │
│   │ Extracts:   │     │ Searches:    │                          │
│   │ - Key ideas │     │ - Definitions│                          │
│   │ - Stories   │     │ - Metrics    │                          │
│   │ - Claims    │     │ - Counterpts │                          │
│   │ - Gaps      │     │ - Context    │                          │
│   │ - Conflicts │     │              │                          │
│   └──────┬──────┘     └──────┬───────┘                          │
│          │                   │                                   │
│          └─────────┬─────────┘                                   │
│                    ▼                                             │
│          ┌─────────────────┐                                     │
│          │   Orchestrator  │    ← Runs AFTER parallel agents    │
│          │                 │                                     │
│          │ Receives:       │                                     │
│          │ - Updated notes │                                     │
│          │ - New research  │                                     │
│          │ - Plan coverage │                                     │
│          │ - Timing info   │                                     │
│          │                 │                                     │
│          │ Decides:        │                                     │
│          │ - Current phase │                                     │
│          │ - Next question │                                     │
│          │ - How to ask it │                                     │
│          └────────┬────────┘                                     │
│                   ▼                                              │
│          ┌─────────────────┐                                     │
│          │ Realtime API    │    ← Instructions sent to voice    │
│          │ Instructions    │                                     │
│          └─────────────────┘                                     │
└─────────────────────────────────────────────────────────────────┘
```

### Parallel vs Sequential Execution

**Parallel (async let)**:
- NoteTaker and Researcher run simultaneously
- They don't depend on each other's output
- Reduces overall latency

**Sequential**:
- Orchestrator runs after both parallel agents complete
- It needs their combined output to make informed decisions

```swift
// Parallel execution
async let notesTask = runNoteTaker(...)
async let researchTask = runResearcher(...)
let (updatedNotes, newResearchItems) = try await (notesTask, researchTask)

// Sequential execution
let decision = try await orchestratorAgent.decideNextQuestion(context: context)
```

---

## Question Coverage Tracking

The system tracks which plan questions have been asked to ensure proper coverage.

### How It Works

1. **Plan Loading**: Each question in the plan has a unique UUID
2. **Prompt Display**: Questions are shown to the Orchestrator with their IDs:
   ```
   ○ NOT ASKED [id: ABC123] [P1] What got you into distributed systems?
   ✓ ASKED [id: DEF456] [P2] Tell me about a major failure...
   ```
3. **Decision Output**: Orchestrator returns `sourceQuestionId` when choosing a plan question
4. **Marking**: The coordinator marks the question as asked
5. **Feedback Loop**: Next cycle, that question shows as "✓ ASKED"

### Fallback Matching

If the LLM doesn't return the exact question ID, the system uses text similarity matching:

```swift
private func findMatchingQuestionId(questionText: String, in plan: PlanSnapshot) -> String? {
    // Calculate Jaccard similarity between question texts
    // Match if similarity > 0.6 threshold
    // Return best matching ID from unasked questions
}
```

### Coverage Signals to Orchestrator

The Orchestrator receives:
- Per-section coverage: `[2/4 asked, high importance]`
- Per-question status: `✓ ASKED` or `○ NOT ASKED`
- Priority indicators: `[P1]`, `[P2]`, `[P3]`

This helps it prioritize unasked P1 questions while avoiding repetition.

---

## Information Flow

### What Each Agent Sees

#### NoteTaker Receives:
- **Transcript window**: Last 20 entries
- **Current notes**: Previous cycle's accumulated insights
- **Plan context**: Topic, research goal, angle

#### Researcher Receives:
- **Transcript window**: Last 20 entries
- **Existing research**: All previously found items
- **Topic**: For relevance filtering

#### Orchestrator Receives:
- **Plan with coverage**: All sections/questions with asked/unasked status
- **Transcript window**: Last 30 entries (larger for decision context)
- **Notes**: Full current state (gaps, contradictions, etc.)
- **Research**: All accumulated research items
- **Timing**: Elapsed seconds, target seconds, calculated phase

### What Flows Back to the Interview

The `LiveUpdateResult` contains instructions for the Realtime API:

```swift
struct LiveUpdateResult {
    let notes: NotesState                    // Updated notes for persistence
    let newResearchItems: [ResearchItem]     // New research to accumulate
    let decision: OrchestratorDecision       // The decision made
    let interviewerInstructions: String      // Formatted for Realtime API
}
```

The `interviewerInstructions` string is formatted as:

```markdown
## Current Phase: DEEP_DIVE

## Next Question to Ask
You mentioned "failing fast" earlier. Can you walk me through a specific time when that philosophy actually backfired?

## How to Ask It
This should feel like a natural follow-up, not an interrogation. Start with a reference to what they said, then probe the edge case gently.

## Research Context
- **Fail Fast principle**: Originally from manufacturing, popularized in software by Kent Beck. Some critics argue it can lead to premature optimization of processes.

## Gaps to Explore (if natural)
- The team structure during the migration wasn't fully explained

## Contradictions to Clarify
- Earlier said "documentation is crucial" but also "we shipped without docs for 6 months"
```

---

## Agent Communication Patterns

### NoteTaker → Orchestrator

NoteTaker's gaps and contradictions directly influence Orchestrator's question selection:

```
NoteTaker finds:
  Gap: "Expert mentioned 'the dark days' but didn't elaborate"
  Suggested followup: "Can you tell me more about what you mean by 'the dark days'?"

Orchestrator may decide:
  source: "gap"
  text: "You referred to 'the dark days' a moment ago. What was happening during that period?"
```

### Researcher → Orchestrator

Research items provide context the Orchestrator can weave into questions:

```
Researcher finds:
  Topic: "Circuit breaker pattern"
  Summary: "Popularized by Michael Nygard in 'Release It!' (2007). Prevents cascade failures."
  How to use: "If expert mentions this, ask about their implementation challenges"

Orchestrator may craft:
  "You mentioned circuit breakers. I know Michael Nygard popularized that pattern—what was
   your experience actually implementing it? Any surprises?"
```

### Orchestrator → Realtime API

The decision is formatted into natural language instructions that guide the AI interviewer:

- **Phase awareness**: Different tones for opening vs. deep dive vs. wrap-up
- **Question text**: The specific question to ask
- **Interviewer brief**: Tone, framing, what to listen for
- **Context injections**: Research facts, gaps to probe, contradictions to clarify

---

## Transcript Windowing

To control prompt size and latency, each agent receives a different-sized window of the transcript:

| Agent | Window Size | Rationale |
|-------|-------------|-----------|
| **NoteTaker** | 20 entries | Needs recent context to identify new insights |
| **Researcher** | 20 entries | Needs enough context to identify researchable topics |
| **Orchestrator** | 30 entries | Needs more context for decision-making |

```swift
private let maxTranscriptEntriesForNotes = 20
private let maxTranscriptEntriesForResearch = 20
private let maxTranscriptEntriesForOrchestrator = 30

private func windowTranscript(_ transcript: [TranscriptEntry], maxEntries: Int) -> [TranscriptEntry] {
    guard transcript.count > maxEntries else { return transcript }
    return Array(transcript.suffix(maxEntries))
}
```

---

## State Management

### Coordinator-Level State

The `AgentCoordinator` maintains session-level state:

```swift
actor AgentCoordinator {
    // Accumulated across the entire interview
    private var accumulatedResearch: [ResearchItem] = []
    private var askedQuestionIds: Set<String> = []
    private var finalNotes: NotesState = .empty

    // UI activity tracking
    private var agentActivity: [String: Double] = [:]
}
```

### Session Reset

When a new interview starts:

```swift
func startNewSession() async {
    accumulatedResearch = []      // Clear research
    askedQuestionIds = []         // Reset coverage tracking
    finalNotes = .empty           // Clear notes
    agentActivity = [:]           // Reset UI meters

    await researcherAgent.reset() // Clear researcher's topic cache
}
```

### Researcher Topic Freshness

The Researcher tracks which topics it has already researched to avoid duplicates:

```swift
actor ResearcherAgent {
    private var researchedTopics: Set<String> = []
    private var researchedAt: [String: Date] = [:]
    private let topicRefreshInterval: TimeInterval = 300  // 5 minutes
}
```

Topics can be re-researched after 5 minutes if new context emerges.

---

## Activity Tracking

Each agent's activity is tracked for the UI activity meters:

```swift
private func updateActivity(agent: String, score: Double) {
    agentActivity[agent] = score
}

// Usage during processing:
updateActivity(agent: "notes", score: 1.0)      // Start
// ... agent runs ...
updateActivity(agent: "notes", score: 0.5)      // Cooling down
```

The UI shows animated meters that pulse when agents are actively processing.

---

## Error Handling & Graceful Degradation

### Agent Failure Fallbacks

The system is designed to continue functioning even when individual agents fail. Each agent has a graceful fallback:

| Agent | On Failure | Fallback Behavior |
|-------|------------|-------------------|
| **NoteTaker** | Returns previous notes | Interview continues with existing insights |
| **Researcher** | Returns empty array | Interview continues without new research |
| **Orchestrator** | Returns fallback decision | System picks next unasked P1 question from plan |

### Fallback Decision Logic

When the Orchestrator fails, `createFallbackDecision()` provides a reasonable next step:

```swift
private func createFallbackDecision(from plan: PlanSnapshot, context: OrchestratorContext) -> OrchestratorDecision {
    // 1. Determine phase based on time
    let progress = Double(context.elapsedSeconds) / Double(context.targetSeconds)
    let phase = progress < 0.15 ? "opening" : (progress > 0.85 ? "wrap_up" : "deep_dive")

    // 2. Find first unasked question, prioritizing P1 > P2 > P3
    for priority in 1...3 {
        for section in plan.sections {
            for question in section.questions where question.priority == priority {
                if !askedQuestionIds.contains(question.id) {
                    return OrchestratorDecision(/* question from plan */)
                }
            }
        }
    }

    // 3. If all questions asked, use generic wrap-up
    return OrchestratorDecision(
        text: "Is there anything else you'd like to add that we haven't covered?",
        source: "gap"
    )
}
```

### Non-Throwing Live Update

The `processLiveUpdate()` function never throws—all agent calls are wrapped with fallbacks:

```swift
func processLiveUpdate(...) async -> LiveUpdateResult {
    // These never throw - failures return fallback values
    let (updatedNotes, newResearchItems) = await (
        runNoteTakerWithFallback(...),
        runResearcherWithFallback(...)
    )

    let decision = await runOrchestratorWithFallback(...)

    return LiveUpdateResult(...)
}
```

This ensures the interview can continue even if the AI backend is having issues.

### Retry Strategy

The `OpenAIClient` implements exponential backoff for transient failures:

```swift
private func withRetry<T>(operation: () async throws -> T) async throws -> T {
    var delay = baseDelaySeconds
    for attempt in 0..<maxRetries {
        do {
            return try await operation()
        } catch let error as OpenAIError where error.isRetryable {
            try await Task.sleep(for: .seconds(min(delay + jitter, maxDelaySeconds)))
            delay *= 2
        }
    }
    throw OpenAIError.maxRetriesExceeded(lastError: lastError)
}
```

### Realtime Instruction Update Failures

If updating the Realtime API instructions fails (network issues), the interview continues with the previous instructions:

```swift
do {
    try await realtimeClient.updateInstructions(result.interviewerInstructions)
} catch {
    NSLog("Failed to update Realtime instructions - continuing with existing")
    // Interview continues normally
}
```

---

## Post-Interview Pipeline

After the interview ends:

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│  Transcript │ ──▶ │  Analysis   │ ──▶ │    Writer    │
│  + Notes    │     │   Agent     │     │    Agent     │
│  + Plan     │     │             │     │              │
└─────────────┘     └─────────────┘     └──────────────┘
                           │                    │
                           ▼                    ▼
                    AnalysisSummary      Markdown Essay
                    - Main claims        - Title
                    - Themes             - Narrative
                    - Tensions           - Quotes
                    - Quotes             - Structure
                    - Title
```

The Analysis agent has access to:
- **Full transcript**: No windowing—sees everything
- **Accumulated notes**: All insights from the interview
- **Plan**: For goal assessment

The Writer agent receives:
- **Full transcript**: For pulling exact quotes
- **Analysis summary**: Structured insights to build from
- **Plan**: For context and angle
- **Style preference**: Standard, punchy, or reflective

---

## Debugging and Logging

The `AgentLogger` provides human-readable logging of agent activity:

```
[14:32:15] 🎛️ Processing update (45% through interview, 24 exchanges so far)
[14:32:15]    ↳ NoteTaker and Researcher working in parallel...
[14:32:17] 📝 NoteTaker found: 2 ideas (scaling challenges, team dynamics), 1 story (the outage)
[14:32:17] 🔍 Researcher wants to look up: circuit breaker pattern, CAP theorem
[14:32:18]    ↳ Researching "circuit breaker pattern" (definition)
[14:32:19]    ↳ Found: Popularized by Michael Nygard in 'Release It!'...
[14:32:19] 🔍 Researcher done — 1 new piece of context
[14:32:19]    ↳ Both finished, asking Orchestrator what to do next
[14:32:20] 🎯 Orchestrator deciding next move (45% done, 3 questions asked)
[14:32:21] 🎯 Orchestrator says: ask about "What surprised you most about..."
[14:32:21]    ↳ Phase: deep_dive, Reason: from the plan
[14:32:21] ✓ Question marked as asked (id: 8F3A2B1C..., method: direct ID)
[14:32:21] ✅ Update complete — now in deep_dive phase
```

---

## Summary

The agent orchestration system is designed to:

1. **Prepare thoughtfully** (Planner creates a research-driven rubric)
2. **Listen actively** (NoteTaker extracts insights in real-time)
3. **Verify skeptically** (Researcher fact-checks and finds counterpoints)
4. **Steer intelligently** (Orchestrator balances plan coverage with organic flow)
5. **Analyze deeply** (Analysis extracts essay-ready structure)
6. **Write compellingly** (Writer produces narrative that captures the expert's voice)

The system balances structure with spontaneity, ensuring that must-hit topics are covered while leaving room for the serendipitous moments that make great interviews.
