import Foundation
import Testing
@testable import GleanerCore

/// Synthetic capture regressions. These exercise the shared extractor and ingestion path;
/// enumerating named files is separate from ranking useful logical objects.
@Suite struct CaptureRetrievalTests {
    func candidates(_ reply: String, cwd: String = "/work/series") -> [DeliveryCandidate] {
        MentionExtractor.candidates(in: Turn(request: "Deliver the outputs", parts: [
            ReplyPart(text: reply, line: 17, at: Date(timeIntervalSince1970: 100), cwd: cwd),
        ])).filter(Admission.admits)
    }

    @Test func aRelativeFolderCanBeHandedOverWithoutInventingItsFiles() {
        let found = candidates("The finished outputs are in `renders/`.")
        #expect(found.map(\.path) == ["/work/series/renders"])
        #expect(found.first?.evidence.first?.mention.rawTarget == "renders/")
        // Folder membership remains the existing bounded, time-aware listing's responsibility.
        #expect(candidates("Branch `origin/main`; command `/goal`.").isEmpty)
    }

    @Test func explicitNumericRangesPreservePaddingAndEvidence() {
        let found = candidates("Outputs: `renders/episode{01..03}.mp4`.")
        #expect(found.map(\.path) == (1...3).map { "/work/series/renders/episode0\($0).mp4" })
        #expect(found.allSatisfy { $0.evidence.count == 1 && $0.evidence[0].part.line == 17 })
        #expect(found.allSatisfy { $0.evidence[0].mention.rawTarget == "renders/episode{01..03}.mp4" })
        #expect(found.allSatisfy { $0.evidence[0].mention.excerpt == "Outputs: `renders/episode{01..03}.mp4`." })
    }

