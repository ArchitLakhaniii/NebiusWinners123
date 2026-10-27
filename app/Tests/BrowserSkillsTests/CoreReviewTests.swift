// Licensed under GPL-3.0. See LICENSE.
//
//  Regression tests for the core-logic review: templating, validator gaps, recorder episodes,
//  store robustness, page scripts and executor serialization.
//

import SQLite3
import WebKit
import Network
import XCTest
@testable import BrowserSkills

private func demo() -> Demonstration {
    let fill = RecordedAction(type: "fill", url: "http://127.0.0.1:4318/orders", selector: "#order", fallbacks: ["input[name=\"order\"]"],
                              label: "Order number", tag: "input", inputType: "text", value: "A-1042")
    let click = RecordedAction(type: "click", url: "http://127.0.0.1:4318/orders", selector: "form > button", label: "Look up", tag: "button")
    return Demonstration(startURL: "http://127.0.0.1:4318/orders", actions: [fill, click],
                         outputs: [PickedOutput(name: "status", selector: "#order-status", sample: "Shipped", many: false)], hint: "")
}

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bs-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class TemplateTests: XCTestCase {
    func testFillTemplateAcceptsTheSameWhitespaceAsTemplateRefs() {
        let values = ["order_number": "B-77"]
        XCTAssertEqual(Workflow.templateRefs("x {{order_number }} y"), ["order_number"])
        XCTAssertEqual(Workflow.fillTemplate("x {{order_number }} y", with: values), "x B-77 y")
        XCTAssertEqual(Workflow.fillTemplate("{{  order_number}}", with: values), "B-77")
        XCTAssertEqual(Workflow.fillTemplate("{{ order_number }}/{{order_number}}", with: values), "B-77/B-77")
        XCTAssertEqual(Workflow.fillTemplate("{{unknown}}", with: values), "{{unknown}}")
    }

    func testFillTemplateIsSinglePass() {
        let out = Workflow.fillTemplate("{{a}}-{{b}}", with: ["a": "{{b}}", "b": "secret"])
        XCTAssertEqual(out, "{{b}}-secret")
    }

    func testURLEncodingEscapesQueryDelimiters() {
        let out = Workflow.fillTemplate("http://h/x?q={{q}}", with: ["q": "a&admin=1 b+c/d#e"], urlEncode: true)
        XCTAssertEqual(out, "http://h/x?q=a%26admin%3D1%20b%2Bc%2Fd%23e")
    }

    func testOriginIsCaseInsensitive() {
        XCTAssertEqual(Workflow.origin(of: URL(string: "HTTPS://Example.COM:443/x")!), "https://example.com")
        XCTAssertEqual(Workflow.authority(of: "https://{{host}}/x?y"), "{{host}}")
        XCTAssertEqual(Workflow.authority(of: "http://127.0.0.1:4318/orders?order={{order_number}}"), "127.0.0.1:4318")
    }
}

final class ValidatorTests: XCTestCase {
    private func valid() throws -> Workflow { try Compiler.fixture(demo()).workflow }

    func testRejectsUnobservedFallbackSelectors() throws {
        var w = try valid()
        w.steps[2].target?.fallbacks = ["#delete-account"]
        let problems = w.problems(knownSelectors: demo().knownSelectors, recordedOrigin: w.origin)
        XCTAssertTrue(problems.contains { $0.contains("not observed") && $0.contains("#delete-account") }, "\(problems)")
    }

    func testRejectsOutputSelectorsNeverPickedOrObserved() throws {
        var w = try valid()
        XCTAssertTrue(w.problems(knownSelectors: demo().knownSelectors, recordedOrigin: w.origin).isEmpty)
        w.outputs.append(WorkflowOutput(name: "leak", description: "", selector: "input[type=password]"))
        w.verify.append(VerifyCheck(kind: .nonEmpty, output: "leak", input: nil))
        let problems = w.problems(knownSelectors: demo().knownSelectors, recordedOrigin: w.origin)
        XCTAssertTrue(problems.contains { $0.contains("output leak") }, "\(problems)")
    }

    func testRejectsTemplateInHostEvenWhenExampleStaysOnOrigin() throws {
        var w = try valid()
        w.inputs.append(WorkflowInput(name: "host", description: "", example: "127.0.0.1:4318"))
        w.steps[0].url = "http://{{host}}/orders"
        let problems = w.problems(knownSelectors: demo().knownSelectors, recordedOrigin: w.origin)
        XCTAssertTrue(problems.contains { $0.contains("scheme or host") }, "\(problems)")
    }

