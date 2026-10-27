// Licensed under GPL-3.0. See LICENSE.
//
//  WorkflowValidationTests.swift
//  BrowserSkillsTests
//
//  Every Workflow.problems rule, the fixture compiler on richer recordings, Recorder.collapse,
//  and the OpenAI-compatible provider's parsing helpers.
//

import Foundation
import XCTest
@testable import BrowserSkills

final class WorkflowProblemsTests: XCTestCase {
    private let origin = "http://127.0.0.1:4318"

    private func valid() -> Workflow {
        Workflow(name: "order_status", title: "Order status", description: "", origin: origin,
                 inputs: [WorkflowInput(name: "order_number", description: "Order number", example: "A-1042")],
                 steps: [WorkflowStep(kind: .navigate, url: "http://127.0.0.1:4318/orders?order={{order_number}}"),
                         WorkflowStep(kind: .fill, target: ElementTarget(selector: "#order"), value: "{{order_number}}"),
                         WorkflowStep(kind: .press, key: "Enter"),
                         WorkflowStep(kind: .click, target: ElementTarget(selector: "form > button"))],
                 outputs: [WorkflowOutput(name: "status", description: "", selector: "#order-status")],
                 verify: [VerifyCheck(kind: .nonEmpty, output: "status", input: nil),
                          VerifyCheck(kind: .containsInput, output: "status", input: "order_number")])
    }

    private let known: Set<String> = ["#order", "form > button"]

    private func problems(_ w: Workflow, known: Set<String>? = nil, recorded: String? = nil) -> [String] {
        w.problems(knownSelectors: known, recordedOrigin: recorded)
    }

    func testValidWorkflowHasNoProblems() {
        XCTAssertEqual(problems(valid(), known: known, recorded: origin), [])
    }

    func testNameFormat() {
        for bad in ["Order", "ab", "1abc", "has-dash", "has space", String(repeating: "a", count: 49), ""] {
            var w = valid(); w.name = bad
            XCTAssertTrue(problems(w).contains { $0.hasPrefix("name must be snake_case") }, bad)
        }
        for good in ["abc", "a_1", String(repeating: "a", count: 48)] {
            var w = valid(); w.name = good
            XCTAssertFalse(problems(w).contains { $0.hasPrefix("name must be snake_case") }, good)
        }
    }

    func testStepCountAndOutputsRequired() {
        var none = valid(); none.steps = []
        XCTAssertTrue(problems(none).contains("workflow has no steps"))
        var many = valid()
        many.steps = Array(repeating: WorkflowStep(kind: .click, target: ElementTarget(selector: "#order")), count: Workflow.maxSteps + 1)
        XCTAssertTrue(problems(many).contains("too many steps (41 > 40)"))
        var exact = valid()
        exact.steps = Array(repeating: WorkflowStep(kind: .click, target: ElementTarget(selector: "#order")), count: Workflow.maxSteps)
        XCTAssertFalse(problems(exact).contains { $0.hasPrefix("too many steps") })
        var noOut = valid(); noOut.outputs = []; noOut.verify = []
        XCTAssertTrue(problems(noOut).contains("workflow has no outputs"))
    }

    func testOriginMustBeHTTPAndStopsFurtherChecks() {
        for bad in ["", "ftp://x.test", "127.0.0.1:4318", "javascript:alert(1)", "http://"] {
            var w = valid(); w.origin = bad
            let p = problems(w)
            XCTAssertTrue(p.contains { $0.hasPrefix("origin must be an http(s) origin") }, bad)
            XCTAssertFalse(p.contains { $0.contains("off the workflow origin") }, "origin rule short-circuits for \(bad)")
        }
    }

    func testOriginMismatchWithRecording() {
        var w = valid(); w.origin = "https://shop.example"
        let p = problems(w, recorded: origin)
        XCTAssertTrue(p.contains("origin https://shop.example differs from the recorded origin http://127.0.0.1:4318"))
        XCTAssertTrue(p.contains { $0.contains("step 1 (navigate): navigates off the workflow origin") })
    }

