import Foundation
import Testing
@testable import GleanerCore

/// The admission rule from first principles (SPEC §9): a delivery is a file the agent hands to
/// the person. Each case below states one principle as a reply an agent might write.
@Suite struct AdmissionTests {
    func admitted(_ reply: String) -> [String] {
        let turn = Turn(request: nil, parts: [ReplyPart(text: reply, line: 1, at: nil, cwd: "/p")])
        return MentionExtractor.candidates(in: turn).filter(Admission.admits).map(\.path)
    }

    @Test func aLinkIsAHandOff() {
        #expect(admitted("Here is the [report](out/report.md).") == ["/p/out/report.md"])
        #expect(admitted("Preview: ![chart](/p/out/chart.png)") == ["/p/out/chart.png"])
    }

    @Test func aPathWithAFolderInCodeOrPlainTextIsAHandOff() {
        #expect(admitted("Rendered `out/demo.mp4` for you.") == ["/p/out/demo.mp4"])
        #expect(admitted("Saved to /p/build/Gleaner.zip") == ["/p/build/Gleaner.zip"])
    }

    @Test func aBareFileNameIsATopicNotAHandOff() {
        // `App.tsx` names a file the conversation is about; no folder means no place was given.
        #expect(admitted("I changed `App.tsx` and `README.md`.") == [])
    }

    @Test func aLineAnchorPointsIntoCodeRatherThanHandingItOver() {
        #expect(admitted("The bug is in `src/app.ts:42` and [here](src/app.ts#L10).") == [])
        #expect(admitted("See [executor.ts:363](packages/core/executor.ts:363).") == [])
        // A heading anchor points at a section of a document that may itself be the delivery.
        #expect(admitted("Records: [review packet](docs/review.md#fixes).") == ["/p/docs/review.md"])
    }

    @Test func aPlaceholderNamesAPatternNotAFile() {
        #expect(admitted("Writes `build/Gleaner-<version>.zip` and `out/{id}.md`.") == [])
    }

    @Test func examplesInsideCodeBlocksAreInstructionsNotHandOffs() {
        #expect(admitted("Run this:\n\n```sh\nopen out/report.md\n```\n") == [])
        #expect(admitted("Write links like `[x](out/x.md)`.") == [])
    }
}