    func testRejectsUnboundedTimeouts() throws {
        var w = try valid()
        w.steps[1].timeoutMs = 10_000_000
        XCTAssertTrue(w.problems().contains { $0.contains("timeoutMs") })
        w.steps[1].timeoutMs = 20_000
        XCTAssertFalse(w.problems().contains { $0.contains("timeoutMs") })
    }

    func testDuplicateInputNamesAreReportedNotFatal() throws {
        var w = try valid()
        w.inputs.append(w.inputs[0])
        XCTAssertTrue(w.problems().contains("duplicate input names"))
    }

    func testNavigateExampleWithSpacesStillValidates() throws {
        var w = try valid()
        w.inputs[0].example = "A 1042"
        w.steps[0].url = "http://127.0.0.1:4318/orders?order={{order_number}}"
        let problems = w.problems(knownSelectors: demo().knownSelectors, recordedOrigin: w.origin)
        XCTAssertTrue(problems.isEmpty, "\(problems)")
    }
}

final class CompilerNormalizeTests: XCTestCase {
    func testNormalizeRestoresPickedOutputsTheModelDropped() throws {
        let obj: [String: Any] = [
            "name": "order_status", "origin": "http://127.0.0.1:4318",
            "inputs": [["name": "order_number", "example": "A-1042"]],
            "steps": [["kind": "navigate", "url": "http://127.0.0.1:4318/orders"],
                      ["kind": "fill", "target": ["selector": "#order"], "value": "{{order_number}}"],
                      ["kind": "click", "target": ["selector": "form > button"]]],
            "outputs": [["name": "state", "selector": "#order-status"]],
        ]
        let w = Compiler.normalize(try Compiler.decodeLenient(obj), demo: demo())
        XCTAssertEqual(w.outputs.map(\.name), ["state", "status"])
        XCTAssertEqual(w.outputs.last?.selector, "#order-status")
        XCTAssertTrue(w.verify.contains { $0.output == "status" && $0.kind == .nonEmpty })
        XCTAssertTrue(w.problems(knownSelectors: demo().knownSelectors, recordedOrigin: "http://127.0.0.1:4318").isEmpty)
    }

    func testKnownSelectorsIncludePickedOutputs() {
        XCTAssertTrue(demo().knownSelectors.contains("#order-status"))
    }
}

final class RecorderEpisodeTests: XCTestCase {
    @MainActor
    func testRepeatIsDetectedAfterIdleCloseOnTheSamePage() {
        let store = SkillStore(directory: tempDirectory())
        let recorder = Recorder(store: store)
        recorder.idleSeconds = 3600
        let fill = RecordedAction(type: "fill", url: "http://127.0.0.1:4318/orders", selector: "#order", value: "A-1042")
        let click = RecordedAction(type: "click", url: "http://127.0.0.1:4318/orders", selector: "form > button")

        recorder.observe(fill); recorder.observe(click)
        recorder.closeEpisode()
        XCTAssertNil(recorder.suggestion)

        // Same site, same page, no navigation in between: the second pass used to lose its start URL and was never stored.
        recorder.observe(RecordedAction(type: "fill", url: fill.url, selector: "#order", value: "B-77")); recorder.observe(click)
        recorder.closeEpisode()
        XCTAssertEqual(recorder.suggestion?.times, 2)
        XCTAssertEqual(recorder.suggestion?.startURL, "http://127.0.0.1:4318/orders")
    }
}

final class SkillStoreTests: XCTestCase {
    @MainActor
    func testUndecodableStoredVersionIsSkippedNotFatal() throws {
        let dir = tempDirectory()
        let store = SkillStore(directory: dir)
        let w = try Compiler.fixture(demo()).workflow
        let v1 = try store.addCandidate(w, compiler: "fixture")
        XCTAssertEqual(v1.version, 1)

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dir.appendingPathComponent("browserskills.sqlite").path, &db), SQLITE_OK)
        let sql = "INSERT INTO versions (skill_id, version, workflow, status, compiler, created) VALUES (\(v1.skillID), 2, '{\"name\": 1}', 'candidate', 'x', 0)"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close_v2(db)

        XCTAssertEqual(store.versions(skillID: v1.skillID).map(\.version), [1])
        let v3 = try store.addCandidate(w, compiler: "fixture")
        XCTAssertEqual(v3.version, 3)
    }

    @MainActor
    func testConflictingOriginLeavesStoreUnchanged() throws {
        let store = SkillStore(directory: tempDirectory())
        var w = try Compiler.fixture(demo()).workflow
        _ = try store.addCandidate(w, compiler: "fixture")
        w.origin = "https://other.example"
        XCTAssertThrowsError(try store.addCandidate(w, compiler: "fixture"))
        XCTAssertEqual(store.skills.count, 1)
        XCTAssertEqual(store.versions(skillID: store.skills[0].id).count, 1)
    }
}

