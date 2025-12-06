import Foundation

// MARK: - Error Types

enum OpenAIError: Error, LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)
    case maxRetriesExceeded(lastError: Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your OpenAI API key in Settings."
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let message):
            return "HTTP error \(statusCode): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .maxRetriesExceeded(let lastError):
            return "Request failed after retries: \(lastError.localizedDescription)"
        }
    }

    /// Whether this error is potentially transient and worth retrying
    var isRetryable: Bool {
        switch self {
        case .httpError(let statusCode, _):
            // Retry on rate limit (429), server errors (5xx)
            return statusCode == 429 || (statusCode >= 500 && statusCode < 600)
        case .networkError:
            return true
        default:
            return false
        }
    }
}

// MARK: - Request/Response Types

struct Message: Codable {
    let role: String
    let content: String

    static func system(_ content: String) -> Message {
        Message(role: "system", content: content)
    }

    static func user(_ content: String) -> Message {
        Message(role: "user", content: content)
    }

    static func assistant(_ content: String) -> Message {
        Message(role: "assistant", content: content)
    }
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat?
    let tools: [Tool]?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case tools
        case maxTokens = "max_tokens"
    }
}

struct ResponseFormat: Codable, Sendable {
    let type: String
    let jsonSchema: JSONSchemaWrapper?

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }

    static func json() -> ResponseFormat {
        ResponseFormat(type: "json_object", jsonSchema: nil)
    }

    static func jsonSchema(name: String, schema: [String: Any], strict: Bool = true) -> ResponseFormat {
        ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchemaWrapper(name: name, strict: strict, schema: schema)
        )
    }
}

struct JSONSchemaWrapper: Codable, @unchecked Sendable {
    let name: String
    let strict: Bool
    let schema: [String: Any]

    enum CodingKeys: String, CodingKey {
        case name
        case strict
        case schema
    }

    init(name: String, strict: Bool, schema: [String: Any]) {
        self.name = name
        self.strict = strict
        self.schema = schema
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        strict = try container.decode(Bool.self, forKey: .strict)

        // Decode schema as Any
        let schemaData = try container.decode(AnyCodable.self, forKey: .schema)
        schema = schemaData.value as? [String: Any] ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(strict, forKey: .strict)
        try container.encode(AnyCodable(schema), forKey: .schema)
    }
}

struct Tool: Codable {
    let type: String
    let function: FunctionDefinition?
    let webSearch: WebSearchConfig?

    enum CodingKeys: String, CodingKey {
        case type
        case function
        case webSearch = "web_search"
    }

    static func webSearch(searchContextSize: String = "medium") -> Tool {
        Tool(type: "web_search", function: nil, webSearch: WebSearchConfig(searchContextSize: searchContextSize))
    }
}

struct FunctionDefinition: Codable {
    let name: String
    let description: String?
    let parameters: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case parameters
    }

    init(name: String, description: String? = nil, parameters: [String: Any]? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)

        if let paramsData = try container.decodeIfPresent(AnyCodable.self, forKey: .parameters) {
            parameters = paramsData.value as? [String: Any]
        } else {
            parameters = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        if let params = parameters {
            try container.encode(AnyCodable(params), forKey: .parameters)
        }
    }
}

struct WebSearchConfig: Codable {
    let searchContextSize: String

    enum CodingKeys: String, CodingKey {
        case searchContextSize = "search_context_size"
    }
}

struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let index: Int
        let message: ResponseMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Codable {
        let role: String
        let content: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: FunctionCall?
    }

    struct FunctionCall: Codable {
        let name: String
        let arguments: String
    }

    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail

    struct ErrorDetail: Codable {
        let message: String
        let type: String?
        let code: String?
    }
}

