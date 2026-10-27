// Licensed under GPL-3.0. See LICENSE.

import AppKit
import SwiftUI

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
                .padding(10).background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(Theme.fill))
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
            switch model.panel {
            case .skills: SkillsPanel(store: model.store, executor: model.executor)
            case .teach: TeachPanel(recorder: model.recorder)
            case .assistant: AssistantPanel(assistant: model.assistant)
            case .settings: SettingsPanel(initial: model.settings)
            }
        }
    }
}

/// Text tabs with a hairline underline. Teach appears only while a recording exists.
struct PanelTabs: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let tabs: [Panel] = model.recorder.teaching || model.panel == .teach ? [.skills, .teach, .assistant, .settings] : [.skills, .assistant, .settings]
        HStack(spacing: 16) {
            ForEach(tabs) { p in
                Button { withAnimation(Theme.quick) { model.panel = p } } label: {
                    Text(p.rawValue).font(.system(size: 12.5, weight: model.panel == p ? .semibold : .medium))
                        .foregroundStyle(model.panel == p ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(model.panel == p ? Color.primary : .clear).frame(height: 1.5).offset(y: 9)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { model.panelVisible = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)) }
                .buttonStyle(.borderless).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
        .overlay(alignment: .bottom) { Hairline() }
        .padding(.bottom, 10)
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
            HStack {
                Text(store.skills.isEmpty ? "No skills yet" : "\(store.skills.count) skill\(store.skills.count == 1 ? "" : "s")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button { model.startTeaching() } label: { Label("Teach", systemImage: "plus") }.buttonStyle(PillButtonStyle(small: true))
            }
            .padding(.horizontal, 14).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if let run = executor.current {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.mini)
                            Text("Running \(store.skills.first { $0.id == run.skillID }?.title ?? "skill")").font(.system(size: 12, weight: .medium))
                            Text(executor.currentStep ?? "").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    if store.skills.isEmpty {
                        Text("Do a task twice and BrowserSkills offers to save it. Or press Teach and do it once. Every saved skill becomes an MCP tool.")
                            .font(.system(size: 12.5)).foregroundStyle(.secondary).padding(10)
                    }
                    ForEach(store.skills) { skill in
                        SkillRow(skill: skill, expanded: expanded == skill.id) {
                            withAnimation(Theme.quick) { expanded = expanded == skill.id ? nil : skill.id }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .id(store.revision)
            Hairline().padding(.horizontal, 14)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect an agent").font(.system(size: 12.5, weight: .medium))
                    Text("Hermes, Claude Code, Cursor").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.mcpConfigJSON, forType: .string)
                    model.status = "Copied the MCP config. It contains the bearer token, so treat it like a password."
                } label: { Label("Copy config", systemImage: "doc.on.doc") }
                .buttonStyle(PillButtonStyle(small: true))
                .contextMenu { Button("Reveal token file") { NSWorkspace.shared.activateFileViewerSelecting([model.mcp.tokenFile]) } }
            }
            .padding(14)
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

    var body: some View {
        let versions = model.store.versions(skillID: skill.id)
        let active = model.store.activeVersion(of: skill)
        let shown = active ?? versions.first
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.title).font(.system(size: 13, weight: .medium))
                    Text("skill_\(skill.name)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                }
                Spacer()
                if active != nil {
                    StatusLabel(text: "Verified", color: Theme.accent)
                    if !expanded, let n = runCount(), n > 0 { Text("\(n) run\(n == 1 ? "" : "s")").font(.system(size: 11.5)).foregroundStyle(.tertiary) }
                } else if let v = versions.first {
                    StatusLabel(text: statusText(v.status), color: Theme.warning)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle()).onTapGesture(perform: toggle)
            if expanded, let v = shown {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(v.workflow.inputs, id: \.name) { input in
                        HStack {
                            Text(input.name).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                            Spacer()
                            TextField(input.example, text: Binding(get: { inputs[input.name] ?? input.example }, set: { inputs[input.name] = $0 }))
                                .textFieldStyle(.plain).font(.system(size: 12.5)).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(Theme.fill))
                    }
                    HStack(spacing: 8) {
                        Button {
                            running = true
                            let values = Dictionary(v.workflow.inputs.map { ($0.name, inputs[$0.name] ?? $0.example) }, uniquingKeysWith: { a, _ in a })
                            Task {
                                lastRun = await model.executor.run(skill: skill, inputs: values, dedupe: false)
                                running = false
                            }
                        } label: { Label(running ? "Running" : "Run", systemImage: "play.fill") }
                        .buttonStyle(PillButtonStyle(primary: true, small: true)).disabled(running || active == nil)
                        Button { model.selectedID = model.agentTab.id } label: { Label("Watch", systemImage: "eye") }
                            .buttonStyle(PillButtonStyle(small: true))
                        Spacer()
                        if let r = lastRun ?? model.store.runs(skillID: skill.id, limit: 1).first, let f = r.finished {
                            Text(String(format: "%.1f s", f.timeIntervalSince(r.started))).font(.system(size: 11.5)).foregroundStyle(.tertiary)
                            if let shot = r.screenshot {
                                Button("Screenshot") { NSWorkspace.shared.open(URL(fileURLWithPath: shot)) }
                                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    if let r = lastRun ?? model.store.runs(skillID: skill.id, limit: 1).first { RunView(run: r) }
                    HStack {
                        Text(v.compiler == "fixture" ? "Compiled by the fixture compiler, no API key" : "Compiled by \(v.compiler.replacingOccurrences(of: "nemotron:", with: ""))")
                            .font(.system(size: 11)).foregroundStyle(v.compiler == "fixture" ? Theme.warning : Color.secondary).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) { model.store.delete(skillID: skill.id) } label: { Image(systemName: "trash").font(.system(size: 11)) }
                            .buttonStyle(.borderless).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(expanded ? Theme.fill : .clear))
    }

    private func runCount() -> Int? { model.store.runs(skillID: skill.id, limit: 50).filter { $0.purpose == "run" }.count }
    private func statusText(_ s: VersionStatus) -> String {
        switch s.rawValue {
        case "needsLogin": return "Needs login"
        case "needsReview": return "Needs review"
        default: return s.rawValue.capitalized
        }
    }
}

struct RunView: View {
    let run: RunRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(run.purpose == "validation" ? "Validation replay" : "Last result")
            ForEach(run.outputs.sorted { $0.key < $1.key }, id: \.key) { k, v in
                HStack(alignment: .top, spacing: 10) {
                    Text(k).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                    Text(v.text).font(.system(size: 12.5)).textSelection(.enabled)
                }
            }
            if let e = run.error { Text(e).font(.system(size: 12)).foregroundStyle(Theme.danger).textSelection(.enabled) }
            if run.status != .success, run.error == nil { StatusLabel(text: run.status.rawValue, color: run.status.isTerminal ? Theme.danger : Theme.accent) }
        }
    }
}

struct StatusLabel: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            StatusDot(color: color, size: 6)
            Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(color)
        }
    }
}

