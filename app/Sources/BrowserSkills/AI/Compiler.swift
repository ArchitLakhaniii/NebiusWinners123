// Licensed under GPL-3.0. See LICENSE.
//
//  Compiler.swift
//  BrowserSkills
//
//  Turns a demonstration into a constrained Workflow. The live path asks Nemotron on Nebius
//  Token Factory; the fixture path is deterministic and is labeled "fixture" wherever it shows.
//  Either way the result is validated against what was actually recorded before it is stored.
//

import Foundation

struct Demonstration {
    var startURL: String
    var actions: [RecordedAction]
    var outputs: [PickedOutput]
    var hint: String

    var origin: String? { URL(string: startURL).flatMap(Workflow.origin(of:)) }

    /// Every selector the recording observed or the user picked; compiled steps and outputs may use only these.
    var knownSelectors: Set<String> {
        Set(actions.flatMap { [$0.selector].compactMap { $0 } + $0.fallbacks } + outputs.map(\.selector))
    }
}

struct CompileResult {
    var workflow: Workflow
    var compiler: String
    var attempts: Int
}

enum CompileError: LocalizedError {
    case invalid([String]), noJSON(String), noOrigin, noOutputs
    var errorDescription: String? {
        switch self {
        case .invalid(let p): return "Compiled workflow failed validation: " + p.joined(separator: "; ")
        case .noJSON(let t): return "Model did not return a workflow: \(t.prefix(200))"
        case .noOrigin: return "The recording has no http(s) start page"
        case .noOutputs: return "Pick at least one result on the page before saving"
        }
    }
}

enum Compiler {
    static func compile(_ demo: Demonstration, settings: AppSettings) async throws -> CompileResult {
        guard demo.origin != nil else { throw CompileError.noOrigin }
        guard !demo.outputs.isEmpty else { throw CompileError.noOutputs }
        if settings.hasModel { return try await nemotron(demo, settings: settings) }
        return try fixture(demo)
    }

    // MARK: Nemotron

    static let systemPrompt = """
    You compile a recorded browser demonstration into a reusable, parameterized workflow.
    Reply with ONE JSON object and nothing else, matching:
    {"name": snake_case 3-48 chars, "title": short imperative title, "description": one sentence for an agent deciding when to call this,
     "origin": the scheme://host[:port] of the start page,
     "inputs": [{"name": snake_case, "description": str, "example": the value typed in the recording}],
     "steps": [{"kind": "navigate"|"fill"|"select"|"click"|"press"|"waitFor", "url"?: str, "target"?: {"selector": str, "fallbacks": [str], "label": str},
                "value"?: literal or "{{input_name}}", "key"?: "Enter", "timeoutMs"?: int}],
     "outputs": [{"name": snake_case, "description": str, "selector": str, "many": bool, "required": bool}],
     "verify": [{"kind": "nonEmpty"|"containsInput", "output": output name, "input"?: input name}]}
    Rules:
    - Start with a navigate step to the start URL. If an entered value appears in a URL, replace it with {{input_name}}.
    - Values the user typed become inputs unless they are clearly constant (e.g. a fixed filter). Never invent inputs.
    - Use ONLY selectors that appear in the recording (selector or fallbacks). Keep the picked output names and selectors exactly.
    - Never navigate to another origin. No JavaScript, no other step kinds.
    - Add a nonEmpty check for every required output. Add containsInput only if the output should literally echo the input.
    - Secret fields are recorded without values: never make them inputs; drop those steps.
    """

