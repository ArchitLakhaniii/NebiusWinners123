// Licensed under GPL-3.0. See LICENSE.

import AppKit
import SwiftUI
import WebKit

/// Two layers: translucent chrome (sidebar, optional panel) and the page as a floating card.
struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                Sidebar().frame(width: Theme.sidebarWidth)
                if let tab = model.selected {
                    WebViewHost(tab: tab)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline, lineWidth: 1))
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                        .padding(.vertical, Theme.inset).padding(.trailing, Theme.inset)
                }
                if model.panelVisible {
                    SidePanel()
                        .frame(width: Theme.panelWidth)
                        .background(Material(material: .popover, blending: .withinWindow))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline, lineWidth: 1))
                        .padding(.vertical, Theme.inset).padding(.trailing, Theme.inset)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            SuggestionToast(recorder: model.recorder)
                .padding(.bottom, Theme.inset + 10)
                .padding(.leading, Theme.sidebarWidth)
        }
        .background(Material(material: .sidebar, blending: .behindWindow).ignoresSafeArea())
        .animation(Theme.quick, value: model.panelVisible)
    }
}

// MARK: Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button { model.panelVisible.toggle() } label: { Image(systemName: "sidebar.right") }
                    .iconButton().foregroundStyle(.tertiary).help("Show panel (⌥⌘P)")
            }
            .padding(.top, 14).padding(.trailing, 14).padding(.leading, 86)
            if let tab = model.selected {
                NavRow(tab: tab)
                AddressField(tab: tab)
            }
            TeachRow(recorder: model.recorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    Caption("Today").padding(.horizontal, 10).padding(.top, 6)
                    ForEach(model.tabs) { tab in TabRow(tab: tab) }
                    Caption("Agent").padding(.horizontal, 10).padding(.top, 10)
                    TabRow(tab: model.agentTab)
                }
            }
            Spacer(minLength: 0)
            Hairline().padding(.horizontal, 10)
            MCPStatus(mcp: model.mcp)
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
    }
}

struct NavRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tab: BrowserTab
    var body: some View {
        HStack(spacing: 12) {
            Button { tab.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!tab.canGoBack)
            Button { tab.webView.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!tab.canGoForward)
            Button { tab.webView.reload() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)) }
            Spacer()
            Button { model.newTab(url: model.homeURL) } label: { Image(systemName: "plus") }.help("New tab (⌘T)")
        }
        .iconButton().foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}

struct AddressField: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tab: BrowserTab
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tab.url?.scheme == "https" ? "lock.fill" : "globe").font(.system(size: 10)).foregroundStyle(.secondary)
            TextField("Search or enter address", text: $text)
                .textFieldStyle(.plain).font(.system(size: 12.5, weight: .medium))
                .focused($focused)
                .onSubmit { model.go(text); focused = false }
                .disabled(tab.isAgent)
            if tab.isLoading { ProgressView().controlSize(.mini) }
        }
        .modifier(FieldChrome(focused: focused))
        .onAppear { text = display(tab.url) }
        .onChange(of: tab.url) { _, new in if !focused { text = display(new) } }
        .onChange(of: tab.id) { _, _ in text = display(tab.url) }
        .onChange(of: focused) { _, f in text = f ? (tab.url?.absoluteString ?? "") : display(tab.url) }
    }
    private func display(_ url: URL?) -> String {
        guard let url else { return "" }
        let host = url.host ?? ""
        let path = url.path == "/" ? "" : url.path
        return host.isEmpty ? url.absoluteString : host + path
    }
}

struct TeachRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var recorder: Recorder
    var body: some View {
        Button {
            if recorder.teaching { model.show(.teach) } else { model.startTeaching() }
        } label: {
            HStack(spacing: 8) {
                if recorder.teaching {
                    StatusDot(color: Theme.danger, size: 8)
                    Text("Recording").font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Text("\(recorder.actions.count) steps").font(.system(size: 11.5)).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "record.circle").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Teach a skill").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("⇧⌘R").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(recorder.teaching ? Theme.danger.opacity(0.12) : .clear))
        }
        .buttonStyle(.plain)
        .help(recorder.teaching ? "Open the recording" : "Record a procedure to save as a skill")
    }
}

struct TabRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tab: BrowserTab
    @State private var hover = false
    var body: some View {
        let selected = model.selectedID == tab.id || (model.selectedID == nil && model.tabs.first?.id == tab.id)
        HStack(spacing: 9) {
            if tab.isAgent {
                StatusDot(color: Theme.accent)
            } else {
                Image(systemName: "globe").font(.system(size: 12)).foregroundStyle(selected ? .primary : .secondary)
            }
            Text(tab.isAgent ? (tab.url?.host ?? "idle") : tab.title)
                .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                .foregroundStyle(selected || tab.isAgent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            Spacer(minLength: 4)
            if tab.isAgent {
                Text(selected ? "Watching" : "Watch").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.accent)
            } else if tab.isLoading {
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

struct MCPStatus: View {
    @ObservedObject var mcp: MCPServer
    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: mcp.running ? Theme.accent : Theme.danger)
            Text(mcp.running ? "MCP  \(mcp.endpoint.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "/mcp", with: ""))" : "MCP off")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if mcp.callCount > 0 { Text("\(mcp.callCount) calls").font(.system(size: 11.5)).foregroundStyle(.tertiary) }
        }
        .row()
        .help(mcp.lastError ?? mcp.endpoint)
    }
}

// MARK: Repeat suggestion

struct SuggestionToast: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var recorder: Recorder
    var body: some View {
        if let s = recorder.suggestion {
            HStack(spacing: 12) {
                Image(systemName: "repeat").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("You did this \(s.times) times on \(s.host)").font(.system(size: 13, weight: .semibold))
                    Text(s.actions.prefix(3).map(\.summary).joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 10)
                Button("Save as skill") { model.adoptSuggestion() }.buttonStyle(PillButtonStyle(primary: true))
                Button("Not now") { recorder.dismissSuggestion() }.buttonStyle(PlainActionStyle())
            }
            .padding(.leading, 12).padding(.trailing, 14).padding(.vertical, 12)
            .frame(maxWidth: 560)
            .background(Material(material: .popover, blending: .withinWindow))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(Theme.quick, value: s.times)
        }
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
