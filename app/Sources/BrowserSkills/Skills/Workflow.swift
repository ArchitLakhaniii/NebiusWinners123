// Licensed under GPL-3.0. See LICENSE.
//
//  Workflow.swift
//  BrowserSkills
//
//  The constrained workflow a demonstration compiles into. The executor only understands these
//  step kinds, so a compiled workflow can never run arbitrary code on a page.
//

import Foundation

struct WorkflowInput: Codable, Hashable {
    var name: String
    var description: String
    var example: String
}

/// One field read off the final page. `many` reads every match as a list.
struct WorkflowOutput: Codable, Hashable {
    var name: String
    var description: String
    var selector: String
    var many: Bool = false
    var required: Bool = true
}

/// How to find an element: the recorded selector, alternates recorded with it, and its visible label.
struct ElementTarget: Codable, Hashable {
    var selector: String
    var fallbacks: [String] = []
    var label: String?
}

enum StepKind: String, Codable, CaseIterable {
    case navigate, fill, select, click, press, waitFor
}

struct WorkflowStep: Codable, Hashable {
    var kind: StepKind
    var url: String?
    var target: ElementTarget?
    /// Literal text or a `{{input}}` template.
    var value: String?
    var key: String?
    var timeoutMs: Int?
}

/// An independent check run after extraction. A run is a success only when every check passes.
struct VerifyCheck: Codable, Hashable {
    enum Kind: String, Codable { case nonEmpty, containsInput }
    var kind: Kind
    var output: String
    var input: String?
}

struct Workflow: Codable, Hashable {
    var name: String
    var title: String
    var description: String
    var origin: String
    var inputs: [WorkflowInput]
    var steps: [WorkflowStep]
    var outputs: [WorkflowOutput]
    var verify: [VerifyCheck]

    static let maxSteps = 40

    /// Every problem that keeps this workflow from being stored. Empty means valid.
    /// `knownSelectors` are the selectors the recording produced; a compiled step may not
    /// reach for an element that was never observed.
    func problems(knownSelectors: Set<String>? = nil, recordedOrigin: String? = nil) -> [String] {
        var out: [String] = []
        if !name.range(of: #"^[a-z][a-z0-9_]{2,47}$"#, options: .regularExpression).map({ _ in true }).orFalse {
            out.append("name must be snake_case, 3-48 chars: \(name)")
        }
        if steps.isEmpty { out.append("workflow has no steps") }
        if steps.count > Self.maxSteps { out.append("too many steps (\(steps.count) > \(Self.maxSteps))") }
        if outputs.isEmpty { out.append("workflow has no outputs") }
        guard let originURL = URL(string: origin), let scheme = originURL.scheme, ["http", "https"].contains(scheme), originURL.host != nil else {
            out.append("origin must be an http(s) origin: \(origin)")
            return out
        }
        if let recordedOrigin, recordedOrigin != origin { out.append("origin \(origin) differs from the recorded origin \(recordedOrigin)") }
        let inputNames = Set(inputs.map(\.name))
        if inputNames.count != inputs.count { out.append("duplicate input names") }
        for input in inputs where !input.name.range(of: #"^[a-z][a-z0-9_]{0,39}$"#, options: .regularExpression).map({ _ in true }).orFalse {
            out.append("input name must be snake_case: \(input.name)")
        }
        for (i, step) in steps.enumerated() {
            let at = "step \(i + 1) (\(step.kind.rawValue))"
            switch step.kind {
            case .navigate:
                guard let raw = step.url, let url = URL(string: Self.fillTemplate(raw, with: Dictionary(uniqueKeysWithValues: inputs.map { ($0.name, $0.example) }))) else {
                    out.append("\(at): missing url"); continue
                }
                if Self.origin(of: url) != origin { out.append("\(at): navigates off the workflow origin to \(raw)") }
            case .fill, .select, .click, .waitFor, .press:
                guard let target = step.target, !target.selector.isEmpty else {
                    if step.kind != .press { out.append("\(at): missing target") }
                    continue
                }
                if let knownSelectors, !knownSelectors.contains(target.selector) {
                    out.append("\(at): selector was not observed in the recording: \(target.selector)")
                }
            }
            if step.kind == .fill || step.kind == .select, step.value == nil { out.append("\(at): missing value") }
            if step.kind == .press, step.key == nil { out.append("\(at): missing key") }
            for ref in Self.templateRefs(step.value) + Self.templateRefs(step.url) where !inputNames.contains(ref) {
                out.append("\(at): references unknown input {{\(ref)}}")
            }
        }
        let outputNames = Set(outputs.map(\.name))
        for check in verify {
            if !outputNames.contains(check.output) { out.append("verify references unknown output \(check.output)") }
            if check.kind == .containsInput, !(check.input.map(inputNames.contains) ?? false) {
                out.append("verify containsInput references unknown input \(check.input ?? "nil")")
            }
        }
        return out
    }

    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        let defaultPort = (scheme == "https" ? 443 : 80)
        if let port = url.port, port != defaultPort { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    static func templateRefs(_ text: String?) -> [String] {
        guard let text else { return [] }
        let regex = try! NSRegularExpression(pattern: #"\{\{\s*([a-zA-Z0-9_]+)\s*\}\}"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func fillTemplate(_ text: String, with values: [String: String], urlEncode: Bool = false) -> String {
        var out = text
        for (k, v) in values {
            let value = urlEncode ? (v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v) : v
            out = out.replacingOccurrences(of: "{{\(k)}}", with: value)
            out = out.replacingOccurrences(of: "{{ \(k) }}", with: value)
        }
        return out
    }

    /// JSON Schema for the MCP tool that runs this workflow.
    var inputSchema: [String: Any] {
        var props: [String: Any] = [:]
        for input in inputs {
            props[input.name] = ["type": "string", "description": "\(input.description) (e.g. \(input.example))"]
        }
        return ["type": "object", "properties": props, "required": inputs.map(\.name)]
    }
}

private extension Optional where Wrapped == Bool {
    var orFalse: Bool { self ?? false }
}

// MARK: - Recorded actions

/// One user action captured by the recorder script, before compilation.
struct RecordedAction: Codable, Hashable, Identifiable {
    var id = UUID()
    var type: String            // navigate, click, fill, select, press, submit
    var url: String
    var selector: String?
    var fallbacks: [String] = []
    var label: String?
    var tag: String?
    var inputType: String?
    var value: String?
    var secret: Bool = false
    var key: String?
    var at = Date()

    /// The action without its value, so two runs of the same procedure compare equal.
    var shape: String {
        [type, selector ?? Workflow.origin(of: URL(string: url) ?? URL(string: "about:blank")!) ?? url, key ?? ""].joined(separator: "|")
    }

    var summary: String {
        switch type {
        case "navigate": return "Open \(url)"
        case "fill": return "Type \(secret ? "••••" : "“\(value ?? "")”") into \(label ?? selector ?? "field")"
        case "select": return "Choose “\(value ?? "")” in \(label ?? selector ?? "menu")"
        case "click": return "Click \(label.map { "“\($0)”" } ?? selector ?? "element")"
        case "press": return "Press \(key ?? "key") in \(label ?? selector ?? "field")"
        default: return type
        }
    }
}

/// An element the user marked as a result while teaching.
struct PickedOutput: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var selector: String
    var sample: String
    var many: Bool
}
