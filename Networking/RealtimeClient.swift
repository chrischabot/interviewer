import Foundation
import AVFoundation

// MARK: - Realtime Event Types

enum RealtimeEventType: String, Codable {
    // Client events
    case sessionUpdate = "session.update"
    case inputAudioBufferAppend = "input_audio_buffer.append"
    case inputAudioBufferCommit = "input_audio_buffer.commit"
    case inputAudioBufferClear = "input_audio_buffer.clear"
    case conversationItemCreate = "conversation.item.create"
    case responseCreate = "response.create"
    case responseCancel = "response.cancel"

    // Server events
    case error = "error"
    case sessionCreated = "session.created"
    case sessionUpdated = "session.updated"
    case inputAudioBufferCommitted = "input_audio_buffer.committed"
    case inputAudioBufferCleared = "input_audio_buffer.cleared"
    case inputAudioBufferSpeechStarted = "input_audio_buffer.speech_started"
    case inputAudioBufferSpeechStopped = "input_audio_buffer.speech_stopped"
    case conversationItemCreated = "conversation.item.created"
    case conversationItemInputAudioTranscriptionCompleted = "conversation.item.input_audio_transcription.completed"
    case conversationItemInputAudioTranscriptionFailed = "conversation.item.input_audio_transcription.failed"
    case conversationItemTruncated = "conversation.item.truncated"
    case conversationItemDeleted = "conversation.item.deleted"
    case responseCreated = "response.created"
    case responseDone = "response.done"
    case responseOutputItemAdded = "response.output_item.added"
    case responseOutputItemDone = "response.output_item.done"
    case responseContentPartAdded = "response.content_part.added"
    case responseContentPartDone = "response.content_part.done"
    case responseTextDelta = "response.text.delta"
    case responseTextDone = "response.text.done"
    case responseAudioTranscriptDelta = "response.audio_transcript.delta"
    case responseAudioTranscriptDone = "response.audio_transcript.done"
    case responseAudioDelta = "response.audio.delta"
    case responseAudioDone = "response.audio.done"
    case responseFunctionCallArgumentsDelta = "response.function_call_arguments.delta"
    case responseFunctionCallArgumentsDone = "response.function_call_arguments.done"
    case rateLimitsUpdated = "rate_limits.updated"
}

// MARK: - Realtime Messages

struct RealtimeEvent: Codable {
    let type: String
    let eventId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
    }
}

struct SessionUpdateEvent: Codable {
    let type: String
    let session: SessionConfig

    init(session: SessionConfig) {
        self.type = "session.update"
        self.session = session
    }
}

struct SessionConfig: Codable {
    var modalities: [String]?
    var instructions: String?
    var voice: String?
    var inputAudioFormat: String?
    var outputAudioFormat: String?
    var inputAudioTranscription: InputAudioTranscription?
    var turnDetection: TurnDetection?
    var temperature: Double?
    var maxResponseOutputTokens: MaxTokens?

    enum CodingKeys: String, CodingKey {
        case modalities
        case instructions
        case voice
        case inputAudioFormat = "input_audio_format"
        case outputAudioFormat = "output_audio_format"
        case inputAudioTranscription = "input_audio_transcription"
        case turnDetection = "turn_detection"
        case temperature
        case maxResponseOutputTokens = "max_response_output_tokens"
    }
}

struct InputAudioTranscription: Codable {
    let model: String

    init(model: String = "whisper-1") {
        self.model = model
    }
}

struct TurnDetection: Codable {
    let type: String
    let threshold: Double?
    let prefixPaddingMs: Int?
    let silenceDurationMs: Int?
    let createResponse: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case threshold
        case prefixPaddingMs = "prefix_padding_ms"
        case silenceDurationMs = "silence_duration_ms"
        case createResponse = "create_response"
    }

    static func serverVAD(threshold: Double = 0.5, prefixPaddingMs: Int = 300, silenceDurationMs: Int = 500, createResponse: Bool = true) -> TurnDetection {
        TurnDetection(
            type: "server_vad",
            threshold: threshold,
            prefixPaddingMs: prefixPaddingMs,
            silenceDurationMs: silenceDurationMs,
            createResponse: createResponse
        )
    }
}

enum MaxTokens: Codable {
    case int(Int)
    case inf

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self), stringValue == "inf" {
            self = .inf
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected Int or 'inf'")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .inf:
            try container.encode("inf")
        }
    }
}