    static func nemotron(_ demo: Demonstration, settings: AppSettings) async throws -> CompileResult {
        let provider = OpenAICompatibleProvider(apiKey: settings.apiKey, baseURL: settings.baseURL)
        let recording: [[String: Any]] = demo.actions.filter { !$0.secret }.map { a in
            var d: [String: Any] = ["type": a.type, "url": a.url]
            if let s = a.selector { d["selector"] = s }
            if !a.fallbacks.isEmpty { d["fallbacks"] = a.fallbacks }
            if let l = a.label { d["label"] = l }
            if let v = a.value { d["value"] = v }
            if let k = a.key { d["key"] = k }
            if let t = a.inputType, !t.isEmpty { d["inputType"] = t }
            return d
        }
        let payload: [String: Any] = [
            "start_url": demo.startURL,
            "user_hint": demo.hint,
            "recording": recording,
            "picked_outputs": demo.outputs.map { ["name": $0.name, "selector": $0.selector, "many": $0.many, "sample": $0.sample] },
        ]
        let user = String(data: try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!
        var messages = [AIMessage(role: .system, content: systemPrompt), AIMessage(role: .user, content: user)]
        var lastProblems: [String] = []
        for attempt in 1...3 {
            let response = try await provider.sendMessage(messages: messages, model: settings.compilerModel,
                                                          config: AIGenerationConfig(temperature: 0.1, maxTokens: 6000, jsonMode: true), tools: [])
            guard let obj = OpenAICompatibleProvider.firstJSONObject(in: response.content) else { throw CompileError.noJSON(response.content) }
            var workflow: Workflow
            do { workflow = try decodeLenient(obj) } catch {
                lastProblems = ["JSON does not match the schema: \(error)"]
                messages += [AIMessage(role: .assistant, content: response.content), AIMessage(role: .user, content: "Fix: " + lastProblems.joined(separator: "; "))]
                continue
            }
            workflow = normalize(workflow, demo: demo)
            lastProblems = workflow.problems(knownSelectors: demo.knownSelectors, recordedOrigin: demo.origin)
            if lastProblems.isEmpty { return CompileResult(workflow: workflow, compiler: "nemotron:\(settings.compilerModel)", attempts: attempt) }
            messages += [AIMessage(role: .assistant, content: response.content),
                         AIMessage(role: .user, content: "That workflow is invalid. Fix every problem and reply with the full JSON again:\n- " + lastProblems.joined(separator: "\n- "))]
        }
        throw CompileError.invalid(lastProblems)
    }

    /// Fills defaults a model commonly omits (fallbacks, many, required, verify) before decoding.
    static func decodeLenient(_ obj: [String: Any]) throws -> Workflow {
        var o = obj
        o["verify"] = o["verify"] ?? []
        o["description"] = o["description"] ?? ""
        o["title"] = o["title"] ?? (o["name"] ?? "Workflow")
        o["origin"] = o["origin"] ?? ""
        o["steps"] = (o["steps"] as? [[String: Any]] ?? []).map { s -> [String: Any] in
            var s = s
            if var t = s["target"] as? [String: Any] { t["fallbacks"] = t["fallbacks"] ?? []; s["target"] = t }
            return s
        }
        o["outputs"] = (o["outputs"] as? [[String: Any]] ?? []).map { out -> [String: Any] in
            var out = out
            out["many"] = out["many"] ?? false; out["required"] = out["required"] ?? true; out["description"] = out["description"] ?? ""
            return out
        }
        o["inputs"] = (o["inputs"] as? [[String: Any]] ?? []).map { i -> [String: Any] in
            var i = i; i["description"] = i["description"] ?? ""; i["example"] = i["example"] ?? ""; return i
        }
        return try JSONDecoder().decode(Workflow.self, from: JSONSerialization.data(withJSONObject: o))
    }

    /// Pins what the model must not change: the origin, and output selectors the user picked.
    static func normalize(_ w: Workflow, demo: Demonstration) -> Workflow {
        var w = w
        if let origin = demo.origin { w.origin = origin }
        let picked = Dictionary(demo.outputs.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        w.outputs = w.outputs.map { o in
            guard let p = picked[o.name] else { return o }
            var o = o; o.selector = p.selector; o.many = p.many; return o
        }
        // A picked output the model renamed or dropped is still what the user asked for.
        let present = Set(w.outputs.map(\.name))
        w.outputs += demo.outputs.filter { !present.contains($0.name) }.map {
            WorkflowOutput(name: $0.name, description: $0.sample.isEmpty ? $0.name : "e.g. \($0.sample.prefix(60))", selector: $0.selector, many: $0.many)
        }
        if w.verify.isEmpty {
            w.verify = w.outputs.filter(\.required).map { VerifyCheck(kind: .nonEmpty, output: $0.name, input: nil) }
        }
        return w
    }

    // MARK: Fixture

    /// Deterministic compile: every typed value becomes an input named after its field.
    static func fixture(_ demo: Demonstration) throws -> CompileResult {
        guard let origin = demo.origin else { throw CompileError.noOrigin }
        var inputs: [WorkflowInput] = []
        var steps: [WorkflowStep] = []
        var startURL = demo.startURL
        let actions = Recorder.collapse(demo.actions.filter { !$0.secret })
        for a in actions where (a.type == "fill" || a.type == "select") && a.value != nil && a.selector != nil {
            var name = Recorder.snake(a.label ?? "input")
            if inputs.contains(where: { $0.name == name }) { name += "_\(inputs.count + 1)" }
            inputs.append(WorkflowInput(name: name, description: a.label ?? name, example: a.value!))
        }
        for input in inputs where !input.example.isEmpty {
            let forms = [input.example,
                         input.example.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                         input.example.addingPercentEncoding(withAllowedCharacters: .alphanumerics)]
            if let form = forms.compactMap({ $0 }).first(where: { startURL.contains("=\($0)") }) {
                startURL = startURL.replacingOccurrences(of: "=\(form)", with: "={{\(input.name)}}")
            }
        }
        steps.append(WorkflowStep(kind: .navigate, url: startURL))
        var inputIndex = 0
        for a in actions {
            let target = a.selector.map { ElementTarget(selector: $0, fallbacks: a.fallbacks, label: a.label) }
            switch a.type {
            case "fill", "select":
                guard let target, a.value != nil else { continue }
                steps.append(WorkflowStep(kind: a.type == "fill" ? .fill : .select, target: target, value: "{{\(inputs[inputIndex].name)}}"))
                inputIndex += 1
            case "click":
                if let target { steps.append(WorkflowStep(kind: .click, target: target)) }
            case "press":
                steps.append(WorkflowStep(kind: .press, target: target, key: a.key ?? "Enter"))
            case "navigate":
                steps.append(WorkflowStep(kind: .navigate, url: a.url))
            default: continue
            }
        }
        let host = URL(string: origin)?.host?.replacingOccurrences(of: "www.", with: "") ?? "site"
        let base = Recorder.snake(demo.hint.isEmpty ? "\(inputs.first?.name ?? "run")_on_\(host)" : demo.hint)
        let outputs = demo.outputs.map {
            WorkflowOutput(name: $0.name, description: $0.sample.isEmpty ? $0.name : "e.g. \($0.sample.prefix(60))", selector: $0.selector, many: $0.many)
        }
        let workflow = Workflow(
            name: String(base.prefix(48)),
            title: demo.hint.isEmpty ? "Look up \(inputs.map(\.name).joined(separator: ", ")) on \(host)" : demo.hint,
            description: "Repeats the recorded procedure on \(host) and returns \(outputs.map(\.name).joined(separator: ", ")).",
            origin: origin, inputs: inputs, steps: steps, outputs: outputs,
            verify: outputs.map { VerifyCheck(kind: .nonEmpty, output: $0.name, input: nil) })
        let problems = workflow.problems(knownSelectors: demo.knownSelectors, recordedOrigin: origin)
        guard problems.isEmpty else { throw CompileError.invalid(problems) }
        return CompileResult(workflow: workflow, compiler: "fixture", attempts: 1)
    }
}