    func testNavigateRules() {
        var missing = valid(); missing.steps[0].url = nil
        XCTAssertTrue(problems(missing).contains("step 1 (navigate): missing url"))
        var off = valid(); off.steps[0].url = "http://127.0.0.1:9999/orders"
        XCTAssertTrue(problems(off).contains { $0.contains("navigates off the workflow origin to http://127.0.0.1:9999/orders") })
        var unknownRef = valid(); unknownRef.steps[0].url = "http://127.0.0.1:4318/orders?order={{missing}}"
        XCTAssertTrue(problems(unknownRef).contains("step 1 (navigate): references unknown input {{missing}}"))
        var defaultPort = valid(); defaultPort.origin = "https://shop.example"
        defaultPort.steps = [WorkflowStep(kind: .navigate, url: "https://shop.example:443/orders")]
        XCTAssertFalse(problems(defaultPort).contains { $0.contains("off the workflow origin") })
    }

    func testTargetValueAndKeyRules() {
        var noTarget = valid(); noTarget.steps[1].target = nil
        XCTAssertTrue(problems(noTarget).contains("step 2 (fill): missing target"))
        var emptyTarget = valid(); emptyTarget.steps[1].target = ElementTarget(selector: "")
        XCTAssertTrue(problems(emptyTarget).contains("step 2 (fill): missing target"))
        var noValue = valid(); noValue.steps[1].value = nil
        XCTAssertTrue(problems(noValue).contains("step 2 (fill): missing value"))
        var select = valid(); select.steps[1].kind = .select; select.steps[1].value = nil
        XCTAssertTrue(problems(select).contains("step 2 (select): missing value"))
        // A press step with a target and no key is flagged. A press step with neither target nor key is
        // currently accepted because the target guard continues before the key check (reported in the PR, not fixed here).
        var noKey = valid(); noKey.steps[2].key = nil; noKey.steps[2].target = ElementTarget(selector: "#order")
        XCTAssertTrue(problems(noKey).contains("step 3 (press): missing key"))
        XCTAssertFalse(problems(valid()).contains("step 3 (press): missing target"), "press may target the focused field")
        var clickNoTarget = valid(); clickNoTarget.steps[3].target = nil
        XCTAssertTrue(problems(clickNoTarget).contains("step 4 (click): missing target"))
        var waitNoTarget = valid(); waitNoTarget.steps.append(WorkflowStep(kind: .waitFor))
        XCTAssertTrue(problems(waitNoTarget).contains("step 5 (waitFor): missing target"))
    }

    func testUnknownSelectorsOnlyWhenRecordingIsKnown() {
        var w = valid(); w.steps[3].target = ElementTarget(selector: "#delete-account")
        XCTAssertEqual(problems(w), [], "without a recording any selector is allowed")
        XCTAssertTrue(problems(w, known: known).contains("step 4 (click): selector was not observed in the recording: #delete-account"))
        XCTAssertEqual(problems(valid(), known: known), [])
    }

    func testTemplateRefsMustBeInputs() {
        var w = valid(); w.steps[1].value = "{{ order_number }} and {{nope}}"
        let p = problems(w)
        XCTAssertEqual(p, ["step 2 (fill): references unknown input {{nope}}"])
        XCTAssertEqual(Workflow.templateRefs("{{a}} {{ b }} {{c-d}} {{"), ["a", "b"])
        XCTAssertEqual(Workflow.templateRefs(nil), [])
    }

    func testInputNames() {
        // Navigate steps are removed because Workflow.problems builds a uniqueKeysWithValues dictionary
        // from the inputs while checking them, which traps on duplicates (reported in the PR, not fixed here).
        var dup = valid(); dup.inputs.append(dup.inputs[0]); dup.steps.removeFirst()
        XCTAssertTrue(problems(dup).contains("duplicate input names"))
        for bad in ["Order", "1x", "a-b", "", String(repeating: "a", count: 41)] {
            var w = valid(); w.inputs[0].name = bad; w.steps = [WorkflowStep(kind: .click, target: ElementTarget(selector: "#order"))]; w.verify = []
            XCTAssertTrue(problems(w).contains("input name must be snake_case: \(bad)"), bad)
        }
    }

    func testVerifyReferencesMustExist() {
        var out = valid(); out.verify.append(VerifyCheck(kind: .nonEmpty, output: "eta", input: nil))
        XCTAssertTrue(problems(out).contains("verify references unknown output eta"))
        var input = valid(); input.verify.append(VerifyCheck(kind: .containsInput, output: "status", input: "zip"))
        XCTAssertTrue(problems(input).contains("verify containsInput references unknown input zip"))
        var nilInput = valid(); nilInput.verify.append(VerifyCheck(kind: .containsInput, output: "status", input: nil))
        XCTAssertTrue(problems(nilInput).contains("verify containsInput references unknown input nil"))
    }

