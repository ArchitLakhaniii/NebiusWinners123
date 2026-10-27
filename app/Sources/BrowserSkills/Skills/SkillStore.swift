// Licensed under GPL-3.0. See LICENSE.
//
//  SkillStore.swift
//  BrowserSkills
//
//  SQLite registry: skills, their versions (candidate or validated), runs with evidence,
//  repeated-procedure traces, and a small procedural memory.
//

import Foundation
import SQLite3

enum VersionStatus: String, Codable { case candidate, validated, failedValidation = "failed_validation" }

enum RunStatus: String, Codable, CaseIterable {
    case queued, running, verifying, success, failed, needsLogin = "needs_login", needsReview = "needs_review", cancelled, interrupted
    var isTerminal: Bool { ![.queued, .running, .verifying].contains(self) }
}

struct SkillVersion: Identifiable, Hashable {
    var id: Int64
    var skillID: Int64
    var version: Int
    var workflow: Workflow
    var status: VersionStatus
    var compiler: String          // e.g. "nemotron:nvidia/nemotron-3-super-120b-a12b" or "fixture"
    var created: Date
}

struct Skill: Identifiable, Hashable {
    var id: Int64
    var name: String
    var title: String
    var origin: String
    var activeVersion: Int?
    var created: Date
}

struct StepLog: Codable, Hashable {
    var index: Int
    var kind: String
    var ok: Bool
    var ms: Int
    var detail: String
}

struct RunRecord: Identifiable, Hashable {
    var id: String
    var skillID: Int64
    var version: Int
    var inputs: [String: String]
    var status: RunStatus
    var outputs: [String: JSONValue]
    var log: [StepLog]
    var error: String?
    var checks: [String]
    var screenshot: String?
    var started: Date
    var finished: Date?
    var purpose: String           // "run", "validation"
}

/// Minimal JSON value so outputs (strings or string lists) round-trip through SQLite and MCP.
enum JSONValue: Codable, Hashable {
    case string(String), list([String]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null } else if let s = try? c.decode(String.self) { self = .string(s) } else { self = .list(try c.decode([String].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let s): try c.encode(s); case .list(let l): try c.encode(l); case .null: try c.encodeNil() }
    }
    init(any: Any?) {
        if let s = any as? String { self = .string(s) } else if let l = any as? [Any] { self = .list(l.compactMap { $0 as? String }) } else { self = .null }
    }
    var any: Any { switch self { case .string(let s): return s; case .list(let l): return l; case .null: return NSNull() } }
    var text: String { switch self { case .string(let s): return s; case .list(let l): return l.joined(separator: ", "); case .null: return "" } }
    var isEmpty: Bool { switch self { case .string(let s): return s.trimmingCharacters(in: .whitespaces).isEmpty; case .list(let l): return l.isEmpty; case .null: return true } }
}

@MainActor
final class SkillStore: ObservableObject {
    @Published private(set) var skills: [Skill] = []
    @Published private(set) var revision = 0

    private var db: OpaquePointer?
    let directory: URL

