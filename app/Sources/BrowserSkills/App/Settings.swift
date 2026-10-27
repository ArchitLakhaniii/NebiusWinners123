// Licensed under GPL-3.0. See LICENSE.
//
//  Settings.swift
//  BrowserSkills
//
//  Local configuration in a 0600 file. Environment variables override it so scripts can run
//  the app without touching the file. The API key is never logged or sent anywhere but the
//  configured HTTPS endpoint.
//

import Foundation

struct AppSettings: Codable, Equatable {
    var apiKey = ""
    var baseURL = "https://api.tokenfactory.nebius.com/v1"
    /// Reasoning-heavy work: compiling a demonstration into a workflow.
    var compilerModel = "nvidia/nemotron-3-super-120b-a12b"
    /// Fast everyday calls: the assistant's tool-calling loop.
    var assistantModel = "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B"
    var tavilyKey = ""
    var mcpPort = 4317
    /// Development only: compile without a model. Runs are labeled "fixture" everywhere.
    var allowFixtureCompiler = true

    static func fileURL(in dir: URL) -> URL { dir.appendingPathComponent("settings.json") }

    static func load(from dir: URL) -> AppSettings {
        var s = (try? Data(contentsOf: fileURL(in: dir))).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
        let env = ProcessInfo.processInfo.environment
        if let v = env["NEBIUS_API_KEY"], !v.isEmpty { s.apiKey = v }
        if let v = env["NEBIUS_BASE_URL"], !v.isEmpty { s.baseURL = v }
        if let v = env["NEMOTRON_COMPILER_MODEL"], !v.isEmpty { s.compilerModel = v }
        if let v = env["NEMOTRON_ASSISTANT_MODEL"], !v.isEmpty { s.assistantModel = v }
        if let v = env["TAVILY_API_KEY"], !v.isEmpty { s.tavilyKey = v }
        if let v = env["BROWSERSKILLS_MCP_PORT"], let p = Int(v) { s.mcpPort = p }
        return s
    }

    func save(to dir: URL) {
        let url = Self.fileURL(in: dir)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    var hasModel: Bool { !apiKey.isEmpty }
}
