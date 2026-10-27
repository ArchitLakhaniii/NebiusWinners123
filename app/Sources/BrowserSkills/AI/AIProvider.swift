// Licensed under GPL-3.0. See LICENSE.
//
//  AIProvider.swift
//  BrowserSkills
//
//  Provider protocol and message types. Adapted from Nook's AIProvider.swift
//  (nook-browser/Nook, GPL-3.0), trimmed to what an OpenAI-compatible endpoint needs.
//

import Foundation

struct AIGenerationConfig {
    var temperature: Double = 0.2
    var maxTokens: Int = 4096
    /// Ask for `response_format: json_object`; dropped automatically if the endpoint rejects it.
    var jsonMode = false
}

protocol AIProviderProtocol {
    func sendMessage(messages: [AIMessage], model: String, config: AIGenerationConfig, tools: [AIToolDefinition]) async throws -> AIResponse
}

struct AIMessage {
    let role: AIMessageRole
    let content: String
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
}

enum AIMessageRole: String { case system, user, assistant, tool }

struct AIResponse {
    var content: String = ""
    var toolCalls: [AIToolCall] = []
    var usage: AIUsage?
    var finishReason: AIFinishReason = .stop
}

enum AIFinishReason: String { case stop, toolCalls = "tool_calls", maxTokens = "max_tokens", error }

struct AIUsage { let promptTokens: Int; let completionTokens: Int; var totalTokens: Int { promptTokens + completionTokens } }

struct AIToolCall: Identifiable {
    let id: String
    let name: String
    let arguments: [String: Any]
    init(id: String = UUID().uuidString, name: String, arguments: [String: Any] = [:]) {
        self.id = id; self.name = name; self.arguments = arguments
    }
}

struct AIToolResult {
    let toolCallId: String
    let toolName: String
    let content: String
    let isError: Bool
}

struct AIToolDefinition {
    let name: String
    let description: String
    let parameters: [String: Any]

    func toOpenAIFormat() -> [String: Any] {
        ["type": "function", "function": ["name": name, "description": description, "parameters": parameters]]
    }
}

enum AIProviderError: LocalizedError {
    case invalidAPIKey, invalidResponse, rateLimited
    case httpError(Int, String)
    case insecureURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "Missing Nebius Token Factory API key. Add it in Settings or set NEBIUS_API_KEY."
        case .invalidResponse: return "Failed to parse the model response"
        case .rateLimited: return "Rate limited by the model endpoint. Try again shortly."
        case .httpError(let code, let msg): return "HTTP \(code): \(msg.prefix(400))"
        case .insecureURL(let url): return "Model endpoint must use HTTPS for non-local hosts: \(url)"
        }
    }
}
