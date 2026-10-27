// Licensed under GPL-3.0. See LICENSE.
//
//  MCPServerTests.swift
//  BrowserSkillsTests
//
//  HTTP parsing edge cases and the JSON-RPC layer, driven through MCPServer.handle without sockets.
//

import Foundation
import XCTest
@testable import BrowserSkills

// MARK: - HTTPRequest

final class HTTPRequestParsingTests: XCTestCase {
    private let head = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\n"

    func testBodyArrivingInPiecesIsIncompleteUntilTheLastByte() {
        let full = head + "Content-Length: 12\r\n\r\n{\"a\":\"bcde\"}"
        let bytes = Array(full.utf8)
        var buffer = Data()
        var parsed: HTTPRequest?
        for (i, b) in bytes.enumerated() {
            buffer.append(b)
            parsed = HTTPRequest(buffer)
            if i < bytes.count - 1 { XCTAssertNil(parsed, "complete after \(i + 1) of \(bytes.count) bytes") }
        }
        XCTAssertEqual(parsed?.body, Data("{\"a\":\"bcde\"}".utf8))
        XCTAssertEqual(parsed?.method, "POST")
        XCTAssertEqual(parsed?.path, "/mcp")
    }

    func testHeaderNamesAreCaseInsensitiveAndValuesTrimmed() {
        let raw = head + "CONTENT-LENGTH:   2 \r\nauthorization: Bearer abc\r\nX-Custom: v\r\n\r\n{}"
        let req = HTTPRequest(Data(raw.utf8))
        XCTAssertEqual(req?.headers["content-length"], "2")
        XCTAssertEqual(req?.headers["authorization"], "Bearer abc")
        XCTAssertEqual(req?.headers["x-custom"], "v")
        XCTAssertEqual(req?.body, Data("{}".utf8))
    }

    func testMissingContentLengthMeansEmptyBody() {
        let req = HTTPRequest(Data((head + "\r\n{\"ignored\":true}").utf8))
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.body.count, 0)
    }

    func testMalformedOrNegativeContentLengthDoesNotCrash() {
        XCTAssertEqual(HTTPRequest(Data((head + "Content-Length: -5\r\n\r\n").utf8))?.body.count, 0)
        XCTAssertEqual(HTTPRequest(Data((head + "Content-Length: abc\r\n\r\nxyz").utf8))?.body.count, 0)
    }

    func testIncompleteHeadersAreIncomplete() {
        XCTAssertNil(HTTPRequest(Data("POST /mcp HTTP/1.1\r\nHost: x\r\n".utf8)))
        XCTAssertNil(HTTPRequest(Data("GARBAGE\r\n\r\n".utf8)))
    }

    func testChunkedBodyArrivingInPieces() {
        let chunked = head + "Transfer-Encoding: chunked\r\n\r\n5;ext=1\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"
        let bytes = Array(chunked.utf8)
        for cut in stride(from: 10, to: bytes.count, by: 7) {
            XCTAssertNil(HTTPRequest(Data(bytes[..<cut])), "complete after \(cut) bytes")
        }
        let req = HTTPRequest(Data(bytes))
        XCTAssertEqual(req.map { String(decoding: $0.body, as: UTF8.self) }, "hello world")
    }

    func testChunkedBodyWithTrailersAndMixedCaseEncoding() {
        let raw = head + "transfer-encoding: Chunked\r\n\r\n2\r\n{}\r\n0\r\nX-Trailer: t\r\n\r\n"
        XCTAssertEqual(HTTPRequest(Data(raw.utf8))?.body, Data("{}".utf8))
        XCTAssertNil(HTTPRequest(Data((head + "transfer-encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\nX-Trailer: t\r\n").utf8)))
    }

    func testMalformedChunkSizeYieldsEmptyBodyInsteadOfHanging() {
        XCTAssertEqual(HTTPRequest(Data((head + "Transfer-Encoding: chunked\r\n\r\nzz\r\n").utf8))?.body.count, 0)
    }

    func testParsesDataSlicesWithNonZeroStartIndex() {
        let padded = Data("XX".utf8) + Data((head + "Content-Length: 2\r\n\r\n{}").utf8)
        let req = HTTPRequest(padded[2...])
        XCTAssertEqual(req?.method, "POST")
        XCTAssertEqual(req?.body, Data("{}".utf8))
    }

    func testKeepsQueryInPath() {
        XCTAssertEqual(HTTPRequest(Data("GET /mcp?x=1 HTTP/1.1\r\n\r\n".utf8))?.path, "/mcp?x=1")
    }
}