    func testOriginNormalizationAndTemplates() {
        XCTAssertEqual(Workflow.origin(of: URL(string: "http://h.test:80/x")!), "http://h.test")
        XCTAssertEqual(Workflow.origin(of: URL(string: "https://h.test:443/x")!), "https://h.test")
        XCTAssertEqual(Workflow.origin(of: URL(string: "https://h.test:8443/x")!), "https://h.test:8443")
        XCTAssertEqual(Workflow.origin(of: URL(string: "http://127.0.0.1:4318/orders?order=1")!), "http://127.0.0.1:4318")
        XCTAssertNil(Workflow.origin(of: URL(string: "about:blank")!))
        XCTAssertEqual(Workflow.fillTemplate("q={{a}}&r={{ a }}", with: ["a": "x y"]), "q=x y&r=x y")
        XCTAssertEqual(Workflow.fillTemplate("q={{a}}", with: ["a": "x y&z"], urlEncode: true), "q=x%20y&z")
        XCTAssertEqual(Workflow.fillTemplate("{{b}}", with: ["a": "x"]), "{{b}}")
    }

    func testInputSchema() {
        let schema = valid().inputSchema
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["required"] as? [String], ["order_number"])
        let props = schema["properties"] as? [String: [String: Any]]
        XCTAssertEqual(props?["order_number"]?["description"] as? String, "Order number (e.g. A-1042)")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(schema))
    }

    func testCodableRoundTrip() throws {
        let w = valid()
        let data = try JSONEncoder().encode(w)
        XCTAssertEqual(try JSONDecoder().decode(Workflow.self, from: data), w)
    }
}

final class FixtureCompilerTests: XCTestCase {
    private let flights = "http://127.0.0.1:4318/flights"

    private func flightDemo(hint: String = "") -> Demonstration {
        let select = RecordedAction(type: "select", url: flights, selector: "#airline", fallbacks: ["select[name=\"airline\"]"], label: "Airline", tag: "select", value: "NV")
        let fill = RecordedAction(type: "fill", url: flights, selector: "#number", label: "Flight number", tag: "input", inputType: "text", value: "204")
        let press = RecordedAction(type: "press", url: flights, selector: "#number", label: "Flight number", key: "Enter")
        let click = RecordedAction(type: "click", url: flights, selector: "form > button", label: "Check flight", tag: "button")
        return Demonstration(startURL: flights, actions: [select, fill, press, click],
                             outputs: [PickedOutput(name: "state", selector: "#flight-state", sample: "On time", many: false),
                                       PickedOutput(name: "gates", selector: ".card dd", sample: "A3", many: true)], hint: hint)
    }

    func testMultiInputRecordingWithSelectAndPress() throws {
        let r = try Compiler.fixture(flightDemo())
        let w = r.workflow
        XCTAssertEqual(r.compiler, "fixture")
        XCTAssertEqual(r.attempts, 1)
        XCTAssertEqual(w.inputs.map(\.name), ["airline", "flight_number"])
        XCTAssertEqual(w.inputs.map(\.example), ["NV", "204"])
        XCTAssertEqual(w.inputs.map(\.description), ["Airline", "Flight number"])
        XCTAssertEqual(w.steps.map(\.kind), [.navigate, .select, .fill, .press, .click])
        XCTAssertEqual(w.steps[0].url, flights)
        XCTAssertEqual(w.steps[1].target?.selector, "#airline")
        XCTAssertEqual(w.steps[1].target?.fallbacks, ["select[name=\"airline\"]"])
        XCTAssertEqual(w.steps[1].value, "{{airline}}")
        XCTAssertEqual(w.steps[2].value, "{{flight_number}}")
        XCTAssertEqual(w.steps[3].key, "Enter")
        XCTAssertEqual(w.steps[3].target?.selector, "#number")
        XCTAssertEqual(w.name, "airline_on_127_0_0_1")
        XCTAssertEqual(w.title, "Look up airline, flight_number on 127.0.0.1")
        XCTAssertEqual(w.origin, "http://127.0.0.1:4318")
        XCTAssertEqual(w.outputs.map(\.name), ["state", "gates"])
        XCTAssertEqual(w.outputs.map(\.many), [false, true])
        XCTAssertEqual(w.outputs[0].description, "e.g. On time")
        XCTAssertEqual(w.verify.map(\.output), ["state", "gates"])
        XCTAssertTrue(w.verify.allSatisfy { $0.kind == .nonEmpty })
        XCTAssertEqual(w.problems(knownSelectors: flightDemo().knownSelectors, recordedOrigin: w.origin), [])
    }

