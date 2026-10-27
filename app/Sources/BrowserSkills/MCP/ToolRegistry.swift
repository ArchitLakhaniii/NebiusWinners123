// Licensed under GPL-3.0. See LICENSE.
//
//  ToolRegistry.swift
//  BrowserSkills
//
//  The one tool layer behind both the MCP server and the built-in assistant:
//  - one tool per validated skill (`skill_<name>`), typed from the workflow's inputs;
//  - generic page tools that make any webpage usable by an agent before it has a skill.
//  Every tool drives the agent tab, never the user's own tabs. Page tools are a fixed
//  vocabulary (open, describe, act on a ref, read); none of them runs caller-supplied code.
//

import Foundation

struct ToolOutput {
    var text: String
    var isError = false
    var structured: [String: Any]?
}

@MainActor
final class ToolRegistry {
    let store: SkillStore
    let executor: Executor
    let settings: () -> AppSettings
    var tab: BrowserTab { executor.tab }

    init(store: SkillStore, executor: Executor, settings: @escaping () -> AppSettings) {
        self.store = store; self.executor = executor; self.settings = settings
    }

    static let skillPrefix = "skill_"

    func definitions() -> [AIToolDefinition] {
        var tools: [AIToolDefinition] = []
        for skill in store.skills {
            guard let v = store.activeVersion(of: skill) else { continue }
            let w = v.workflow
            let outs = w.outputs.map(\.name).joined(separator: ", ")
            tools.append(AIToolDefinition(
                name: Self.skillPrefix + skill.name,
                description: "\(w.title). \(w.description) Runs a verified, recorded procedure on \(w.origin) in the browser and returns \(outs). Read-only replay of what the user taught.",
                parameters: w.inputSchema))
        }
        tools += [
            AIToolDefinition(name: "skills_list", description: "List the browser's saved skills (cached workflows the user taught or repeated), with inputs, outputs and the site they run on.",
                             parameters: ["type": "object", "properties": [:] as [String: Any]]),
            AIToolDefinition(name: "browser_open", description: "Open an http(s) URL in the agent tab and return the page title. Use page_describe next to see what is on it.",
                             parameters: ["type": "object", "properties": ["url": ["type": "string", "description": "Absolute http(s) URL"]], "required": ["url"]]),
            AIToolDefinition(name: "page_describe", description: "Turn the page open in the agent tab into tools: readable text, forms with their fields, and clickable actions. Each element has a ref for page_act.",
                             parameters: ["type": "object", "properties": ["max_text": ["type": "integer", "description": "Max characters of page text (default 3000)"]]]),
            AIToolDefinition(name: "page_act", description: "Act on an element from page_describe: click a link or button, fill a field, choose a select option, or submit a form.",
                             parameters: ["type": "object", "properties": [
                                "ref": ["type": "string", "description": "Element ref from page_describe"],
                                "action": ["type": "string", "enum": ["click", "fill", "select", "submit"]],
                                "value": ["type": "string", "description": "Text for fill, option for select"],
                             ], "required": ["ref", "action"]]),
            AIToolDefinition(name: "page_read", description: "Read the text of elements matching a CSS selector on the agent tab's page.",
                             parameters: ["type": "object", "properties": [
                                "selector": ["type": "string"], "many": ["type": "boolean", "description": "Return every match (default false)"],
                             ], "required": ["selector"]]),
            AIToolDefinition(name: "run_get", description: "Get a skill run's status, outputs, checks and step log by run id.",
                             parameters: ["type": "object", "properties": ["run_id": ["type": "string"]], "required": ["run_id"]]),
        ]
        if !settings().tavilyKey.isEmpty {
            tools.append(AIToolDefinition(name: "web_search", description: "Search the web with Tavily and return the top results with snippets. Use to find which site to open.",
                                          parameters: ["type": "object", "properties": ["query": ["type": "string"]], "required": ["query"]]))
        }
        return tools
    }

