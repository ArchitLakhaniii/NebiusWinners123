// Licensed under GPL-3.0. See LICENSE.

import AppKit
import SwiftUI

struct SidePanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.panel) {
                ForEach(Panel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(10)
            if let status = model.status {
                HStack(alignment: .top) {
                    Text(status).font(.caption).textSelection(.enabled)
                    Spacer()
                    Button { model.status = nil } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.borderless)
                }
                .padding(8).background(Color.accentColor.opacity(0.1)).padding(.horizontal, 10)
            }
            Divider().padding(.top, 6)
            switch model.panel {
            case .skills: SkillsPanel(store: model.store, executor: model.executor)
            case .teach: TeachPanel(recorder: model.recorder)
            case .assistant: AssistantPanel(assistant: model.assistant)
            case .settings: SettingsPanel(initial: model.settings)
            }
        }
        .background(.background)
    }
}

// MARK: Skills

struct SkillsPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: SkillStore
    @ObservedObject var executor: Executor
    @State private var expanded: Int64?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let run = executor.current {
                    Label("Running \(store.skills.first { $0.id == run.skillID }?.name ?? "skill") · \(executor.currentStep ?? "")", systemImage: "gearshape.2")
                        .font(.caption).foregroundStyle(.green)
                }
                if store.skills.isEmpty {
                    Text("No skills yet").font(.headline)
                    Text("Press Teach and do a task once, or just do the same task twice: BrowserSkills notices repeats and offers to cache them. Every saved skill becomes an MCP tool.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(store.skills) { skill in
                    SkillCard(skill: skill, expanded: expanded == skill.id) { expanded = expanded == skill.id ? nil : skill.id }
                }
                Divider()
                Text("Connect an agent").font(.headline)
                Text("Point any MCP client at the browser. Tools: one per skill, plus browser_open, page_describe, page_act, page_read for any page.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Copy MCP config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.mcpConfigJSON, forType: .string)
                        model.status = "Copied MCP config with the bearer token. Treat it like a password."
                    }
                    Button("Reveal token file") { NSWorkspace.shared.activateFileViewerSelecting([model.mcp.tokenFile]) }
                }
            }
            .padding(12)
        }
        .id(store.revision)
    }
}

struct SkillCard: View {
    @EnvironmentObject var model: AppModel
    let skill: Skill
    let expanded: Bool
    let toggle: () -> Void
    @State private var inputs: [String: String] = [:]
    @State private var lastRun: RunRecord?
    @State private var running = false