// MARK: - JSON-RPC dispatch

@MainActor
final class FakeTools: MCPToolSource {
    var calls: [(name: String, args: [String: Any])] = []

    func definitions() -> [AIToolDefinition] {
        [AIToolDefinition(name: "echo", description: "Echoes text",
                          parameters: ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"]]),
         AIToolDefinition(name: "fail", description: "Always fails", parameters: ["type": "object", "properties": [:] as [String: Any]])]
    }

    func call(_ name: String, _ args: [String: Any]) async -> ToolOutput {
        calls.append((name, args))
        switch name {
        case "echo": return ToolOutput(text: args["text"] as? String ?? "", structured: ["echoed": args["text"] ?? NSNull()])
        case "fail": return ToolOutput(text: "boom", isError: true)
        default: return ToolOutput(text: "unknown tool \(name)", isError: true)
        }
    }
}

@MainActor
final class MCPDispatchTests: XCTestCase {
    private var dir: URL!
    private var tools: FakeTools!
    private var server: MCPServer!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("browserskills-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tools = FakeTools()
        server = MCPServer(registry: tools, port: 0, directory: dir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func request(method: String = "POST", path: String = "/mcp", headers: [String: String] = [:], body: String = "", auth: Bool = true) -> HTTPRequest {
        var h = ["Host": "127.0.0.1", "Content-Type": "application/json", "Content-Length": "\(body.utf8.count)"]
        if auth { h["Authorization"] = "Bearer \(server.token)" }
        for (k, v) in headers { h[k] = v }
        let head = "\(method) \(path) HTTP/1.1\r\n" + h.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n") + "\r\n\r\n"
        return HTTPRequest(Data((head + body).utf8))!
    }

    private func post(_ body: String, headers: [String: String] = [:], auth: Bool = true) async -> (status: Int, json: Any?, headers: [String: String]) {
        let (status, data, extra) = await server.handle(request(headers: headers, body: body, auth: auth))
        return (status, data.flatMap { try? JSONSerialization.jsonObject(with: $0) }, extra)
    }

    private func error(_ json: Any?) -> (code: Int?, message: String?, id: Any?) {
        let d = json as? [String: Any]
        let e = d?["error"] as? [String: Any]
        return (e?["code"] as? Int, e?["message"] as? String, d?["id"])
    }

    private func result(_ json: Any?) -> [String: Any]? { (json as? [String: Any])?["result"] as? [String: Any] }

    // Token file

    func testTokenFileIsPrivateAndReused() throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: server.tokenFile.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertGreaterThanOrEqual(server.token.count, 32)
        XCTAssertEqual(MCPServer(registry: tools, port: 0, directory: dir).token, server.token)
    }

    // Transport guards

    func testRejectsMissingAndWrongBearerToken() async {
        let missing = await post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, auth: false)
        XCTAssertEqual(missing.status, 401)
        XCTAssertEqual(missing.headers["WWW-Authenticate"], "Bearer")
        XCTAssertEqual(error(missing.json).code, -32001)
        let wrong = await post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["Authorization": "Bearer " + String(server.token.reversed())], auth: false)
        XCTAssertEqual(wrong.status, 401)
        let lowercaseScheme = await post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["Authorization": "bearer \(server.token)"], auth: false)
        XCTAssertEqual(lowercaseScheme.status, 401)
        XCTAssertTrue(tools.calls.isEmpty)
    }

    func testRejectsNonLoopbackOrigins() async {
        for origin in ["https://evil.example", "http://127.0.0.1.evil.example", "http://localhost.evil.example:4318", "null", "file://", "http://10.0.0.5"] {
            let r = await post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["Origin": origin])
            XCTAssertEqual(r.status, 403, origin)
            XCTAssertEqual(error(r.json).code, -32600, origin)
        }
        for origin in ["http://127.0.0.1:4318", "http://localhost", "http://localhost:3000", "https://127.0.0.1", "http://[::1]:5000"] {
            let r = await post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["Origin": origin])
            XCTAssertEqual(r.status, 200, origin)
        }
        XCTAssertTrue(MCPServer.isLoopbackOrigin("http://localhost:4318"))
        XCTAssertFalse(MCPServer.isLoopbackOrigin("http://127.0.0.1.evil.example"))
        XCTAssertFalse(MCPServer.isLoopbackOrigin("ws://127.0.0.1"))
    }

    func testOriginIsCheckedBeforeAuthSoBrowsersLearnNothing() async {
        let r = await post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["Origin": "https://evil.example"], auth: false)
        XCTAssertEqual(r.status, 403)
    }

    func testOtherPathsAndMethods() async {
        let (notFound, _, _) = await server.handle(request(path: "/other", body: "{}"))
        XCTAssertEqual(notFound, 404)
        let (get, getBody, allow) = await server.handle(request(method: "GET"))
        XCTAssertEqual(get, 405)
        XCTAssertNil(getBody)
        XCTAssertEqual(allow["Allow"], "POST, DELETE")
        let (delete, _, _) = await server.handle(request(method: "DELETE"))
        XCTAssertEqual(delete, 200)
        let (query, _, _) = await server.handle(request(path: "/mcp?session=1", body: #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#))
        XCTAssertEqual(query, 200)
    }

    // JSON-RPC

    func testInvalidJSONIsParseError() async {
        let r = await post("{not json")
        XCTAssertEqual(r.status, 400)
        XCTAssertEqual(error(r.json).code, -32700)
        XCTAssertTrue(error(r.json).id is NSNull)
    }

    func testValidJSONThatIsNotARequestIsInvalidRequest() async {
        for body in [#""hello""#, "42", #"{"id":1,"method":"ping"}"#, #"{"jsonrpc":"2.0","id":1}"#, #"{"jsonrpc":"2.0","id":{"x":1},"method":"ping"}"#] {
            let r = await post(body)
            XCTAssertEqual(r.status, 200, body)
            XCTAssertEqual(error(r.json).code, -32600, body)
        }
        let withID = await post(#"{"id":7,"method":"ping"}"#)
        XCTAssertEqual(error(withID.json).id as? Int, 7)
    }

    func testUnknownMethodIsMethodNotFound() async {
        let r = await post(#"{"jsonrpc":"2.0","id":"abc","method":"resources/list"}"#)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(error(r.json).code, -32601)
        XCTAssertEqual(error(r.json).id as? String, "abc")
        XCTAssertTrue(error(r.json).message?.contains("resources/list") == true)
    }

    func testNotificationsAndClientResponsesGet202WithNoBody() async {
        for body in [#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
                     #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#,
                     #"{"jsonrpc":"2.0","id":9,"result":{}}"#,
                     #"{"jsonrpc":"2.0","id":9,"error":{"code":-1,"message":"x"}}"#] {
            let (status, data, _) = await server.handle(request(body: body))
            XCTAssertEqual(status, 202, body)
            XCTAssertNil(data, body)
        }
    }

    func testInitializeNegotiatesProtocolVersion() async {
        let same = await post(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#)
        XCTAssertEqual(same.status, 200)
        XCTAssertEqual(result(same.json)?["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((result(same.json)?["serverInfo"] as? [String: Any])?["name"] as? String, "browserskills")
        XCTAssertNotNil((result(same.json)?["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual(same.headers["Mcp-Session-Id"], "browserskills")
        let future = await post(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#)
        XCTAssertEqual(result(future.json)?["protocolVersion"] as? String, MCPServer.latestProtocolVersion)
        let none = await post(#"{"jsonrpc":"2.0","id":3,"method":"initialize"}"#)
        XCTAssertEqual(result(none.json)?["protocolVersion"] as? String, MCPServer.latestProtocolVersion)
    }

    func testPingReturnsEmptyResult() async {
        let r = await post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(result(r.json)?.count, 0)
        XCTAssertEqual((r.json as? [String: Any])?["jsonrpc"] as? String, "2.0")
        XCTAssertEqual((r.json as? [String: Any])?["id"] as? Int, 1)
    }

    func testToolsListExposesSchemas() async {
        let r = await post(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#)
        let list = result(r.json)?["tools"] as? [[String: Any]]
        XCTAssertEqual(list?.map { $0["name"] as? String }, ["echo", "fail"])
        let schema = list?.first?["inputSchema"] as? [String: Any]
        XCTAssertEqual(schema?["type"] as? String, "object")
        XCTAssertEqual(schema?["required"] as? [String], ["text"])
        XCTAssertEqual(list?.first?["description"] as? String, "Echoes text")
    }

    func testToolsCallReturnsContentAndStructuredContent() async {
        let r = await post(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi"}}}"#)
        XCTAssertEqual(r.status, 200)
        let res = result(r.json)
        XCTAssertEqual(res?["isError"] as? Bool, false)
        XCTAssertEqual(((res?["content"] as? [[String: Any]])?.first)?["text"] as? String, "hi")
        XCTAssertEqual((res?["structuredContent"] as? [String: Any])?["echoed"] as? String, "hi")
        XCTAssertEqual(tools.calls.count, 1)
        XCTAssertEqual(tools.calls.first?.args["text"] as? String, "hi")
        XCTAssertEqual(server.callCount, 1)
    }

    func testToolFailuresAreIsErrorResultsNotJSONRPCErrors() async {
        let r = await post(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"fail"}}"#)
        XCTAssertEqual(r.status, 200)
        XCTAssertNil((r.json as? [String: Any])?["error"])
        XCTAssertEqual(result(r.json)?["isError"] as? Bool, true)
        XCTAssertEqual(((result(r.json)?["content"] as? [[String: Any]])?.first)?["text"] as? String, "boom")
    }

    func testUnknownToolAndBadArgumentsAreInvalidParams() async {
        let unknown = await post(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#)
        XCTAssertEqual(error(unknown.json).code, -32602)
        let noName = await post(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"arguments":{}}}"#)
        XCTAssertEqual(error(noName.json).code, -32602)
        let badArgs = await post(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":"hi"}}"#)
        XCTAssertEqual(error(badArgs.json).code, -32602)
        XCTAssertTrue(tools.calls.isEmpty)
        let nullArgs = await post(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo","arguments":null}}"#)
        XCTAssertEqual(result(nullArgs.json)?["isError"] as? Bool, false)
    }

    func testBatchRequests() async {
        let batch = #"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","id":"two","method":"tools/call","params":{"name":"echo","arguments":{"text":"b"}}},{"jsonrpc":"2.0","id":3,"method":"nope"}]"#
        let r = await post(batch)
        XCTAssertEqual(r.status, 200)
        let responses = r.json as? [[String: Any]]
        XCTAssertEqual(responses?.count, 3)
        XCTAssertEqual(responses?[0]["id"] as? Int, 1)
        XCTAssertEqual(responses?[1]["id"] as? String, "two")
        XCTAssertEqual(((responses?[1]["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String, "b")
        XCTAssertEqual((responses?[2]["error"] as? [String: Any])?["code"] as? Int, -32601)

        let onlyNotifications = await server.handle(request(body: #"[{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","id":1,"result":{}}]"#))
        XCTAssertEqual(onlyNotifications.0, 202)
        XCTAssertNil(onlyNotifications.1)

        let empty = await post("[]")
        XCTAssertEqual(empty.status, 400)
        XCTAssertEqual(error(empty.json).code, -32600)

        let garbageItem = await post(#"[1]"#)
        XCTAssertEqual((garbageItem.json as? [[String: Any]])?.count, 1)
        XCTAssertEqual(((garbageItem.json as? [[String: Any]])?.first?["error"] as? [String: Any])?["code"] as? Int, -32600)
    }

    func testChunkedPostIsDispatched() async {
        let body = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let raw = "POST /mcp HTTP/1.1\r\nAuthorization: Bearer \(server.token)\r\nTransfer-Encoding: chunked\r\n\r\n\(String(body.utf8.count, radix: 16))\r\n\(body)\r\n0\r\n\r\n"
        let (status, data, _) = await server.handle(HTTPRequest(Data(raw.utf8))!)
        XCTAssertEqual(status, 200)
        XCTAssertNotNil(data)
    }

    // Real socket, loopback only

    func testListenerAnswersOnLoopbackAndAuthenticates() async throws {
        let port = UInt16(Int.random(in: 42000..<60000))
        let live = MCPServer(registry: tools, port: port, directory: dir)
        live.start()
        var waited = 0
        while !live.running, waited < 100 { try await Task.sleep(for: .milliseconds(50)); waited += 1 }
        XCTAssertTrue(live.running, live.lastError ?? "")
        defer { live.stop() }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8)
        let (_, unauthorized) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((unauthorized as? HTTPURLResponse)?.statusCode, 401)

        req.setValue("Bearer \(live.token)", forHTTPHeaderField: "Authorization")
        let (data, ok) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((ok as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((ok as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["id"] as? Int, 1)

        req.httpBody = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        let (empty, accepted) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((accepted as? HTTPURLResponse)?.statusCode, 202)
        XCTAssertEqual(empty.count, 0)
    }
}

// MARK: - ToolRegistry schemas

@MainActor
final class ToolRegistryTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("browserskills-registry-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func flightWorkflow() -> Workflow {
        Workflow(name: "flight_status", title: "Check a flight", description: "Looks up a flight's state and gate.", origin: "http://127.0.0.1:4318",
                 inputs: [WorkflowInput(name: "airline", description: "Airline code", example: "NV"),
                          WorkflowInput(name: "flight_number", description: "Flight number", example: "204")],
                 steps: [WorkflowStep(kind: .navigate, url: "http://127.0.0.1:4318/flights"),
                         WorkflowStep(kind: .select, target: ElementTarget(selector: "#airline"), value: "{{airline}}"),
                         WorkflowStep(kind: .fill, target: ElementTarget(selector: "#number"), value: "{{flight_number}}"),
                         WorkflowStep(kind: .click, target: ElementTarget(selector: "form > button"))],
                 outputs: [WorkflowOutput(name: "state", description: "", selector: "#flight-state"),
                           WorkflowOutput(name: "gate", description: "", selector: "#flight-gate")],
                 verify: [VerifyCheck(kind: .nonEmpty, output: "state", input: nil)])
    }

    func testSkillToolSchemaComesFromWorkflowInputs() async throws {
        let store = SkillStore(directory: dir)
        let executor = Executor(store: store, tab: BrowserTab(isAgent: true))
        var settings = AppSettings()
        let registry = ToolRegistry(store: store, executor: executor, settings: { settings })

        let generic = registry.definitions().map(\.name)
        XCTAssertEqual(generic, ["skills_list", "browser_open", "page_describe", "page_act", "page_read", "run_get"])
        for tool in registry.definitions() {
            XCTAssertEqual(tool.parameters["type"] as? String, "object", tool.name)
            XCTAssertNotNil(tool.parameters["properties"], tool.name)
            XCTAssertTrue(JSONSerialization.isValidJSONObject(tool.parameters), tool.name)
        }

        let version = try store.addCandidate(flightWorkflow(), compiler: "fixture")
        XCTAssertFalse(registry.definitions().contains { $0.name == "skill_flight_status" }, "candidates are not exposed")
        store.setStatus(.validated, skillID: version.skillID, version: version.version)

        guard let tool = registry.definitions().first(where: { $0.name == "skill_flight_status" }) else { return XCTFail("no skill tool") }
        XCTAssertEqual(registry.definitions().first?.name, "skill_flight_status", "skills come before generic tools")
        XCTAssertTrue(tool.description.hasPrefix("Check a flight. Looks up a flight's state and gate."))
        XCTAssertTrue(tool.description.contains("http://127.0.0.1:4318"))
        XCTAssertTrue(tool.description.contains("state, gate"))
        XCTAssertEqual(tool.parameters["type"] as? String, "object")
        XCTAssertEqual(tool.parameters["required"] as? [String], ["airline", "flight_number"])
        let props = tool.parameters["properties"] as? [String: [String: Any]]
        XCTAssertEqual(Set(props?.keys.map { $0 } ?? []), ["airline", "flight_number"])
        XCTAssertEqual(props?["airline"]?["type"] as? String, "string")
        XCTAssertEqual(props?["airline"]?["description"] as? String, "Airline code (e.g. NV)")
        XCTAssertEqual(props?["flight_number"]?["description"] as? String, "Flight number (e.g. 204)")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(tool.parameters))

        XCTAssertFalse(registry.definitions().contains { $0.name == "web_search" })
        settings.tavilyKey = "set"
        XCTAssertTrue(registry.definitions().contains { $0.name == "web_search" })

        let listed = await registry.call("skills_list", [:])
        XCTAssertFalse(listed.isError)
        let skills = listed.structured?["skills"] as? [[String: Any]]
        XCTAssertEqual(skills?.first?["tool"] as? String, "skill_flight_status")
        XCTAssertEqual((skills?.first?["inputs"] as? [[String: String]])?.map { $0["name"] }, ["airline", "flight_number"])

        let unknown = await registry.call("nope", [:])
        XCTAssertTrue(unknown.isError)
        let missingRun = await registry.call("run_get", ["run_id": "none"])
        XCTAssertTrue(missingRun.isError)
        let badURL = await registry.call("browser_open", ["url": "file:///etc/passwd"])
        XCTAssertTrue(badURL.isError)
    }
}