    func call(_ name: String, _ args: [String: Any]) async -> ToolOutput {
        if name.hasPrefix(Self.skillPrefix) { return await runSkill(String(name.dropFirst(Self.skillPrefix.count)), args) }
        switch name {
        case "skills_list": return skillsList()
        case "browser_open": return await open(args["url"] as? String ?? "")
        case "page_describe": return await describe(maxText: args["max_text"] as? Int ?? 3000)
        case "page_act": return await act(ref: args["ref"] as? String ?? "", action: args["action"] as? String ?? "", value: args["value"] as? String)
        case "page_read": return await read(selector: args["selector"] as? String ?? "", many: args["many"] as? Bool ?? false)
        case "run_get": return runGet(args["run_id"] as? String ?? "")
        case "web_search": return await webSearch(args["query"] as? String ?? "")
        default: return ToolOutput(text: "unknown tool \(name)", isError: true)
        }
    }

    // MARK: Skills

    private func runSkill(_ skillName: String, _ args: [String: Any]) async -> ToolOutput {
        guard let skill = store.skill(named: skillName) else { return ToolOutput(text: "no skill named \(skillName)", isError: true) }
        let inputs = args.compactMapValues { v -> String? in
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }
        let r = await executor.run(skill: skill, inputs: inputs)
        return Self.output(for: r, skill: skill)
    }

    static func runDict(_ r: RunRecord) -> [String: Any] {
        var d: [String: Any] = ["run_id": r.id, "status": r.status.rawValue, "version": r.version,
                                "outputs": r.outputs.mapValues(\.any), "checks": r.checks,
                                "steps": r.log.map { ["step": $0.index, "kind": $0.kind, "ok": $0.ok, "ms": $0.ms, "detail": $0.detail] }]
        if let e = r.error { d["error"] = e }
        if let s = r.screenshot { d["screenshot"] = s }
        return d
    }

