import Foundation
import Testing
@testable import GleanerCore

/// How a project's files are listed (docs/design/capture.md): handed over before observed, what a
/// person opens before what a program reads, newest first; a crowded folder of one kind folded; a
/// shared stem shown together. None of it decides what enters or which files are one work.
@Suite struct ListingTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func candidate(_ path: String, at minutes: Double) -> Listing.Entry {
        let date = t0.addingTimeInterval(minutes * 60)
        return .candidate(Candidate(path: path, observations: [Observed(
            path: path, kind: .appeared, logPath: "/logs/s.jsonl", sessionID: "s", provider: .claudeCode, sessionTitle: nil,
            workspace: "/w", size: 1, createdAt: date, modifiedAt: date, device: 1, inode: 1,
            repository: nil, checkout: nil, observedAt: date)]))
    }

    func work(_ path: String, at minutes: Double) -> Listing.Entry {
        let delivery = Delivery(id: path, number: 1, path: path, deliveredAt: t0.addingTimeInterval(minutes * 60), provider: .claudeCode,
                                sessionTitle: nil, request: nil, cwd: "/w", evidence: [], logPath: "/logs/s.jsonl", capture: nil)
        let artifact = Artifact(path: path, deliveries: [delivery])
        return .work(Work(files: [artifact], deliveries: [delivery], project: "/w"))
    }

    func names(_ entries: [Listing.Entry]) -> [String] { entries.map { ($0.path as NSString).lastPathComponent } }

    @Test func aStemIsTheNameBeforeItsFirstDot() {
        #expect(Listing.stem("ep00.mp4") == "ep00")
        #expect(Listing.stem("ep00.narration.wav") == "ep00")
        #expect(Listing.stem("ov-4x3.svg") == "ov-4x3")
        #expect(Listing.stem("Makefile") == "Makefile")
        #expect(Listing.stem(".env.local") == ".env")
        #expect(Listing.stem(".gitignore") == ".gitignore")
    }

    @Test func handedOverComesFirstThenWhatAPersonOpensThenNewestFirst() {
        let entries = [
            candidate("/w/data.csv", at: 50), candidate("/w/cut.mp4", at: 10), work("/w/old-report.md", at: 1),
            candidate("/w/render.py", at: 60), candidate("/w/cover.png", at: 30), work("/w/new-chart.json", at: 40),
        ]
        // A delivered data file still comes before every observed file; within each, kind then date.
        #expect(names(Listing.ordered(entries)) == ["old-report.md", "new-chart.json", "cover.png", "cut.mp4", "render.py", "data.csv"])
    }

    @Test func aFolderOfManyObservedFilesOfOneKindFoldsIntoOneRow() {
        let voices = (0..<Listing.crowded).map { candidate("/w/out/voice/line-\($0).wav", at: Double($0)) }
        let few = (0..<(Listing.crowded - 1)).map { candidate("/w/out/sfx/hit-\($0).wav", at: Double($0)) }
        let delivered = (0..<20).map { work("/w/out/final/ep\($0).mp4", at: Double($0)) }
        let notes = candidate("/w/out/voice/notes.md", at: 100)
        let rows = Listing.rows(voices + few + delivered + [notes])

        var folded: [(String, Artifact.Kind, Int)] = [], single = 0
        for row in rows {
            switch row {
            case .folded(let folder, let kind, let members): folded.append((folder, kind, members.count))
            case .entry: single += 1
            case .together: Issue.record("no names share a stem here")
            }
        }
        // The voice lines fold; the sound effects are too few; what was handed over never folds;
        // another kind in the same folder stays out of the fold.
        #expect(folded.count == 1 && folded[0].0 == "/w/out/voice" && folded[0].1 == .media && folded[0].2 == Listing.crowded)
        #expect(single == 20 + Listing.crowded - 1 + 1)
        // After the deliveries and the newer notes, at the place of its newest line.
        guard case .folded(_, _, let members) = rows[21] else { Issue.record("the fold follows the notes"); return }
        #expect(members.first?.name == "line-\(Listing.crowded - 1).wav")
    }

    @Test func filesSharingAStemInOneFolderAreShownTogetherAndNothingMore() {
        let entries = [
            work("/w/out/ep00.mp4", at: 30), candidate("/w/out/EP00.mix.wav", at: 31), candidate("/w/out/ep00.inputs.json", at: 32),
            candidate("/w/covers/ov-4x3.svg", at: 5), candidate("/w/covers/ov-4x3.png", at: 6),
            candidate("/w/other/ep00.txt", at: 7), candidate("/w/out/ep01.mp4", at: 8),
        ]
        let rows = Listing.rows(entries)
        var groups: [(String, [String])] = [], singles: [String] = []
        for row in rows {
            switch row {
            case .together(let stem, let members): groups.append((stem, names(members)))
            case .entry(let entry): singles.append(names([entry])[0])
            case .folded: Issue.record("nothing is crowded here")
            }
        }
        // The delivered video leads its stem, wherever its observed companions would sort; case
        // doesn't part a stem; another folder's ep00 isn't one of them.
        #expect(groups.map(\.0) == ["ep00", "ov-4x3"])
        #expect(groups[0].1 == ["ep00.mp4", "EP00.mix.wav", "ep00.inputs.json"])
        #expect(groups[1].1 == ["ov-4x3.png", "ov-4x3.svg"])
        #expect(singles == ["ep01.mp4", "ep00.txt"])
        // Each is still its own entry: a work stays a work and a candidate a candidate.
        if case .together(_, let members) = rows[0] {
            #expect(members.map(\.isHandedOver) == [true, false, false])
        }
    }

    @Test func kindsAreOrderedByWhoOpensThem() {
        for kind in [Artifact.Kind.document, .image, .media, .web, .model, .build, .folder] { #expect(kind.isOpenedByPerson) }
        for kind in [Artifact.Kind.code, .data, .other] { #expect(!kind.isOpenedByPerson) }
    }
}