    nonisolated static func defaultDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["BROWSERSKILLS_HOME"] { return URL(fileURLWithPath: override, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BrowserSkills", isDirectory: true)
    }

    init(directory: URL = SkillStore.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory.appendingPathComponent("artifacts"), withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("browserskills.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK { fatalError("cannot open \(path)") }
        exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
        exec("""
        CREATE TABLE IF NOT EXISTS skills (id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, title TEXT NOT NULL, origin TEXT NOT NULL,
          active_version INTEGER, created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS versions (id INTEGER PRIMARY KEY, skill_id INTEGER NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
          version INTEGER NOT NULL, workflow TEXT NOT NULL, status TEXT NOT NULL, compiler TEXT NOT NULL, created REAL NOT NULL,
          UNIQUE(skill_id, version));
        CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY, skill_id INTEGER NOT NULL REFERENCES skills(id) ON DELETE CASCADE, version INTEGER NOT NULL,
          inputs TEXT NOT NULL, status TEXT NOT NULL, outputs TEXT NOT NULL, log TEXT NOT NULL, error TEXT, checks TEXT NOT NULL,
          screenshot TEXT, started REAL NOT NULL, finished REAL, purpose TEXT NOT NULL, dedupe_key TEXT);
        CREATE TABLE IF NOT EXISTS traces (id INTEGER PRIMARY KEY, origin TEXT NOT NULL, signature TEXT NOT NULL, actions TEXT NOT NULL, created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS memory (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated REAL NOT NULL);
        """)
        // A run that was in flight when the app quit cannot be trusted: mark it interrupted.
        exec("UPDATE runs SET status='interrupted', finished=\(Date().timeIntervalSince1970) WHERE status IN ('queued','running','verifying')")
        reload()
    }

    deinit { sqlite3_close_v2(db) }

    // MARK: Skills and versions

    func reload() {
        skills = query("SELECT id, name, title, origin, active_version, created FROM skills ORDER BY created DESC") { s in
            Skill(id: s.int64(0), name: s.text(1), title: s.text(2), origin: s.text(3), activeVersion: s.isNull(4) ? nil : Int(s.int64(4)), created: s.date(5))
        }
        revision += 1
    }

    /// Stores a compiled workflow as the next candidate version, creating the skill when new.
    @discardableResult
    func addCandidate(_ workflow: Workflow, compiler: String) throws -> SkillVersion {
        let json = String(data: try JSONEncoder().encode(workflow), encoding: .utf8)!
        let now = Date().timeIntervalSince1970
        let skillID: Int64
        exec("BEGIN")
        if let existing = skills.first(where: { $0.name == workflow.name }) {
            guard existing.origin == workflow.origin else {
                exec("ROLLBACK")
                throw StoreError.conflict("skill \(workflow.name) already exists for \(existing.origin)")
            }
            skillID = existing.id
            run("UPDATE skills SET title=? WHERE id=?", [workflow.title, skillID])
        } else {
            guard run("INSERT INTO skills (name, title, origin, created) VALUES (?, ?, ?, ?)", [workflow.name, workflow.title, workflow.origin, now]) else {
                exec("ROLLBACK")
                throw StoreError.failed("could not create skill \(workflow.name): \(lastError)")
            }
            skillID = sqlite3_last_insert_rowid(db)
        }
        let next = (query("SELECT MAX(version) FROM versions WHERE skill_id=?", [skillID]) { $0.isNull(0) ? 0 : Int($0.int64(0)) }.first ?? 0) + 1
        guard run("INSERT INTO versions (skill_id, version, workflow, status, compiler, created) VALUES (?, ?, ?, ?, ?, ?)",
                  [skillID, next, json, VersionStatus.candidate.rawValue, compiler, now]) else {
            exec("ROLLBACK")
            throw StoreError.failed("could not store version \(next) of \(workflow.name): \(lastError)")
        }
        exec("COMMIT")
        reload()
        guard let version = versions(skillID: skillID).first(where: { $0.version == next }) else {
            throw StoreError.failed("stored version \(next) of \(workflow.name) does not decode")
        }
        return version
    }

    /// Versions whose stored workflow no longer decodes (schema drift) are skipped rather than crashing the app.
    func versions(skillID: Int64) -> [SkillVersion] {
        query("SELECT id, skill_id, version, workflow, status, compiler, created FROM versions WHERE skill_id=? ORDER BY version DESC", [skillID]) { s -> SkillVersion? in
            guard let workflow = try? JSONDecoder().decode(Workflow.self, from: Data(s.text(3).utf8)) else {
                NSLog("BrowserSkills: skipping undecodable version %lld of skill %lld", s.int64(2), s.int64(1)); return nil
            }
            return SkillVersion(id: s.int64(0), skillID: s.int64(1), version: Int(s.int64(2)), workflow: workflow,
                                status: VersionStatus(rawValue: s.text(4)) ?? .candidate, compiler: s.text(5), created: s.date(6))
        }.compactMap { $0 }
    }

    func setStatus(_ status: VersionStatus, skillID: Int64, version: Int) {
        run("UPDATE versions SET status=? WHERE skill_id=? AND version=?", [status.rawValue, skillID, version])
        if status == .validated { run("UPDATE skills SET active_version=? WHERE id=?", [version, skillID]) }
        reload()
    }

    /// The pinned version a run uses: the active validated version.
    func activeVersion(of skill: Skill) -> SkillVersion? {
        guard let v = skill.activeVersion else { return nil }
        return versions(skillID: skill.id).first { $0.version == v && $0.status == .validated }
    }

    func skill(named name: String) -> Skill? { skills.first { $0.name == name } }

    func delete(skillID: Int64) {
        run("DELETE FROM skills WHERE id=?", [skillID])
        reload()
    }

    // MARK: Runs

    func insertRun(_ r: RunRecord, dedupeKey: String? = nil) {
        run("""
        INSERT INTO runs (id, skill_id, version, inputs, status, outputs, log, error, checks, screenshot, started, finished, purpose, dedupe_key)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [r.id, r.skillID, r.version, Self.json(r.inputs), r.status.rawValue, Self.json(r.outputs), Self.json(r.log), r.error,
              Self.json(r.checks), r.screenshot, r.started.timeIntervalSince1970, r.finished?.timeIntervalSince1970, r.purpose, dedupeKey])
        revision += 1
    }

    func updateRun(_ r: RunRecord) {
        run("UPDATE runs SET status=?, outputs=?, log=?, error=?, checks=?, screenshot=?, finished=? WHERE id=?",
            [r.status.rawValue, Self.json(r.outputs), Self.json(r.log), r.error, Self.json(r.checks), r.screenshot, r.finished?.timeIntervalSince1970, r.id])
        revision += 1
    }

    /// A recent run with the same dedupe key, so a client retrying a call does not run the procedure twice.
    func recentRun(dedupeKey: String, within seconds: TimeInterval) -> RunRecord? {
        runs(where: "dedupe_key=? AND started>?", [dedupeKey, Date().timeIntervalSince1970 - seconds]).first
    }

    func run(id: String) -> RunRecord? { runs(where: "id=?", [id]).first }

    func runs(skillID: Int64, limit: Int = 20) -> [RunRecord] { runs(where: "skill_id=?", [skillID], limit: limit) }

    func recentRuns(limit: Int = 30) -> [RunRecord] { runs(where: "1=1", [], limit: limit) }

    private func runs(where clause: String, _ args: [Any?], limit: Int = 50) -> [RunRecord] {
        query("SELECT id, skill_id, version, inputs, status, outputs, log, error, checks, screenshot, started, finished, purpose FROM runs WHERE \(clause) ORDER BY started DESC LIMIT \(limit)", args) { s in
            RunRecord(id: s.text(0), skillID: s.int64(1), version: Int(s.int64(2)),
                      inputs: Self.decode(s.text(3)) ?? [:], status: RunStatus(rawValue: s.text(4)) ?? .failed,
                      outputs: Self.decode(s.text(5)) ?? [:], log: Self.decode(s.text(6)) ?? [], error: s.isNull(7) ? nil : s.text(7),
                      checks: Self.decode(s.text(8)) ?? [], screenshot: s.isNull(9) ? nil : s.text(9), started: s.date(10),
                      finished: s.isNull(11) ? nil : s.date(11), purpose: s.text(12))
        }
    }

    // MARK: Traces (repeat detection) and memory

    func addTrace(origin: String, signature: String, actions: [RecordedAction]) {
        // Values of secret fields never reach the recorder, so they are not stored here either.
        run("INSERT INTO traces (origin, signature, actions, created) VALUES (?, ?, ?, ?)",
            [origin, signature, Self.json(actions), Date().timeIntervalSince1970])
        // Raw examples expire: keep a week, at most 200.
        run("DELETE FROM traces WHERE created < ? OR id NOT IN (SELECT id FROM traces ORDER BY created DESC LIMIT 200)",
            [Date().timeIntervalSince1970 - 7 * 86400])
    }

    func traces(origin: String, signature: String) -> [[RecordedAction]] {
        query("SELECT actions FROM traces WHERE origin=? AND signature=? ORDER BY created DESC LIMIT 5", [origin, signature]) { s in
            Self.decode(s.text(0)) ?? []
        }
    }

    func remember(_ key: String, _ value: String) {
        run("INSERT INTO memory (key, value, updated) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated=excluded.updated",
            [key, value, Date().timeIntervalSince1970])
    }

    func recall(_ key: String) -> String? { query("SELECT value FROM memory WHERE key=?", [key]) { $0.text(0) }.first }

    func resetAll() {
        exec("DELETE FROM runs; DELETE FROM versions; DELETE FROM skills; DELETE FROM traces; DELETE FROM memory;")
        reload()
    }

    // MARK: SQLite plumbing

    enum StoreError: LocalizedError {
        case conflict(String), failed(String)
        var errorDescription: String? { switch self { case .conflict(let m), .failed(let m): return m } }
    }

    private var lastError: String { String(cString: sqlite3_errmsg(db)) }

    static func json<T: Encodable>(_ value: T) -> String { String(data: (try? JSONEncoder().encode(value)) ?? Data("null".utf8), encoding: .utf8)! }
    static func decode<T: Decodable>(_ text: String) -> T? { try? JSONDecoder().decode(T.self, from: Data(text.utf8)) }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK { NSLog("BrowserSkills sqlite: %@", String(cString: err!)); sqlite3_free(err) }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func prepare(_ sql: String, _ args: [Any?]) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("BrowserSkills sqlite prepare: %@ %@", String(cString: sqlite3_errmsg(db)), sql); return nil
        }
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg {
            case nil: sqlite3_bind_null(stmt, idx)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, Self.transient)
            default: sqlite3_bind_text(stmt, idx, "\(arg!)", -1, Self.transient)
            }
        }
        return stmt
    }

    @discardableResult
    private func run(_ sql: String, _ args: [Any?]) -> Bool {
        guard let stmt = prepare(sql, args) else { return false }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { NSLog("BrowserSkills sqlite step: %@", lastError); return false }
        return true
    }

    private func query<T>(_ sql: String, _ args: [Any?] = [], _ row: (Row) -> T) -> [T] {
        guard let stmt = prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(row(Row(stmt: stmt))) }
        return out
    }

    struct Row {
        let stmt: OpaquePointer?
        func int64(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func text(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
        func date(_ i: Int32) -> Date { Date(timeIntervalSince1970: sqlite3_column_double(stmt, i)) }
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
    }
}
