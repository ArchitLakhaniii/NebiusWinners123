// Licensed under GPL-3.0. See LICENSE.
//
//  Assistant.swift
//  BrowserSkills
//
//  The built-in assistant: Nemotron tool calling over the same ToolRegistry external MCP
//  clients see. The loop mirrors Nook's AIService tool loop (nook-browser/Nook, GPL-3.0).
//

import Foundation

@MainActor
final class Assistant: ObservableObject {
    struct Line: Identifiable, Hashable {
        enum Role: String { case user, assistant, tool, error }
        let id = UUID()
        let role: Role
        let text: String
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var busy = false

    private let registry: ToolRegistry
    private let settings: () -> AppSettings
    private var history: [AIMessage] = []
    static let maxToolIterations = 8

    init(registry: ToolRegistry, settings: @escaping () -> AppSettings) {
        self.registry = registry; self.settings = settings
    }

    var systemPrompt: String {
        """
        You are the assistant inside BrowserSkills, an AI-native browser. You act through tools that drive the browser's agent tab.
        Prefer a skill_* tool when one fits: those are verified procedures the user taught, and their outputs are checked.
        Otherwise use browser_open, page_describe, page_act and page_read to work with any webpage directly.
        Never type into secret fields; ask the user to sign in themselves. Report results with the run id and the values returned.
        Be brief.
        """
    }

    func reset() { history = []; lines = [] }

    func send(_ text: String) async {
        let s = settings()
        lines.append(Line(role: .user, text: text))
        guard s.hasModel else {
            lines.append(Line(role: .error, text: "Add a Nebius Token Factory API key in Settings to use the assistant. Skills still run from the Skills panel and over MCP."))
            return
        }
        busy = true
        defer { busy = false }
        if history.isEmpty { history.append(AIMessage(role: .system, content: systemPrompt)) }
        history.append(AIMessage(role: .user, content: text))
        let provider = OpenAICompatibleProvider(apiKey: s.apiKey, baseURL: s.baseURL)
        do {
            for _ in 0..<Self.maxToolIterations {
                let tools = registry.definitions()
                let response = try await provider.sendMessage(messages: history, model: s.assistantModel,
                                                              config: AIGenerationConfig(temperature: 0.2, maxTokens: 2048), tools: tools)
                history.append(AIMessage(role: .assistant, content: response.content, toolCalls: response.toolCalls))
                if response.toolCalls.isEmpty {
                    lines.append(Line(role: .assistant, text: response.content.isEmpty ? "(no answer)" : response.content))
                    return
                }
                if !response.content.isEmpty { lines.append(Line(role: .assistant, text: response.content)) }
                var results: [AIToolResult] = []
                for call in response.toolCalls {
                    let argText = (try? JSONSerialization.data(withJSONObject: call.arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    lines.append(Line(role: .tool, text: "→ \(call.name) \(argText)"))
                    let out = await registry.call(call.name, call.arguments)
                    lines.append(Line(role: .tool, text: (out.isError ? "✗ " : "✓ ") + String(out.text.prefix(400))))
                    results.append(AIToolResult(toolCallId: call.id, toolName: call.name, content: String(out.text.prefix(8000)), isError: out.isError))
                }
                history.append(AIMessage(role: .tool, content: "", toolResults: results))
            }
            lines.append(Line(role: .error, text: "Stopped after \(Self.maxToolIterations) tool rounds."))
        } catch {
            lines.append(Line(role: .error, text: error.localizedDescription))
        }
    }
}
