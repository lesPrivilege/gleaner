// Proposed regression checks for Opus to run in a disposable macOS test checkout.
// Not compiled or run by this Linux review; expected to expose baseline defects.
import Foundation
import Testing
@testable import GleanerCore

@Suite struct AuditRegressionTests {
    func delivery(path: String, directory: Bool = false) -> Delivery {
        Delivery(id: "synthetic-d1", number: 1, path: path, deliveredAt: Date(), provider: .claudeCode,
                 sessionTitle: "Synthetic", request: "report", cwd: "/synthetic", evidence: [], logPath: "/synthetic/log.jsonl",
                 capture: Capture(sha256: directory ? nil : "h1", size: directory ? nil : 2, modifiedAt: Date(),
                                  observedAt: Date(), savedAt: directory ? nil : Date(), provenance: .atDelivery,
                                  isDirectory: directory))
    }

    @Test func aReplacementFolderMustNotOverrideSavedFileBytes() {
        let d = delivery(path: "/synthetic/report.md")
        let a = Artifact(path: d.path, deliveries: [d])
        let now = FileObservation(state: LocatorState(kind: .directory, git: .notInRepo), checkedAt: Date())
        #expect(a.handoff(d, now: now, hasSaved: { _ in true }) == .ready(sha: "h1", from: .savedCopy, firstSeen: nil))
    }

    @Test func missingFolderMustNotProduceAnEnabledFolderHandoff() {
        let d = delivery(path: "/synthetic/folder", directory: true)
        let a = Artifact(path: d.path, deliveries: [d])
        let now = FileObservation(state: LocatorState(kind: .missing, git: .notInRepo), checkedAt: Date())
        #expect(a.handoff(d, now: now, hasSaved: { _ in false }) == .lost)
    }

    @Test func anUnclosedCodeFenceStillMeansExample() {
        let turn = Turn(request: nil, parts: [ReplyPart(text: "Example:\n```sh\ncat /tmp/out/report.md\n", line: 1, at: nil, cwd: "/synthetic")])
        #expect(MentionExtractor.candidates(in: turn).filter(Admission.admits).isEmpty)
    }

    @Test func partialMalformedRereadMustPreserveAnEarlierCapture() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("gleaner-audit-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let sources = LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex"))
        let logs = sources.claudeProjects.appendingPathComponent("project")
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        let output = root.appendingPathComponent("report.md")
        try "original bytes".write(to: output, atomically: true, encoding: .utf8)
        let log = logs.appendingPathComponent("audit.jsonl")
        let record: [String: Any] = ["type": "assistant", "sessionId": "synthetic-audit", "cwd": root.path,
            "timestamp": "2026-10-17T00:00:00Z", "message": ["model": "synthetic-test", "content": [["type": "text", "text": "[report](\(output.path))"]]]]
        let good = try JSONSerialization.data(withJSONObject: record)
        try good.write(to: log)
        let registry = try Registry(path: root.appendingPathComponent("registry.sqlite").path)
        let store = ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging"))
        let indexer = Indexer(registry: registry, store: store, sources: sources)
        _ = try indexer.run()
        let before = try #require(registry.artifacts().first?.latest.capture)
        try "{malformed\n".write(to: log, atomically: true, encoding: .utf8)
        _ = try indexer.run()
        #expect(try registry.artifacts().first?.latest.capture == before)
    }
}
