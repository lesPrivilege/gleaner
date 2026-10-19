import Foundation
import Testing
@testable import GleanerCore

/// Projects, works and the person's corrections: Gleaner groups files only as it found them or as
/// the person said, suggests joins with a reason, and keeps every decision across rereads.
@Suite struct OrganizationTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    func delivery(_ path: String, _ number: Int, at hours: Double, sha: String?, request: String? = nil) -> Delivery {
        Delivery(id: "\(path)#\(number)", number: number, path: path, deliveredAt: start.addingTimeInterval(hours * 3600),
                 replyLine: number, replyRank: 0, provider: .claudeCode, sessionTitle: nil, request: request,
                 cwd: (path as NSString).deletingLastPathComponent, evidence: [], logPath: "/logs/s.jsonl",
                 capture: Capture(sha256: sha, size: 1, modifiedAt: nil, observedAt: start, savedAt: nil,
                                  provenance: .atDelivery, kind: .file))
    }

    /// A file delivered at `hours`, newest last, with its bytes per delivery.
    func file(_ path: String, _ versions: [(Double, String?)], requests: [String?] = [], repository: String? = nil) -> Artifact {
        let deliveries = versions.enumerated().map { i, v in
            delivery(path, i + 1, at: v.0, sha: v.1, request: i < requests.count ? requests[i] : nil)
        }
        return Artifact(path: path, deliveries: deliveries.reversed(), repository: repository)
    }

    func correction(_ kind: Correction.Kind, _ subject: String, _ target: String, at hours: Double = 0) -> Correction {
        Correction(id: Int64(hours * 10), kind: kind, subject: subject, target: target, madeAt: start.addingTimeInterval(hours * 3600))
    }

    @Test func eachFileIsItsOwnWorkInTheProjectGleanerFound() {
        let a = file("/w/client-a/app/report.md", [(1, "a")], repository: "/w/client-a/app")
        let b = file("/w/client-b/app/report.md", [(2, "a")], repository: "/w/client-b/app")
        let org = Organization(artifacts: [a, b])
        // Equal bytes in two projects stay two works (SPEC §5.2).
        #expect(org.works.count == 2)
        #expect(org.projects.map(\.name) == ["client-b/app", "client-a/app"])
        #expect(org.projects.map(\.origin) == [.repository, .repository])
        #expect(org.placement(of: org.works[0]) == .found)
        #expect(org.suggestions.isEmpty)
    }

    @Test func filesThePersonJoinedAreOneWorkWithEveryDelivery() throws {
        let draft = file("/w/board/board-draft.md", [(1, "d1"), (2, "d2")], requests: ["first board report", "tighten it"])
        let final = file("/w/board/board-final.md", [(5, "f1")], requests: ["make it final"])
        let org = Organization(artifacts: [draft, final], corrections: [correction(.sameWork, final.path, draft.path)])
        let work = try #require(org.work(containing: final.path))
        #expect(org.works.count == 1)
        #expect(work.id == draft.path)
        #expect(work.name == "board-final.md")
        #expect(work.deliveries.map(\.id) == [final.deliveries[0].id, draft.deliveries[0].id, draft.deliveries[1].id])
        // Search lands on the delivery whose own words matched, in whichever file it is.
        #expect(work.match(["first"], project: "board")?.id == draft.deliveries[1].id)
        #expect(work.match(["final"], project: "board")?.id == final.deliveries[0].id)
        #expect(work.file(of: draft.deliveries[1]).path == draft.path)
        #expect(org.links(of: work).count == 1)
    }

    @Test func aWorkMovedToAnotherProjectStaysThereAndSaysWhy() throws {
        let deck = file("/w/mono/web/deck.key", [(1, "k")], repository: "/w/mono")
        let api = file("/w/mono/api/notes.md", [(2, "n")], repository: "/w/mono")
        let mine = UserProject(key: "user:web", name: "Web launch", createdAt: start)
        let move = correction(.project, deck.path, mine.key, at: 1)
        let org = Organization(artifacts: [deck, api], corrections: [move], projects: [mine])
        let work = try #require(org.work(containing: deck.path))
        #expect(work.project == "user:web")
        #expect(org.placement(of: work) == .moved(move))
        #expect(org.project("user:web")?.origin == .yours)
        #expect(org.project("/w/mono")?.works.map(\.name) == ["notes.md"])
        // A move to a project that no longer exists is not applied.
        #expect(Organization(artifacts: [deck], corrections: [move]).works[0].project == "/w/mono")
    }

    @Test func aProjectCombinedIntoAnotherShowsItsWorkThere() throws {
        let site = file("/w/site/index.html", [(1, "s")], repository: "/w/site")
        let brand = file("/w/brand/logo.png", [(2, "l")], repository: "/w/brand")
        let combine = correction(.combine, "/w/brand", "/w/site", at: 1)
        let org = Organization(artifacts: [site, brand], corrections: [combine])
        #expect(org.projects.map(\.key) == ["/w/site"])
        let logo = try #require(org.work(containing: brand.path))
        #expect(org.placement(of: logo) == .combined(from: "/w/brand", combine))
        #expect(org.projects[0].combined.map(\.folder) == ["/w/brand"])
        // A loop of combinations stops where it would return.
        let loop = Organization(artifacts: [site, brand], corrections: [combine, correction(.combine, "/w/site", "/w/brand", at: 2)])
        #expect(Set(loop.works.map(\.project)).count == 1)
    }

    @Test func aRenamedFileIsSuggestedOnlyOnceItsOldPathIsGone() {
        let draft = file("/w/board/notes-old.md", [(1, "same")])
        let final = file("/w/board/summary.md", [(3, "same")])
        #expect(Organization(artifacts: [draft, final]).suggestions.isEmpty)
        let gone = Organization(artifacts: [draft, final], missing: [draft.path])
        #expect(gone.suggestions == [.init(earlier: draft.path, later: final.path, reason: .moved)])
    }

    @Test func namesThatDifferOnlyByAVersionMarkAreSuggested() {
        func suggested(_ a: String, _ b: String) -> Bool {
            !Organization(artifacts: [file(a, [(1, "x")]), file(b, [(2, "y")])]).suggestions.isEmpty
        }
        #expect(suggested("/w/r/report-v1.pdf", "/w/r/report-v2.pdf"))
        #expect(suggested("/w/r/board-draft.md", "/w/r/board-final.md"))
        #expect(suggested("/w/r/brief.docx", "/w/r/brief (1).docx"))
        // A date names another day's document; a long number, another receipt.
        #expect(!suggested("/w/r/plan 2026-10-01.md", "/w/r/plan 2026-10-18.md"))
        #expect(!suggested("/w/r/receipt-10293847.pdf", "/w/r/receipt-56473829.pdf"))
        // A number alone names another part; another folder or kind is another file.
        #expect(!suggested("/w/r/chapter1.md", "/w/r/chapter2.md"))
        #expect(!suggested("/w/r/report-v1.pdf", "/w/other/report-v2.pdf"))
        #expect(!suggested("/w/r/report-v1.pdf", "/w/r/report-v2.md"))
        #expect(!suggested("/w/r/v1.md", "/w/r/v2.md"))
    }

    @Test func aSuggestionThePersonDeclinedOrAcceptedIsNotMadeAgain() {
        let a = file("/w/r/deck-v1.key", [(1, "x")]), b = file("/w/r/deck-v2.key", [(2, "y")])
        #expect(Organization(artifacts: [a, b], corrections: [correction(.notSameWork, b.path, a.path)]).suggestions.isEmpty)
        #expect(Organization(artifacts: [a, b], corrections: [correction(.sameWork, a.path, b.path)]).suggestions.isEmpty)
        // Declined, it isn't replaced by the next older version.
        let c = file("/w/r/deck-v3.key", [(3, "z")])
        let declined = Organization(artifacts: [a, b, c], corrections: [correction(.notSameWork, c.path, b.path)])
        #expect(declined.suggestions == [.init(earlier: a.path, later: b.path, reason: .versionName)])
    }

    @Test func copiesDeliveredTogetherAreNotSuggestedAsRenamed() {
        let out = file("/w/out/report.pdf", [(1, "same")]), dist = file("/w/dist/report.pdf", [(1, "same")])
        #expect(Organization(artifacts: [out, dist], missing: [out.path, dist.path]).suggestions.isEmpty)
    }

    @Test func aJoinThroughAFileNoLongerInTheLibraryHolds() {
        let draft = file("/w/r/report-draft.md", [(1, "d")]), final = file("/w/r/report-final.md", [(3, "f")])
        let org = Organization(artifacts: [draft, final], corrections: [
            correction(.sameWork, draft.path, "/w/r/report-v2.md"), correction(.sameWork, "/w/r/report-v2.md", final.path)])
        #expect(org.works.count == 1)
    }

    @Test func aFolderOfManyVersionsIsSuggestedQuickly() {
        let files = (0..<1500).map { file("/w/r/notes-v\($0).md", [(Double($0), "s\($0)")]) }
        let clock = ContinuousClock.now
        let org = Organization(artifacts: files)
        #expect(ContinuousClock.now - clock < .seconds(2))
        #expect(org.suggestions.count == 1499)
    }

    @Test func correctionsAreKeptApartFromWhatGleanerFoundAndSurviveReopening() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString).sqlite").path
        let registry = try Registry(path: path)
        let project = try registry.addProject(named: "Board", at: start)
        try registry.correct(.project, subject: "/w/a.md", target: project.key, at: start)
        try registry.correct(.project, subject: "/w/a.md", target: "/w/other", at: start.addingTimeInterval(1))
        try registry.correct(.notSameWork, subject: "/w/b.md", target: "/w/a.md", at: start)
        try registry.correct(.sameWork, subject: "/w/a.md", target: "/w/b.md", at: start.addingTimeInterval(2))
        let reopened = try Registry(path: path)
        // Moves are appended, so undoing one returns to the one before it; one answer per pair: the latest.
        #expect(try reopened.corrections().map(\.kind) == [.project, .project, .sameWork])
        #expect(try reopened.corrections().last { $0.kind == .project }?.target == "/w/other")
        #expect(try reopened.userProjects().map(\.name) == ["Board"])
        try reopened.correct(.project, subject: "/w/c.md", target: project.key, at: start)
        try reopened.removeProject(project.key)
        #expect(try reopened.corrections().map(\.subject) == ["/w/a.md", "/w/a.md"])
        try reopened.undoAllCorrections()
        #expect(try reopened.corrections().isEmpty)
    }

    @Test func notTheSameForOneFileOfAWorkEndsTheSuggestionForTheWork() {
        let a = file("/w/r/deck-v1.key", [(1, "x")]), b = file("/w/r/deck-v2.key", [(2, "y")]), c = file("/w/r/deck-v3.key", [(3, "z")])
        let joined = correction(.sameWork, b.path, c.path)
        let before = Organization(artifacts: [a, b, c], corrections: [joined])
        let work = before.work(containing: c.path)!
        #expect(!before.suggestions(for: work).isEmpty)
        let after = Organization(artifacts: [a, b, c], corrections: [joined, correction(.notSameWork, a.path, b.path, at: 1)])
        #expect(after.suggestions(for: after.work(containing: c.path)!).isEmpty)
    }

    @Test func aJoinThroughAGoneFileCanStillBeUndone() {
        let draft = file("/w/r/report-draft.md", [(1, "d")]), final = file("/w/r/report-final.md", [(3, "f")])
        let org = Organization(artifacts: [draft, final], corrections: [
            correction(.sameWork, draft.path, "/w/r/report-v2.md"), correction(.sameWork, "/w/r/report-v2.md", final.path, at: 1)])
        #expect(org.links(of: org.works[0]).count == 2)
    }
}
