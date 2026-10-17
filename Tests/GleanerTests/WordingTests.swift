import Foundation
import Testing
@testable import Gleaner
@testable import GleanerCore

@Suite struct WordingTests {
    @Test func aFailedSaveSaysWhyInWords() {
        #expect(Wording.saveFailed(ContentStore.Failure.changed(expected: "a", found: "b"), delivery: 2)
                == "The file changed before Gleaner could save it; it no longer holds delivery 2.")
        // The path is no longer a regular file, or its bytes couldn't be read.
        #expect(Wording.saveFailed(ContentStore.Failure.unavailable, delivery: 2)
                == "Gleaner couldn’t read delivery 2’s bytes at this path.")
    }

    @Test func aLogShorterThanWhenLastReadIsNamedAsSuch() {
        let source = Indexer.Report.Source(folder: .listed, shortenedLogs: ["/logs/a.jsonl"])
        #expect(Wording.sourcesLine([.claudeCode: source]) == "Claude Code: read with problems (1 log shorter than when last read)")
    }

    // MARK: The type badge (A17)

    @Test func theTypeBadgeKeepsTheExactExtension() {
        #expect(Wording.kindLabel(.model, path: "/p/out/bracket.SLDPRT") == "SLDPRT")
        #expect(Wording.kindLabel(.document, path: "/p/out/notes.markdown") == "MARKDOWN")
        #expect(Wording.kindLabel(.folder, path: "/p/out/site") == "FOLDER")
    }
}