struct InputAudioBufferAppendEvent: Codable {
    let type: String
    let audio: String  // base64 encoded

    init(audio: String) {
        self.type = "input_audio_buffer.append"
        self.audio = audio
    }
}

struct InputAudioBufferCommitEvent: Codable {
    let type: String

    init() {
        self.type = "input_audio_buffer.commit"
    }
}

struct InputAudioBufferClearEvent: Codable {
    let type: String

    init() {
        self.type = "input_audio_buffer.clear"
    }
}

struct ResponseCreateEvent: Codable {
    let type: String

    init() {
        self.type = "response.create"
    }
}

// MARK: - Server Response Types

struct ServerEvent: Codable {
    let type: String
    let eventId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
    }
}

struct AudioDeltaEvent: Codable {
    let type: String
    let eventId: String?
    let responseId: String?
    let itemId: String?
    let outputIndex: Int?
    let contentIndex: Int?
    let delta: String  // base64 encoded audio

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case delta
    }
}

struct TranscriptDeltaEvent: Codable {
    let type: String
    let eventId: String?
    let responseId: String?
    let itemId: String?
    let outputIndex: Int?
    let contentIndex: Int?
    let delta: String

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case delta
    }
}

struct TranscriptDoneEvent: Codable {
    let type: String
    let eventId: String?
    let responseId: String?
    let itemId: String?
    let outputIndex: Int?
    let contentIndex: Int?
    let transcript: String

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case responseId = "response_id"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case transcript
    }
}

struct InputTranscriptionCompletedEvent: Codable {
    let type: String
    let eventId: String?
    let itemId: String?
    let contentIndex: Int?
    let transcript: String

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case itemId = "item_id"
        case contentIndex = "content_index"
        case transcript
    }
}

struct ErrorEvent: Codable {
    let type: String
    let eventId: String?
    let error: ErrorDetail

    struct ErrorDetail: Codable {
        let type: String?
        let code: String?
        let message: String
        let param: String?
    }

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case error
    }
}

// MARK: - Realtime Client Delegate

protocol RealtimeClientDelegate: AnyObject, Sendable {
    func realtimeClientDidConnect(_ client: RealtimeClient) async
    func realtimeClientDidDisconnect(_ client: RealtimeClient, error: Error?) async
    func realtimeClient(_ client: RealtimeClient, didReceiveAudio data: Data) async
    func realtimeClient(_ client: RealtimeClient, didReceiveTranscript text: String, isFinal: Bool, speaker: String) async
    func realtimeClient(_ client: RealtimeClient, didReceiveError error: Error) async
    func realtimeClient(_ client: RealtimeClient, didDetectSpeechStart: Bool) async
    func realtimeClient(_ client: RealtimeClient, didDetectSpeechEnd: Bool) async
}

// MARK: - Realtime Client Errors

enum RealtimeClientError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case invalidResponse
    case apiError(String)
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to Realtime API"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let message):
            return "API error: \(message)"
        case .noAPIKey:
            return "No API key configured"
        }
    }
}

// MARK: - Realtime Client

