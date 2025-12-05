# Interviewer

### *"You don't know what you know, until you are asked."*

---

There exists, in every expert's mind, a treasury of hard-won wisdom—stories of failure and triumph, opinions forged in the fires of experience, insights so deeply embedded they have become invisible to their keeper. The tragedy of expertise is that its possessor often cannot see it clearly enough to share it.

This application proposes a remedy.

**Interviewer** is a voice-first companion that conducts podcast-style conversations with subject-matter experts, drawing forth their knowledge through the ancient art of the well-timed question. But beneath its conversational veneer operates a symphony of specialized agents—a Note-Taker cataloging every story and claim, a Researcher pursuing promising threads in real-time, an Orchestrator conducting the flow of inquiry like a maestro before an orchestra.

The result? A conversation that feels remarkably like speaking with an old friend who happens to be deeply curious about precisely the right things.

---

## The Art of Drawing Out What You Didn't Know You Knew

Consider the peculiar difficulty of writing about one's own expertise. The blank page stares back, demanding structure from chaos, narrative from the jumbled collection of experiences that constitute "knowing something well." Most experts freeze, overwhelmed not by what they don't know, but by everything they do.

An interview changes everything.

When someone asks "What was the moment you realized this approach wouldn't work?"—suddenly the story pours forth, vivid and immediate. The questioner provides what the blank page cannot: direction, curiosity, and the gentle pressure of another mind wanting to understand.

**Interviewer** amplifies this dynamic through multi-agent orchestration. While you converse naturally with a single voice, six specialized intelligences collaborate invisibly:

- **The Planner** designs the interview's arc before a word is spoken
- **The Note-Taker** tracks every insight, gap, and contradiction
- **The Researcher** pursues new concepts as they arise, enriching the conversation
- **The Orchestrator** selects each question with strategic precision
- **The Analyst** distills the conversation into themes and claims
- **The Writer** transforms the whole into a publishable narrative

You speak for fifteen minutes. You receive an essay that captures what you actually believe.

---

## Why Agents? Why Orchestration?

A single intelligence, however capable, cannot simultaneously listen, remember, research, strategize, and write. Humans manage this through specialization—the interviewer asks, the producer researches, the editor shapes.

This application follows the same principle. Each agent focuses on one task, performs it excellently, and passes its insights to colleagues. The Orchestrator receives the Note-Taker's observations about uncovered topics, the Researcher's discoveries about unfamiliar terms, and decides: "Now is the moment to ask about that failure they mentioned in passing."

The effect is uncanny. The conversation feels guided by someone who was paying attention, someone who caught the throw-away comment and recognized its significance. Because, in a sense, someone was.

---

## The Promise

Speak for a quarter hour about something you know deeply. Receive prose that sounds like you at your most articulate—the essay you would have written if you had infinite patience and perfect recall.

This is not transcription. This is translation: from the meandering river of spoken thought to the structured clarity of the written word.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Native Swift App                          │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                      SwiftUI Views                          │  │
│  │   Home  │  Plan Editor  │  Interview  │  Analysis  │  Draft │  │
│  └────────────────────────────────────────────────────────────┘  │
│                              │                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                   Agent Coordinator                         │  │
│  │                                                              │  │
│  │   ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │  │
│  │   │ Planner │  │Note-Taker│  │Researcher│  │Orchestrator│  │  │
│  │   └─────────┘  └──────────┘  └──────────┘  └────────────┘  │  │
│  │   ┌─────────┐  ┌──────────┐                                 │  │
│  │   │ Analyst │  │  Writer  │                                 │  │
│  │   └─────────┘  └──────────┘                                 │  │
│  └────────────────────────────────────────────────────────────┘  │
│                              │                                    │
│  ┌────────────┐  ┌───────────────┐  ┌──────────────────────┐    │
│  │   Audio    │  │    OpenAI     │  │      Keychain        │    │
│  │   Engine   │  │    Client     │  │      Manager         │    │
│  └────────────┘  └───────────────┘  └──────────────────────┘    │
│                              │                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                       SwiftData                             │  │
│  │        Sessions  │  Plans  │  Transcripts  │  Drafts        │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                           OpenAI                                 │
│   ┌─────────────────────┐    ┌────────────────────────────────┐ │
│   │    Realtime API     │    │    Chat Completions API        │ │
│   │  (Voice + STT/TTS)  │    │   (Structured Outputs)         │ │
│   └─────────────────────┘    └────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Platform Requirements

- macOS 26 (Tahoe) or iOS 26
- OpenAI API key with Realtime API access
- A microphone and a quarter hour to spare

---

## Getting Started

1. Clone this repository
2. Open in Xcode 26+
3. Build and run
4. Enter your OpenAI API key in Settings
5. Choose a topic you know well
6. Speak

The rest happens automatically.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

*Built with Swift, SwiftUI, and a profound respect for the difficulty of knowing what you know.*
