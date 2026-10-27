// Licensed under GPL-3.0. See LICENSE.

import XCTest
@testable import BrowserSkills

final class WorkflowTests: XCTestCase {
    private func recording() -> Demonstration {
        let fill = RecordedAction(type: "fill", url: "http://127.0.0.1:4318/orders", selector: "#order", fallbacks: ["input[name=\"order\"]"],
                                  label: "Order number", tag: "input", inputType: "text", value: "A-1042")
        let click = RecordedAction(type: "click", url: "http://127.0.0.1:4318/orders", selector: "form > button", label: "Look up", tag: "button")
        return Demonstration(startURL: "http://127.0.0.1:4318/orders", actions: [fill, click],
                             outputs: [PickedOutput(name: "status", selector: "#order-status", sample: "Shipped", many: false)], hint: "")
    }

    func testFixtureCompilesValidParameterizedWorkflow() throws {
        let result = try Compiler.fixture(recording())
        let w = result.workflow
        XCTAssertEqual(result.compiler, "fixture")
        XCTAssertEqual(w.origin, "http://127.0.0.1:4318")
        XCTAssertEqual(w.inputs.map(\.name), ["order_number"])
        XCTAssertEqual(w.inputs.first?.example, "A-1042")
        XCTAssertEqual(w.steps.map(\.kind), [.navigate, .fill, .click])
        XCTAssertEqual(w.steps[1].value, "{{order_number}}")
        XCTAssertTrue(w.problems(knownSelectors: recording().knownSelectors, recordedOrigin: w.origin).isEmpty)
    }

    func testFixtureTemplatesValueInStartURL() throws {
        var demo = recording()
        demo.startURL = "http://127.0.0.1:4318/orders?order=A-1042"
        let w = try Compiler.fixture(demo).workflow
        XCTAssertEqual(w.steps[0].url, "http://127.0.0.1:4318/orders?order={{order_number}}")
    }

    func testValidationRejectsUnobservedSelectorsAndOffOriginNavigation() throws {
        var w = try Compiler.fixture(recording()).workflow
        w.steps.append(WorkflowStep(kind: .click, target: ElementTarget(selector: "#delete-account")))
        w.steps.append(WorkflowStep(kind: .navigate, url: "https://evil.example/steal"))
        let problems = w.problems(knownSelectors: recording().knownSelectors, recordedOrigin: w.origin)
        XCTAssertTrue(problems.contains { $0.contains("not observed") })
        XCTAssertTrue(problems.contains { $0.contains("off the workflow origin") })
    }

    func testValidationRejectsUnknownTemplateRefs() throws {
        var w = try Compiler.fixture(recording()).workflow
        w.steps[1].value = "{{nope}}"
        XCTAssertTrue(w.problems().contains { $0.contains("unknown input {{nope}}") })
    }

    func testSecretValuesNeverBecomeInputs() throws {
        var demo = recording()
        demo.actions.insert(RecordedAction(type: "fill", url: demo.startURL, selector: "#pw", label: "Password", inputType: "password", value: nil, secret: true), at: 0)
        let w = try Compiler.fixture(demo).workflow
        XCTAssertFalse(w.inputs.contains { $0.name == "password" })
        XCTAssertFalse(w.steps.contains { $0.target?.selector == "#pw" })
    }

    func testShapeIgnoresValues() {
        let a = RecordedAction(type: "fill", url: "http://x.test/a", selector: "#q", value: "one")
        let b = RecordedAction(type: "fill", url: "http://x.test/a", selector: "#q", value: "two")
        XCTAssertEqual(a.shape, b.shape)
    }

    func testCollapseKeepsLastValue() {
        let a = RecordedAction(type: "fill", url: "u", selector: "#q", value: "o")
        let b = RecordedAction(type: "fill", url: "u", selector: "#q", value: "order")
        XCTAssertEqual(Recorder.collapse([a, b]).map(\.value), ["order"])
    }

    func testLenientDecodeAndNormalizePinPickedSelectors() throws {
        let obj: [String: Any] = [
            "name": "order_status", "origin": "https://wrong.example",
            "inputs": [["name": "order_number", "example": "A-1042"]],
            "steps": [["kind": "navigate", "url": "http://127.0.0.1:4318/orders"],
                      ["kind": "fill", "target": ["selector": "#order"], "value": "{{order_number}}"],
                      ["kind": "click", "target": ["selector": "form > button"]]],
            "outputs": [["name": "status", "selector": "body"]],
        ]
        let w = Compiler.normalize(try Compiler.decodeLenient(obj), demo: recording())
        XCTAssertEqual(w.origin, "http://127.0.0.1:4318")
        XCTAssertEqual(w.outputs.first?.selector, "#order-status")
        XCTAssertEqual(w.verify.first?.kind, .nonEmpty)
        XCTAssertTrue(w.problems(knownSelectors: recording().knownSelectors).isEmpty)
    }
}

final class ProviderTests: XCTestCase {
    func testFirstJSONObjectSkipsProseAndFences() {
        let text = "Sure! ```json\n{\"name\": \"a_b\", \"x\": {\"y\": \"}\"}}\n``` done"
        XCTAssertEqual(OpenAICompatibleProvider.firstJSONObject(in: text)?["name"] as? String, "a_b")
    }

    func testStripReasoning() {
        XCTAssertEqual(OpenAICompatibleProvider.stripReasoning("<think>hmm</think>\n{\"a\":1}"), "{\"a\":1}")
        XCTAssertEqual(OpenAICompatibleProvider.stripReasoning("plan...</think>answer"), "answer")
    }

    func testParsesToolCalls() throws {
        let json = #"{"choices":[{"finish_reason":"tool_calls","message":{"content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"skills_list","arguments":"{}"}}]}}]}"#
        let r = try OpenAICompatibleProvider.parse(Data(json.utf8))
        XCTAssertEqual(r.finishReason, .toolCalls)
        XCTAssertEqual(r.toolCalls.first?.name, "skills_list")
    }
}

final class HTTPRequestTests: XCTestCase {
    func testWaitsForFullBody() {
        let head = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 10\r\nAuthorization: Bearer t\r\n\r\n"
        XCTAssertNil(HTTPRequest(Data((head + "12345").utf8)))
        let req = HTTPRequest(Data((head + "1234567890").utf8))
        XCTAssertEqual(req?.method, "POST")
        XCTAssertEqual(req?.headers["authorization"], "Bearer t")
        XCTAssertEqual(req?.body.count, 10)
    }
}
