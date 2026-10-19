import Foundation
import Testing
@testable import GleanerCore
import GleanerRetrievalExperiments

/// Opt-in synthetic cost experiment; no production behavior and no process-RSS assertion.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GLEANER_CYCLE2_MEASURE"] == "1"))
struct OriginalResolutionMeasurements {
    struct Measurement: Codable {
        var mode: String
        var fileBytes: Int
        var hashByteLimit: Int64
        var state: String
        var elapsedNanoseconds: [UInt64]
        var bytesRead: [UInt64]
        var medianNanoseconds: UInt64
    }

    struct Report: Codable {
        var kind = "synthetic_current_original_cost"
        var platform: String
        var fixture = "deterministic repeated-byte files; one listed folder member per size"
        var cacheConditions = "Five repeated reads of the same newly written file; cache warmth is uncontrolled. No cold-cache claim."
        var setupExcluded = true
        var processResidentMemoryMeasured = false
        var readBufferBytes = 256 << 10
        var memoryNote = "A 256 KiB buffer plus a temporary Data copy up to 256 KiB; no measured process-memory bound."
        var measurements: [Measurement]
    }

    @Test func measureOriginalModes() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("gleaner-original-cost-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let resultsDirectory = try #require(ProcessInfo.processInfo.environment["GLEANER_CYCLE2_RESULTS_DIR"])
        var measurements: [Measurement] = []

        for size in [4 << 10, 1 << 20, 16 << 20] {
            let original = root.appendingPathComponent("current-\(size).bin")
            try Data(repeating: 0x5A, count: size).write(to: original)
            var delivery = Delivery(id: "synthetic-listed-\(size)", number: 1, path: original.path,
                                    deliveredAt: Date(timeIntervalSince1970: 100), replyLine: 4, provider: .codex,
                                    cwd: root.path, evidence: [], logPath: root.appendingPathComponent("synthetic.jsonl").path,
                                    capture: Capture(sha256: nil, size: Int64(size), modifiedAt: nil,
                                                     observedAt: Date(timeIntervalSince1970: 101), savedAt: nil,
                                                     provenance: .listed, kind: .file))
            delivery.member = Membership(folderDelivery: "synthetic-folder", folder: root.path)
            for mode in OriginalResolutionExperiment.Mode.allCases {
                var times: [UInt64] = [], reads: [UInt64] = []
                var state = ""
                for _ in 0..<5 {
                    let result = OriginalResolutionExperiment.resolve(delivery: delivery, mode: mode, authorizedRoots: [root])
                    let expected: OriginalResolutionExperiment.State = switch mode {
                    case .pathOnly: .unverifiedPath
                    case .metadata: .metadataOnly
                    case .hashCurrent: .hashedCurrent
                    }
                    #expect(result.current.state == expected)
                    #expect(result.capturedSha256 == nil && result.captureState == .listed && result.evidenceKind == .folderMember)
                    #expect(result.bytesRead == (mode == .hashCurrent ? UInt64(size) : 0))
                    times.append(result.elapsedNanoseconds)
                    reads.append(result.bytesRead)
                    state = result.current.state.rawValue
                }
                measurements.append(Measurement(mode: mode.rawValue, fileBytes: size, hashByteLimit: 64 << 20,
                                                state: state, elapsedNanoseconds: times, bytesRead: reads,
                                                medianNanoseconds: times.sorted()[times.count / 2]))
            }
            if size == 16 << 20 {
                let result = OriginalResolutionExperiment.resolve(delivery: delivery, mode: .hashCurrent,
                                                                  authorizedRoots: [root], hashByteLimit: 1 << 20)
                #expect(result.current.state == .hashLimitExceeded && result.bytesRead == 0)
                measurements.append(Measurement(mode: "hash_current_oversize", fileBytes: size, hashByteLimit: 1 << 20,
                                                state: result.current.state.rawValue,
                                                elapsedNanoseconds: [result.elapsedNanoseconds], bytesRead: [result.bytesRead],
                                                medianNanoseconds: result.elapsedNanoseconds))
            }
        }
        #if os(Linux)
        let platform = "linux"
        #else
        let platform = "macos"
        #endif
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let output = URL(fileURLWithPath: resultsDirectory).appendingPathComponent("original-cost-results.json")
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(Report(platform: platform, measurements: measurements)).write(to: output)
    }
}
