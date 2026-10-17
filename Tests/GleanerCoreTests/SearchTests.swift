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
        #expect(video.match(["demo"])?.deliveryIndex == 1)
        // Only the file name matched: the newest delivery.
        #expect(video.match(["mp4"])?.deliveryIndex == 0)
    }
}
