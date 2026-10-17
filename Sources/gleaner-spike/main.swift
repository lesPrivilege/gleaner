// Spike A: read-only delivery extraction over local agent logs.
// Writes a labeling sheet, a recall sample, and a summary. See docs/SPEC.md §12–13.

import Foundation
import GleanerCore

struct Options {
    var claudeRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    var codexRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    var out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("out")
    var sample = 50
    var seed: UInt64 = 42

    init(_ arguments: [String]) {
        var it = arguments.dropFirst().makeIterator()
        while let flag = it.next() {
            guard let value = it.next() else { usage() }
            switch flag {
            case "--claude-root": claudeRoot = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            case "--codex-home": codexRoot = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            case "--out": out = URL(fileURLWithPath: value)
            case "--sample": guard let n = Int(value) else { usage() }; sample = n
            case "--seed": guard let n = UInt64(value) else { usage() }; seed = n
            default: usage()
            }
        }
    }

    func usage() -> Never {
        FileHandle.standardError.write(Data(
            "usage: gleaner-spike [--claude-root DIR] [--codex-home DIR] [--out DIR] [--sample N] [--seed N]\n".utf8))
        exit(2)
    }
}

struct Candidate {
    var session: SessionInfo
    var turn: Turn
    var mention: Mention
}

/// Deterministic sampling so a labeled sheet can be regenerated.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class Collector<T>: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var items: [T] = []
    func append(_ item: T) { lock.withLock { items.append(item) } }
}

let options = Options(CommandLine.arguments)
let codex = CodexAdapter(titles: CodexAdapter.loadTitles(index: options.codexRoot.appendingPathComponent("session_index.jsonl")))

enum Parsed {
    case log(SessionLog)
    case skipped(Provider, String)
    case failed(Provider, String, String)
}

let jobs: [(Provider, URL)] =
    ClaudeCodeAdapter.sessionFiles(root: options.claudeRoot).map { (.claudeCode, $0) }
    + CodexAdapter.sessionFiles(root: options.codexRoot.appendingPathComponent("sessions")).map { (.codex, $0) }
FileHandle.standardError.write(Data("parsing \(jobs.count) session files…\n".utf8))

let parsed = Collector<Parsed>()
DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
    let (provider, url) = jobs[index]
    do {
        switch provider {
        case .claudeCode: parsed.append(.log(try ClaudeCodeAdapter.parse(url)))
        case .codex: parsed.append(try codex.parse(url).map(Parsed.log) ?? .skipped(.codex, url.path))
        }
    } catch {
        parsed.append(.failed(provider, url.path, "\(error)"))
    }
}

let logs = parsed.items.compactMap { if case .log(let log) = $0 { log } else { nil } }
    .sorted { $0.session.logPath < $1.session.logPath }
let candidates = logs.flatMap { log in
    log.turns.flatMap { turn in
        MentionExtractor.extract(from: turn.reply, cwd: turn.cwd).map { Candidate(session: log.session, turn: turn, mention: $0) }
    }
}

let paths = Array(Set(candidates.map(\.mention.path)))
FileHandle.standardError.write(Data("observing \(paths.count) paths…\n".utf8))
let observed = Collector<(String, LocatorState)>()
DispatchQueue.concurrentPerform(iterations: paths.count) { index in
    observed.append((paths[index], Locator.observe(paths[index])))
}
let states = Dictionary(uniqueKeysWithValues: observed.items)
let mentionCounts = Dictionary(grouping: candidates, by: \.mention.path).mapValues(\.count)

// MARK: Output

let dateFormat = Date.ISO8601FormatStyle(timeZone: .current)

func cell(_ value: String?) -> String {
    (value ?? "").replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ⏎ ")
}

func clip(_ text: String?, _ limit: Int) -> String {
    guard let text else { return "" }
    return text.count > limit ? String(text.prefix(limit)) + "…" : text
}

/// The folder a person would call the project; worktrees are named after their parent repository.
func projectName(_ cwd: String?) -> String {
    guard let cwd else { return "" }
    for marker in ["/.claude/worktrees/", "/.worktrees/", "/worktrees/"] {
        if let range = cwd.range(of: marker) {
            return (String(cwd[..<range.lowerBound]) as NSString).lastPathComponent
        }
    }
    return (cwd as NSString).lastPathComponent
}

try FileManager.default.createDirectory(at: options.out, withIntermediateDirectories: true)

