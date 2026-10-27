// Licensed under GPL-3.0. See LICENSE.
//
//  OpenAICompatibleProvider.swift
//  BrowserSkills
//
//  OpenAI-compatible chat completions with tool calling, used for Nemotron on Nebius Token
//  Factory. Adapted from Nook's OpenAICompatibleProvider.swift (nook-browser/Nook, GPL-3.0).
//

import Foundation

struct OpenAICompatibleProvider: AIProviderProtocol {
    let apiKey: String
    let baseURL: String

    func sendMessage(messages: [AIMessage], model: String, config: AIGenerationConfig, tools: [AIToolDefinition]) async throws -> AIResponse {
        guard !apiKey.isEmpty else { throw AIProviderError.invalidAPIKey }
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        // The API key must never travel in clear text.
        if let parsed = URL(string: base) {
            let host = parsed.host?.lowercased() ?? ""
            let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
            if parsed.scheme?.lowercased() != "https" && !isLocal { throw AIProviderError.insecureURL(base) }
        }
        var request = URLRequest(url: URL(string: "\(base)/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "messages": Self.encode(messages),
            "temperature": config.temperature,
            "max_tokens": config.maxTokens,
        ]
        if !tools.isEmpty { body["tools"] = tools.map { $0.toOpenAIFormat() } }
        if config.jsonMode { body["response_format"] = ["type": "json_object"] }

        var attempts = 0
        while true {
            attempts += 1
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
            if http.statusCode == 400, attempts < 4, let fixed = Self.body(body, fixingRejectionIn: data) {
                body = fixed
                continue
            }
            if http.statusCode == 429 { throw AIProviderError.rateLimited }
            guard http.statusCode == 200 else {
                throw AIProviderError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            return try Self.parse(data)
        }
    }

    static func encode(_ messages: [AIMessage]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for m in messages {
            switch m.role {
            case .system, .user:
                out.append(["role": m.role.rawValue, "content": m.content])
            case .assistant:
                var msg: [String: Any] = ["role": "assistant", "content": m.content]
                if !m.toolCalls.isEmpty {
                    msg["tool_calls"] = m.toolCalls.map { tc -> [String: Any] in
                        let args = (try? JSONSerialization.data(withJSONObject: tc.arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        return ["id": tc.id, "type": "function", "function": ["name": tc.name, "arguments": args]]
                    }
                }
                out.append(msg)
            case .tool:
                for r in m.toolResults { out.append(["role": "tool", "tool_call_id": r.toolCallId, "content": r.content]) }
            }
        }
        return out
    }

    /// Some endpoints reject `max_tokens`, `temperature` or `response_format` and name the
    /// parameter in the error. Returns the body with it fixed, or nil.
    static func body(_ body: [String: Any], fixingRejectionIn data: Data) -> [String: Any]? {
        let text = String(data: data, encoding: .utf8)?.lowercased() ?? ""
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let param = ((json?["error"] as? [String: Any])?["param"] as? String) ?? ""
        var body = body
        if param == "response_format" || (text.contains("response_format") && body["response_format"] != nil) {
            body.removeValue(forKey: "response_format"); return body
        }
        if param == "max_tokens", let limit = body.removeValue(forKey: "max_tokens") {
            body["max_completion_tokens"] = limit; return body
        }
        if param == "temperature", body.removeValue(forKey: "temperature") != nil { return body }
        return nil
    }

    static func parse(_ data: Data) throws -> AIResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choice = (json?["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else { throw AIProviderError.invalidResponse }
        var toolCalls: [AIToolCall] = []
        for tc in message["tool_calls"] as? [[String: Any]] ?? [] {
            guard let fn = tc["function"] as? [String: Any], let name = fn["name"] as? String else { continue }
            let argsText = fn["arguments"] as? String ?? "{}"
            let args = (try? JSONSerialization.jsonObject(with: Data(argsText.utf8))) as? [String: Any] ?? [:]
            toolCalls.append(AIToolCall(id: tc["id"] as? String ?? UUID().uuidString, name: name, arguments: args))
        }
        let finish: AIFinishReason
        switch choice["finish_reason"] as? String ?? "stop" {
        case "tool_calls": finish = .toolCalls
        case "length": finish = .maxTokens
        default: finish = toolCalls.isEmpty ? .stop : .toolCalls
        }
        var usage: AIUsage?
        if let u = json?["usage"] as? [String: Any] {
            usage = AIUsage(promptTokens: u["prompt_tokens"] as? Int ?? 0, completionTokens: u["completion_tokens"] as? Int ?? 0)
        }
        return AIResponse(content: stripReasoning(message["content"] as? String ?? ""), toolCalls: toolCalls, usage: usage, finishReason: finish)
    }

    /// Nemotron reasoning modes may prefix the answer with a <think> block.
    static func stripReasoning(_ text: String) -> String {
        var out = text
        while let open = out.range(of: "<think>"), let close = out.range(of: "</think>", range: open.upperBound..<out.endIndex) {
            out.removeSubrange(open.lowerBound..<close.upperBound)
        }
        if let close = out.range(of: "</think>") { out = String(out[close.upperBound...]) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first balanced JSON object in model text, ignoring code fences and prose around it.
    static func firstJSONObject(in text: String) -> [String: Any]? {
        let chars = Array(text)
        var depth = 0, start: Int?, inString = false, escaped = false
        for (i, c) in chars.enumerated() {
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true }
            else if c == "{" { if depth == 0 { start = i }; depth += 1 }
            else if c == "}", depth > 0 {
                depth -= 1
                if depth == 0, let s = start {
                    let candidate = String(chars[s...i])
                    if let obj = (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) as? [String: Any] { return obj }
                    start = nil
                }
            }
        }
        return nil
    }
}