// MARK: Teach

struct TeachPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var recorder: Recorder
    @State private var hint = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !recorder.teaching {
                    Text("Teach a skill").font(.system(size: 13, weight: .semibold))
                    Text("Open the page you start from, press Teach, do the task once and pick the result fields. The skill is replayed once before it is saved.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    Button("Start recording") { model.startTeaching() }.buttonStyle(PillButtonStyle(primary: true))
                } else {
                    HStack(spacing: 10) {
                        StatusDot(color: Theme.danger, size: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recording").font(.system(size: 13, weight: .semibold))
                            Text(recorder.actions.isEmpty ? "Use the site like you normally do" : (recorder.startURL.flatMap { URL(string: $0)?.host } ?? "")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10).background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.danger.opacity(0.10)))
                    Caption("Steps")
                    if recorder.actions.isEmpty {
                        Text("Type, choose and click in the page. Each action shows up here.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    }
                    ForEach(Array(recorder.actions.enumerated()), id: \.element.id) { i, a in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                .frame(width: 20, height: 20).background(Circle().fill(Theme.fill))
                            Text(a.summary).font(.system(size: 12.5)).lineLimit(2)
                            Spacer()
                            Button { recorder.removeAction(a.id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)) }
                                .buttonStyle(.borderless).foregroundStyle(.tertiary)
                        }
                    }
                    Caption("Results")
                    ForEach($recorder.picked) { $p in
                        HStack(spacing: 10) {
                            TextField("name", text: $p.name).textFieldStyle(.plain).font(.system(size: 11.5, design: .monospaced)).frame(width: 90)
                            Text(p.sample).font(.system(size: 12.5)).lineLimit(1).foregroundStyle(.secondary)
                            Spacer()
                            Toggle("list", isOn: Binding(get: { p.many }, set: { on in
                                p.many = on
                                if let s = on ? p.listSelector : p.singleSelector { p.selector = s }
                            }))
                            .toggleStyle(.checkbox).font(.system(size: 11)).foregroundStyle(.secondary).disabled(p.listSelector == nil)
                        }
                        .padding(.horizontal, 10).frame(height: 30).background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(Theme.fill))
                    }
                    Button { model.pickOutput() } label: {
                        Label(recorder.picking ? "Click a result on the page" : "Pick a result on the page", systemImage: "scope")
                    }
                    .buttonStyle(PillButtonStyle(small: true)).disabled(recorder.picking)
                    Caption("Name")
                    TextField("What does this do?", text: $hint).textFieldStyle(.plain).font(.system(size: 12.5)).modifier(FieldChrome())
                    HStack(spacing: 12) {
                        Button(model.compiling ? "Saving" : "Save skill") { Task { await model.saveTeaching(hint: hint) } }
                            .buttonStyle(PillButtonStyle(primary: true))
                            .disabled(model.compiling || recorder.actions.isEmpty || recorder.picked.isEmpty)
                        Button("Discard") { recorder.cancelTeaching() }.buttonStyle(PlainActionStyle())
                        Spacer()
                        if model.compiling { ProgressView().controlSize(.small) }
                    }
                    Text(model.settings.hasModel ? "Replayed once before it is saved" : "No API key, so the fixture compiler is used and the skill is labeled fixture")
                        .font(.system(size: 11.5)).foregroundStyle(model.settings.hasModel ? Color.secondary : Theme.warning)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }
}

