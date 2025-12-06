import Foundation
import AnthropicSwift

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
}

final class AnthropicAdapter: LLMClient, @unchecked Sendable {
    private let client: AnthropicClient

    init(apiKey: String) {
        self.client = AnthropicClient(apiKey: apiKey)
    }

    private func log(_ message: String) {
        StructuredLogger.log(component: "Anthropic Adapter", message: message)
    }

    func chatStructured<T: Decodable & Sendable>(
        messages: [Message],
        model: String,
        schemaName: String,
        schema: [String: Any],
        maxTokens: Int?
    ) async throws -> T {
        let params = MessageCreateParams(
            model: model,
            maxTokens: maxTokens,
            messages: messages.map { MessageInput(role: $0.role, content: [.text($0.content)]) }
        )
        log("Structured chat request model=\(model) schema=\(schemaName) messages=\(messages.count)")
        do {
            return try await client.messages.createStructured(params, decodeAs: T.self)
        } catch {
            log("Anthropic structured error: \(error.localizedDescription)")
            throw error
        }
    }

    func chatText(
        messages: [Message],
        model: String,
        maxTokens: Int?
    ) async throws -> String {
        let params = MessageCreateParams(
            model: model,
            maxTokens: maxTokens,
            messages: messages.map { MessageInput(role: $0.role, content: [.text($0.content)]) }
        )
        log("Text chat request model=\(model) messages=\(messages.count)")
        do {
            let response = try await client.messages.create(params)
            return response.textContent()
        } catch {
            log("Anthropic text error: \(error.localizedDescription)")
            throw error
        }
    }
}
