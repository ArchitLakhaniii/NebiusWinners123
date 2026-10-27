// Licensed under GPL-3.0. See LICENSE.
//
//  MCPServer.swift
//  BrowserSkills
//
//  MCP over Streamable HTTP on 127.0.0.1, bearer-token protected. Adapted from Nook's
//  DevMCPServer (nook-browser/Nook, GPL-3.0): same loopback binding, 0600 token file and
//  JSON-RPC dispatch; tools come from the shared ToolRegistry instead of dev tools.
//  Responses are plain JSON (no SSE stream), which the Streamable HTTP transport allows.
//

import Foundation
import Network

/// What the server exposes: ToolRegistry in the app, a fake in tests.
@MainActor
protocol MCPToolSource: AnyObject {
    func definitions() -> [AIToolDefinition]
    func call(_ name: String, _ args: [String: Any]) async -> ToolOutput
}

extension ToolRegistry: MCPToolSource {}

@MainActor
final class MCPServer: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var lastError: String?
    @Published private(set) var callCount = 0

    let port: UInt16
    let token: String
    let tokenFile: URL
    private let registry: any MCPToolSource
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "browserskills.mcp")

    var endpoint: String { "http://127.0.0.1:\(port)/mcp" }

    static let supportedProtocolVersions = ["2024-11-05", "2025-03-26", "2025-06-18"]
    static let latestProtocolVersion = "2025-06-18"

    init(registry: any MCPToolSource, port: UInt16, directory: URL) {
        self.registry = registry
        self.port = port
        tokenFile = directory.appendingPathComponent("mcp-token")
        token = Self.loadOrCreateToken(at: tokenFile)
    }

    private static func loadOrCreateToken(at file: URL) -> String {
        if let existing = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), existing.count >= 32 {
            return existing
        }
        let fresh = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        try? Data(fresh.utf8).write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return fresh
    }

    func start() {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.running = true; self?.lastError = nil
                    case .failed(let e): self?.running = false; self?.lastError = e.localizedDescription; self?.listener = nil
                    case .cancelled: self?.running = false
                    default: break
                    }
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() { listener?.cancel(); listener = nil }

    // MARK: HTTP

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    nonisolated private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if buf.count > 4 << 20 { Self.send(conn, status: 413, body: Self.rpcError(nil, -32600, "request too large")); return }
            if let request = HTTPRequest(buf) {
                Task { @MainActor in
                    let (status, body, extra) = await self.handle(request)
                    Self.send(conn, status: status, body: body, headers: extra)
                }
            } else if done || error != nil {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    nonisolated private static func send(_ conn: NWConnection, status: Int, body: Data?, headers: [String: String] = [:]) {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body?.count ?? 0)\r\nConnection: close\r\n"
        if body != nil { head += "Content-Type: application/json\r\n" }
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        var out = Data((head + "\r\n").utf8)
        if let body { out.append(body) }
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    /// Only pages served from loopback may talk to the server (DNS-rebinding guard). A prefix
    /// match is not enough: http://127.0.0.1.evil.example starts with http://127.0.0.1.
    nonisolated static func isLoopbackOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
    }

    /// Transport-independent: one parsed HTTP request in, (status, body, extra headers) out.
    func handle(_ req: HTTPRequest) async -> (Int, Data?, [String: String]) {
        // DNS-rebinding guard: browsers send Origin; only loopback pages may talk to us.
        if let origin = req.headers["origin"], !origin.isEmpty, !Self.isLoopbackOrigin(origin) {
            return (403, Self.rpcError(nil, -32600, "origin not allowed"), [:])
        }
        guard req.path.split(separator: "?").first == "/mcp" else { return (404, nil, [:]) }
        guard req.headers["authorization"] == "Bearer \(token)" else {
            return (401, Self.rpcError(nil, -32001, "missing or wrong bearer token (see \(tokenFile.path))"), ["WWW-Authenticate": "Bearer"])
        }
        switch req.method {
        case "POST": break
        case "DELETE": return (200, nil, [:])
        default: return (405, nil, ["Allow": "POST, DELETE"])
        }
        guard let json = try? JSONSerialization.jsonObject(with: req.body, options: [.fragmentsAllowed]) else {
            return (400, Self.rpcError(nil, -32700, "parse error"), [:])
        }
        let session = ["Mcp-Session-Id": "browserskills"]
        if let batch = json as? [Any] {
            guard !batch.isEmpty else { return (400, Self.rpcError(nil, -32600, "invalid request: empty batch"), [:]) }
            var responses: [Data] = []
            for message in batch {
                if let response = await dispatch(message) { responses.append(Self.encode(response)) }
            }
            // A batch of only notifications or responses gets no body, like a single one.
            guard !responses.isEmpty else { return (202, nil, [:]) }
            return (200, Data("[".utf8) + Data(responses.joined(separator: Data(",".utf8))) + Data("]".utf8), session)
        }
        guard let response = await dispatch(json) else { return (202, nil, [:]) }
        return (200, Self.encode(response), session)
    }

    /// One JSON-RPC message in, its response object out. Notifications and client responses
    /// (messages without an id, or with a result/error instead of a method) get nil: no reply.
    func dispatch(_ message: Any) async -> [String: Any]? {
        guard let msg = message as? [String: Any] else { return Self.rpcErrorObject(nil, -32600, "invalid request: expected a JSON-RPC object") }
        let id = msg["id"]
        if let id, !(id is String || id is NSNumber || id is NSNull) {
            return Self.rpcErrorObject(nil, -32600, "invalid request: id must be a string or number")
        }
        if msg["method"] == nil, msg["result"] != nil || msg["error"] != nil { return nil }
        guard msg["jsonrpc"] as? String == "2.0", let method = msg["method"] as? String else {
            return Self.rpcErrorObject(id, -32600, "invalid request: jsonrpc must be \"2.0\" and method a string")
        }
        guard let id else { return nil }   // notification, e.g. notifications/initialized
        let params = msg["params"] as? [String: Any] ?? [:]

        let result: Any
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            result = [
                "protocolVersion": Self.supportedProtocolVersions.contains(requested) ? requested : Self.latestProtocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "browserskills", "version": "0.1.0"],
                "instructions": "BrowserSkills: a browser that caches workflows its user taught or repeated. skill_* tools replay verified procedures; browser_open/page_describe/page_act/page_read turn any webpage into tools. Everything runs in the browser's agent tab with the user's logins.",
            ] as [String: Any]
        case "ping":
            result = [String: Any]()
        case "tools/list":
            result = ["tools": registry.definitions().map { ["name": $0.name, "description": $0.description, "inputSchema": $0.parameters] }]
        case "tools/call":
            // Unknown tools and malformed params are protocol errors; a tool that runs and fails is an isError result.
            guard let name = params["name"] as? String, !name.isEmpty else { return Self.rpcErrorObject(id, -32602, "invalid params: name is required") }
            guard registry.definitions().contains(where: { $0.name == name }) else { return Self.rpcErrorObject(id, -32602, "unknown tool: \(name)") }
            let arguments: [String: Any]
            switch params["arguments"] {
            case nil, is NSNull: arguments = [:]
            case let a as [String: Any]: arguments = a
            default: return Self.rpcErrorObject(id, -32602, "invalid params: arguments must be an object")
            }
            callCount += 1
            let out = await registry.call(name, arguments)
            var r: [String: Any] = ["content": [["type": "text", "text": out.text]], "isError": out.isError]
            if let s = out.structured, JSONSerialization.isValidJSONObject(s) { r["structuredContent"] = s }
            result = r
        default:
            return Self.rpcErrorObject(id, -32601, "method not found: \(method)")
        }
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }

    nonisolated static func encode(_ response: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: response)) ?? rpcError(response["id"], -32603, "unserializable result")
    }

    nonisolated static func rpcErrorObject(_ id: Any?, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    nonisolated static func rpcError(_ id: Any?, _ code: Int, _ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: rpcErrorObject(id, code, message))) ?? Data()
    }
}

