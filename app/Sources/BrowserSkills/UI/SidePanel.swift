// Licensed under GPL-3.0. See LICENSE.

import AppKit
import SwiftUI

/// Right column on the window material: a segmented control, then one panel.
struct SidePanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            PanelTabs()
            if let status = model.status {
                HStack(alignment: .top, spacing: 8) {
                    Text(status).font(.system(size: 12)).textSelection(.enabled)
                    Spacer()
                    Button { model.status = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)) }
                        .buttonStyle(.borderless).foregroundStyle(.tertiary)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(Theme.control))
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
            Group {
                switch model.panel {
                case .skills: SkillsPanel(store: model.store, executor: model.executor)
                case .teach: TeachPanel(recorder: model.recorder)
                case .assistant: AssistantPanel(assistant: model.assistant)
                case .settings: SettingsPanel(initial: model.settings)
                }
            }
            .id(model.panel)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.15), value: model.panel)
    }
}

/// Segmented control, 28pt: control fill outer, control-2 selected segment.
struct PanelTabs: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Panel.allCases) { p in
                Button { model.panel = p } label: {
                    Text(p.rawValue).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(model.panel == p ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(model.panel == p ? Theme.control2 : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.control))
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 14)
    }
}

// MARK: Skills

struct SkillsPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: SkillStore
    @ObservedObject var executor: Executor
    @State private var expanded: Int64?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.skills.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No skills yet").font(.system(size: 14, weight: .medium))
                            Text("Do a task twice and the browser offers to save it. Or press Teach a skill and do it once. Every saved skill becomes an MCP tool.")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                            Button("Teach a skill") { model.startTeaching() }.buttonStyle(ControlButtonStyle()).padding(.top, 4)
                        }
                        .padding(.horizontal, 12).padding(.bottom, 12)
                    }
                    ForEach(Array(store.skills.enumerated()), id: \.element.id) { i, skill in
                        if i > 0 { Hairline().padding(.horizontal, 12) }
                        SkillRow(skill: skill, expanded: expanded == skill.id || (expanded == nil && i == 0 && store.skills.count == 1)) {
                            expanded = expanded == skill.id ? nil : skill.id
                        }
                    }
                }
            }
            .id(store.revision)
            Spacer(minLength: 0)
            Hairline().padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect an agent").font(.system(size: 14, weight: .medium))
                Text("Point any MCP client at the browser. One tool per skill, plus browser_open, page_describe, page_act and page_read for any page.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Copy MCP config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.mcpConfigJSON, forType: .string)
                        model.status = "Copied the MCP config. It contains the bearer token, so treat it like a password."
                    }
                    Button("Reveal token file") { NSWorkspace.shared.activateFileViewerSelecting([model.mcp.tokenFile]) }
                }
                .buttonStyle(ControlButtonStyle()).padding(.top, 6)
            }
            .padding(12)
        }
    }
}

struct SkillRow: View {
    @EnvironmentObject var model: AppModel
    let skill: Skill
    let expanded: Bool
    let toggle: () -> Void
    @State private var inputs: [String: String] = [:]
    @State private var lastRun: RunRecord?
    @State private var running = false
    @State private var showSteps = false

