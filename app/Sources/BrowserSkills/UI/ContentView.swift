// Licensed under GPL-3.0. See LICENSE.

import AppKit
import SwiftUI
import WebKit

/// One window material. The sidebar, the optional panel and the repeat strip sit directly on it;
/// the page is an opaque card on top, like paper on a desk.
struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar().frame(width: Theme.sidebarWidth)
            VStack(spacing: 0) {
                RepeatStrip(recorder: model.recorder)
                if let tab = model.selected {
                    WebViewHost(tab: tab)
                        .background(Theme.page)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.pageRadius))
                        .shadow(color: .black.opacity(0.30), radius: 3, y: 1)
                        .padding(.bottom, Theme.inset).padding(.trailing, Theme.inset)
                        .padding(.top, model.recorder.suggestion == nil ? Theme.inset : 0)
                }
            }
            if model.panelVisible {
                SidePanel()
                    .frame(width: Theme.panelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .background(Material(material: .sidebar, blending: .behindWindow).ignoresSafeArea())
        .animation(Theme.panelMotion, value: model.panelVisible)
    }
}

// MARK: Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let tab = model.selected {
                NavRow(tab: tab)
                AddressPill(tab: tab)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Caption("Today")
                        Spacer()
                        if model.tabs.count > 1 {
                            Button("Clear") { model.closeOthers() }.buttonStyle(.plain)
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10).frame(height: 24).padding(.top, 4)
                    ForEach(model.tabs) { tab in TabRow(tab: tab) }
                    Hairline().padding(.horizontal, 10).padding(.vertical, 8)
                    AgentRow(tab: model.agentTab, executor: model.executor)
                }
            }
            Spacer(minLength: 0)
            TeachRow(recorder: model.recorder)
            Button { model.newTab(url: model.homeURL) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 16)
                    Text("New tab").font(.system(size: 13))
                    Spacer()
                    Shortcut("⌘T")
                }
                .row()
            }
            .buttonStyle(.plain)
            Hairline().padding(.horizontal, 10)
            MCPStatus(mcp: model.mcp, store: model.store)
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
    }
}

struct NavRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tab: BrowserTab
    var body: some View {
        HStack(spacing: 14) {
            Button { tab.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!tab.canGoBack)
            Button { tab.webView.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!tab.canGoForward)
            Spacer()
            Button { model.panelVisible.toggle() } label: { Image(systemName: "sidebar.right") }.help("Show panel (⌥⌘P)")
        }
        .iconButton().foregroundStyle(.secondary)
        .padding(.leading, 86).padding(.trailing, 8).frame(height: 28).padding(.top, 10)
    }
}

/// Host in medium, path in tertiary, reload at the trailing edge. Click to edit the full URL.
struct AddressPill: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tab: BrowserTab
    @State private var text = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if editing {
                TextField("Enter address", text: $text)
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
                    .focused($focused)
                    .onSubmit { model.go(text); stop() }
                    .onExitCommand { stop() }
            } else {
                Text(host).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(path).font(.system(size: 13)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if tab.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Button { tab.webView.reload() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)) }
                        .buttonStyle(.borderless).foregroundStyle(.tertiary)
                }
            }
        }
        .modifier(FieldChrome(radius: Theme.pillRadius, height: 32))
        .contentShape(RoundedRectangle(cornerRadius: Theme.pillRadius))
        .onTapGesture { if !editing, !tab.isAgent { text = tab.url?.absoluteString ?? ""; editing = true; focused = true } }
        .onChange(of: focused) { _, f in if !f { editing = false } }
        .onChange(of: tab.id) { _, _ in stop() }
    }

    private var host: String {
        guard let url = tab.url else { return tab.isAgent ? "Agent tab" : "New tab" }
        return url.host.map { $0 + (url.port.map { ":\($0)" } ?? "") } ?? url.absoluteString
    }
    private var path: String {
        guard let url = tab.url, url.host != nil, url.path != "/" || url.query != nil else { return "" }
        return url.path + (url.query.map { "?" + $0 } ?? "")
    }
    private func stop() { editing = false; focused = false }
}

struct TabRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tab: BrowserTab
    @State private var hover = false
    var body: some View {
        let selected = model.selectedID == tab.id || (model.selectedID == nil && model.tabs.first?.id == tab.id)
        HStack(spacing: 9) {
            Image(systemName: "globe").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 4).fill(Theme.control))
            Text(tab.title).font(.system(size: 13)).lineLimit(1)
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Spacer(minLength: 4)
            if tab.isLoading {
                ProgressView().controlSize(.mini)
            } else if hover || selected {
                Button { model.close(tab) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)) }
                    .buttonStyle(.borderless).foregroundStyle(.tertiary)
            }
        }
        .row(active: selected)
        .onHover { hover = $0 }
        .onTapGesture { model.selectedID = tab.id }
    }
}

