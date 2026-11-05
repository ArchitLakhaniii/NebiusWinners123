// Licensed under GPL-3.0. See LICENSE.
//
//  Recorder.swift
//  BrowserSkills
//
//  Watches what the user does in their tabs. Two modes:
//  - Passive: actions on a site are grouped into episodes. When the same procedure (same
//    actions on the same elements, any values) shows up twice, the browser offers to save it.
//  - Teach: an explicit recording the user then marks outputs on and saves.
//

import Foundation

struct RepeatSuggestion: Identifiable, Equatable {
    let id = UUID()
    let origin: String
    let startURL: String
    let actions: [RecordedAction]
    let times: Int
    var host: String { URL(string: origin)?.host ?? origin }
}

@MainActor
final class Recorder: ObservableObject {
    @Published var teaching = false
    @Published var picking = false
    @Published private(set) var actions: [RecordedAction] = []
    @Published var picked: [PickedOutput] = []
    @Published var suggestion: RepeatSuggestion?
    @Published private(set) var startURL: String?

    private let store: SkillStore
    private var episode: [RecordedAction] = []
    private var episodeStart: String?
    private var episodeOrigin: String?
    private var idleTask: Task<Void, Never>?
    private var dismissed: Set<String> = []

    /// An episode ends after this much inactivity or when the user leaves the site.
    var idleSeconds: Double = 20

    init(store: SkillStore) { self.store = store }

    // MARK: Teach

    func startTeaching(at url: URL?) {
        actions = []; picked = []; teaching = true; suggestion = nil
        startURL = url?.absoluteString
    }

    /// Starts teaching from a detected repeat: its actions are already the demonstration.
    func adopt(_ s: RepeatSuggestion) {
        actions = s.actions; picked = []; startURL = s.startURL; teaching = true; suggestion = nil
    }

    func cancelTeaching() { teaching = false; picking = false; actions = []; picked = []; startURL = nil }

    func removeAction(_ id: UUID) { actions.removeAll { $0.id == id } }

    func addPicked(_ body: [String: Any]) {
        picking = false
        guard let selector = body["selector"] as? String else { return }
        let label = (body["label"] as? String) ?? ""
        let listSelector = body["listSelector"] as? String
        let many = (body["listCount"] as? Int ?? 1) > 1 && listSelector != nil
        var name = Self.snake(label.isEmpty ? "result" : label)
        if picked.contains(where: { $0.name == name }) { name += "_\(picked.count + 1)" }
        picked.append(PickedOutput(name: name, selector: many ? listSelector! : selector, sample: body["text"] as? String ?? "", many: many,
                                   singleSelector: selector, listSelector: listSelector))
    }

    // MARK: Observation

    func observe(_ action: RecordedAction) {
        if teaching, !picking { actions.append(action) }
        guard !teaching, let origin = URL(string: action.url).flatMap(Workflow.origin(of:)) else { return }
        if origin != episodeOrigin { closeEpisode(); episodeOrigin = origin }
        // After an idle close on the same site the next action opens a new episode starting on its page.
        if episodeStart == nil { episodeStart = action.url }
        episode.append(action)
        scheduleClose()
    }

    /// Navigations: address-bar loads are steps while teaching; leaving a site closes its episode.
    func navigated(to url: URL, typed: Bool) {
        if teaching, typed {
            if actions.isEmpty { startURL = url.absoluteString }
            else { actions.append(RecordedAction(type: "navigate", url: url.absoluteString)) }
        }
        guard !teaching else { return }
        let origin = Workflow.origin(of: url)
        if origin != episodeOrigin { closeEpisode(); episodeOrigin = origin; episodeStart = url.absoluteString }
        else if episode.isEmpty || typed { episodeStart = url.absoluteString }
        scheduleClose()
    }

    private func scheduleClose() {
        idleTask?.cancel()
        let delay = idleSeconds
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.closeEpisode()
        }
    }

    func closeEpisode() {
        idleTask?.cancel()
        defer { episode = []; episodeStart = nil }
        guard let origin = episodeOrigin, let start = episodeStart else { return }
        let steps = Self.collapse(episode)
        // Worth caching only when the procedure takes input and does something with it.
        guard steps.count >= 2, steps.contains(where: { $0.type == "fill" || $0.type == "select" }) else { return }
        let signature = steps.map(\.shape).joined(separator: "\n")
        store.addTrace(origin: origin, signature: signature, actions: steps)
        let times = store.traces(origin: origin, signature: signature).count
        guard times >= 2, !dismissed.contains(signature) else { return }
        suggestion = RepeatSuggestion(origin: origin, startURL: start, actions: steps, times: times)
    }

    func dismissSuggestion() {
        if let s = suggestion { dismissed.insert(s.actions.map(\.shape).joined(separator: "\n")) }
        suggestion = nil
    }

    /// Repeated fills of the same field keep the last value.
    nonisolated static func collapse(_ actions: [RecordedAction]) -> [RecordedAction] {
        var out: [RecordedAction] = []
        for a in actions {
            if let last = out.last, last.type == a.type, last.selector == a.selector, ["fill", "select"].contains(a.type) {
                out[out.count - 1] = a
            } else {
                out.append(a)
            }
        }
        return out
    }

    nonisolated static func snake(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
        var s = lowered.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if s.count > 30 { s = String(s.prefix(30)).trimmingCharacters(in: CharacterSet(charactersIn: "_")) }
        if s.isEmpty || s.first!.isNumber { s = "field_" + s }
        return s
    }
}