    @Test func writtenNumericRangesAreBoundedAndKeepTheWrittenStem() {
        #expect(candidates("Files: `exports/shot07–shot09.png`.").map(\.path)
                == (7...9).map { "/work/series/exports/shot0\($0).png" })
        #expect(candidates("Files: [charts](plots/chart7—chart9.svg).").map(\.path)
                == (7...9).map { "/work/series/plots/chart\($0).svg" })
        #expect(candidates("Files: `out/report{1..256}.md`.").count == 256)
        #expect(candidates("Files: `out/report{1..257}.md`.").isEmpty)
        #expect(candidates("Files: `out/report{9..1}.md`.").isEmpty)
        #expect(candidates("Files: `out/report{1..9999999999999999999999999}.md`.").isEmpty)
        #expect(candidates("Files: `out/report{01..3}.md`.").isEmpty)
    }

    @Test func ordinaryNumbersAndAmbiguousNamesAreNotRanges() {
        #expect(candidates("Report: `out/forecast-2024-2025.pdf`.").map(\.path)
                == ["/work/series/out/forecast-2024-2025.pdf"])
        #expect(candidates("Report: `out/forecast2024–2025.pdf`.").map(\.path)
                == ["/work/series/out/forecast2024–2025.pdf"])
        #expect(candidates("Report: `out/shot01–take03.png`.").isEmpty)
        #expect(candidates("Template: `out/{id}.md`.").isEmpty)
        #expect(candidates("Template: `out/{1..2}/report{1..2}.md`.").isEmpty)
    }

    @Test func unsupportedGlobTextNeverBecomesALiteralMissingArtifact() {
        #expect(candidates("Exports: `renders/*.mp4`; [files](renders/episode?.mp4).").isEmpty)
        // Encoded metacharacters explicitly name literal files; ordinary bracketed names stay literal.
        #expect(candidates("[literal](out/star%2A.md) [note](<out/note [1].md>)").map(\.path)
                == ["/work/series/out/star*.md", "/work/series/out/note [1].md"])
        #expect(candidates("[section](out/review.md#questions?open)").first?.evidence.first?.mention.anchor
                == "#questions?open")
    }

    @Test func rangeExpansionDoesNotCrossFoldersOrExecuteSourceText() {
        #expect(candidates("Files: `../other/chunk{1..3}.pdf`.").map(\.path)
                == (1...3).map { "/work/other/chunk\($0).pdf" })
        // A named original may be outside cwd; expansion adds no directory search and follows no link.
        #expect(candidates("Files: `out/{1..3}/chunk.pdf`.").isEmpty)
        #expect(candidates("Example:\n```sh\nopen out/chunk{1..3}.pdf\n```").isEmpty)
        #expect(MentionExtractor.extract(from: "[bad](out/a%00.md)", cwd: "/work/series").isEmpty)
    }

    @Test func renamedProjectsAndExtensionsKeepTheSameExpansion() {
        for (cwd, stem, ext) in [("/work/copper", "part", "mp4"), ("/work/river", "plate", "svg"),
                                 ("/work/hill", "appendix", "md")] {
            let found = candidates("[deliveries](out/\(stem){10..12}.\(ext))", cwd: cwd)
            #expect(found.map(\.path) == (10...12).map { "\(cwd)/out/\(stem)\($0).\(ext)" })
        }
    }

    @Test func repeatedEvidenceProducesOneCandidatePerExpandedPath() {
        let found = candidates("[batch](out/panel{1..3}.png), again `out/panel2.png`.")
        #expect(found.count == 3)
        #expect(found.first { $0.path.hasSuffix("panel2.png") }?.evidence.count == 2)
    }

    @Test func plainRelativePathsKeepTheirIdentityEvenWhenTheyRepeatTheWorkingFolderName() {
        // The text could mean a nested folder or a mistaken project prefix. The extractor must
        // not guess based on which original happens to exist during this index run.
        #expect(candidates("[report](series/out/report.md)").map(\.path)
                == ["/work/series/series/out/report.md"])
        #expect(candidates("[report](./out/report.md) [other](../other/report.md)").map(\.path)
                == ["/work/series/out/report.md", "/work/other/report.md"])
    }

    @Test func rangeIngestionKeepsOriginalsEvidenceAndFirstCapturesOnReread() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("gleaner-capture-\(UUID().uuidString)")
        let workspace = root.appendingPathComponent("work/series")
        try fm.createDirectory(at: workspace.appendingPathComponent("out"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for n in 1...3 {
            try "Original \(n)".write(to: workspace.appendingPathComponent("out/part\(n).md"), atomically: true, encoding: .utf8)
        }
        let indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
        let delivered = Date(timeIntervalSince1970: 100)
        let log = SessionLog(
            session: SessionInfo(provider: .codex, id: "synthetic-series", cwd: workspace.path,
                                 logPath: root.appendingPathComponent("synthetic.jsonl").path),
            turns: [Turn(request: "Deliver the chapters", parts: [
                ReplyPart(text: "Chapters: `out/part{1..4}.md`.", line: 8, at: delivered, cwd: workspace.path),
            ])], records: 2, answeredTurns: 1, closedReplies: 1, unknownRecordTypes: [:], unknownFields: [:], malformedLines: 0)
        let first = try indexer.ingest(log, isComplete: true, now: Date())
        #expect(first.added == 4)
        let before = try indexer.registry.artifacts().flatMap(\.deliveries)
        #expect(before.filter { $0.capture?.provenance == .firstSeenAfterDelivery }.count == 3)
        #expect(before.filter { $0.capture?.provenance == .neverObserved }.count == 1)
        #expect(before.allSatisfy { $0.evidence.first?.rawTarget == "out/part{1..4}.md" && $0.evidence.first?.line == 8 })
        #expect(before.allSatisfy { $0.provider == .codex && $0.sessionID == "synthetic-series" && $0.deliveredAt == delivered })
        let captures = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.capture) })
        try "Changed later".write(to: workspace.appendingPathComponent("out/part1.md"), atomically: true, encoding: .utf8)
        #expect(try indexer.ingest(log, isComplete: true, now: Date()).added == 0)
        let after = try indexer.registry.artifacts().flatMap(\.deliveries)
        #expect(after.count == 4)
        #expect(after.allSatisfy { captures[$0.id] == $0.capture })
        #expect(try indexer.registry.observations().isEmpty)
    }
}