// MARK: Assistant

struct AssistantPanel: View {
    @ObservedObject var assistant: Assistant
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if assistant.lines.isEmpty {
                            Text("Ask about this page or run a skill. The assistant uses your saved skills first and can work any page through the same tools agents get over MCP.")
                                .font(.system(size: 12.5)).foregroundStyle(.secondary)
                        }
                        ForEach(assistant.lines) { line in
                            switch line.role {
                            case .user:
                                Text(line.text).font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.fillStrong))
                                    .frame(maxWidth: .infinity, alignment: .trailing).textSelection(.enabled).id(line.id)
                            case .tool:
                                HStack(spacing: 8) {
                                    Image(systemName: "terminal").font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Text(line.text).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .id(line.id)
                            case .error:
                                Text(line.text).font(.system(size: 12.5)).foregroundStyle(Theme.danger).textSelection(.enabled).id(line.id)
                            default:
                                Text(line.text).font(.system(size: 13)).textSelection(.enabled).id(line.id)
                            }
                        }
                        if assistant.busy { ProgressView().controlSize(.small) }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
                .onChange(of: assistant.lines.count) { _, _ in if let last = assistant.lines.last { withAnimation(Theme.quick) { proxy.scrollTo(last.id, anchor: .bottom) } } }
            }
            HStack(spacing: 8) {
                TextField("Ask about this page or run a skill", text: $text).textFieldStyle(.plain).font(.system(size: 12.5))
                    .focused($focused).onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Circle().fill(text.isEmpty || assistant.busy ? Color.secondary.opacity(0.4) : Theme.accent))
                }
                .buttonStyle(.plain).disabled(text.isEmpty || assistant.busy)
            }
            .padding(.leading, 12).padding(.trailing, 6).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.fill))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1))
            .contextMenu { Button("Clear conversation") { assistant.reset() } }
            .padding(14)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Caption("Models")
                    SettingField(label: "Nebius API key", note: "Stored locally with mode 0600") { SecureField("", text: $initial.apiKey) }
                    SettingField(label: "Base URL") { TextField("", text: $initial.baseURL) }
                    SettingField(label: "Compiler") { TextField("", text: $initial.compilerModel) }
                    SettingField(label: "Assistant") { TextField("", text: $initial.assistantModel) }
                    SettingField(label: "Tavily key", note: "Optional, enables web_search") { SecureField("", text: $initial.tavilyKey) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Caption("MCP")
                    SettingField(label: "Endpoint", note: "Loopback only, bearer token") {
                        Text(model.mcp.endpoint.replacingOccurrences(of: "http://", with: "")).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    SettingField(label: "Port") { TextField("", value: $initial.mcpPort, format: .number.grouping(.never)) }
                    HStack(spacing: 8) {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([model.mcp.tokenFile]) } label: { Label("Reveal token", systemImage: "key") }
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.mcpConfigJSON, forType: .string)
                            model.status = "Copied the MCP config. It contains the bearer token, so treat it like a password."
                        } label: { Label("Copy Hermes config", systemImage: "doc.on.doc") }
                    }
                    .buttonStyle(PillButtonStyle(small: true))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Caption("Privacy")
                    Text("Passwords and one-time codes are never recorded.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    Text("Skills run in a hidden tab with your normal logins.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    Text("NEBIUS_API_KEY in the environment overrides the saved key.").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                }
                Button("Save") { model.saveSettings(initial) }.buttonStyle(PillButtonStyle(primary: true))
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }
}

struct SettingField<Content: View>: View {
    let label: String
    var note: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                if let note { Text(note).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1) }
            }
            content.textFieldStyle(.plain).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.rowRadius).fill(Theme.fill))
    }
}
