// Licensed under GPL-3.0. See LICENSE.
//
//  SkillStoreTests.swift
//  BrowserSkillsTests
//
//  SQLite round trips against a temporary directory: skills, versions, promotion, runs, traces, memory.
//

import Foundation
import XCTest
@testable import BrowserSkills

@MainActor
final class SkillStoreTests: XCTestCase {
    private var dir: URL!
    private var store: SkillStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("browserskills-store-\(UUID().uuidString)", isDirectory: true)
        store = SkillStore(directory: dir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func workflow(name: String = "order_status", title: String = "Order status", origin: String = "http://127.0.0.1:4318") -> Workflow {
        Workflow(name: name, title: title, description: "d", origin: origin,
                 inputs: [WorkflowInput(name: "order_number", description: "Order number", example: "A-1042")],
                 steps: [WorkflowStep(kind: .navigate, url: "\(origin)/orders"),
                         WorkflowStep(kind: .fill, target: ElementTarget(selector: "#order", fallbacks: ["input[name=\"order\"]"], label: "Order"), value: "{{order_number}}"),
                         WorkflowStep(kind: .click, target: ElementTarget(selector: "form > button"))],
                 outputs: [WorkflowOutput(name: "status", description: "", selector: "#order-status"),
                           WorkflowOutput(name: "items", description: "", selector: "li", many: true, required: false)],
                 verify: [VerifyCheck(kind: .nonEmpty, output: "status", input: nil)])
    }

    private func run(id: String = UUID().uuidString, skillID: Int64, version: Int, status: RunStatus = .success, purpose: String = "run", started: Date = Date()) -> RunRecord {
        RunRecord(id: id, skillID: skillID, version: version, inputs: ["order_number": "B-77"], status: status,
                  outputs: ["status": .string("Shipped"), "items": .list(["a", "b"]), "missing": .null],
                  log: [StepLog(index: 1, kind: "navigate", ok: true, ms: 120, detail: "opened")],
                  error: status == .success ? nil : "boom", checks: ["status is present"], screenshot: nil, started: started, finished: Date(), purpose: purpose)
    }

    func testCreatesDirectoryAndDatabase() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("artifacts").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("browserskills.sqlite").path))
        XCTAssertEqual(store.skills, [])
    }

    func testAddCandidateCreatesSkillAndVersions() throws {
        let v1 = try store.addCandidate(workflow(), compiler: "fixture")
        XCTAssertEqual(v1.version, 1)
        XCTAssertEqual(v1.status, .candidate)
        XCTAssertEqual(v1.compiler, "fixture")
        XCTAssertEqual(v1.workflow, workflow())
        XCTAssertEqual(store.skills.map(\.name), ["order_status"])
        let skill = store.skill(named: "order_status")!
        XCTAssertEqual(skill.id, v1.skillID)
        XCTAssertEqual(skill.title, "Order status")
        XCTAssertEqual(skill.origin, "http://127.0.0.1:4318")
        XCTAssertNil(skill.activeVersion)
        XCTAssertNil(store.activeVersion(of: skill), "candidates never run")

        let v2 = try store.addCandidate(workflow(title: "Order status v2"), compiler: "nemotron:test")
        XCTAssertEqual(v2.version, 2)
        XCTAssertEqual(v2.skillID, v1.skillID)
        XCTAssertEqual(store.skills.count, 1)
        XCTAssertEqual(store.skill(named: "order_status")?.title, "Order status v2")
        XCTAssertEqual(store.versions(skillID: v1.skillID).map(\.version), [2, 1])
        XCTAssertNil(store.skill(named: "nope"))
    }

    func testSameNameOnAnotherOriginIsAConflict() throws {
        _ = try store.addCandidate(workflow(), compiler: "fixture")
        XCTAssertThrowsError(try store.addCandidate(workflow(origin: "https://shop.example"), compiler: "fixture")) { error in
            XCTAssertTrue(error.localizedDescription.contains("already exists"), error.localizedDescription)
        }
        XCTAssertEqual(store.versions(skillID: store.skills[0].id).count, 1)
    }

    func testPromotionPinsTheActiveVersion() throws {
        let v1 = try store.addCandidate(workflow(), compiler: "fixture")
        let v2 = try store.addCandidate(workflow(title: "second"), compiler: "fixture")
        store.setStatus(.validated, skillID: v1.skillID, version: v1.version)
        XCTAssertEqual(store.skills[0].activeVersion, 1)
        XCTAssertEqual(store.activeVersion(of: store.skills[0])?.version, 1)

        store.setStatus(.failedValidation, skillID: v2.skillID, version: v2.version)
        XCTAssertEqual(store.skills[0].activeVersion, 1, "a failed candidate does not move the pin")
        XCTAssertEqual(store.versions(skillID: v1.skillID).first { $0.version == 2 }?.status, .failedValidation)

        store.setStatus(.validated, skillID: v2.skillID, version: v2.version)
        XCTAssertEqual(store.activeVersion(of: store.skills[0])?.version, 2)
        XCTAssertEqual(store.activeVersion(of: store.skills[0])?.workflow.title, "second")

        let v3 = try store.addCandidate(workflow(title: "third"), compiler: "fixture")
        XCTAssertEqual(v3.version, 3)
        XCTAssertEqual(store.activeVersion(of: store.skills[0])?.version, 2, "new candidates do not replace the active version")
    }

    func testRunRoundTripAndListing() throws {
        let v = try store.addCandidate(workflow(), compiler: "fixture")
        let earlier = run(id: "run-1", skillID: v.skillID, version: 1, started: Date(timeIntervalSinceNow: -60))
        store.insertRun(earlier)
        var later = run(id: "run-2", skillID: v.skillID, version: 1, status: .running)
        later.finished = nil
        store.insertRun(later, dedupeKey: "k")

        let got = store.run(id: "run-1")
        XCTAssertEqual(got?.inputs, ["order_number": "B-77"])
        XCTAssertEqual(got?.outputs["status"], .string("Shipped"))
        XCTAssertEqual(got?.outputs["items"], .list(["a", "b"]))
        XCTAssertEqual(got?.outputs["missing"], .null)
        XCTAssertEqual(got?.log, earlier.log)
        XCTAssertEqual(got?.checks, ["status is present"])
        XCTAssertEqual(got?.status, .success)
        XCTAssertEqual(got?.purpose, "run")
        XCTAssertNil(got?.error)
        XCTAssertNotNil(got?.finished)
        XCTAssertEqual(got.map { Int($0.started.timeIntervalSince1970) }, Int(earlier.started.timeIntervalSince1970))
        XCTAssertNil(store.run(id: "run-2")?.finished)
        XCTAssertNil(store.run(id: "nope"))

        XCTAssertEqual(store.runs(skillID: v.skillID).map(\.id), ["run-2", "run-1"], "newest first")
        XCTAssertEqual(store.runs(skillID: v.skillID, limit: 1).map(\.id), ["run-2"])
        XCTAssertEqual(store.recentRuns().map(\.id), ["run-2", "run-1"])

        later.status = .failed; later.error = "step 2 failed"; later.finished = Date(); later.screenshot = "/tmp/x.png"
        let revision = store.revision
        store.updateRun(later)
        XCTAssertGreaterThan(store.revision, revision)
        XCTAssertEqual(store.run(id: "run-2")?.status, .failed)
        XCTAssertEqual(store.run(id: "run-2")?.error, "step 2 failed")
        XCTAssertEqual(store.run(id: "run-2")?.screenshot, "/tmp/x.png")
    }

    func testDedupeFindsRecentRunsByKey() throws {
        let v = try store.addCandidate(workflow(), compiler: "fixture")
        store.insertRun(run(id: "old", skillID: v.skillID, version: 1, started: Date(timeIntervalSinceNow: -30)), dedupeKey: "k")
        XCTAssertNil(store.recentRun(dedupeKey: "k", within: 10))
        XCTAssertEqual(store.recentRun(dedupeKey: "k", within: 60)?.id, "old")
        store.insertRun(run(id: "new", skillID: v.skillID, version: 1), dedupeKey: "k")
        XCTAssertEqual(store.recentRun(dedupeKey: "k", within: 10)?.id, "new")
        XCTAssertNil(store.recentRun(dedupeKey: "other", within: 60))
    }

    func testDeleteCascadesToVersionsAndRuns() throws {
        let v = try store.addCandidate(workflow(), compiler: "fixture")
        store.insertRun(run(id: "r", skillID: v.skillID, version: 1))
        store.delete(skillID: v.skillID)
        XCTAssertEqual(store.skills, [])
        XCTAssertEqual(store.versions(skillID: v.skillID), [])
        XCTAssertNil(store.run(id: "r"))
    }

    func testReopeningKeepsDataAndMarksInFlightRunsInterrupted() throws {
        let v = try store.addCandidate(workflow(), compiler: "fixture")
        store.setStatus(.validated, skillID: v.skillID, version: 1)
        store.insertRun(run(id: "flying", skillID: v.skillID, version: 1, status: .running))
        store.insertRun(run(id: "done", skillID: v.skillID, version: 1))
        store = nil

        let reopened = SkillStore(directory: dir)
        XCTAssertEqual(reopened.skills.map(\.name), ["order_status"])
        XCTAssertEqual(reopened.activeVersion(of: reopened.skills[0])?.version, 1)
        XCTAssertEqual(reopened.run(id: "flying")?.status, .interrupted)
        XCTAssertNotNil(reopened.run(id: "flying")?.finished)
        XCTAssertEqual(reopened.run(id: "done")?.status, .success)
        store = reopened
    }

    func testTracesAndMemory() {
        let action = RecordedAction(type: "fill", url: "http://x.test/", selector: "#q", value: "v")
        store.addTrace(origin: "http://x.test", signature: "sig", actions: [action])
        store.addTrace(origin: "http://x.test", signature: "sig", actions: [action])
        store.addTrace(origin: "http://x.test", signature: "other", actions: [action])
        XCTAssertEqual(store.traces(origin: "http://x.test", signature: "sig").count, 2)
        XCTAssertEqual(store.traces(origin: "http://x.test", signature: "sig").first?.first?.value, "v")
        XCTAssertEqual(store.traces(origin: "http://y.test", signature: "sig").count, 0)

        XCTAssertNil(store.recall("k"))
        store.remember("k", "v1")
        store.remember("k", "v2")
        XCTAssertEqual(store.recall("k"), "v2")

        store.resetAll()
        XCTAssertEqual(store.traces(origin: "http://x.test", signature: "sig").count, 0)
        XCTAssertNil(store.recall("k"))
    }

    func testJSONValueCodingAndText() throws {
        let values: [JSONValue] = [.string("a"), .list(["x", "y"]), .null]
        let data = try JSONEncoder().encode(values)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["a",["x","y"],null]"#)
        XCTAssertEqual(try JSONDecoder().decode([JSONValue].self, from: data), values)
        XCTAssertEqual(JSONValue.list(["x", "y"]).text, "x, y")
        XCTAssertTrue(JSONValue.string("  ").isEmpty)
        XCTAssertTrue(JSONValue.list([]).isEmpty)
        XCTAssertFalse(JSONValue.string("s").isEmpty)
        XCTAssertEqual(JSONValue(any: ["a", 1, "b"]), .list(["a", "b"]))
        XCTAssertEqual(JSONValue(any: 3), .null)
    }
}