/// The hidden tab skills run in. Its state is a word at the trailing edge, accent only while it works.
struct AgentRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tab: BrowserTab
    @ObservedObject var executor: Executor
    var body: some View {
        let selected = model.selectedID == tab.id
        let busy = executor.current != nil
        HStack(spacing: 9) {
            Image(systemName: "sparkles").font(.system(size: 10, weight: .medium)).foregroundStyle(busy ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 4).fill(Theme.control))
            Text("Agent tab").font(.system(size: 13)).foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            Spacer(minLength: 4)
            Text(busy ? "replaying" : "idle").font(.system(size: 11)).foregroundStyle(busy ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
        }
        .row(active: selected)
        .onTapGesture { model.selectedID = tab.id }
        .help("Skills replay here with your normal logins")
    }
}

struct TeachRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var recorder: Recorder
    var body: some View {
        Button {
            if recorder.teaching { model.show(.teach) } else { model.startTeaching() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: recorder.teaching ? "record.circle.fill" : "record.circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(recorder.teaching ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary)).frame(width: 16)
                Text(recorder.teaching ? "Recording, \(recorder.actions.count) step\(recorder.actions.count == 1 ? "" : "s")" : "Teach a skill").font(.system(size: 13))
                Spacer()
                if recorder.teaching {
                    Button("Stop") { model.show(.teach) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Shortcut("⇧⌘R")
                }
            }
            .row(active: recorder.teaching)
        }
        .buttonStyle(.plain)
        .help(recorder.teaching ? "Open the recording" : "Record a procedure once to save it as a skill")
    }
}

/// Two lines of text, no indicator shape.
struct MCPStatus: View {
    @ObservedObject var mcp: MCPServer
    @ObservedObject var store: SkillStore
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(mcp.running ? "MCP serving \(store.skills.count) skill\(store.skills.count == 1 ? "" : "s")" : "MCP off")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text("\(mcp.callCount) call\(mcp.callCount == 1 ? "" : "s") today · \(mcp.endpoint.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "/mcp", with: ""))")
                .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.top, 6)
        .help(mcp.lastError ?? mcp.endpoint)
    }
}

// MARK: Repeat suggestion

/// A 36pt strip above the page, not a floating toast: it is part of the desk, so it never covers content.
struct RepeatStrip: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var recorder: Recorder
    var body: some View {
        if let s = recorder.suggestion {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                Text("You did this \(s.times == 2 ? "twice" : "\(s.times) times") on \(s.host)").font(.system(size: 13, weight: .medium))
                Text(describe(s.actions)).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 16)
                Button("Not now") { recorder.dismissSuggestion() }.buttonStyle(PlainActionStyle())
                Button("Save as skill") { model.adoptSuggestion() }.buttonStyle(AccentButtonStyle())
            }
            .padding(.leading, 8).padding(.trailing, Theme.inset)
            .frame(height: 48)
            .transition(.opacity)
        }
    }

    private func describe(_ actions: [RecordedAction]) -> String {
        let fields = actions.filter { $0.type == "fill" || $0.type == "select" }.compactMap(\.label)
        if fields.isEmpty { return "Same steps, different values" }
        return "Same fields, different \(fields.first!.lowercased())\(fields.first!.lowercased().hasSuffix("s") ? "" : "s")"
    }
}

/// Hosts a tab's WKWebView. The agent web view goes back to its parking window when hidden.
struct WebViewHost: NSViewRepresentable {
    let tab: BrowserTab

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        attach(tab.webView, to: container)
        context.coordinator.tab = tab
        DispatchQueue.main.async { container.window?.makeFirstResponder(tab.webView) }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard context.coordinator.tab !== tab else { return }
        if let old = context.coordinator.tab, old.isAgent { ParkingWindow.shared.park(old.webView) } else { container.subviews.forEach { $0.removeFromSuperview() } }
        attach(tab.webView, to: container)
        context.coordinator.tab = tab
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        if let t = coordinator.tab, t.isAgent { ParkingWindow.shared.park(t.webView) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var tab: BrowserTab? }

    private func attach(_ webView: WKWebView, to container: NSView) {
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