@MainActor
final class PageScriptTests: XCTestCase {
    private func load(_ html: String) async throws -> BrowserTab {
        let tab = BrowserTab(isAgent: true)
        let before = tab.navigationCount
        tab.webView.loadHTMLString(html, baseURL: URL(string: "http://127.0.0.1:4318/test"))
        let ok = await tab.waitForLoad(since: before, timeout: 10)
        XCTAssertTrue(ok)
        return tab
    }

    private func extract(_ tab: BrowserTab, _ selector: String) async throws -> Any? {
        let r = try await tab.call(Scripts.extract, ["outputs": [["name": "v", "selector": selector, "many": false]], "timeoutMs": 300]) as? [String: Any]
        return (r?["outputs"] as? [String: Any])?["v"]
    }

    func testReadNeverReturnsSecretFieldValues() async throws {
        let tab = try await load("""
        <input id="q" value="A-1042"><input type="password" id="pw" value="hunter2">
        <input id="otp_code" name="otp" value="123456"><div id="out">Shipped</div>
        """)
        let q = try await extract(tab, "#q") as? String
        XCTAssertEqual(q, "A-1042")
        let out = try await extract(tab, "#out") as? String
        XCTAssertEqual(out, "Shipped")
        let pw = try await extract(tab, "#pw")
        XCTAssertTrue(pw == nil || (pw as? String) == "" || pw is NSNull, "password value leaked: \(String(describing: pw))")
        let otp = try await extract(tab, "#otp_code")
        XCTAssertTrue(otp == nil || (otp as? String) == "" || otp is NSNull, "otp value leaked: \(String(describing: otp))")
    }

    func testSelectAcceptsOptionTextOrValue() async throws {
        let tab = try await load("""
        <select id="s"><option value="">Pick</option><option value="us">United States</option><option value="ca">Canada</option></select>
        """)
        let step: [String: Any] = ["kind": "select", "target": ["selector": "#s", "fallbacks": []]]
        var r = try await tab.call(Scripts.runStep, ["step": step, "value": "Canada"]) as? [String: Any]
        XCTAssertEqual(r?["ok"] as? Bool, true)
        var selected = try await tab.call("return document.getElementById('s').value") as? String
        XCTAssertEqual(selected, "ca")
        r = try await tab.call(Scripts.runStep, ["step": step, "value": "us"]) as? [String: Any]
        XCTAssertEqual(r?["ok"] as? Bool, true)
        selected = try await tab.call("return document.getElementById('s').value") as? String
        XCTAssertEqual(selected, "us")
        r = try await tab.call(Scripts.runStep, ["step": step, "value": "Mars"]) as? [String: Any]
        XCTAssertEqual(r?["ok"] as? Bool, false)
        XCTAssertEqual(r?["error"] as? String, "cannot_fill")
    }

    func testSubmitOnElementOutsideAFormReportsInsteadOfThrowing() async throws {
        let tab = try await load("<button id='b'>Go</button>")
        _ = try await tab.call("document.getElementById('b').dataset.bsRef = 'e1'; return true")
        let r = try await tab.call(Scripts.actOnRef, ["ref": "e1", "op": "submit", "value": ""]) as? [String: Any]
        XCTAssertEqual(r?["ok"] as? Bool, false)
        XCTAssertEqual(r?["error"] as? String, "not_a_form")
    }

    func testFillWritesContentEditable() async throws {
        let tab = try await load("<div id='ed' contenteditable='true'></div>")
        _ = try await tab.call("document.getElementById('ed').dataset.bsRef = 'e1'; return true")
        let r = try await tab.call(Scripts.actOnRef, ["ref": "e1", "op": "fill", "value": "hello"]) as? [String: Any]
        XCTAssertEqual(r?["ok"] as? Bool, true)
        let text = try await tab.call("return document.getElementById('ed').textContent") as? String
        XCTAssertEqual(text, "hello")
    }
}

