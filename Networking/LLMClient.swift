import Foundation

protocol LLMClient: Sendable {
    func chatStructured<T: Decodable & Sendable>(
        messages: [Message],
        model: String,
        schemaName: String,
        schema: [String: Any],
        maxTokens: Int?
    ) async throws -> T

    func chatText(
        messages: [Message],
        model: String,
        maxTokens: Int?
    ) async throws -> String

    func chatTextStreaming(
        messages: [Message],
        model: String,
        maxTokens: Int?
    ) -> AsyncThrowingStream<String, Error>
}

final class OpenAIAdapter: LLMClient, @unchecked Sendable {
    private let client: OpenAIClient

    init(client: OpenAIClient = .shared) {
        self.client = client
    }

    private func log(_ message: String) {
        StructuredLogger.log(component: "OpenAI Adapter", message: message)
    }

    func chatStructured<T: Decodable & Sendable>(
        messages: [Message],
        model: String,
        schemaName: String,
        schema: [String: Any],
        maxTokens: Int?
    ) async throws -> T {
        log("Structured chat request model=\(model) schema=\(schemaName) messages=\(messages.count)")

        let response = try await client.chatCompletion(
            messages: messages,
            model: model,
            responseFormat: .jsonSchema(name: schemaName, schema: schema),
            tools: nil,
            maxTokens: maxTokens
        )

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            throw OpenAIError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            log("Decoding structured response failed: \(error.localizedDescription)")
            throw OpenAIError.decodingError(error)
        }
    }

    func chatText(
        messages: [Message],
        model: String,
        maxTokens: Int?
    ) async throws -> String {
        log("Text chat request model=\(model) messages=\(messages.count)")

        let response = try await client.chatCompletion(
            messages: messages,
            model: model,
            responseFormat: nil,
            tools: nil,
            maxTokens: maxTokens
        )
        guard let content = response.choices.first?.message.content else {
            throw OpenAIError.invalidResponse
        }
        return content
    }

    func chatTextStreaming(
        messages: [Message],
        model: String,
        maxTokens: Int?
    ) -> AsyncThrowingStream<String, Error> {
        log("Streaming text chat request model=\(model) messages=\(messages.count)")

        return AsyncThrowingStream { continuation in
            Task {
                let stream = await client.chatCompletionStreaming(
                    messages: messages,
                    model: model,
                    maxTokens: maxTokens
                )

                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