    func testHintNamesTheSkill() throws {
        let w = try Compiler.fixture(flightDemo(hint: "Check a flight's gate")).workflow
        XCTAssertEqual(w.name, "check_a_flight_s_gate")
        XCTAssertEqual(w.title, "Check a flight's gate")
    }

    func testTemplatesEveryInputThatAppearsInTheStartURL() throws {
        var demo = flightDemo()
        demo.startURL = "http://127.0.0.1:4318/flights?airline=NV&number=204"
        let w = try Compiler.fixture(demo).workflow
        XCTAssertEqual(w.steps[0].url, "http://127.0.0.1:4318/flights?airline={{airline}}&number={{flight_number}}")
    }

    func testTemplatesPercentEncodedValuesInStartURL() throws {
        var demo = flightDemo()
        demo.actions[1].value = "A 204"
        demo.startURL = "http://127.0.0.1:4318/flights?number=A%20204"
        let w = try Compiler.fixture(demo).workflow
        XCTAssertEqual(w.steps[0].url, "http://127.0.0.1:4318/flights?number={{flight_number}}")
    }

    func testRepeatedFillsCollapseIntoOneInputAndDuplicateLabelsAreSuffixed() throws {
        var demo = flightDemo()
        demo.actions.insert(RecordedAction(type: "fill", url: flights, selector: "#number", label: "Flight number", value: "20"), at: 1)
        demo.actions.append(RecordedAction(type: "fill", url: flights, selector: "#other", label: "Flight number", value: "9"))
        let w = try Compiler.fixture(demo).workflow
        XCTAssertEqual(w.inputs.map(\.name), ["airline", "flight_number", "flight_number_3"])
        XCTAssertEqual(w.inputs.map(\.example), ["NV", "204", "9"])
        XCTAssertEqual(w.steps.filter { $0.kind == .fill }.map(\.value), ["{{flight_number}}", "{{flight_number_3}}"])
    }

    func testUnlabeledFieldsAndNavigationsInsideTheRecording() throws {
        var demo = flightDemo()
        demo.actions = [RecordedAction(type: "navigate", url: "http://127.0.0.1:4318/flights?x=1"),
                        RecordedAction(type: "fill", url: flights, selector: "input[name=\"q\"]", value: "gpu"),
                        RecordedAction(type: "submit", url: flights, selector: "form"),
                        RecordedAction(type: "click", url: flights, selector: nil)]
        let w = try Compiler.fixture(demo).workflow
        XCTAssertEqual(w.inputs.map(\.name), ["input"])
        XCTAssertEqual(w.steps.map(\.kind), [.navigate, .navigate, .fill], "submit and targetless clicks are dropped")
        XCTAssertEqual(w.steps[1].url, "http://127.0.0.1:4318/flights?x=1")
    }

    func testRejectsRecordingsWithoutOrigin() {
        var demo = flightDemo(); demo.startURL = "about:blank"
        XCTAssertThrowsError(try Compiler.fixture(demo)) { XCTAssertEqual($0.localizedDescription, CompileError.noOrigin.localizedDescription) }
    }

    func testCompileRequiresOutputs() async {
        var demo = flightDemo(); demo.outputs = []
        do {
            _ = try await Compiler.compile(demo, settings: AppSettings())
            XCTFail("expected noOutputs")
        } catch {
            XCTAssertEqual(error.localizedDescription, CompileError.noOutputs.localizedDescription)
        }
    }

    func testOffOriginNavigationInsideRecordingFailsValidation() {
        var demo = flightDemo()
        demo.actions.append(RecordedAction(type: "navigate", url: "https://evil.example/"))
        XCTAssertThrowsError(try Compiler.fixture(demo)) { error in
            XCTAssertTrue(error.localizedDescription.contains("off the workflow origin"), error.localizedDescription)
        }
    }

    func testKnownSelectorsIncludeFallbacks() {
        XCTAssertEqual(flightDemo().knownSelectors, ["#airline", "select[name=\"airline\"]", "#number", "form > button"])
    }
}

final class RecorderCollapseTests: XCTestCase {
    private func a(_ type: String, _ selector: String?, _ value: String? = nil) -> RecordedAction {
        RecordedAction(type: type, url: "http://x.test/", selector: selector, value: value)
    }

    func testConsecutiveFillsOfSameFieldKeepLast() {
        let out = Recorder.collapse([a("fill", "#q", "a"), a("fill", "#q", "ab"), a("fill", "#q", "abc")])
        XCTAssertEqual(out.map(\.value), ["abc"])
    }

