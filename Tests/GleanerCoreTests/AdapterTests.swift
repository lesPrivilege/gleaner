import Foundation
import Testing
@testable import GleanerCore

func fixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
}

@Suite struct ClaudeCodeAdapterTests {
    let log: SessionLog

    init() throws {
        log = try ClaudeCodeAdapter.parse(try fixture("claude-code-session"))
    }

    @Test func sessionMetadata() {
        #expect(log.session.provider == .claudeCode)
        #expect(log.session.id == "s-claude")
        #expect(log.session.title == "Praxis ch3 video")
        #expect(log.session.cwd == "/work/Praxis")
    }

    @Test func finalReplyIsTextAfterLastToolCall() {
        #expect(log.turns.count == 2)
        #expect(log.turns[0].reply == "Done. Video: [demo.mp4](output/final.mp4)")
        #expect(log.turns[0].logLine == 8)
        #expect(log.turns[0].deliveredAt == Timestamp.parse("2026-07-12T10:19:00.000Z"))
    }

    @Test func notificationTurnKeepsHumanRequest() {
        #expect(log.turns[0].request == "Make the Praxis chapter 3 explainer video about Agent Harness")
        #expect(log.turns[1].request == log.turns[0].request)
        #expect(log.turns[1].reply == "The subtitle pass is in `output/subs.srt`.")
    }

    @Test func replyCwdFollowsTheAgent() {
        #expect(log.turns[0].cwd == "/work/Praxis/.claude/worktrees/w1")
        #expect(log.turns[1].cwd == "/work/Praxis")
    }

    @Test func unknownRecordsAreReported() {
        #expect(log.unknownRecordTypes == ["brand-new-record": 1, "<malformed>": 1])
    }
}

@Suite struct CodexAdapterTests {
    let adapter: CodexAdapter

    init() throws {
        adapter = CodexAdapter(titles: CodexAdapter.loadTitles(index: try fixture("codex-session-index")))
    }

    @Test func finalAnswersOnly() throws {
        let log = try #require(try adapter.parse(try fixture("codex-rollout")))
        #expect(log.session.id == "thread-1")
        #expect(log.session.title == "Seal codebase review")
        #expect(log.session.cwd == "/work/Sealwright")
        #expect(log.turns.count == 1)
        #expect(log.turns[0].reply == "Report: [review](/work/Sealwright/docs/reviews/review.md)")
        #expect(log.turns[0].request == "Review the seal codebase")
        #expect(log.turns[0].cwd == "/work/Sealwright")
        #expect(log.unknownRecordTypes == ["mystery": 1])
    }

    @Test func subagentThreadsAreSkipped() throws {
        #expect(try adapter.parse(try fixture("codex-subagent")) == nil)
    }
}
