// Licensed under GPL-3.0. See LICENSE.

import AppKit
import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            TabSidebar()
                .frame(width: 210)
            Divider()
            VStack(spacing: 0) {
                if let tab = model.selected {
                    AddressBar(tab: tab)
                    Divider()
                    SuggestionBanner(recorder: model.recorder)
                    WebViewHost(tab: tab)
                }
            }
            Divider()
            SidePanel()
                .frame(width: 360)
        }
    }
}

struct TabSidebar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("BrowserSkills").font(.headline)
                Spacer()
                Button { model.newTab(url: model.homeURL) } label: { Image(systemName: "plus") }.buttonStyle(.borderless).help("New tab (⌘T)")
            }
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.tabs) { tab in TabRow(tab: tab) }
                    Divider().padding(.vertical, 6)
                    TabRow(tab: model.agentTab)
                }
                .padding(.horizontal, 6)
            }
            Spacer()
            MCPStatus(mcp: model.mcp).padding(10)
        }
        .background(.regularMaterial)
    }
}

struct TabRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tab: BrowserTab
    var body: some View {
        let selected = model.selectedID == tab.id || (model.selectedID == nil && model.tabs.first?.id == tab.id)
        HStack(spacing: 6) {
            Image(systemName: tab.isAgent ? "sparkles" : "globe").foregroundStyle(tab.isAgent ? Color.green : Color.secondary)
            Text(tab.isAgent ? "Agent tab" + (tab.url.map { " · \($0.host ?? "")" } ?? "") : tab.title).lineLimit(1)
            Spacer()
            if tab.isLoading { ProgressView().controlSize(.mini) }
            if !tab.isAgent {
                Button { model.close(tab) } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.18) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = tab.id }
    }
}

struct MCPStatus: View {
    @ObservedObject var mcp: MCPServer
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(mcp.running ? Color.green : Color.red).frame(width: 7, height: 7)
                Text(mcp.running ? "MCP live" : "MCP off").font(.caption.bold())
                if mcp.callCount > 0 { Text("· \(mcp.callCount) calls").font(.caption).foregroundStyle(.secondary) }
            }
            Text(mcp.lastError ?? mcp.endpoint).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

struct AddressBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tab: BrowserTab
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Button { tab.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!tab.canGoBack)
            Button { tab.webView.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!tab.canGoForward)
            Button { tab.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
            TextField("Search or enter address", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.go(text) }
                .disabled(tab.isAgent)
            TeachButton(recorder: model.recorder)
        }
        .buttonStyle(.borderless)
        .padding(8)
        .onAppear { text = tab.url?.absoluteString ?? "" }
        .onChange(of: tab.url) { _, new in text = new?.absoluteString ?? "" }
        .onChange(of: tab.id) { _, _ in text = tab.url?.absoluteString ?? "" }
    }
}

struct TeachButton: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var recorder: Recorder
    var body: some View {
        if recorder.teaching {
            Button { model.panel = .teach } label: {
                Label("Recording \(recorder.actions.count)", systemImage: "record.circle.fill").foregroundStyle(.red)
            }
        } else {
            Button { model.startTeaching() } label: { Label("Teach", systemImage: "record.circle") }
                .help("Record a procedure to save as a skill (⇧⌘R)")
        }
    }
}

struct SuggestionBanner: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var recorder: Recorder
    var body: some View {
        if let s = recorder.suggestion {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("You've done this \(s.times)× on \(s.host)").font(.callout.bold())
                    Text(s.actions.prefix(4).map(\.summary).joined(separator: " → ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Save as skill") { model.adoptSuggestion() }.buttonStyle(.borderedProminent).tint(.green)
                Button("Not now") { recorder.dismissSuggestion() }
            }
            .padding(10)
            .background(Color.green.opacity(0.12))
        }
    }
}

/// Hosts a tab's WKWebView. The agent web view goes back to its parking window when hidden.
struct WebViewHost: NSViewRepresentable {
    let tab: BrowserTab

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(tab.webView, to: container)
        context.coordinator.tab = tab
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
