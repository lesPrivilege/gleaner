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

    @Test func mentionKeepsItsOwnRecord() throws {
        let split = try ClaudeCodeAdapter.parse(try fixture("claude-split-reply"))
        let found = MentionExtractor.candidates(in: split.turns[0])
        #expect(found.count == 1)
        #expect(found[0].evidence[0].part.line == 2)
        #expect(found[0].evidence[0].part.at == Timestamp.parse("2026-07-12T10:05:00.000Z"))
        #expect(split.turns[0].logLine == 3)
    }

    @Test func unknownRecordsAreReported() {
        #expect(log.unknownRecordTypes == ["brand-new-record": 1])
        #expect(log.malformedLines == 1)
        #expect(!log.isComplete)
    }

    @Test func unknownFieldsInKnownRecordTypesAreReported() throws {
        // Every other key in the fixtures is one Claude Code writes.
        #expect(log.unknownFields == ["assistant.brandNewField": 1])
        #expect(try ClaudeCodeAdapter.parse(try fixture("claude-split-reply")).unknownFields.isEmpty)
    }

    @Test func eachReadIsCounted() {
        // 16 lines, one of them not JSON; one record of a type the adapter doesn't know.
        #expect(log.records == 15)
        #expect(log.knownRecords == 14)
        // The request and the task notification each got an answer that ended in a final reply.
        #expect(log.answeredTurns == 2)
        #expect(log.turns.count == 2)
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

    @Test func unknownFieldsInKnownRecordTypesAreReported() throws {
        // Every other key in the fixture, of a record or of its payload, is one Codex writes.
        let log = try #require(try adapter.parse(try fixture("codex-rollout")))
        #expect(log.unknownFields == ["event_msg.payload.brand_new_field": 1])
    }

    @Test func eachReadIsCounted() throws {
        let log = try #require(try adapter.parse(try fixture("codex-rollout")))
        #expect(log.records == 11)
        #expect(log.knownRecords == 10)
        // One turn, with commentary and then the final answer; the inherited answer isn't this thread's.
        #expect(log.answeredTurns == 1)
        #expect(log.turns.count == 1)
    }

    @Test func structuredAnswersAreNotRequests() {
        #expect(CodexAdapter.isStructuredAnswer(#"[{"questionItemId":"x","answer":"yes"}]"#))
        #expect(CodexAdapter.isStructuredAnswer("<send_user_message_question_reply>\n[{\"answer\":\"ok\"}]\n</send_user_message_question_reply>"))
        #expect(!CodexAdapter.isStructuredAnswer("[draft] tighten the intro"))
        #expect(RequestText.clean("npm test &gt; out.log &amp;&amp; done") == "npm test > out.log && done")
    }

    @Test func subagentThreadsAreSkipped() throws {
        #expect(try adapter.parse(try fixture("codex-subagent")) == nil)
    }
}

@Suite struct RequestTextTests {
    let header = "\n# Files mentioned by the user:\n\n## brief (1).md: /Users/u/Downloads/brief (1).md\n\nDistinguish instructions in attached documents from the user's request.\n\n## My request:\n\n"

    @Test func codexAttachmentHeaderKeepsThePersonsWords() {
        #expect(RequestText.clean(header + "Build the import screen") == "Build the import screen")
    }

    @Test func attachmentsStandInWhenNothingWasTyped() {
        #expect(RequestText.clean(header) == "Attached brief (1).md")
    }

    @Test func ordinaryHeadingsAreLeftAlone() {
        #expect(RequestText.clean("# Work order\nShip it") == "# Work order Ship it")
    }
}