@MainActor
final class BrowserTabLoadTests: XCTestCase {
    func testFailedNavigationIsNotReportedAsLoaded() async {
        let tab = BrowserTab(isAgent: true)
        let before = tab.navigationCount
        tab.load(URL(string: "http://nonexistent.invalid/unreachable")!)
        let ok = await tab.waitForLoad(since: before, timeout: 10)
        XCTAssertFalse(ok)
        XCTAssertTrue(tab.lastLoadFailed)
    }

    func testEarlierTimeoutDoesNotResolveALaterWait() async {
        let tab = BrowserTab(isAgent: true)
        let idle = await tab.waitForLoad(since: tab.navigationCount, timeout: 0.05)
        XCTAssertFalse(idle)
        let before = tab.navigationCount
        tab.webView.loadHTMLString("<p>ok</p>", baseURL: URL(string: "http://127.0.0.1:4318/"))
        let loaded = await tab.waitForLoad(since: before, timeout: 10)
        XCTAssertTrue(loaded)
    }
}

@MainActor
final class ExecutorDedupeTests: XCTestCase {
    func testConcurrentIdenticalCallsShareOneRun() async throws {
        let store = SkillStore(directory: tempDirectory())
        var w = try Compiler.fixture(demo()).workflow
        w.origin = "http://nonexistent.invalid"
        w.steps = [WorkflowStep(kind: .navigate, url: "http://nonexistent.invalid/orders", timeoutMs: 5000)]
        let version = try store.addCandidate(w, compiler: "fixture")
        store.setStatus(.validated, skillID: version.skillID, version: version.version)
        let skill = store.skills[0]
        let executor = Executor(store: store, tab: BrowserTab(isAgent: true))

        async let a = executor.run(skill: skill, inputs: ["order_number": "A-1042"])
        async let b = executor.run(skill: skill, inputs: ["order_number": "A-1042"])
        let (ra, rb) = await (a, b)
        XCTAssertEqual(ra.id, rb.id)
        XCTAssertTrue(ra.status.isTerminal)
        XCTAssertEqual(store.runs(skillID: skill.id).count, 1)
    }
}

/// One-shot HTTP server: `/orders` redirects to the same path on `localhost` (a different origin), everything else is 200.
@MainActor
final class RedirectingServer {
    let listener: NWListener
    var port: UInt16 { listener.port?.rawValue ?? 0 }
    private var connections: [NWConnection] = []

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] c in Task { @MainActor in self?.accept(c) } }
        listener.start(queue: .main)
    }

    private func accept(_ c: NWConnection) {
        connections.append(c)
        c.start(queue: .main)
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, let head = String(data: data, encoding: .utf8)?.components(separatedBy: "\r\n").first else { return }
            let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let body = "<p id=\"status\">landed</p>"
            let response = path.hasPrefix("/orders")
                ? "HTTP/1.1 302 Found\r\nLocation: http://localhost:\(self.port)/landed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                : "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
            c.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in c.cancel() })
        }
    }

    func waitUntilReady() async {
        for _ in 0..<100 where port == 0 { try? await Task.sleep(for: .milliseconds(20)) }
    }
}

@MainActor
final class ExecutorOriginTests: XCTestCase {
    func testRedirectOffOriginFailsTheRunInsteadOfContinuing() async throws {
        let server = try RedirectingServer()
        await server.waitUntilReady()
        XCTAssertNotEqual(server.port, 0)
        let origin = "http://127.0.0.1:\(server.port)"

        let store = SkillStore(directory: tempDirectory())
        var w = try Compiler.fixture(demo()).workflow
        w.origin = origin
        w.steps = [WorkflowStep(kind: .navigate, url: "\(origin)/orders", timeoutMs: 10_000)]
        w.outputs = [WorkflowOutput(name: "status", description: "", selector: "#status", many: false)]
        w.verify = []
        let version = try store.addCandidate(w, compiler: "fixture")
        store.setStatus(.validated, skillID: version.skillID, version: version.version)
        let executor = Executor(store: store, tab: BrowserTab(isAgent: true))

        let run = await executor.run(skill: store.skills[0], inputs: ["order_number": "A-1042"], dedupe: false)
        XCTAssertEqual(run.status, .failed)
        XCTAssertTrue(run.error?.contains("refused to continue off \(origin)") == true, run.error ?? "")
        XCTAssertTrue(run.outputs.isEmpty)
    }
}
