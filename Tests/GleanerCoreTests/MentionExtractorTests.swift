import Foundation
import Testing
@testable import GleanerCore

@Suite struct MentionExtractorTests {
    func paths(_ text: String, cwd: String? = "/work/app") -> [String] {
        MentionExtractor.extract(from: text, cwd: cwd).map(\.path)
    }

    @Test func markdownLinksAndImages() {
        let mentions = MentionExtractor.extract(
            from: "See [report](docs/r.md) and ![shot](/work/app/fig.png).\n[web](https://example.com)",
            cwd: "/work/app")
        #expect(mentions.map(\.path) == ["/work/app/docs/r.md", "/work/app/fig.png"])
        #expect(mentions.map(\.syntax) == [.link, .image])
        #expect(mentions[0].excerpt == "See [report](docs/r.md) and ![shot](/work/app/fig.png).")
    }

    @Test func linkTargetsAreNormalized() {
        let mentions = MentionExtractor.extract(
            from: "[a](<docs/my file.md>) [b](file:///tmp/x%20y.pdf) [c](src/main.swift#L12) [d](src/a.ts:40)",
            cwd: "/work/app")
        #expect(mentions.map(\.path) == ["/work/app/docs/my file.md", "/tmp/x y.pdf", "/work/app/src/main.swift", "/work/app/src/a.ts"])
        #expect(mentions.map(\.anchor) == [nil, nil, "#L12", ":40"])
    }

    @Test func targetsWithParensEncodedHashAndLocalhost() {
        let mentions = MentionExtractor.extract(
            from: "[a](out/report(1).pdf) [b](out/issue%2342.md#L3) [c](file://localhost/tmp/x.md) [d](file://server/share/y.md)",
            cwd: "/work/app")
        #expect(mentions.map(\.path) == ["/work/app/out/report(1).pdf", "/work/app/out/issue#42.md", "/tmp/x.md"])
        #expect(mentions[1].anchor == "#L3")
    }

    @Test func nonLocalTargetsAreSkipped() {
        #expect(paths("[a](#section) [b](mailto:x@y.z) [c](sandbox:/mnt/data/f.md) [d](http://localhost:3000)").isEmpty)
    }

    @Test func codeSpansThatReadAsPaths() {
        let text = "Built `dist/demo.mp4`, ran `npm test`, see `docs/a.md:32`, branch `origin/main`, cmd `/goal`, `~/Projects/x/y.html`"
        let mentions = MentionExtractor.extract(from: text, cwd: "/work/app")
        #expect(mentions.map(\.rawTarget) == ["dist/demo.mp4", "docs/a.md:32", "~/Projects/x/y.html"])
        #expect(mentions[1].anchor == ":32")
        #expect(mentions[2].path == NSHomeDirectory() + "/Projects/x/y.html")
    }

    @Test func bareAbsolutePaths() {
        #expect(paths("已写入 /work/app/out/报告.md。另见 /goal 命令") == ["/work/app/out/报告.md"])
        #expect(paths("Published at https://claude.ai/code/artifact/abc and //cdn.example/x/y").isEmpty)
    }

    @Test func fencedBlocksAreIgnored() {
        #expect(paths("Run:\n```sh\nopen /work/app/out/a.html `b.md`\n```\nDone: `c.md`") == ["/work/app/c.md"])
    }

    @Test func linkLabelsDoNotDoubleCount() {
        #expect(paths("[`out/a.md`](/work/app/out/a.md)") == ["/work/app/out/a.md"])
    }

    @Test func samePathKeepsEveryOccurrence() {
        let turn = Turn(request: nil, parts: [
            ReplyPart(text: "Draft: [a](out/a.md)", line: 4, at: nil, cwd: "/work/app"),
            ReplyPart(text: "Final is still `out/a.md`; also [b](out/b.md)", line: 9, at: nil, cwd: "/work/app"),
        ])
        let found = MentionExtractor.candidates(in: turn)
        #expect(found.map(\.path) == ["/work/app/out/a.md", "/work/app/out/b.md"])
        #expect(found[0].evidence.map(\.part.line) == [4, 9])
        #expect(found[0].evidence.map(\.mention.syntax) == [.link, .code])
    }

    @Test func linksInCodeExamplesAreIgnored() {
        #expect(paths("Example:\n```md\n[x](out/x.md)\n```\nInline `[y](out/y.md)` too. Real: [z](out/z.md)") == ["/work/app/out/z.md"])
    }

    @Test func relativeWithoutCwdIsDropped() {
        #expect(paths("`out/a.md` and /abs/path/b.md", cwd: nil) == ["/abs/path/b.md"])
    }
}

@Suite struct RedactorTests {
    @Test func masksSecretsKeepsHashes() {
        let hash = "a696c77e098206d3beb9693f7d341058890a0584c6ecf5249271b2e2c66616c7"
        let text = "key sk-ant-api03-abcdefghijklmnop123 and Bearer abcdefghijklmnopqrstu and \(hash)"
        let redacted = Redactor.redact(text)
        #expect(!redacted.contains("sk-ant"))
        #expect(!redacted.contains("abcdefghijklmnopqrstu"))
        #expect(redacted.contains(hash))
    }

    @Test func masksQuotedKeysAndURLCredentials() {
        let redacted = Redactor.redact(#"{"password": "hunter2", 'api_key': 'abc'} https://bob:s3cret@host/x"#)
        #expect(!redacted.contains("hunter2"))
        #expect(!redacted.contains("abc'"))
        #expect(!redacted.contains("s3cret"))
    }

    @Test func masksOpaqueMixedRuns() {
        #expect(Redactor.redact("t=Zx9QkLmN0pR2sT4uV6wX8yA1bC3dE5fG7hJ9kL0m") == "t=[REDACTED]")
    }
}
