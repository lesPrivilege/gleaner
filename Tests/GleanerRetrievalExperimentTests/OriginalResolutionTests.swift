import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import GleanerCore
@testable import GleanerRetrievalExperiments

@Suite struct OriginalResolutionTests {
    private final class Fixture {
        let root: URL
        let original: URL
        init(bytes: Data = Data("current synthetic report".utf8)) throws {
            // Foundation resolvingSymlinksInPath can shorten /private/var back to /var.
            // POSIX realpath supplies the physical spelling required by the strict nofollow walk.
            let physical = try #require(realpath(FileManager.default.temporaryDirectory.path, nil))
            defer { free(physical) }
            root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
                .appendingPathComponent("gleaner-original-experiment-\(UUID().uuidString)")
            original = root.appendingPathComponent("out/report.md")
            try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: original)
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        func delivery(path: String? = nil, captured: String? = nil) -> Delivery {
            let path = path ?? original.path
            return Delivery(id: "synthetic-delivery", number: 1, path: path,
                            deliveredAt: Date(timeIntervalSince1970: 100), replyLine: 8, provider: .codex,
                            sessionID: "synthetic-session", request: "Write the report", cwd: root.path,
                            evidence: [Evidence(line: 8, syntax: "link", rawTarget: "out/report.md", anchor: "#R1", excerpt: "The report is ready.")],
                            logPath: root.appendingPathComponent("synthetic-log.jsonl").path,
                            capture: Capture(sha256: captured, size: nil, modifiedAt: nil,
                                             observedAt: Date(timeIntervalSince1970: 101), savedAt: nil,
                                             provenance: captured == nil ? .listed : .firstSeenAfterDelivery, kind: .file))
        }

        func resolve(_ delivery: Delivery? = nil, mode: OriginalResolutionExperiment.Mode = .hashCurrent,
                     limit: Int64 = 64 << 20) -> OriginalResolutionExperiment.Result {
            OriginalResolutionExperiment.resolve(delivery: delivery ?? self.delivery(), mode: mode,
                                                  authorizedRoots: [root], hashByteLimit: limit)
        }
    }

    @Test func modesKeepListingAndCurrentObservationSeparate() throws {
        let fixture = try Fixture()
        var delivery = fixture.delivery()
        delivery.member = Membership(folderDelivery: "synthetic-folder", folder: fixture.original.deletingLastPathComponent().path)
        for mode in OriginalResolutionExperiment.Mode.allCases {
            let result = fixture.resolve(delivery, mode: mode)
            #expect(result.evidenceKind == .folderMember && result.folderDeliveryID == "synthetic-folder")
            #expect(result.captureState == .listed && result.capturedSha256 == nil)
            #expect(result.evidence == delivery.evidence && result.sessionID == delivery.sessionID)
            #expect(result.current.matchesCapturedBytes == nil)
            switch mode {
            case .pathOnly:
                #expect(result.current.state == .unverifiedPath && result.current.observedAt == nil)
                #expect(result.current.metadata == nil && result.bytesRead == 0)
            case .metadata:
                #expect(result.current.state == .metadataOnly && result.current.observedAt != nil)
                #expect(result.current.observedCurrentSha256 == nil && result.bytesRead == 0)
            case .hashCurrent:
                #expect(result.current.state == .hashedCurrent && result.current.observedAt != nil)
                #expect(result.current.observedCurrentSha256 == Locator.sha256(fixture.original.path))
                #expect(result.bytesRead == UInt64(try #require(result.current.metadata?.size)))
            }
        }
        #expect(delivery.capture?.provenance == .listed && delivery.sha256 == nil)
    }

    @Test func aCurrentHashDoesNotReplaceCapturedBytesOrChangeEvidenceKind() throws {
        let fixture = try Fixture()
        let captured = try #require(Locator.sha256(fixture.original.path))
        let delivery = fixture.delivery(captured: captured)
        try Data("another revision".utf8).write(to: fixture.original)
        let result = fixture.resolve(delivery)
        #expect(result.evidenceKind == .explicitDelivery && result.captureState == .firstSeenAfterDelivery)
        #expect(result.capturedSha256 == captured && result.current.matchesCapturedBytes == false)
        #expect(result.current.observedCurrentSha256 != result.capturedSha256)
        var kept = fixture.delivery()
        kept.kept = Keeping(keptAt: Date(timeIntervalSince1970: 200), observed: .changed)
        kept.evidence = []
        let keptResult = fixture.resolve(kept)
        #expect(keptResult.evidenceKind == .kept && keptResult.evidence.isEmpty)
        #expect(keptResult.keptAt == kept.kept?.keptAt && keptResult.captureState == .listed)
    }