/// A complete HTTP/1.1 request, or nil while more bytes are needed. Bodies may be sized by
/// Content-Length or chunked; header names are case-insensitive.
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<sep.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var h: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            h[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let rest = data[sep.upperBound...]
        if h["transfer-encoding"]?.lowercased().contains("chunked") == true {
            guard let decoded = Self.dechunk(rest) else { return nil }
            body = decoded
        } else {
            // A missing, malformed or negative Content-Length means no body (never a crashing range).
            let length = max(0, Int(h["content-length"] ?? "0") ?? 0)
            guard rest.count >= length else { return nil }
            body = Data(rest.prefix(length))
        }
        method = String(start[0]); path = String(start[1]); headers = h
    }

    /// Decodes a chunked body; nil until the terminating zero-size chunk (and its trailer line) is in.
    private static func dechunk(_ data: Data) -> Data? {
        let crlf = Data("\r\n".utf8)
        var out = Data()
        var i = data.startIndex
        while true {
            guard let lineEnd = data.range(of: crlf, in: i..<data.endIndex) else { return nil }
            let sizeField = String(decoding: data[i..<lineEnd.lowerBound], as: UTF8.self).split(separator: ";").first ?? ""
            guard let size = Int(sizeField.trimmingCharacters(in: .whitespaces), radix: 16) else { return Data() }
            let chunkStart = lineEnd.upperBound
            if size == 0 {
                return data.range(of: Data("\r\n\r\n".utf8), in: lineEnd.lowerBound..<data.endIndex) == nil ? nil : out
            }
            guard data.endIndex - chunkStart >= size + 2 else { return nil }
            out.append(data[chunkStart..<chunkStart + size])
            i = chunkStart + size + 2
        }
    }
}