    var body: some View {
        let versions = model.store.versions(skillID: skill.id)
        let active = model.store.activeVersion(of: skill)
        let shown = active ?? versions.first
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.title).font(.system(size: 13, weight: .medium))
                    HStack(spacing: 8) {
                        Text("skill_\(skill.name)").mono(11.5).foregroundStyle(.secondary)
                        Text(URL(string: skill.origin)?.host ?? skill.origin).font(.system(size: 11.5)).foregroundStyle(.tertiary)
                    }
                    .lineLimit(1)
                }
                Spacer()
                Text(statusText(active: active, latest: versions.first)).font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle()).onTapGesture(perform: toggle)
            if expanded, let v = shown {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(v.workflow.inputs, id: \.name) { input in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(input.name).font(.system(size: 12)).foregroundStyle(.secondary)
                            TextField(input.example, text: Binding(get: { inputs[input.name] ?? input.example }, set: { inputs[input.name] = $0 }))
                                .textFieldStyle(.plain).font(.system(size: 13)).modifier(FieldChrome(height: 30))
                        }
                    }
                    HStack(spacing: 8) {
                        Button(running ? "Running" : "Run") {
                            running = true
                            let values = Dictionary(v.workflow.inputs.map { ($0.name, inputs[$0.name] ?? $0.example) }, uniquingKeysWith: { a, _ in a })
                            Task {
                                lastRun = await model.executor.run(skill: skill, inputs: values, dedupe: false)
                                running = false
                            }
                        }
                        .buttonStyle(AccentButtonStyle()).disabled(running || active == nil)
                        Button("Watch") { model.selectedID = model.agentTab.id }.buttonStyle(ControlButtonStyle())
                        Spacer()
                        Button { model.store.delete(skillID: skill.id) } label: { Image(systemName: "trash").font(.system(size: 12)) }
                            .buttonStyle(.borderless).foregroundStyle(.tertiary).help("Delete skill")
                    }
                    if let r = lastRun ?? model.store.runs(skillID: skill.id, limit: 1).first { RunView(run: r) }
                    Button { showSteps.toggle() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showSteps ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                            Text("Steps (\(v.workflow.steps.count))").font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    if showSteps {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(v.workflow.steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(i + 1)").mono(11).foregroundStyle(.tertiary).frame(width: 14, alignment: .trailing)
                                    Text(step.kind.rawValue).mono(11.5).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                                    Text(stepTarget(step)).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                                }
                            }
                        }
                    }
                    Text(v.compiler == "fixture" ? "fixture compiler, no API key" : "compiled by \(v.compiler.replacingOccurrences(of: "nemotron:", with: ""))")
                        .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.bottom, 14)
            }
        }
    }

    private func statusText(active: SkillVersion?, latest: SkillVersion?) -> String {
        if let active { return "v\(active.version) · verified" }
        guard let latest else { return "" }
        switch latest.status {
        case .candidate: return "v\(latest.version) · not verified"
        case .failedValidation: return "v\(latest.version) · replay failed"
        case .validated: return "v\(latest.version) · verified"
        }
    }

    private func stepTarget(_ step: WorkflowStep) -> String {
        if let t = step.target { return t.label ?? t.selector }
        if let u = step.url { return u }
        if let k = step.key { return k }
        return step.value ?? ""
    }
}

