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

@MainActor
final class MCPServer: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var lastError: String?
    @Published private(set) var callCount = 0

    let port: UInt16
    let token: String
    let tokenFile: URL
    private let registry: ToolRegistry
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "browserskills.mcp")

    var endpoint: String { "http://127.0.0.1:\(port)/mcp" }

    init(registry: ToolRegistry, port: UInt16, directory: URL) {
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

    private func handle(_ req: HTTPRequest) async -> (Int, Data?, [String: String]) {
        // DNS-rebinding guard: browsers send Origin; only loopback pages may talk to us.
        if let origin = req.headers["origin"], !origin.isEmpty,
           !(origin.hasPrefix("http://127.0.0.1") || origin.hasPrefix("http://localhost")) {
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
        guard let msg = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] else {
            return (400, Self.rpcError(nil, -32700, "parse error"), [:])
        }
        let id = msg["id"]
        let method = msg["method"] as? String ?? ""
        let params = msg["params"] as? [String: Any] ?? [:]
        if id == nil { return (202, nil, [:]) }   // notification, e.g. notifications/initialized

        let result: Any
        switch method {
        case "initialize":
            result = [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "browserskills", "version": "0.1.0"],
                "instructions": "BrowserSkills: a browser that caches workflows its user taught or repeated. skill_* tools replay verified procedures; browser_open/page_describe/page_act/page_read turn any webpage into tools. Everything runs in the browser's agent tab with the user's logins.",
            ] as [String: Any]
        case "ping":
            result = [String: Any]()
        case "tools/list":
            result = ["tools": registry.definitions().map { ["name": $0.name, "description": $0.description, "inputSchema": $0.parameters] }]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            callCount += 1
            let out = await registry.call(name, params["arguments"] as? [String: Any] ?? [:])
            var r: [String: Any] = ["content": [["type": "text", "text": out.text]], "isError": out.isError]
            if let s = out.structured, JSONSerialization.isValidJSONObject(s) { r["structuredContent"] = s }
            result = r
        default:
            return (200, Self.rpcError(id, -32601, "method not found: \(method)"), [:])
        }
        let body = (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id!, "result": result])) ?? Self.rpcError(id, -32603, "unserializable result")
        return (200, body, ["Mcp-Session-Id": "browserskills"])
    }

    nonisolated static func rpcError(_ id: Any?, _ code: Int, _ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])) ?? Data()
    }
}

/// A complete HTTP/1.1 request, or nil while more bytes are needed.
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<sep.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var h: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            h[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(h["content-length"] ?? "0") ?? 0
        let bodyStart = sep.upperBound
        guard data.count - bodyStart >= length else { return nil }
        method = String(start[0]); path = String(start[1]); headers = h
        body = data.subdata(in: bodyStart..<(bodyStart + length))
    }
}