    var body: some View {
        let versions = model.store.versions(skillID: skill.id)
        let active = model.store.activeVersion(of: skill)
        let shown = active ?? versions.first
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.title).font(.callout.bold())
                    Text("skill_\(skill.name) · \(URL(string: skill.origin)?.host ?? skill.origin)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: active != nil ? "v\(active!.version) verified" : (versions.first?.status.rawValue ?? "?"),
                            color: active != nil ? .green : .orange)
            }
            .contentShape(Rectangle()).onTapGesture(perform: toggle)
            if expanded, let v = shown {
                Text("Compiled by \(v.compiler)").font(.caption2)
                    .foregroundStyle(v.compiler == "fixture" ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                ForEach(v.workflow.inputs, id: \.name) { input in
                    TextField(input.name, text: Binding(get: { inputs[input.name] ?? input.example }, set: { inputs[input.name] = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button(running ? "Running…" : "Run") {
                        running = true
                        let values = Dictionary(uniqueKeysWithValues: v.workflow.inputs.map { ($0.name, inputs[$0.name] ?? $0.example) })
                        Task {
                            lastRun = await model.executor.run(skill: skill, inputs: values, dedupe: false)
                            running = false
                        }
                    }
                    .disabled(running || active == nil)
                    Button("Watch") { model.selectedID = model.agentTab.id }
                    Spacer()
                    Button(role: .destructive) { model.store.delete(skillID: skill.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
                if let r = lastRun ?? model.store.runs(skillID: skill.id, limit: 1).first { RunView(run: r) }
                DisclosureGroup("Steps (\(v.workflow.steps.count))") {
                    ForEach(Array(v.workflow.steps.enumerated()), id: \.offset) { i, step in
                        Text("\(i + 1). \(step.kind.rawValue) \(step.url ?? step.target?.label ?? step.target?.selector ?? "") \(step.value ?? step.key ?? "")")
                            .font(.caption.monospaced()).lineLimit(2)
                    }
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct RunView: View {
    let run: RunRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                StatusBadge(text: run.status.rawValue, color: run.status == .success ? .green : (run.status.isTerminal ? .red : .blue))
                Text(run.purpose == "validation" ? "validation replay" : "run \(run.id.prefix(8))").font(.caption2).foregroundStyle(.secondary)
                if let f = run.finished { Text(String(format: "%.1fs", f.timeIntervalSince(run.started))).font(.caption2).foregroundStyle(.secondary) }
            }
            ForEach(run.outputs.sorted { $0.key < $1.key }, id: \.key) { k, v in
                Text("\(k): ").font(.caption.bold()) + Text(v.text).font(.caption)
            }
            if let e = run.error { Text(e).font(.caption).foregroundStyle(.red) }
            if !run.checks.isEmpty { Text(run.checks.map { "✓ " + $0 }.joined(separator: "  ")).font(.caption2).foregroundStyle(.green) }
            if let shot = run.screenshot { Button("Evidence screenshot") { NSWorkspace.shared.open(URL(fileURLWithPath: shot)) }.font(.caption2).buttonStyle(.link) }
        }
        .textSelection(.enabled)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18))).foregroundStyle(color)
    }
}

// MARK: Teach

struct TeachPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var recorder: Recorder
    @State private var hint = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !recorder.teaching {
                    Text("Teach a skill").font(.headline)
                    Text("1. Open the page you start from.\n2. Press Teach and do the task once.\n3. Pick the result fields.\n4. Save. Nemotron compiles it, BrowserSkills replays it to verify, and it becomes a tool.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Start recording") { model.startTeaching() }.buttonStyle(.borderedProminent)
                } else {
                    Text("Recording from \(recorder.startURL ?? "current page")").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text("Steps").font(.headline)
                    if recorder.actions.isEmpty { Text("Do the task in the page: type, choose, click.").font(.callout).foregroundStyle(.secondary) }
                    ForEach(recorder.actions) { a in
                        HStack {
                            Text(a.summary).font(.caption).lineLimit(2)
                            Spacer()
                            Button { recorder.removeAction(a.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    Divider()
                    Text("Results").font(.headline)
                    ForEach($recorder.picked) { $p in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                TextField("name", text: $p.name).textFieldStyle(.roundedBorder).font(.caption.monospaced())
                                Toggle("list", isOn: $p.many).toggleStyle(.checkbox).font(.caption)
                            }
                            Text(p.sample).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Button(recorder.picking ? "Click a result on the page…" : "Pick a result on the page") { model.pickOutput() }
                        .disabled(recorder.picking)
                    Divider()
                    TextField("What does this do? (optional, e.g. Look up order status)", text: $hint).textFieldStyle(.roundedBorder)
                    HStack {
                        Button(model.compiling ? "Saving…" : "Save skill") { Task { await model.saveTeaching(hint: hint) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.compiling || recorder.actions.isEmpty || recorder.picked.isEmpty)
                        Button("Discard") { recorder.cancelTeaching() }
                    }
                    if !model.settings.hasModel {
                        Text("No API key: the fixture compiler will be used and the skill is labeled “fixture”.").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: Assistant

struct AssistantPanel: View {
    @ObservedObject var assistant: Assistant
    @State private var text = ""
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if assistant.lines.isEmpty {
                            Text("Ask for something on the web. The assistant uses your saved skills first, and can work any page through the same tools agents get over MCP.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(assistant.lines) { line in
                            Text(line.text)
                                .font(line.role == .tool ? .caption.monospaced() : .callout)
                                .foregroundStyle(line.role == .tool ? AnyShapeStyle(.secondary) : (line.role == .error ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary)))
                                .frame(maxWidth: .infinity, alignment: line.role == .user ? .trailing : .leading)
                                .padding(line.role == .user ? 8 : 0)
                                .background(line.role == .user ? RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)) : nil)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                        if assistant.busy { ProgressView().controlSize(.small) }
                    }
                    .padding(12)
                }
                .onChange(of: assistant.lines.count) { _, _ in if let last = assistant.lines.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            Divider()
            HStack {
                TextField("Ask Nemotron…", text: $text).textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Clear") { assistant.reset() }.buttonStyle(.borderless)
            }
            .padding(10)
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
    var body: some View {
        Form {
            Section("Nemotron on Nebius Token Factory") {
                SecureField("API key", text: $initial.apiKey)
                TextField("Base URL", text: $initial.baseURL)
                TextField("Compiler model", text: $initial.compilerModel)
                TextField("Assistant model", text: $initial.assistantModel)
            }
            Section("Optional") {
                SecureField("Tavily API key (web_search tool)", text: $initial.tavilyKey)
                TextField("MCP port", value: $initial.mcpPort, format: .number.grouping(.never))
            }
            Button("Save") { model.saveSettings(initial) }.buttonStyle(.borderedProminent)
            Text("Stored at \(AppSettings.fileURL(in: model.store.directory).path) (mode 0600). NEBIUS_API_KEY in the environment overrides it.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