    @Test func matchingHashStillPreservesBackfillProvenance() throws {
        let fixture = try Fixture()
        let result = fixture.resolve(fixture.delivery(captured: try #require(Locator.sha256(fixture.original.path))))
        #expect(result.current.matchesCapturedBytes == true)
        #expect(result.captureState == .firstSeenAfterDelivery)
    }

    @Test func movedOriginalsAreNotRediscoveredOrCalledUsableByPathOnlyMode() throws {
        let fixture = try Fixture()
        try FileManager.default.moveItem(at: fixture.original, to: fixture.root.appendingPathComponent("moved.md"))
        #expect(fixture.resolve().current.state == .missing)
        let path = fixture.resolve(mode: .pathOnly)
        #expect(path.current.state == .unverifiedPath && path.current.observedCurrentSha256 == nil)
        #expect(path.bytesRead == 0)
    }

    @Test func exactScopeChecksRejectSiblingPrefixesAndNeverTreatDirectoriesAsFiles() throws {
        let fixture = try Fixture()
        let outside = fixture.delivery(path: fixture.root.path + "-neighbor/report.md")
        for mode in OriginalResolutionExperiment.Mode.allCases {
            #expect(fixture.resolve(outside, mode: mode).current.state == .deniedScope)
            #expect(OriginalResolutionExperiment.resolve(delivery: fixture.delivery(), mode: mode, authorizedRoots: []).current.state == .deniedScope)
        }
        #expect(fixture.resolve(fixture.delivery(path: fixture.root.path)).current.state == .notRegular)
        let fifo = fixture.root.appendingPathComponent("pipe")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(fixture.resolve(fixture.delivery(path: fifo.path)).current.state == .notRegular)
    }

    @Test func physicalSpellingIsPreservedAndAliasRootsRemainDenied() throws {
        let fixture = try Fixture()
        let physical = try #require(realpath(fixture.original.path, nil))
        defer { free(physical) }
        #expect(fixture.original.path == String(cString: physical))
        let physicalResult = fixture.resolve()
        #expect(physicalResult.current.path == fixture.original.path)
        #expect(physicalResult.current.state == .hashedCurrent)

        // Portable analogue of a system alias: a known physical directory has a symlink name.
        // Choosing the physical name does not grant permission to follow the alias as a root.
        let alias = fixture.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(atPath: alias.path,
            withDestinationPath: fixture.original.deletingLastPathComponent().path)
        let aliasPath = alias.appendingPathComponent("report.md").path
        let aliasDelivery = fixture.delivery(path: aliasPath)
        let unverified = OriginalResolutionExperiment.resolve(delivery: aliasDelivery, mode: .pathOnly, authorizedRoots: [alias])
        #expect(unverified.current.path == aliasPath && unverified.current.state == .unverifiedPath)
        let checked = OriginalResolutionExperiment.resolve(delivery: aliasDelivery, mode: .hashCurrent, authorizedRoots: [alias])
        #expect(checked.current.state == .deniedScope && checked.bytesRead == 0)

        // Existence is irrelevant to lexical scope. No /private prefix may be removed, and
        // absent originals retain their own spelling instead of borrowing another namespace.
        let absent = "/private/tmp/gleaner-absent-synthetic/part/./report.md"
        let lexical = OriginalResolutionExperiment.resolve(delivery: fixture.delivery(path: absent), mode: .pathOnly,
            authorizedRoots: [URL(fileURLWithPath: "/private/tmp/gleaner-absent-synthetic", isDirectory: true)])
        #expect(lexical.current.path == "/private/tmp/gleaner-absent-synthetic/part/report.md")
        #expect(lexical.current.state == .unverifiedPath && lexical.bytesRead == 0)
    }

    @Test func parentComponentsAreRefusedWithoutReinterpretingSymlinkScope() throws {
        let fixture = try Fixture()
        let outside = try Fixture()
        let link = fixture.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: outside.root.path)
        let parentRoot = URL(fileURLWithPath: fixture.root.path + "/out/..", isDirectory: true)
        #expect(parentRoot.path.split(separator: "/").contains(".."))
        for mode in OriginalResolutionExperiment.Mode.allCases {
            // Even the ordinary, usable parent traversal is refused: the experiment does not
            // decide whether a discarded component might refer to a symlink or another mount.
            for path in [fixture.root.path + "/out/../out/report.md", fixture.root.path + "/link/../out/report.md"] {
                let result = fixture.resolve(fixture.delivery(path: path), mode: mode)
                #expect(result.current.state == .deniedScope && result.bytesRead == 0)
                #expect(result.current.observedCurrentSha256 == nil)
            }
            let result = OriginalResolutionExperiment.resolve(delivery: fixture.delivery(), mode: mode, authorizedRoots: [parentRoot])
            #expect(result.current.state == .deniedScope && result.bytesRead == 0)
        }
    }

    @Test func symbolicLinksAreDeniedIncludingLinksWithinTheRootAndLinksUsedAsRoots() throws {
        let fixture = try Fixture()
        let outside = try Fixture(bytes: Data("outside synthetic material".utf8))
        let fm = FileManager.default
        for (name, target) in [("inside", fixture.original.path), ("outside", outside.original.path)] {
            let link = fixture.root.appendingPathComponent(name)
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: target)
            let result = fixture.resolve(fixture.delivery(path: link.path))
            #expect(result.current.state == .deniedScope && result.bytesRead == 0)
        }
        let linkedDirectory = fixture.root.appendingPathComponent("linked")
        try fm.createSymbolicLink(atPath: linkedDirectory.path, withDestinationPath: outside.root.path)
        let named = fixture.delivery(path: linkedDirectory.appendingPathComponent("out/report.md").path)
        #expect(fixture.resolve(named).current.state == .deniedScope)
        #expect(OriginalResolutionExperiment.resolve(delivery: named, mode: .metadata,
                                                     authorizedRoots: [linkedDirectory]).current.state == .deniedScope)
        // The inexpensive alternative explicitly gives no checked-scope or availability promise.
        #expect(fixture.resolve(named, mode: .pathOnly).current.state == .unverifiedPath)
    }

    @Test(.enabled(if: geteuid() != 0, "Permission checks need a non-root process"))
    func unreadableOriginalIsNotMissing() throws {
        let fixture = try Fixture()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: fixture.original.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.original.path) }
        #expect(fixture.resolve().current.state == .unreadable)
    }

    @Test func inPlaceMutationWithRestoredMtimeDiscardsTheHash() throws {
        let fixture = try Fixture(bytes: Data(repeating: 65, count: 512 << 10))
        let before = try #require(FileStat(fixture.original.path))
        var mutated = false
        let result = OriginalResolutionExperiment.resolve(delivery: fixture.delivery(), mode: .hashCurrent,
            authorizedRoots: [fixture.root], hashByteLimit: 1 << 20, afterChunk: { _ in
                guard !mutated else { return }; mutated = true
                let handle = try! FileHandle(forWritingTo: fixture.original)
                try! handle.seek(toOffset: 300 << 10)
                try! handle.write(contentsOf: Data([66]))
                try! handle.close()
                try! FileManager.default.setAttributes([.modificationDate: before.modifiedAt], ofItemAtPath: fixture.original.path)
            })
        #expect(result.current.state == .changedDuringObservation)
        #expect(result.current.observedCurrentSha256 == nil && result.capturedSha256 == nil)
    }

    @Test func replacementOfThePathDiscardsThePinnedFilesHash() throws {
        let fixture = try Fixture(bytes: Data(repeating: 65, count: 512 << 10))
        var mutated = false
        let result = OriginalResolutionExperiment.resolve(delivery: fixture.delivery(), mode: .hashCurrent,
            authorizedRoots: [fixture.root], hashByteLimit: 1 << 20, afterChunk: { _ in
                guard !mutated else { return }; mutated = true
                try! FileManager.default.moveItem(at: fixture.original, to: fixture.root.appendingPathComponent("old.md"))
                try! Data(repeating: 66, count: 512 << 10).write(to: fixture.original)
            })
        #expect(result.current.state == .changedDuringObservation && result.current.observedCurrentSha256 == nil)
    }

    @Test func parentDirectoryReplacementCannotRedirectTheReadOutsideScope() throws {
        let fixture = try Fixture(bytes: Data(repeating: 65, count: 512 << 10))
        let outside = try Fixture(bytes: Data("outside".utf8))
        var mutated = false
        let result = OriginalResolutionExperiment.resolve(delivery: fixture.delivery(), mode: .hashCurrent,
            authorizedRoots: [fixture.root], hashByteLimit: 1 << 20, afterChunk: { _ in
                guard !mutated else { return }; mutated = true
                let directory = fixture.original.deletingLastPathComponent()
                try! FileManager.default.moveItem(at: directory, to: fixture.root.appendingPathComponent("old-out"))
                try! FileManager.default.createSymbolicLink(atPath: directory.path, withDestinationPath: outside.original.deletingLastPathComponent().path)
            })
        #expect(result.current.state == .deniedScope && result.current.observedCurrentSha256 == nil)
        #expect(result.bytesRead == 512 << 10)
    }

    @Test func concurrentAppendCannotExceedTheByteLimitAndOneSentinel() throws {
        let fixture = try Fixture(bytes: Data(repeating: 65, count: 512 << 10))
        var appended = false
        let result = OriginalResolutionExperiment.resolve(delivery: fixture.delivery(), mode: .hashCurrent,
            authorizedRoots: [fixture.root], hashByteLimit: 512 << 10, afterChunk: { _ in
                guard !appended else { return }; appended = true
                let handle = try! FileHandle(forWritingTo: fixture.original)
                try! handle.seekToEnd()
                try! handle.write(contentsOf: Data(repeating: 66, count: 512 << 10))
                try! handle.close()
            })
        #expect(result.current.state == .hashLimitExceeded && result.current.observedCurrentSha256 == nil)
        #expect(result.bytesRead == (512 << 10) + 1)
        #expect(fixture.resolve(limit: 1).bytesRead == 0)
        let empty = try Fixture(bytes: Data())
        #expect(empty.resolve(limit: 0).current.state == .hashedCurrent)
    }

    @Test func actualListedMemberAndDurableStateAreUntouched() throws {
        let fixture = try Fixture()
        let registry = try Registry(path: fixture.root.appendingPathComponent("registry.sqlite").path)
        let source = fixture.delivery()
        let folder = fixture.original.deletingLastPathComponent().path
        try registry.upsert(SessionInfo(provider: .codex, id: "synthetic-session", cwd: fixture.root.path, logPath: source.logPath))
        try registry.upsertDelivery(id: "folder", sessionID: "synthetic-session", logPath: source.logPath, path: folder,
                                    deliveredAt: source.deliveredAt, replyLine: 8, replyRank: 0, cwd: fixture.root.path,
                                    request: source.request, evidence: source.evidence)
        try registry.addCapture(Capture(sha256: nil, size: nil, modifiedAt: nil, observedAt: Date(), savedAt: nil,
                                        provenance: .firstSeenAfterDelivery, kind: .directory),
                                for: "folder", logPath: source.logPath, path: folder, replyTimes: [])
        let file = try #require(Workspace.file(at: fixture.original.path))
        try registry.record(Unpacking(listedAt: Date(), members: 1, notUnpacked: nil, problems: []),
                            members: [(file: file, provenance: .listed)], of: "folder")
        try registry.correct(.project, subject: fixture.original.path, target: "synthetic-correction", at: Date())
        _ = try registry.record(Review(id: 0, kind: .rejected, path: fixture.original.path, note: "synthetic review",
                                       sha256: "earlier-synthetic-bytes", file: try #require(FileStat(fixture.original.path)), madeAt: Date()))
        let listed = try #require(try registry.artifact(at: fixture.original.path)?.deliveries.first)
        #expect(listed.capture?.provenance == .listed && listed.sha256 == nil)
        let reviews = try registry.reviews(), corrections = try registry.corrections()
        let beforeStat = try #require(FileStat(fixture.original.path))
        func snapshot() throws -> [String: Data] {
            let urls = try #require(FileManager.default.enumerator(at: fixture.root, includingPropertiesForKeys: [.isRegularFileKey]))
            var result: [String: Data] = [:]
            for case let url as URL in urls where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                result[url.path] = try Data(contentsOf: url)
            }
            return result
        }
        let before = try snapshot()
        for mode in OriginalResolutionExperiment.Mode.allCases {
            let result = fixture.resolve(listed, mode: mode)
            #expect(result.captureState == .listed && result.capturedSha256 == nil && result.evidenceKind == .folderMember)
        }
        #expect(try snapshot() == before)
        #expect(FileStat(fixture.original.path)?.isUnchanged(since: beforeStat) == true)
        #expect(try registry.reviews() == reviews && registry.corrections() == corrections)
        #expect(try registry.artifact(at: fixture.original.path)?.deliveries.first?.capture == listed.capture)
    }
}