let header = [
    "id", "label", "note", "provider", "project", "session_title", "delivered_at", "syntax", "anchor",
    "raw_target", "resolved_path", "kind", "size", "sha256_12", "git", "mentions_of_path",
    "request", "evidence", "log", "session_id",
]
var tsv = header.joined(separator: "\t") + "\n"
for (index, candidate) in candidates.enumerated() {
    let state = states[candidate.mention.path]
    let row: [String?] = [
        String(index + 1), "", "",
        candidate.session.provider.rawValue,
        projectName(candidate.turn.cwd ?? candidate.session.cwd),
        candidate.session.title.map(Redactor.redact),
        candidate.turn.deliveredAt.map { $0.formatted(dateFormat) },
        candidate.mention.syntax.rawValue,
        candidate.mention.anchor,
        candidate.mention.rawTarget,
        candidate.mention.path,
        state?.kind.rawValue,
        state?.size.map(String.init),
        state?.sha256.map { String($0.prefix(12)) },
        state?.git.rawValue,
        String(mentionCounts[candidate.mention.path] ?? 0),
        Redactor.redact(clip(candidate.turn.request, 300)),
        Redactor.redact(candidate.mention.excerpt),
        "\(candidate.session.logPath):\(candidate.turn.logLine)",
        candidate.session.id,
    ]
    tsv += row.map(cell).joined(separator: "\t") + "\n"
}
try tsv.write(to: options.out.appendingPathComponent("candidates.tsv"), atomically: true, encoding: .utf8)

var rng = SplitMix64(state: options.seed)
let allTurns = logs.flatMap { log in log.turns.map { (log.session, $0) } }
let sample = allTurns.shuffled(using: &rng).prefix(options.sample)
    .sorted { ($0.1.deliveredAt ?? .distantPast) < ($1.1.deliveredAt ?? .distantPast) }
var recall = """
    # Recall sample

    \(sample.count) final replies drawn at random (seed \(options.seed)) from \(allTurns.count).
    For each reply, list any delivered artifact that is missing from "Extracted", and strike extracted
    items that are not deliveries.


    """
for (index, (session, turn)) in sample.enumerated() {
    let extracted = MentionExtractor.extract(from: turn.reply, cwd: turn.cwd)
    recall += """
        ---

        ## \(index + 1). \(Redactor.redact(session.title ?? "(untitled)"))

        - provider: \(session.provider.rawValue) · project: \(projectName(turn.cwd ?? session.cwd)) · \(turn.deliveredAt.map { $0.formatted(dateFormat) } ?? "?")
        - log: `\(session.logPath):\(turn.logLine)`
        - request: \(Redactor.redact(clip(turn.request, 400)).replacingOccurrences(of: "\n", with: " "))

        <details><summary>Reply (\(turn.reply.count) chars)</summary>

        \(Redactor.redact(clip(turn.reply, 4000)))

        </details>

        Extracted:
        \(extracted.isEmpty ? "- (none)" : extracted.map { "- [\($0.syntax.rawValue)] `\($0.path)`\($0.anchor.map { " \($0)" } ?? "") — \(states[$0.path]?.kind.rawValue ?? "?")" }.joined(separator: "\n"))

        Missed:


        """
}
try recall.write(to: options.out.appendingPathComponent("recall-sample.md"), atomically: true, encoding: .utf8)

var summary = "Gleaner Spike A — \(Date().formatted(dateFormat))\n\n"
for provider in Provider.allCases {
    let providerLogs = logs.filter { $0.session.provider == provider }
    let turns = providerLogs.flatMap(\.turns)
    let providerCandidates = candidates.filter { $0.session.provider == provider }
    let skipped = parsed.items.filter { if case .skipped(provider, _) = $0 { true } else { false } }.count
    let failed = parsed.items.compactMap { if case .failed(provider, let path, let error) = $0 { "\(path): \(error)" } else { nil } }
    let unique = Set(providerCandidates.map(\.mention.path))
    func tally<K: Hashable>(_ key: (LocatorState) -> K) -> [K: Int] {
        unique.compactMap { states[$0] }.reduce(into: [:]) { $0[key($1), default: 0] += 1 }
    }
    summary += """
        [\(provider.rawValue)]
        session files parsed: \(providerLogs.count)  skipped (sub-agent): \(skipped)  failed: \(failed.count)
        sessions with replies: \(providerLogs.filter { !$0.turns.isEmpty }.count)
        final replies: \(turns.count)  without request context: \(turns.filter { $0.request == nil }.count)
        replies with candidates: \(turns.filter { !MentionExtractor.extract(from: $0.reply, cwd: $0.cwd).isEmpty }.count)
        candidates: \(providerCandidates.count)  unique paths: \(unique.count)
        by syntax: \(Dictionary(grouping: providerCandidates, by: \.mention.syntax.rawValue).mapValues(\.count).sorted { $0.key < $1.key })
        with line anchor: \(providerCandidates.filter { $0.mention.anchor != nil }.count)
        unique paths by kind: \(tally { $0.kind.rawValue }.sorted { $0.key < $1.key })
        unique paths by git: \(tally { $0.git.rawValue }.sorted { $0.key < $1.key })
        unknown record types: \(providerLogs.reduce(into: [String: Int]()) { acc, log in acc.merge(log.unknownRecordTypes, uniquingKeysWith: +) }.sorted { $0.key < $1.key })
        \(failed.map { "failed: \($0)" }.joined(separator: "\n"))

        """
}
try summary.write(to: options.out.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
print(summary)
print("wrote \(options.out.path)/{candidates.tsv,recall-sample.md,summary.txt}")