    func testSelectsCollapseToo() {
        XCTAssertEqual(Recorder.collapse([a("select", "#s", "NV"), a("select", "#s", "UA")]).map(\.value), ["UA"])
    }

    func testDifferentSelectorsOrTypesAreKept() {
        let out = Recorder.collapse([a("fill", "#a", "1"), a("fill", "#b", "2"), a("fill", "#a", "3")])
        XCTAssertEqual(out.map(\.value), ["1", "2", "3"])
        XCTAssertEqual(Recorder.collapse([a("fill", "#a", "1"), a("select", "#a", "2")]).count, 2)
    }

    func testClicksNeverCollapse() {
        XCTAssertEqual(Recorder.collapse([a("click", "#b"), a("click", "#b")]).count, 2)
        XCTAssertEqual(Recorder.collapse([a("press", "#q"), a("press", "#q")]).count, 2)
    }

    func testFillClickFillSequencePreservesOrder() {
        let out = Recorder.collapse([a("fill", "#q", "x"), a("click", "#go"), a("fill", "#q", "y")])
        XCTAssertEqual(out.map { $0.type + ":" + ($0.value ?? "") }, ["fill:x", "click:", "fill:y"])
    }

    func testEmptyAndSingle() {
        XCTAssertEqual(Recorder.collapse([]).count, 0)
        XCTAssertEqual(Recorder.collapse([a("fill", "#q", "x")]).count, 1)
    }

    func testSnakeCase() {
        XCTAssertEqual(Recorder.snake("Order number"), "order_number")
        XCTAssertEqual(Recorder.snake("  Flight #: (ABC) "), "flight_abc")
        XCTAssertEqual(Recorder.snake("123 go"), "field_123_go")
        XCTAssertEqual(Recorder.snake("!!!"), "field_")
        XCTAssertLessThanOrEqual(Recorder.snake(String(repeating: "word ", count: 20)).count, 30)
    }
}

final class ProviderParsingTests: XCTestCase {
    func testFirstJSONObjectHandlesEscapesAndNestedBraces() {
        let text = #"prefix {"a": "}\" {", "b": {"c": [1, {"d": "}"}]}} suffix {"e": 1}"#
        let obj = OpenAICompatibleProvider.firstJSONObject(in: text)
        XCTAssertEqual(obj?["a"] as? String, "}\" {")
        XCTAssertNotNil(obj?["b"])
        XCTAssertNil(obj?["e"])
    }

    func testFirstJSONObjectSkipsInvalidCandidates() {
        XCTAssertEqual(OpenAICompatibleProvider.firstJSONObject(in: "{oops} then {\"ok\": true}")?["ok"] as? Bool, true)
        XCTAssertNil(OpenAICompatibleProvider.firstJSONObject(in: "no json here"))
        XCTAssertNil(OpenAICompatibleProvider.firstJSONObject(in: "{\"unterminated\": 1"))
        XCTAssertNil(OpenAICompatibleProvider.firstJSONObject(in: "[1, 2, 3]"), "arrays are not objects")
        XCTAssertEqual(OpenAICompatibleProvider.firstJSONObject(in: "{}")?.count, 0)
    }

    func testStripReasoningVariants() {
        XCTAssertEqual(OpenAICompatibleProvider.stripReasoning("<think>a</think>x<think>b</think>y"), "xy")
        XCTAssertEqual(OpenAICompatibleProvider.stripReasoning("  plain  "), "plain")
        XCTAssertEqual(OpenAICompatibleProvider.stripReasoning("<think>a<think>b</think>c</think>d"), "d")
        XCTAssertEqual(OpenAICompatibleProvider.stripReasoning(""), "")
    }

