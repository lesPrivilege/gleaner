import Foundation
import Testing
@testable import GleanerCore

/// Which delivery a search result opens on (SPEC §10).
@Suite struct SearchTests {
    func delivery(_ number: Int, request: String) -> Delivery {
        Delivery(id: "d\(number)", number: number, path: "/work/app/out/demo.mp4", deliveredAt: nil, provider: .claudeCode,
                 sessionTitle: nil, request: request, cwd: "/work/app", evidence: [], logPath: "/logs/s.jsonl", capture: nil)
    }

    @Test func opensOnTheNewestDeliveryWhoseOwnWordsMatched() {
        let video = Artifact(path: "/work/app/out/demo.mp4", deliveries: [
            delivery(3, request: "Tighten the intro"),
            delivery(2, request: "Render the demo again"),
            delivery(1, request: "Make the demo video"),
        ])
        // The file name matches every delivery; the newest one whose own words say "demo" wins.
        #expect(video.match(["demo"]) == 1)
        // Only the file name or its folder matched: the newest delivery.
        #expect(video.match(["mp4"]) == 0)
        #expect(video.match(["out"]) == 0)
    }

    func delivered(_ path: String, request: String, at hours: Double, cwd: String = "/work/elsewhere") -> Delivery {
        Delivery(id: path, number: 1, path: path, deliveredAt: Date(timeIntervalSince1970: hours * 3600), provider: .claudeCode,
                 sessionTitle: nil, request: request, cwd: cwd, evidence: [], logPath: "/logs/s.jsonl", capture: nil)
    }

    @Test func aFileIsFoundByItsFoldersInsideItsProject() {
        let a = "/work/app/palantir/series-a/assembly/covers/cmp-4x3.svg", b = "/work/app/palantir/series-b/assembly/covers/cmp-4x3.svg"
        let first = Artifact(path: a, deliveries: [delivered(a, request: "Draw it", at: 1)], repository: "/work/app")
        let second = Artifact(path: b, deliveries: [delivered(b, request: "Draw it", at: 2)], repository: "/work/app")
        // An ancestor folder inside the project finds it, as its own name does; the same name in
        // another series doesn't answer for it.
        #expect(first.match(["series-a", "covers"]) != nil && first.match(["cmp-4x3"]) != nil)
        #expect(second.match(["series-a", "covers"]) == nil)
        // The folders above the project don't: every file would match them.
        #expect(first.match(["work"]) == nil)
    }

    @Test func filesNamedByTheSearchComeBeforeThoseOnlyMentioningIt() {
        let cover = "/work/app/series/covers/c1.svg", notes = "/work/app/notes.md", spec = "/work/app/docs/SPEC.md"
        let organization = Organization(artifacts: [
            Artifact(path: notes, deliveries: [delivered(notes, request: "That covers the SPEC changes", at: 3)], repository: "/work/app"),
            Artifact(path: spec, deliveries: [delivered(spec, request: "Apply the changes", at: 2)], repository: "/work/app"),
            Artifact(path: cover, deliveries: [delivered(cover, request: "Draw the series art", at: 1)], repository: "/work/app"),
        ])
        // A newer file whose request only says the word comes after the files named by it.
        #expect(organization.search(["covers"]).map(\.work.id) == [cover, notes])
        #expect(organization.search(["spec"]).map(\.work.id) == [spec, notes])
        // Without a search, the library's order: newest first.
        #expect(organization.search([]).map(\.work.id) == [notes, spec, cover])
    }
}