/// Streaming response chunk from OpenAI
struct StreamChunk: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [StreamChoice]

    struct StreamChoice: Codable {
        let index: Int
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Codable {
        let role: String?
        let content: String?
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// MARK: - OpenAI Client Actor

actor OpenAIClient {
    static let shared = OpenAIClient()

    private let baseURL = "https://api.openai.com/v1"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120  // writer/analysis calls can be long
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Retry Configuration

    private let maxRetries = 3
    private let baseDelaySeconds: Double = 1.0
    private let maxDelaySeconds: Double = 30.0

    private func log(_ message: String) {
        StructuredLogger.log(component: "OpenAIClient", message: message)
    }

    // MARK: - API Key

    private func getAPIKey() async throws -> String {
        guard let key = try await KeychainManager.shared.currentOpenAIKey() else {
            throw OpenAIError.noAPIKey
        }
        return key
    }

    // MARK: - Retry Logic

    /// Execute an async operation with exponential backoff retry
    private func withRetry<T>(
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error = OpenAIError.invalidResponse
        var delay = baseDelaySeconds

        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch let error as OpenAIError where error.isRetryable {
                lastError = error
                let attemptNumber = attempt + 1

                if attemptNumber < maxRetries {
                    // Add jitter to prevent thundering herd
                    let jitter = Double.random(in: 0...0.5)
                    let sleepDuration = min(delay + jitter, maxDelaySeconds)

                    log("Attempt \(attemptNumber) failed (\(error.localizedDescription)), retrying in \(String(format: "%.1f", sleepDuration))s")

                    try await Task.sleep(for: .seconds(sleepDuration))
                    delay *= 2  // Exponential backoff
                }
            } catch {
                // Non-retryable error, throw immediately
                throw error
            }
        }

        throw OpenAIError.maxRetriesExceeded(lastError: lastError)
    }

    // MARK: - Chat Completions

    func chatCompletion(
        messages: [Message],
        model: String = "gpt-4o",
        responseFormat: ResponseFormat? = nil,
        tools: [Tool]? = nil,
        maxTokens: Int? = nil
    ) async throws -> ChatCompletionResponse {
        // Get API key outside of retry loop (no need to retry auth errors)
        let apiKey = try await getAPIKey()

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw OpenAIError.invalidURL
        }

        // Build request body once outside retry loop
        let requestBody = ChatCompletionRequest(
            model: model,
            messages: messages,
            responseFormat: responseFormat,
            tools: tools,
            maxTokens: maxTokens
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        // Wrap the network request in retry logic
        return try await withRetry { [session] in
            let startedAt = Date()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = bodyData

            let formatDesc: String
            if let responseFormat {
                formatDesc = responseFormat.type
            } else {
                formatDesc = "text"
            }

            log("POST /chat/completions model=\(model) format=\(formatDesc) tools=\(tools?.count ?? 0)")

            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAIError.invalidResponse
                }

                let elapsed = String(format: "%.2fs", Date().timeIntervalSince(startedAt))

                if httpResponse.statusCode != 200 {
                    let errorMessage: String?
                    if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                        errorMessage = errorResponse.error.message
                    } else {
                        errorMessage = String(data: data, encoding: .utf8)
                    }
                    log("HTTP \(httpResponse.statusCode) \(elapsed) model=\(model) error=\(errorMessage ?? "unknown")")
                    throw OpenAIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
                }

                do {
                    let decoder = JSONDecoder()
                    let decoded = try decoder.decode(ChatCompletionResponse.self, from: data)
                    log("HTTP 200 \(elapsed) model=\(model) tokens=\(decoded.usage?.totalTokens ?? 0)")
                    return decoded
                } catch {
                    log("Decoding error \(elapsed): \(error.localizedDescription)")
                    throw OpenAIError.decodingError(error)
                }
            } catch {
                log("Network error model=\(model): \(error.localizedDescription)")
                throw error
            }
        }
    }

    // MARK: - Convenience Methods

    func simpleCompletion(
        systemPrompt: String,
        userPrompt: String,
        model: String = "gpt-4o"
    ) async throws -> String {
        let messages = [
            Message.system(systemPrompt),
            Message.user(userPrompt)
        ]

        let response = try await chatCompletion(messages: messages, model: model)

        guard let content = response.choices.first?.message.content else {
            throw OpenAIError.invalidResponse
        }

        return content
    }

    func jsonCompletion<T: Decodable>(
        messages: [Message],
        model: String = "gpt-4o",
        responseType: T.Type
    ) async throws -> T {
        let response = try await chatCompletion(
            messages: messages,
            model: model,
            responseFormat: .json()
        )

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            throw OpenAIError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw OpenAIError.decodingError(error)
        }
    }

    // MARK: - Streaming Chat Completions

    /// Stream chat completion responses, yielding text chunks as they arrive
    func chatCompletionStreaming(
        messages: [Message],
        model: String = "gpt-4o",
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try await getAPIKey()

                    guard let url = URL(string: "\(baseURL)/chat/completions") else {
                        continuation.finish(throwing: OpenAIError.invalidURL)
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

                    // Build request with stream: true
                    var bodyDict: [String: Any] = [
                        "model": model,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true
                    ]
                    if let maxTokens {
                        bodyDict["max_tokens"] = maxTokens
                    }

                    request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

                    log("POST /chat/completions (streaming) model=\(model)")

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: OpenAIError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode != 200 {
                        // Collect error response
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        let errorMessage = String(data: errorData, encoding: .utf8)
                        continuation.finish(throwing: OpenAIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage))
                        return
                    }

                    // Parse SSE stream
                    for try await line in bytes.lines {
                        // SSE format: "data: {...}"
                        guard line.hasPrefix("data: ") else { continue }

                        let jsonString = String(line.dropFirst(6))

                        // Stream ends with "data: [DONE]"
                        if jsonString == "[DONE]" {
                            break
                        }

                        // Parse the chunk
                        guard let data = jsonString.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let delta = chunk.choices.first?.delta,
                              let content = delta.content else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Validation

    func validateAPIKey() async throws -> Bool {
        // Make a minimal API call to validate the key
        let messages = [Message.user("Hi")]

        do {
            _ = try await chatCompletion(
                messages: messages,
                model: "gpt-4o-mini",
                maxTokens: 1
            )
            return true
        } catch OpenAIError.httpError(let statusCode, _) where statusCode == 401 {
            return false
        }
    }
}