struct RunView: View {
    let run: RunRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if run.status == .success { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                Text(statusWord).font(.system(size: 12.5, weight: .medium))
                Text(meta).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(run.outputs.sorted { $0.key < $1.key }, id: \.key) { k, v in
                    GridRow {
                        Text(k).mono(11.5).foregroundStyle(.secondary)
                        Text(v.text).font(.system(size: 13)).textSelection(.enabled).lineLimit(2)
                    }
                }
            }
            if !run.checks.isEmpty {
                Text(run.checks.map { "✓ " + $0 }.joined(separator: "   ")).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(2)
            }
            if let e = run.error { Text(e).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled) }
            if let shot = run.screenshot {
                Button("Evidence screenshot") { NSWorkspace.shared.open(URL(fileURLWithPath: shot)) }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
            }
        }
    }
    private var statusWord: String {
        switch run.status {
        case .success: return "Succeeded"
        case .needsLogin: return "Needs login"
        case .needsReview: return "Needs review"
        case .queued, .running, .verifying: return "Running"
        default: return run.status.rawValue.capitalized
        }
    }
    private var meta: String {
        var parts = ["run \(run.id.prefix(7))"]
        if let f = run.finished { parts.append(String(format: "%.1f s", f.timeIntervalSince(run.started))) }
        parts.append(run.started.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

// MARK: Teach

struct TeachPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var recorder: Recorder
    @State private var hint = ""
    @State private var started = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !recorder.teaching {
                    Text("Teach a skill").font(.system(size: 14, weight: .medium))
                    Text("Open the page you start from, press Teach a skill, do the task once and click the values you want back. The agent tab replays it before it is saved.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Button("Start recording") { model.startTeaching(); started = Date() }.buttonStyle(AccentButtonStyle())
                } else {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.accent).frame(width: 8, height: 8)
                        Text("Recording from \(recorder.startURL.flatMap { URL(string: $0) }.map { ($0.host ?? "") + ($0.path == "/" ? "" : $0.path) } ?? "this page")")
                            .font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        TimelineView(.periodic(from: started, by: 1)) { ctx in
                            Text(elapsed(ctx.date)).mono(11.5).foregroundStyle(.tertiary)
                        }
                    }
                    Caption("Steps")
                    if recorder.actions.isEmpty {
                        Text("Type, choose and click in the page. Each action shows up here.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(recorder.actions.enumerated()), id: \.element.id) { i, a in
                            StepLine(index: i + 1, action: a) { recorder.removeAction(a.id) }
                        }
                    }
                    Hairline()
                    HStack {
                        Caption("Results")
                        Spacer()
                        Text(recorder.picking ? "Click a value on the page" : "").font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                    ForEach($recorder.picked) { $p in
                        HStack(spacing: 10) {
                            TextField("name", text: $p.name).textFieldStyle(.plain).mono(12)
                                .padding(.horizontal, 10).frame(width: 130, height: 28)
                                .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(Theme.control))
                            Text(p.sample).font(.system(size: 13)).lineLimit(1).foregroundStyle(.secondary)
                            Spacer()
                            Toggle("list", isOn: Binding(get: { p.many }, set: { on in
                                p.many = on
                                if let s = on ? p.listSelector : p.singleSelector { p.selector = s }
                            }))
                            .toggleStyle(.checkbox).font(.system(size: 12)).foregroundStyle(.secondary).disabled(p.listSelector == nil)
                        }
                    }
                    Button(recorder.picked.isEmpty ? "Pick a result" : "Pick another result") { model.pickOutput() }
                        .buttonStyle(ControlButtonStyle()).disabled(recorder.picking)
                    Hairline()
                    Caption("What does this do?")
                    TextField("Look up order status", text: $hint).textFieldStyle(.plain).font(.system(size: 13)).modifier(FieldChrome())
                    HStack(spacing: 14) {
                        Button(model.compiling ? "Saving" : "Save skill") { Task { await model.saveTeaching(hint: hint) } }
                            .buttonStyle(AccentButtonStyle())
                            .disabled(model.compiling || recorder.actions.isEmpty || recorder.picked.isEmpty)
                        Button("Discard") { recorder.cancelTeaching() }.buttonStyle(PlainActionStyle())
                        Spacer()
                        if model.compiling { ProgressView().controlSize(.small) }
                    }
                    Text(model.settings.hasModel
                         ? "Nemotron compiles the recording into typed steps. The agent tab replays it, and the skill is kept only if the replay passes its checks."
                         : "No API key, so the fixture compiler turns the recording into typed steps. The agent tab replays it, and the skill is kept only if the replay passes its checks.")
                        .font(.system(size: 11.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 14)
        }
        .onAppear { if recorder.teaching { started = recorder.actions.first?.at ?? Date() } }
    }

    private func elapsed(_ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(started)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// One recorded action: index, kind in mono, target, remove on hover.
struct StepLine: View {
    let index: Int
    let action: RecordedAction
    let remove: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(index)").mono(11).foregroundStyle(.tertiary).frame(width: 14, alignment: .trailing)
            Text(action.type).mono(11.5).foregroundStyle(.secondary).frame(width: 54, alignment: .leading)
            Text(target).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if hover {
                Button(action: remove) { Image(systemName: "minus.circle").font(.system(size: 12)) }
                    .buttonStyle(.borderless).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(hover ? Theme.control : .clear))
        .onHover { hover = $0 }
    }
    private var target: String {
        switch action.type {
        case "navigate": return URL(string: action.url).map { $0.path + ($0.query.map { "?" + $0 } ?? "") } ?? action.url
        case "fill", "select": return "\(action.label ?? action.selector ?? "field") · \(action.secret ? "••••" : (action.value ?? ""))"
        case "press": return "\(action.key ?? "key") in \(action.label ?? action.selector ?? "field")"
        default: return action.label ?? action.selector ?? action.type
        }
    }
}

// MARK: Assistant

struct AssistantPanel: View {
    @ObservedObject var assistant: Assistant
    @EnvironmentObject var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if assistant.lines.isEmpty {
                            Text(model.settings.hasModel
                                 ? "Ask about this page or run a skill. The assistant uses your saved skills first and can work any page through the same tools agents get over MCP."
                                 : "Add a Nebius API key in Settings to use the assistant. Saved skills still run from the Skills panel and over MCP.")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        ForEach(assistant.lines) { line in
                            switch line.role {
                            case .user:
                                Text(line.text).font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.control))
                                    .frame(maxWidth: .infinity, alignment: .trailing).textSelection(.enabled).id(line.id)
                            case .tool:
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: line.text.hasPrefix("→") || line.text.hasPrefix("->") ? "arrow.turn.down.left" : "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Text(line.text).mono(11.5).foregroundStyle(.secondary).lineLimit(3)
                                }
                                .id(line.id)
                            case .error:
                                Text(line.text).font(.system(size: 12.5)).foregroundStyle(.secondary).textSelection(.enabled).id(line.id)
                            default:
                                Text(line.text).font(.system(size: 13)).textSelection(.enabled).id(line.id)
                            }
                        }
                        if assistant.busy {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Working").font(.system(size: 12.5)).foregroundStyle(.secondary)
                                ProgressView().progressViewStyle(.linear).tint(Theme.accent).frame(height: 2)
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 10)
                }
                .onChange(of: assistant.lines.count) { _, _ in if let last = assistant.lines.last { withAnimation(Theme.quick) { proxy.scrollTo(last.id, anchor: .bottom) } } }
            }
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Ask Nemotron", text: $text).textFieldStyle(.plain).font(.system(size: 13))
                        .focused($focused).onSubmit(send)
                    Button(action: send) { Image(systemName: "return").font(.system(size: 11, weight: .medium)) }
                        .buttonStyle(.borderless).foregroundStyle(text.isEmpty || assistant.busy ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                        .disabled(text.isEmpty || assistant.busy)
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.control))
                Button("Clear") { assistant.reset() }.buttonStyle(PlainActionStyle()).disabled(assistant.lines.isEmpty)
            }
            .padding(12)
        }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !assistant.busy else { return }
        text = ""
        Task { await assistant.send(t) }
    }
}