    func testParseContentStripsReasoningAndReadsUsage() throws {
        let json = #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"<think>plan</think>{\"name\":\"x\"}"}}],"usage":{"prompt_tokens":10,"completion_tokens":5}}"#
        let r = try OpenAICompatibleProvider.parse(Data(json.utf8))
        XCTAssertEqual(r.content, #"{"name":"x"}"#)
        XCTAssertEqual(r.finishReason, .stop)
        XCTAssertEqual(r.usage?.totalTokens, 15)
        XCTAssertTrue(r.toolCalls.isEmpty)
    }

    func testParseFinishReasons() throws {
        let length = #"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#
        XCTAssertEqual(try OpenAICompatibleProvider.parse(Data(length.utf8)).finishReason, .maxTokens)
        let implicitTools = #"{"choices":[{"message":{"content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"page_read","arguments":"{\"selector\":\".x\"}"}}]}}]}"#
        let r = try OpenAICompatibleProvider.parse(Data(implicitTools.utf8))
        XCTAssertEqual(r.finishReason, .toolCalls)
        XCTAssertEqual(r.toolCalls.first?.arguments["selector"] as? String, ".x")
        XCTAssertEqual(r.content, "")
    }

    func testParseToleratesMalformedToolArgumentsAndSkipsNamelessCalls() throws {
        let json = #"{"choices":[{"finish_reason":"tool_calls","message":{"content":"","tool_calls":[{"id":"c1","function":{"name":"skills_list","arguments":"not json"}},{"id":"c2","function":{}}]}}]}"#
        let r = try OpenAICompatibleProvider.parse(Data(json.utf8))
        XCTAssertEqual(r.toolCalls.count, 1)
        XCTAssertEqual(r.toolCalls.first?.id, "c1")
        XCTAssertTrue(r.toolCalls.first?.arguments.isEmpty == true)
    }

    func testParseRejectsResponsesWithoutChoices() {
        XCTAssertThrowsError(try OpenAICompatibleProvider.parse(Data(#"{"error":{"message":"bad"}}"#.utf8)))
        XCTAssertThrowsError(try OpenAICompatibleProvider.parse(Data("not json".utf8)))
        XCTAssertThrowsError(try OpenAICompatibleProvider.parse(Data(#"{"choices":[]}"#.utf8)))
    }

    func testBodyFixesForRejectedParameters() {
        let body: [String: Any] = ["model": "m", "max_tokens": 10, "temperature": 0.1, "response_format": ["type": "json_object"]]
        let maxTokens = OpenAICompatibleProvider.body(body, fixingRejectionIn: Data(#"{"error":{"param":"max_tokens","message":"unsupported"}}"#.utf8))
        XCTAssertNil(maxTokens?["max_tokens"])
        XCTAssertEqual(maxTokens?["max_completion_tokens"] as? Int, 10)
        let format = OpenAICompatibleProvider.body(body, fixingRejectionIn: Data("response_format is not supported".utf8))
        XCTAssertNil(format?["response_format"])
        let temperature = OpenAICompatibleProvider.body(body, fixingRejectionIn: Data(#"{"error":{"param":"temperature"}}"#.utf8))
        XCTAssertNil(temperature?["temperature"])
        XCTAssertNil(OpenAICompatibleProvider.body(body, fixingRejectionIn: Data(#"{"error":{"message":"quota"}}"#.utf8)))
    }

    func testEncodeExpandsToolResultsAndToolCalls() {
        let messages = [AIMessage(role: .system, content: "s"),
                        AIMessage(role: .assistant, content: "", toolCalls: [AIToolCall(id: "c1", name: "ping", arguments: ["a": 1])]),
                        AIMessage(role: .tool, content: "", toolResults: [AIToolResult(toolCallId: "c1", toolName: "ping", content: "ok", isError: false),
                                                                           AIToolResult(toolCallId: "c2", toolName: "ping", content: "no", isError: true)])]
        let out = OpenAICompatibleProvider.encode(messages)
        XCTAssertEqual(out.map { $0["role"] as? String }, ["system", "assistant", "tool", "tool"])
        let call = ((out[1]["tool_calls"] as? [[String: Any]])?.first?["function"] as? [String: Any])
        XCTAssertEqual(call?["name"] as? String, "ping")
        XCTAssertEqual(call?["arguments"] as? String, #"{"a":1}"#)
        XCTAssertEqual(out[3]["tool_call_id"] as? String, "c2")
    }

    func testRefusesPlainHTTPForRemoteHostsBeforeSendingTheKey() async {
        let provider = OpenAICompatibleProvider(apiKey: "k", baseURL: "http://api.example.com/v1")
        do {
            _ = try await provider.sendMessage(messages: [], model: "m", config: AIGenerationConfig(), tools: [])
            XCTFail("expected insecureURL")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("HTTPS"), error.localizedDescription)
        }
        do {
            _ = try await OpenAICompatibleProvider(apiKey: "", baseURL: "https://x").sendMessage(messages: [], model: "m", config: AIGenerationConfig(), tools: [])
            XCTFail("expected invalidAPIKey")
        } catch {
            XCTAssertEqual(error.localizedDescription, AIProviderError.invalidAPIKey.localizedDescription)
        }
    }
}