    static func output(for r: RunRecord, skill: Skill) -> ToolOutput {
        let d = runDict(r)
        let lines = r.outputs.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.text)" }.joined(separator: "\n")
        let text = r.status == .success
            ? "\(skill.title) succeeded (run \(r.id), v\(r.version), verified: \(r.checks.joined(separator: "; ")))\n\(lines)"
            : "\(skill.title) \(r.status.rawValue): \(r.error ?? "")"
        return ToolOutput(text: text, isError: r.status != .success, structured: d)
    }

    private func skillsList() -> ToolOutput {
        let list: [[String: Any]] = store.skills.compactMap { s in
            guard let v = store.activeVersion(of: s) else { return nil }
            return ["tool": Self.skillPrefix + s.name, "title": v.workflow.title, "origin": s.origin, "version": v.version,
                    "inputs": v.workflow.inputs.map { ["name": $0.name, "example": $0.example] },
                    "outputs": v.workflow.outputs.map(\.name)]
        }
        let text = list.isEmpty ? "No validated skills yet. Teach one in the browser, or repeat a task twice."
            : list.map { "\($0["tool"]!) - \($0["title"]!) on \($0["origin"]!)" }.joined(separator: "\n")
        return ToolOutput(text: text, structured: ["skills": list])
    }

    private func runGet(_ id: String) -> ToolOutput {
        guard let r = store.run(id: id) else { return ToolOutput(text: "no run \(id)", isError: true) }
        return ToolOutput(text: "run \(id): \(r.status.rawValue)", structured: Self.runDict(r))
    }

    // MARK: Page tools

    private func open(_ raw: String) async -> ToolOutput {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            return ToolOutput(text: "only absolute http(s) URLs can be opened: \(raw)", isError: true)
        }
        let before = tab.navigationCount
        tab.load(url)
        let ok = await tab.waitForLoad(since: before, timeout: 20)
        return ToolOutput(text: ok ? "Opened \(tab.webView.url?.absoluteString ?? raw) - \(tab.webView.title ?? "")" : "Timed out loading \(raw)",
                          isError: !ok, structured: ["url": tab.webView.url?.absoluteString ?? raw, "title": tab.webView.title ?? ""])
    }

    private func describe(maxText: Int) async -> ToolOutput {
        guard tab.webView.url != nil else { return ToolOutput(text: "The agent tab is empty. Call browser_open first.", isError: true) }
        do {
            let page = try await tab.call(Scripts.describePage, ["maxText": max(200, min(maxText, 20000))]) as? [String: Any] ?? [:]
            var lines = ["# \(page["title"] ?? "") - \(page["url"] ?? "")"]
            for f in page["forms"] as? [[String: Any]] ?? [] {
                lines.append("form \(f["ref"] ?? "") \(f["name"] ?? ""):")
                for field in f["fields"] as? [[String: Any]] ?? [] {
                    let secret = field["secret"] as? Bool == true ? " (secret - ask the user)" : ""
                    let opts = (field["options"] as? [String]).map { " options: \($0.prefix(10).joined(separator: " | "))" } ?? ""
                    lines.append("  [\(field["ref"] ?? "")] \(field["type"] ?? "") “\(field["label"] ?? "")”\(secret)\(opts)")
                }
                if let s = f["submit"] as? [String: Any] { lines.append("  [\(s["ref"] ?? "")] submit “\(s["label"] ?? "")”") }
            }
            let actions = page["actions"] as? [[String: Any]] ?? []
            if !actions.isEmpty {
                lines.append("actions:")
                lines += actions.prefix(40).map { "  [\($0["ref"] ?? "")] \($0["kind"] ?? "") “\($0["label"] ?? "")”" }
            }
            lines.append("text:\n\(page["text"] ?? "")")
            return ToolOutput(text: lines.joined(separator: "\n"), structured: page)
        } catch {
            return ToolOutput(text: "could not read the page: \(error.localizedDescription)", isError: true)
        }
    }

    private func act(ref: String, action: String, value: String?) async -> ToolOutput {
        guard ["click", "fill", "select", "submit"].contains(action) else { return ToolOutput(text: "action must be click, fill, select or submit", isError: true) }
        let before = tab.navigationCount
        let result: [String: Any]
        do {
            result = try await tab.call(Scripts.actOnRef, ["ref": ref, "op": action, "value": value ?? ""]) as? [String: Any] ?? [:]
        } catch {
            if await tab.waitForLoad(since: before, timeout: 10) { return ToolOutput(text: "Navigated to \(tab.webView.url?.absoluteString ?? "")") }
            return ToolOutput(text: error.localizedDescription, isError: true)
        }
        guard result["ok"] as? Bool == true else { return ToolOutput(text: "\(result["error"] ?? "error"): \(result["detail"] ?? "")", isError: true) }
        if action == "click" || action == "submit" {
            try? await Task.sleep(for: .milliseconds(350))
            if tab.navigationCount > before || tab.webView.isLoading { _ = await tab.waitForLoad(since: before, timeout: 15) }
        }
        return ToolOutput(text: "\(result["detail"] ?? action). Now at \(tab.webView.url?.absoluteString ?? "") - call page_describe to see the result.")
    }

    private func read(selector: String, many: Bool) async -> ToolOutput {
        guard !selector.isEmpty else { return ToolOutput(text: "selector is required", isError: true) }
        let r = try? await tab.call(Scripts.extract, ["outputs": [["name": "value", "selector": selector, "many": many]], "timeoutMs": 3000]) as? [String: Any]
        let value = JSONValue(any: (r?["outputs"] as? [String: Any])?["value"])
        return ToolOutput(text: value.isEmpty ? "no text matched \(selector)" : value.text, isError: value.isEmpty, structured: ["value": value.any])
    }

    private func webSearch(_ query: String) async -> ToolOutput {
        let key = settings().tavilyKey
        guard !key.isEmpty else { return ToolOutput(text: "web search needs TAVILY_API_KEY", isError: true) }
        var req = URLRequest(url: URL(string: "https://api.tavily.com/search")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "max_results": 5])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ToolOutput(text: "Tavily error: \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")", isError: true)
            }
            let results = json["results"] as? [[String: Any]] ?? []
            let text = results.map { "- \($0["title"] ?? "") \($0["url"] ?? "")\n  \(String(describing: $0["content"] ?? "").prefix(300))" }.joined(separator: "\n")
            return ToolOutput(text: text.isEmpty ? "no results" : text, structured: ["results": results])
        } catch {
            return ToolOutput(text: error.localizedDescription, isError: true)
        }
    }
}
