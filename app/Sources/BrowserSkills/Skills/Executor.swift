// Licensed under GPL-3.0. See LICENSE.
//
//  Executor.swift
//  BrowserSkills
//
//  Replays a pinned workflow version in the agent tab, one constrained step at a time, then
//  reads and independently checks the outputs. Runs are serialized: one agent tab, one run.
//

import Foundation

@MainActor
final class Executor: ObservableObject {
    @Published private(set) var current: RunRecord?
    @Published private(set) var currentStep: String?

    let store: SkillStore
    let tab: BrowserTab
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var cancelled = Set<String>()

    init(store: SkillStore, tab: BrowserTab) { self.store = store; self.tab = tab }

    func cancel(runID: String) { cancelled.insert(runID) }

    /// Runs the active validated version of `skill`. Identical calls within 10s return the earlier run.
    func run(skill: Skill, inputs: [String: String], dedupe: Bool = true) async -> RunRecord {
        let key = dedupe ? "\(skill.id)|" + inputs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&") : nil
        if let key, let earlier = store.recentRun(dedupeKey: key, within: 10), earlier.status.isTerminal { return earlier }
        guard let version = store.activeVersion(of: skill) else {
            return failure(skill: skill, inputs: inputs, "skill \(skill.name) has no validated version")
        }
        return await run(version: version, inputs: inputs, purpose: "run", dedupeKey: key)
    }

    func run(version: SkillVersion, inputs: [String: String], purpose: String, dedupeKey: String? = nil) async -> RunRecord {
        await acquire()
        defer { release() }
        let w = version.workflow
        var record = RunRecord(id: UUID().uuidString.lowercased(), skillID: version.skillID, version: version.version, inputs: inputs,
                               status: .running, outputs: [:], log: [], error: nil, checks: [], screenshot: nil, started: Date(), finished: nil, purpose: purpose)
        store.insertRun(record, dedupeKey: dedupeKey)
        current = record
        defer { current = nil; currentStep = nil }

        let missing = w.inputs.map(\.name).filter { (inputs[$0] ?? "").isEmpty }
        if !missing.isEmpty { return finish(&record, .failed, error: "missing inputs: \(missing.joined(separator: ", "))") }

        for (i, step) in w.steps.enumerated() {
            if cancelled.remove(record.id) != nil { return finish(&record, .cancelled, error: "cancelled") }
            currentStep = "\(i + 1)/\(w.steps.count) \(step.kind.rawValue)"
            let t0 = Date()
            let (ok, detail) = await perform(step, workflow: w, inputs: inputs)
            record.log.append(StepLog(index: i + 1, kind: step.kind.rawValue, ok: ok, ms: Int(Date().timeIntervalSince(t0) * 1000), detail: detail))
            store.updateRun(record)
            if !ok {
                await saveScreenshot(&record)
                if await loginWall() { return finish(&record, .needsLogin, error: "the site asked for a login at step \(i + 1); sign in in a normal tab, then retry") }
                return finish(&record, .failed, error: "step \(i + 1) (\(step.kind.rawValue)) failed: \(detail)")
            }
        }

        record.status = .verifying; store.updateRun(record); currentStep = "verifying"
        let specs = w.outputs.map { ["name": $0.name, "selector": $0.selector, "many": $0.many] as [String: Any] }
        let extracted = (try? await tab.call(Scripts.extract, ["outputs": specs, "timeoutMs": 8000])) as? [String: Any]
        let values = extracted?["outputs"] as? [String: Any] ?? [:]
        for o in w.outputs { record.outputs[o.name] = JSONValue(any: values[o.name]) }
        await saveScreenshot(&record)

        var failed: [String] = []
        for o in w.outputs where o.required && (record.outputs[o.name]?.isEmpty ?? true) { failed.append("required output \(o.name) is empty") }
        for c in w.verify {
            let value = record.outputs[c.output] ?? .null
            switch c.kind {
            case .nonEmpty:
                if value.isEmpty { failed.append("\(c.output) is empty") } else { record.checks.append("\(c.output) is present") }
            case .containsInput:
                let needle = inputs[c.input ?? ""] ?? ""
                if value.text.localizedCaseInsensitiveContains(needle) { record.checks.append("\(c.output) mentions \(needle)") }
                else { failed.append("\(c.output) does not mention \(needle)") }
            }
        }
        if !failed.isEmpty {
            if extracted?["loginWall"] as? Bool == true { return finish(&record, .needsLogin, error: "the result page asks for a login") }
            return finish(&record, .needsReview, error: failed.joined(separator: "; "))
        }
        return finish(&record, .success, error: nil)
    }

    private func perform(_ step: WorkflowStep, workflow w: Workflow, inputs: [String: String]) async -> (Bool, String) {
        switch step.kind {
        case .navigate:
            let raw = Workflow.fillTemplate(step.url ?? "", with: inputs, urlEncode: true)
            guard let url = URL(string: raw), Workflow.origin(of: url) == w.origin else { return (false, "refused to leave \(w.origin): \(raw)") }
            let before = tab.navigationCount
            tab.load(url)
            let loaded = await tab.waitForLoad(since: before, timeout: Double(step.timeoutMs ?? 15000) / 1000)
            return (loaded, loaded ? "opened \(url.absoluteString)" : "page did not finish loading")
        default:
            var stepDict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(step))) as? [String: Any] ?? [:]
            if stepDict["target"] == nil {
                guard step.kind == .press else { return (false, "no target") }
                stepDict["target"] = ["selector": ":focus", "fallbacks": ["input"]]
            }
            let value = step.value.map { Workflow.fillTemplate($0, with: inputs) }
            let before = tab.navigationCount
            let result: [String: Any]
            do {
                result = (try await tab.call(Scripts.runStep, ["step": stepDict, "value": value ?? NSNull()])) as? [String: Any] ?? [:]
            } catch {
                // A click that navigates tears down the page mid-call; that is success if a load follows.
                if await tab.waitForLoad(since: before, timeout: 10) { return (true, "navigated") }
                return (false, error.localizedDescription)
            }
            guard result["ok"] as? Bool == true else { return (false, "\(result["error"] ?? "error"): \(result["detail"] ?? "")") }
            if step.kind == .click || step.kind == .press {
                try? await Task.sleep(for: .milliseconds(350))
                if tab.navigationCount > before || tab.webView.isLoading { _ = await tab.waitForLoad(since: before, timeout: 15) }
            }
            return (true, "\(step.kind.rawValue) \(result["label"] as? String ?? "") via \(result["via"] as? String ?? "?")")
        }
    }

    private func loginWall() async -> Bool {
        ((try? await tab.call("return !!document.querySelector('input[type=password]')")) as? Bool) ?? false
    }

    private func saveScreenshot(_ r: inout RunRecord) async {
        guard let png = await tab.snapshotPNG() else { return }
        let url = store.directory.appendingPathComponent("artifacts/\(r.id).png")
        if (try? png.write(to: url)) != nil { r.screenshot = url.path }
    }

    private func finish(_ r: inout RunRecord, _ status: RunStatus, error: String?) -> RunRecord {
        r.status = status; r.error = error; r.finished = Date()
        store.updateRun(r)
        return r
    }

    private func failure(skill: Skill, inputs: [String: String], _ message: String) -> RunRecord {
        let r = RunRecord(id: UUID().uuidString.lowercased(), skillID: skill.id, version: 0, inputs: inputs, status: .failed, outputs: [:],
                          log: [], error: message, checks: [], screenshot: nil, started: Date(), finished: Date(), purpose: "run")
        store.insertRun(r)
        return r
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}
