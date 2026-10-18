import Foundation
import Testing
@testable import GleanerCore

func fixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
}

/// The fixture `name` with `records` written after it, as a log in a folder of its own.
func fixture(_ name: String, then records: String...) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-fixture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let log = folder.appendingPathComponent(name + ".jsonl")
    try (String(contentsOf: try fixture(name), encoding: .utf8) + records.map { $0 + "\n" }.joined())
        .write(to: log, atomically: true, encoding: .utf8)
    return log
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

    /// The model the provider answered with, from the reply's own records.
    @Test func theModelBehindAReply() {
        #expect(log.turns.map(\.model) == ["claude-fable-5", "claude-fable-5"])
        #expect(log.session.modelProvider == nil)
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

    @Test func aPullRequestLinkIsKnownAndHoldsNoReply() {
        // Claude Code records the pull request a session opened or was linked to: its number, URL
        // and repository.
        #expect(log.unknownRecordTypes["pr-link"] == nil)
        #expect(!log.unknownFields.keys.contains { $0.hasPrefix("pr-link.") })
        #expect(!log.turns.contains { $0.reply.contains("pull/42") })
    }

    @Test func eachReadIsCounted() {
        // 17 lines, one of them not JSON; one record of a type the adapter doesn't know.
        #expect(log.records == 16)
        #expect(log.knownRecords == 15)
        // The request and the task notification each got an answer that ended in a final reply.
        #expect(log.turns.count == 2)
        // The task notification closed the request's turn; its own is the log's last, still open.
        #expect(log.answeredTurns == 1)
        #expect(log.finalReplies == 1)
    }

    @Test func aLastTurnThatEndsOnAToolCallIsNotYetCountedAsAnswered() throws {
        // The session may still be running, or it ended on a tool call: the text before the call
        // is no final reply, and the turn isn't over.
        let open = try ClaudeCodeAdapter.parse(try fixture("claude-open-turn"))
        #expect(open.turns.isEmpty)
        #expect(open.answeredTurns == 0)
        #expect(open.unknownRecordTypes.isEmpty && open.unknownFields.isEmpty)

        // The next request closes it: answered, without a final reply.
        let next = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":"Is it uploaded?"},"origin":{"kind":"human"},"timestamp":"2026-07-12T11:20:00.000Z","cwd":"/work/Praxis","sessionId":"s-open"}"#
        let closed = try ClaudeCodeAdapter.parse(try fixture("claude-open-turn", then: next))
        #expect(closed.turns.isEmpty)
        #expect(closed.answeredTurns == 1)
        #expect(closed.finalReplies == 0)
    }

    @Test func aLastTurnsReplyIsNotYetCounted() throws {
        // The text a turn ends on is its reply until a tool call follows it, so only a closed
        // turn's reply is counted; the reply is still read.
        let split = try ClaudeCodeAdapter.parse(try fixture("claude-split-reply"))
        #expect(split.turns.count == 1)
        #expect(split.answeredTurns == 0 && split.finalReplies == 0)
    }

    static let redirect = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":"Render the teaser instead"},"origin":{"kind":"human"},"uuid":"u2","timestamp":"2026-07-12T12:01:00.000Z","cwd":"/work/Praxis","sessionId":"s-interrupted"}"#
    static let redirectToolCall = #"{"type":"assistant","isSidechain":false,"message":{"model":"claude-fable-5","role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"make teaser"}}]},"timestamp":"2026-07-12T12:01:05.000Z","cwd":"/work/Praxis","sessionId":"s-interrupted"}"#
    static let redirectReply = #"{"type":"assistant","isSidechain":false,"message":{"model":"claude-fable-5","role":"assistant","content":[{"type":"text","text":"Teaser: [teaser.mp4](output/teaser.mp4)"}]},"timestamp":"2026-07-12T12:03:00.000Z","cwd":"/work/Praxis","sessionId":"s-interrupted"}"#
    static let thanks = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":"Thanks"},"origin":{"kind":"human"},"uuid":"u3","timestamp":"2026-07-12T12:05:00.000Z","cwd":"/work/Praxis","sessionId":"s-interrupted"}"#

    @Test func aTurnThePersonInterruptedIsNotAnswered() throws {
        // They stop the first request's tool call and leave: the interruption ends the turn, and
        // the text before the tool call is no answer.
        let left = try ClaudeCodeAdapter.parse(try fixture("claude-interrupted"))
        #expect(left.turns.isEmpty)
        #expect(left.answeredTurns == 0 && left.finalReplies == 0)
        #expect(left.unknownRecordTypes.isEmpty && left.unknownFields.isEmpty)

        // They ask for something else, which is still running.
        let running = try ClaudeCodeAdapter.parse(try fixture("claude-interrupted", then: Self.redirect, Self.redirectToolCall))
        #expect(running.turns.isEmpty)
        #expect(running.answeredTurns == 0 && running.finalReplies == 0)

        // It is answered: the reply is read, and counted once the next request closes its turn.
        let answered = try ClaudeCodeAdapter.parse(try fixture(
            "claude-interrupted", then: Self.redirect, Self.redirectToolCall, Self.redirectReply))
        #expect(answered.turns.map(\.request) == ["Render the teaser instead"])
        #expect(answered.answeredTurns == 0 && answered.finalReplies == 0)
        let closed = try ClaudeCodeAdapter.parse(try fixture(
            "claude-interrupted", then: Self.redirect, Self.redirectToolCall, Self.redirectReply, Self.thanks))
        #expect(closed.answeredTurns == 1 && closed.finalReplies == 1)
    }

    @Test func textBeforeAnInterruptionIsStillRead() throws {
        // Stopped while it wrote: what it wrote is read as before, and counted as a closed turn's
        // reply, but the turn was not answered.
        let log = try ClaudeCodeAdapter.parse(try fixture("claude-interrupted-reply"))
        #expect(log.turns.map(\.reply) == ["So far, [the release notes](docs/release-notes.md) cover the import screen and"])
        #expect(log.turns[0].request == "Summarize what changed in the release")
        #expect(log.answeredTurns == 0 && log.finalReplies == 1)
        #expect(log.unknownRecordTypes.isEmpty && log.unknownFields.isEmpty)
        // The interruption is not a request.
        let next = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":"Keep going"},"origin":{"kind":"human"},"timestamp":"2026-07-12T13:01:00.000Z","cwd":"/work/Praxis","sessionId":"s-interrupted-reply"}"#
        let reply = #"{"type":"assistant","isSidechain":false,"message":{"model":"claude-fable-5","role":"assistant","content":[{"type":"text","text":"Done."}]},"timestamp":"2026-07-12T13:01:30.000Z","cwd":"/work/Praxis","sessionId":"s-interrupted-reply"}"#
        let resumed = try ClaudeCodeAdapter.parse(try fixture("claude-interrupted-reply", then: next, reply))
        #expect(resumed.turns.map(\.request) == ["Summarize what changed in the release", "Keep going"])
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
        #expect(log.turns.count == 1)
        // It is the log's last, still open: not counted yet.
        #expect(log.answeredTurns == 0 && log.finalReplies == 0)
        let next = #"{"timestamp":"2026-10-05T05:30:00.000Z","type":"turn_context","payload":{"turn_id":"t2","cwd":"/work/Sealwright"}}"#
        let closed = try #require(try adapter.parse(try fixture("codex-rollout", then: next)))
        #expect(closed.answeredTurns == 1 && closed.finalReplies == 1)
    }

    @Test func aLastTurnWithoutAFinalAnswerIsNotYetCountedAsAnswered() throws {
        // Commentary, then a tool call: the thread may still be running, or it ended there.
        let open = try #require(try adapter.parse(try fixture("codex-open-turn")))
        #expect(open.turns.isEmpty)
        #expect(open.answeredTurns == 0)
        #expect(open.unknownRecordTypes.isEmpty && open.unknownFields.isEmpty)

        // Codex starts the next turn: that one was answered, without a final answer.
        let next = #"{"timestamp":"2026-10-05T06:20:00.000Z","type":"turn_context","payload":{"turn_id":"t2","cwd":"/work/Sealwright"}}"#
        let closed = try #require(try adapter.parse(try fixture("codex-open-turn", then: next)))
        #expect(closed.turns.isEmpty)
        #expect(closed.answeredTurns == 1)
        #expect(closed.finalReplies == 0)
    }

    static let redirectContext = #"{"timestamp":"2026-10-05T07:01:00.000Z","type":"turn_context","payload":{"turn_id":"t2","cwd":"/work/Sealwright"}}"#
    static let redirect = #"{"timestamp":"2026-10-05T07:01:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Fix only the second finding"}],"internal_chat_message_metadata_passthrough":{"content_item_kinds":["user.text"]}}}"#
    static let redirectToolCall = #"{"timestamp":"2026-10-05T07:01:05.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"make\"}","call_id":"c2"}}"#
    static let redirectAnswer = #"{"timestamp":"2026-10-05T07:03:00.000Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"Fixed: [review](docs/reviews/review.md)"}]}}"#
    static let nextContext = #"{"timestamp":"2026-10-05T07:05:00.000Z","type":"turn_context","payload":{"turn_id":"t3","cwd":"/work/Sealwright"}}"#

    @Test func anAbortedTurnIsNotAnswered() throws {
        // The person interrupts the first request and leaves.
        let left = try #require(try adapter.parse(try fixture("codex-interrupted")))
        #expect(left.turns.isEmpty)
        #expect(left.answeredTurns == 0 && left.finalReplies == 0)
        #expect(left.unknownRecordTypes.isEmpty && left.unknownFields.isEmpty)

        // They ask for something else, which is still running: the aborted turn is closed, and was
        // not answered.
        let running = try #require(try adapter.parse(try fixture(
            "codex-interrupted", then: Self.redirectContext, Self.redirect, Self.redirectToolCall)))
        #expect(running.turns.isEmpty)
        #expect(running.answeredTurns == 0 && running.finalReplies == 0)

        // It is answered: the answer is read, and counted once the next turn starts.
        let answered = try #require(try adapter.parse(try fixture(
            "codex-interrupted", then: Self.redirectContext, Self.redirect, Self.redirectToolCall, Self.redirectAnswer)))
        #expect(answered.turns.map(\.request) == ["Fix only the second finding"])
        #expect(answered.answeredTurns == 0 && answered.finalReplies == 0)
        let closed = try #require(try adapter.parse(try fixture(
            "codex-interrupted", then: Self.redirectContext, Self.redirect, Self.redirectToolCall, Self.redirectAnswer,
            Self.nextContext)))
        #expect(closed.answeredTurns == 1 && closed.finalReplies == 1)
    }

    /// The provider is the session's, from its meta; the model the turn's, from its context.
    @Test func theProviderAndModelBehindAReply() throws {
        let log = try #require(try adapter.parse(try fixture("codex-rollout")))
        #expect(log.session.modelProvider == "openai")
        #expect(log.turns[0].model == "gpt-5-codex")
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
