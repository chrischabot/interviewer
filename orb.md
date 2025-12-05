# SwiftUI Voice Orb (TTS Visualizer)

This guide shows how to build a glowing, pulsing “voice orb” in **SwiftUI** that reacts to **text‑to‑speech (TTS)** audio output.

It includes:

1. A `SpeechVisualizer` class that:
   - Generates speech audio buffers using `AVSpeechSynthesizer.write`.
   - Plays those buffers via `AVAudioEngine` + `AVAudioPlayerNode`.
   - Taps the engine’s mixer to compute a 0…1 `level` value based on audio amplitude.

2. A `VoiceOrbView` SwiftUI view that:
   - Shows a glowing orb.
   - Scales and glows based on the `level` from the audio.

3. A simple `ContentView` + `@main` app entry to wire it all up.

---

## 1. SpeechVisualizer (TTS + audio levels)

```swift
import SwiftUI
import AVFoundation

final class SpeechVisualizer: NSObject, ObservableObject {
    @Published var level: CGFloat = 0          // 0...1 for the orb
    @Published var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // MARK: - Public API

    func speak(_ text: String,
               language: String = "en-US",
               rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        stop()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSpeaking = true

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate  = rate

        // Generate speech buffers instead of auto‑playing
        synthesizer.write(utterance) { [weak self] buffer in
            guard let self else { return }
            guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

            // Apple calls the callback one last time with an "empty" buffer at the end.
            if pcmBuffer.frameLength == 0 {
                DispatchQueue.main.async {
                    self.finish()
                }
                return
            }

            DispatchQueue.main.async {
                self.enqueue(buffer: pcmBuffer)
            }
        }
    }

    func stop() {
        // reset UI state
        level = 0
        isSpeaking = false

        // tear down audio engine
        playerNode?.stop()
        if let mixer = engine?.mainMixerNode {
            mixer.removeTap(onBus: 0)
        }
        engine?.stop()
        engine?.reset()
        engine = nil
        playerNode = nil

        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Internal helpers

    private func finish() {
        // Let any queued buffers finish playing,
        // then gently fade level back to 0.
        withAnimation(.easeOut(duration: 0.25)) {
            self.level = 0
        }
        isSpeaking = false

        // You could delay teardown a bit if you want.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.stop()
        }
    }

    private func enqueue(buffer: AVAudioPCMBuffer) {
        // Lazily configure engine with the format from the first buffer
        if engine == nil {
            configureEngine(with: buffer.format)
        }

        guard let playerNode else { return }

        // Copy buffer to avoid any lifetime surprises
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                          frameCapacity: buffer.frameLength) else {
            return
        }
        copy.frameLength = buffer.frameLength

        if let src = buffer.floatChannelData,
           let dst = copy.floatChannelData {
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)

            for channel in 0..<channelCount {
                dst[channel].assign(from: src[channel], count: frameCount)
            }
        }

        playerNode.scheduleBuffer(copy, completionHandler: nil)
    }

    private func configureEngine(with format: AVAudioFormat) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Tap the mixer to get real-time amplitudes for visualization.
        installTap(on: engine.mainMixerNode)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback,
                                    mode: .spokenAudio,
                                    options: [.duckOthers])
            try session.setActive(true)

            try engine.start()
            player.play()
        } catch {
            print("Audio engine start error:", error)
        }

        self.engine = engine
        self.playerNode = player
    }

    private func installTap(on mixer: AVAudioMixerNode) {
        let format = mixer.outputFormat(forBus: 0)
        mixer.installTap(onBus: 0,
                         bufferSize: 1024,
                         format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        // AVAudioEngine's main mixer typically yields Float32 samples.
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Compute RMS
        var sum: Float = 0
        for i in 0..<frameCount {
            let s = channelData[i]
            sum += s * s
        }
        let rms = sqrt(sum / Float(frameCount))

        // Convert to dB
        let minRms: Float = 0.000_02           // avoid log(0)
        let clippedRms = max(minRms, rms)
        let db = 20 * log10(clippedRms)

        // Map from [-50, 0] dB to [0, 1]
        let minDb: Float = -50
        let clampedDb = max(minDb, db)
        let normalized = (clampedDb - minDb) / -minDb  // 0...1

        DispatchQueue.main.async {
            withAnimation(.linear(duration: 0.05)) {
                self.level = CGFloat(normalized)
            }
        }
    }
}
```

---

## 2. VoiceOrbView (glowing orb visualization)

```swift
import SwiftUI

struct VoiceOrbView: View {
    var level: CGFloat       // 0...1
    var isSpeaking: Bool

    private var clampedLevel: CGFloat {
        min(max(level, 0), 1)
    }

    var body: some View {
        let scale = 0.85 + 0.5 * clampedLevel
        let glowOpacity = 0.3 + 0.7 * clampedLevel

        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.6),
                            Color.purple.opacity(0.1)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .scaleEffect(scale * 1.3)
                .blur(radius: 30)
                .opacity(isSpeaking ? glowOpacity : 0)

            // Main orb
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.cyan,
                            Color.blue,
                            Color.purple
                        ]),
                        center: .center,
                        startRadius: 10,
                        endRadius: 80
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 2)
                )
                .scaleEffect(scale)

            // Subtle ring ripple
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.3),
                            Color.blue.opacity(0.8),
                            Color.cyan.opacity(0.3),
                            Color.purple.opacity(0.3)
                        ]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .scaleEffect(isSpeaking ? (1.0 + 0.7 * clampedLevel) : 0.9)
                .opacity(isSpeaking ? 0.8 : 0)
        }
        .frame(width: 160, height: 160)
        .animation(.easeOut(duration: 0.15), value: clampedLevel)
        .animation(.easeInOut(duration: 0.6), value: isSpeaking)
    }
}
```

---

## 3. SwiftUI wiring (ContentView + App)

```swift
struct ContentView: View {
    @StateObject private var speech = SpeechVisualizer()
    @State private var text: String = "Hello, this is a glowing voice orb."

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VoiceOrbView(level: speech.level,
                         isSpeaking: speech.isSpeaking)

            Text(speech.isSpeaking ? "Speaking…" : "Idle")
                .foregroundColor(.secondary)

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("Text to speak")
                    .font(.headline)

                TextEditor(text: $text)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            HStack(spacing: 16) {
                Button(action: {
                    speech.speak(text)
                }) {
                    Label("Speak", systemImage: "waveform.circle.fill")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive, action: {
                    speech.stop()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
            }
            .padding([.horizontal, .bottom])
        }
    }
}
```

```swift
@main
struct VoiceOrbApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

---

## Usage notes

- This example uses **text‑to‑speech only** (no microphone input), so you don’t need microphone permissions.
- You can tweak:
  - Colors and gradients in `VoiceOrbView`.
  - The RMS → dB mapping range in `process(buffer:)` to make the orb more/less sensitive.
  - Animation durations in both `SpeechVisualizer` and `VoiceOrbView` for smoother or snappier motion.

Drop these types into a SwiftUI iOS app project (Swift 6‑compatible), set `VoiceOrbApp` as the app entry, and you’ll get a glowing orb that pulses in sync with your TTS audio.
