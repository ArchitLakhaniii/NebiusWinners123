// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserTab.swift
//  BrowserSkills
//
//  One WKWebView with the recorder and picker installed. The agent tab is an ordinary tab the
//  executor and page tools drive; it shares the default website data store, so the user's
//  logins apply and cookies never leave the browser profile.
//

import AppKit
import WebKit

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let isAgent: Bool
    let webView: WKWebView
    @Published var title = "New Tab"
    @Published var url: URL?
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false

    var onRecorded: ((RecordedAction) -> Void)?
    var onPicked: (([String: Any]) -> Void)?
    var onNavigated: ((URL) -> Void)?

    private(set) var navigationCount = 0
    /// True when the most recent navigation ended in an error instead of a loaded page.
    private(set) var lastLoadFailed = false
    private var loadWaiters: [(id: Int, since: Int, cont: CheckedContinuation<Bool, Never>)] = []
    private var nextWaiterID = 0
    private var titleObservation: NSKeyValueObservation?

    init(isAgent: Bool = false) {
        self.isAgent = isAgent
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let controller = WKUserContentController()
        Scripts.userScripts().forEach(controller.addUserScript)
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        super.init()
        let proxy = WeakMessageProxy(self)
        controller.add(proxy, contentWorld: Scripts.world, name: Scripts.recorderHandler)
        controller.add(proxy, contentWorld: Scripts.world, name: Scripts.pickerHandler)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        titleObservation = webView.observe(\.title) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.syncState() }
        }
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    /// Typed into the address bar: a URL, a host, or a search.
    func load(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme) { load(url); return }
        if trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1"), let url = URL(string: "http://" + trimmed) { load(url); return }
        if trimmed.contains("."), !trimmed.contains(" "), let url = URL(string: "https://" + trimmed) { load(url); return }
        var comps = URLComponents(string: "https://duckduckgo.com/")!
        comps.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        load(comps.url!)
    }

    /// Waits for a navigation after `since` (a `navigationCount` value) to finish.
    func waitForLoad(since: Int, timeout: Double = 15) async -> Bool {
        if navigationCount > since && !webView.isLoading { return loaded(since: since) }
        nextWaiterID += 1
        let id = nextWaiterID
        return await withCheckedContinuation { cont in
            loadWaiters.append((id, since, cont))
            // Each waiter has its own timer, so an earlier call's expiry cannot cut a later wait short.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.resolveWaiters(timedOutID: id)
            }
        }
    }

    private func loaded(since: Int) -> Bool { navigationCount > since && !webView.isLoading && !lastLoadFailed }

    private func resolveWaiters(timedOutID: Int? = nil) {
        var keep: [(id: Int, since: Int, cont: CheckedContinuation<Bool, Never>)] = []
        for w in loadWaiters {
            if w.id == timedOutID { w.cont.resume(returning: loaded(since: w.since)) }
            else if navigationCount > w.since { w.cont.resume(returning: !lastLoadFailed) }
            else { keep.append(w) }
        }
        loadWaiters = keep
    }

    /// Runs `body` as an async function in the isolated world with `args` as named parameters.
    func call(_ body: String, _ args: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: Scripts.world)
    }

    func startPicker() { Task { _ = try? await call("window.__bsPicker && window.__bsPicker.start(); return true") } }
    func stopPicker() { Task { _ = try? await call("window.__bsPicker && window.__bsPicker.stop(); return true") } }

    func snapshotPNG() async -> Data? {
        guard let image = try? await webView.takeSnapshot(configuration: nil),
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch message.name {
        case Scripts.recorderHandler:
            guard let type = body["type"] as? String else { return }
            let action = RecordedAction(
                type: type, url: body["url"] as? String ?? url?.absoluteString ?? "",
                selector: body["selector"] as? String, fallbacks: body["fallbacks"] as? [String] ?? [],
                label: (body["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }, tag: body["tag"] as? String,
                inputType: body["inputType"] as? String, value: body["value"] as? String,
                secret: body["secret"] as? Bool ?? false, key: body["key"] as? String)
            onRecorded?(action)
        case Scripts.pickerHandler:
            onPicked?(body)
        default: break
        }
    }

    private func syncState() {
        url = webView.url
        title = webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? url?.host ?? "New Tab"
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    private func finished(failed: Bool) {
        lastLoadFailed = failed
        navigationCount += 1
        syncState()
        resolveWaiters()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { syncState() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { syncState() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished(failed: false)
        if let u = webView.url { onNavigated?(u) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finished(failed: true) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // A cancelled provisional load (another navigation superseded it) is not a failure of the page.
        finished(failed: (error as NSError).code != NSURLErrorCancelled)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let scheme = navigationAction.request.url?.scheme?.lowercased() else { return .cancel }
        return ["http", "https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel
    }

    // MARK: WKUIDelegate

    /// Popups open in this tab, so an agent run never spawns windows.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
        return nil
    }

    /// The agent tab dismisses dialogs itself; a person's tab shows them.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        guard !isAgent else { return }
        let alert = NSAlert(); alert.messageText = message; alert.runModal()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        guard !isAgent else { return false }
        let alert = NSAlert(); alert.messageText = message; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// WKUserContentController retains its handlers; this keeps it from retaining the tab.
private final class WeakMessageProxy: NSObject, WKScriptMessageHandler {
    weak var tab: BrowserTab?
    init(_ tab: BrowserTab) { self.tab = tab }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { tab?.receive(message) }
    }
}