actor RealtimeClient {
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var receiveTask: Task<Void, Never>?
    private var sessionCreatedContinuation: CheckedContinuation<Void, Error>?
    private var sessionUpdatedContinuation: CheckedContinuation<Void, Error>?

    weak var delegate: RealtimeClientDelegate?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {}

    // MARK: - Connection

    func connect(instructions: String, voice: String = "shimmer") async throws {
        NSLog("[RealtimeClient] 🔌 Starting connection...")

        guard let apiKey = try? await KeychainManager.shared.retrieveAPIKey() else {
            NSLog("[RealtimeClient] ❌ No API key found")
            throw RealtimeClientError.noAPIKey
        }
        NSLog("[RealtimeClient] ✓ API key retrieved (length: %d)", apiKey.count)

        let model = "gpt-4o-realtime-preview"
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)") else {
            throw RealtimeClientError.connectionFailed("Invalid URL")
        }
        NSLog("[RealtimeClient] 📡 Connecting to: %@", url.absoluteString)

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        self.webSocket = task
        task.resume()
        NSLog("[RealtimeClient] ✓ WebSocket task resumed")

        isConnected = true

        // Start receiving messages
        receiveTask = Task { [weak self] in
            await self?.receiveMessages()
        }

        // Wait for session.created before configuring
        NSLog("[RealtimeClient] ⏳ Waiting for session.created...")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.sessionCreatedContinuation = continuation
        }
        NSLog("[RealtimeClient] ✓ Received session.created")

        // Configure session with audio
        NSLog("[RealtimeClient] 📤 Configuring session...")
        try await configureSession(instructions: instructions, voice: voice)
        NSLog("[RealtimeClient] ✓ Session configured")

        await delegate?.realtimeClientDidConnect(self)
        NSLog("[RealtimeClient] ✓ Connection complete")
    }

    func disconnect() async {
        receiveTask?.cancel()
        receiveTask = nil

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false

        await delegate?.realtimeClientDidDisconnect(self, error: nil)
    }

    var connected: Bool {
        isConnected
    }

    // MARK: - Session Configuration

    private func configureSession(instructions: String, voice: String) async throws {
        let config = SessionConfig(
            modalities: ["text", "audio"],
            instructions: instructions,
            voice: voice,
            inputAudioFormat: "pcm16",
            outputAudioFormat: "pcm16",
            inputAudioTranscription: InputAudioTranscription(model: "whisper-1"),
            turnDetection: .serverVAD(threshold: 0.5, prefixPaddingMs: 300, silenceDurationMs: 3000, createResponse: true),
            temperature: 0.8,
            maxResponseOutputTokens: .inf
        )

        NSLog("[RealtimeClient] 📋 Config: modalities=text,audio, voice=%@, format=pcm16", voice)

        let event = SessionUpdateEvent(session: config)
        try await send(event)

        // Wait for session.updated confirmation
        NSLog("[RealtimeClient] ⏳ Waiting for session.updated...")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.sessionUpdatedContinuation = continuation
        }
        NSLog("[RealtimeClient] ✓ Session update confirmed")

        // Trigger AI to start the conversation
        NSLog("[RealtimeClient] 🎤 Triggering initial response...")
        try await triggerResponse()
    }

    func triggerResponse() async throws {
        let event = ResponseCreateEvent()
        try await send(event)
    }

    /// Commits the audio buffer and triggers a response - use this when create_response is false
    func commitAndRespond() async throws {
        NSLog("[RealtimeClient] 📤 Committing audio buffer and triggering response...")
        try await commitAudioBuffer()
        try await triggerResponse()
    }

    func updateInstructions(_ instructions: String) async throws {
        let config = SessionConfig(instructions: instructions)
        let event = SessionUpdateEvent(session: config)
        try await send(event)
    }

    // MARK: - Audio

    func sendAudio(_ audioData: Data) async throws {
        guard isConnected else { throw RealtimeClientError.notConnected }

        let base64Audio = audioData.base64EncodedString()
        let event = InputAudioBufferAppendEvent(audio: base64Audio)
        try await send(event)
    }

    func commitAudioBuffer() async throws {
        guard isConnected else { throw RealtimeClientError.notConnected }
        let event = InputAudioBufferCommitEvent()
        try await send(event)
    }

    func clearAudioBuffer() async throws {
        guard isConnected else { throw RealtimeClientError.notConnected }
        NSLog("[RealtimeClient] 🗑️ Clearing audio buffer")
        let event = InputAudioBufferClearEvent()
        try await send(event)
    }

    // MARK: - Sending

    private func send<T: Encodable>(_ event: T) async throws {
        guard let webSocket = webSocket else {
            throw RealtimeClientError.notConnected
        }

        let data = try encoder.encode(event)

        // Convert to string for text WebSocket frame (required by OpenAI Realtime API)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw RealtimeClientError.invalidResponse
        }

        // Log what we're sending (except audio data which is large)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {
            if type != "input_audio_buffer.append" {
                NSLog("[RealtimeClient] 📤 Sending: %@", type)
                NSLog("[RealtimeClient]    Payload: %@", String(jsonString.prefix(500)))
            }
        }

        // IMPORTANT: Send as TEXT frame, not binary - OpenAI Realtime API requires text frames for JSON
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        try await webSocket.send(message)
    }

    // MARK: - Receiving

    private func receiveMessages() async {
        guard let webSocket = webSocket else {
            NSLog("[RealtimeClient] ⚠️ receiveMessages called but no webSocket")
            return
        }

        NSLog("[RealtimeClient] 👂 Starting to receive messages...")

        while !Task.isCancelled && isConnected {
            do {
                let message = try await webSocket.receive()
                await handleMessage(message)
            } catch {
                NSLog("[RealtimeClient] ❌ Receive error: %@", String(describing: error))
                if !Task.isCancelled {
                    isConnected = false
                    await delegate?.realtimeClientDidDisconnect(self, error: error)
                }
                break
            }
        }
        NSLog("[RealtimeClient] 🛑 Stopped receiving messages")
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        @unknown default:
            return
        }

        // Parse event type first
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeString = json["type"] as? String else {
            NSLog("[RealtimeClient] ⚠️ Could not parse message type")
            return
        }

        // Log all received events (except high-frequency audio)
        if !typeString.contains("audio.delta") {
            NSLog("[RealtimeClient] 📥 Received: %@", typeString)
        }

        switch typeString {
        case "error":
            if let event = try? decoder.decode(ErrorEvent.self, from: data) {
                NSLog("[RealtimeClient] ❌ Error: %@", event.error.message)
                NSLog("[RealtimeClient]    Type: %@", event.error.type ?? "unknown")
                NSLog("[RealtimeClient]    Code: %@", event.error.code ?? "unknown")

                let error = RealtimeClientError.apiError(event.error.message)

                // If we're still waiting for session events, fail the connection
                if let continuation = sessionCreatedContinuation {
                    sessionCreatedContinuation = nil
                    continuation.resume(throwing: error)
                } else if let continuation = sessionUpdatedContinuation {
                    sessionUpdatedContinuation = nil
                    continuation.resume(throwing: error)
                } else {
                    await delegate?.realtimeClient(self, didReceiveError: error)
                }
            } else {
                // Try to print raw error
                if let errorJson = json["error"] as? [String: Any] {
                    NSLog("[RealtimeClient] ❌ Raw error: %@", String(describing: errorJson))
                }
            }

        case "response.audio.delta":
            do {
                let event = try decoder.decode(AudioDeltaEvent.self, from: data)
                if let audioData = Data(base64Encoded: event.delta) {
                    await delegate?.realtimeClient(self, didReceiveAudio: audioData)
                } else {
                    NSLog("[RealtimeClient] ⚠️ Failed to decode base64 audio delta")
                }
            } catch {
                NSLog("[RealtimeClient] ⚠️ Failed to decode audio delta event: %@", error.localizedDescription)
            }

        case "response.audio_transcript.delta":
            if let event = try? decoder.decode(TranscriptDeltaEvent.self, from: data) {
                NSLog("[RealtimeClient] 📝 Transcript delta: '%@'", event.delta)
                await delegate?.realtimeClient(self, didReceiveTranscript: event.delta, isFinal: false, speaker: "assistant")
            } else {
                NSLog("[RealtimeClient] ⚠️ Failed to decode transcript delta")
            }

        case "response.audio_transcript.done":
            if let event = try? decoder.decode(TranscriptDoneEvent.self, from: data) {
                NSLog("[RealtimeClient] ✅ Transcript done: '%@'", String(event.transcript.prefix(100)))
                // Send the complete transcript with isFinal=true
                await delegate?.realtimeClient(self, didReceiveTranscript: event.transcript, isFinal: true, speaker: "assistant")
            } else {
                NSLog("[RealtimeClient] ⚠️ Failed to decode transcript done")
            }

        case "conversation.item.input_audio_transcription.completed":
            if let event = try? decoder.decode(InputTranscriptionCompletedEvent.self, from: data) {
                await delegate?.realtimeClient(self, didReceiveTranscript: event.transcript, isFinal: true, speaker: "user")
            }

        case "input_audio_buffer.speech_started":
            await delegate?.realtimeClient(self, didDetectSpeechStart: true)

        case "input_audio_buffer.speech_stopped":
            await delegate?.realtimeClient(self, didDetectSpeechEnd: true)

        case "session.created":
            // Resume the continuation to signal connection is ready
            if let continuation = sessionCreatedContinuation {
                sessionCreatedContinuation = nil
                continuation.resume()
            }

        case "session.updated":
            // Resume the continuation to signal session is configured
            if let continuation = sessionUpdatedContinuation {
                sessionUpdatedContinuation = nil
                continuation.resume()
            }

        case "response.created", "response.done",
             "response.output_item.added", "response.output_item.done",
             "response.content_part.added", "response.content_part.done",
             "response.audio.done", "input_audio_buffer.committed",
             "conversation.item.created", "rate_limits.updated":
            // These events are informational, no action needed
            break

        default:
            // Unknown event type
            break
        }
    }
}