// MARK: Settings

struct SettingsPanel: View {
    @EnvironmentObject var model: AppModel
    @State var initial: AppSettings
    @State private var savedAt: Date?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Caption("Nemotron on Nebius Token Factory")
                SettingsGroup {
                    SettingRow("API key") { SecureField("Not set, fixture mode", text: $initial.apiKey) }
                    SettingRow("Base URL") { TextField("", text: $initial.baseURL, axis: .vertical).mono(12) }
                    SettingRow("Compiler model") { TextField("", text: $initial.compilerModel, axis: .vertical).mono(12) }
                    SettingRow("Assistant model") { TextField("", text: $initial.assistantModel, axis: .vertical).mono(12) }
                }
                Caption("Optional").padding(.top, 8)
                SettingsGroup {
                    SettingRow("Tavily API key") { SecureField("Not set, web_search is off", text: $initial.tavilyKey) }
                    SettingRow("MCP port") { TextField("", value: $initial.mcpPort, format: .number.grouping(.never)).mono(12) }
                }
                HStack(spacing: 12) {
                    Button("Save") { model.saveSettings(initial); savedAt = Date() }.buttonStyle(AccentButtonStyle())
                    if let savedAt { Text("Saved \(savedAt.formatted(date: .omitted, time: .shortened))").font(.system(size: 12)).foregroundStyle(.tertiary) }
                    Spacer()
                    Button("Copy MCP config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.mcpConfigJSON, forType: .string)
                        model.status = "Copied the MCP config. It contains the bearer token, so treat it like a password."
                    }
                    .buttonStyle(ControlButtonStyle())
                }
                .padding(.top, 8)
                Text("Stored at ~/Library/Application Support/BrowserSkills/settings.json with mode 0600. NEBIUS_API_KEY in the environment overrides the key. Passwords and one-time codes are never recorded; skills run in the agent tab with your normal logins.")
                    .font(.system(size: 11.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            .padding(.horizontal, 12).padding(.bottom, 14)
        }
    }
}

/// Rows on one control fill, separated by hairlines.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(Theme.control))
    }
}

struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) { self.label = label; self.content = content() }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 13)).frame(width: 110, alignment: .leading)
            content.textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 9).frame(minHeight: 36)
        .overlay(alignment: .bottom) { Hairline().padding(.leading, 12) }
    }
}
