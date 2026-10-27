// Licensed under GPL-3.0. See LICENSE.
//
//  AppModel.swift
//  BrowserSkills
//
//  Wires the browser together: user tabs plus one agent tab, the recorder, compiler,
//  registry, executor, MCP server and assistant.
//

import AppKit
import Foundation

enum Panel: String, CaseIterable, Identifiable {
    case skills = "Skills", teach = "Teach", assistant = "Assistant", settings = "Settings"
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    let store: SkillStore
    @Published var settings: AppSettings
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID: UUID?
    @Published var panel: Panel = .skills
    @Published var panelVisible = false
    @Published var status: String?
    @Published private(set) var compiling = false

    let agentTab: BrowserTab
    let recorder: Recorder
    let executor: Executor
    let registry: ToolRegistry
    let mcp: MCPServer
    let assistant: Assistant
    private var typedLoads = Set<UUID>()

    var homeURL: URL {
        ProcessInfo.processInfo.environment["BROWSERSKILLS_HOME_URL"].flatMap(URL.init(string:)) ?? URL(string: "http://127.0.0.1:4318/")!
    }

    init() {
        let store = SkillStore()
        self.store = store
        let settings = AppSettings.load(from: store.directory)
        self.settings = settings
        agentTab = BrowserTab(isAgent: true)
        agentTab.title = "Agent"
        recorder = Recorder(store: store)
        executor = Executor(store: store, tab: agentTab)
        var current: () -> AppSettings = { settings }
        let registry = ToolRegistry(store: store, executor: executor, settings: { current() })
        self.registry = registry
        mcp = MCPServer(registry: registry, port: UInt16(settings.mcpPort), directory: store.directory)
        assistant = Assistant(registry: registry, settings: { current() })
        current = { [weak self] in self?.settings ?? settings }
        ParkingWindow.shared.park(agentTab.webView)
        mcp.start()
        newTab(url: homeURL)
    }

    func show(_ p: Panel) {
        panel = p
        panelVisible = true
    }

    var selected: BrowserTab? {
        if selectedID == agentTab.id { return agentTab }
        return tabs.first { $0.id == selectedID } ?? tabs.first
    }

    // MARK: Tabs

    func newTab(url: URL? = nil) {
        let tab = BrowserTab()
        tab.onRecorded = { [weak self] action in self?.recorder.observe(action) }
        tab.onPicked = { [weak self] body in self?.recorder.addPicked(body); self?.show(.teach) }
        tab.onNavigated = { [weak self, weak tab] url in
            guard let self, let tab else { return }
            self.recorder.navigated(to: url, typed: self.typedLoads.remove(tab.id) != nil)
        }
        tabs.append(tab)
        selectedID = tab.id
        if let url { tab.load(url) }
    }

    func close(_ tab: BrowserTab) {
        guard !tab.isAgent else { return }
        tabs.removeAll { $0.id == tab.id }
        if selectedID == tab.id { selectedID = tabs.last?.id }
        if tabs.isEmpty { newTab(url: homeURL) }
    }

    func go(_ text: String) {
        guard let tab = selected, !tab.isAgent else { return }
        typedLoads.insert(tab.id)
        tab.load(text: text)
    }

    // MARK: Teach

    func startTeaching() {
        guard let tab = selected, !tab.isAgent else { return }
        recorder.startTeaching(at: tab.url)
        show(.teach)
    }

    func adoptSuggestion() {
        guard let s = recorder.suggestion else { return }
        recorder.adopt(s)
        show(.teach)
        status = "Mark the result fields on this page, then Save."
    }

    func pickOutput() {
        guard let tab = selected, !tab.isAgent else { return }
        recorder.picking = true
        tab.startPicker()
    }

    /// Compile → validate statically → store candidate → replay in the agent tab → promote.
    func saveTeaching(hint: String) async {
        let start = recorder.startURL ?? recorder.actions.first?.url ?? selected?.url?.absoluteString ?? ""
        let demo = Demonstration(startURL: start, actions: recorder.actions, outputs: recorder.picked, hint: hint)
        compiling = true
        defer { compiling = false }
        do {
            status = settings.hasModel ? "Compiling with \(settings.compilerModel)…" : "Compiling with the fixture compiler (no API key)…"
            let compiled = try await Compiler.compile(demo, settings: settings)
            let version = try store.addCandidate(compiled.workflow, compiler: compiled.compiler)
            status = "Replaying \(compiled.workflow.name) v\(version.version) in the agent tab to verify…"
            let examples = Dictionary(uniqueKeysWithValues: compiled.workflow.inputs.map { ($0.name, $0.example) })
            let run = await executor.run(version: version, inputs: examples, purpose: "validation")
            if run.status == .success {
                store.setStatus(.validated, skillID: version.skillID, version: version.version)
                status = "Saved \(compiled.workflow.title) (v\(version.version), \(compiled.compiler)). It is now an MCP tool: skill_\(compiled.workflow.name)."
                recorder.cancelTeaching()
                show(.skills)
            } else {
                store.setStatus(.failedValidation, skillID: version.skillID, version: version.version)
                status = "Replay did not verify (\(run.status.rawValue)): \(run.error ?? ""). Adjust the steps or outputs and save again."
            }
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: Settings

    func saveSettings(_ s: AppSettings) {
        let portChanged = s.mcpPort != settings.mcpPort
        settings = s
        s.save(to: store.directory)
        status = portChanged ? "Saved. Restart BrowserSkills to move MCP to port \(s.mcpPort)." : "Settings saved."
    }

    /// Ready-to-paste MCP client config (Claude Code, Cursor, Hermes all accept this shape).
    var mcpConfigJSON: String {
        """
        {"mcpServers": {"browserskills": {"type": "http", "url": "\(mcp.endpoint)", "headers": {"Authorization": "Bearer \(mcp.token)"}}}}
        """
    }
}

/// Keeps the agent web view in a real (off-screen) window so pages render and timers run
/// at full speed while the user is looking at another tab.
@MainActor
final class ParkingWindow {
    static let shared = ParkingWindow()
    private let window: NSWindow

    private init() {
        window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1280, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900))
        window.orderBack(nil)
    }

    func park(_ view: NSView) {
        guard let content = window.contentView else { return }
        view.removeFromSuperview()
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
    }
}
