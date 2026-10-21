// Spike A: read-only delivery extraction over local agent logs.
// Writes a labeling sheet, whose labels a rerun carries over, a recall sample, and a summary.
// See docs/SPEC.md §12–13.

import CryptoKit
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

/// The first 12 hex digits of the SHA-256 of `data`.
func hex12(_ data: Data) -> String {
    SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
}

/// One labeling row: a path named in one reply, with every place the reply names it.
struct Candidate {
    var session: SessionInfo
    var turn: Turn
    var delivery: DeliveryCandidate

    var first: (part: ReplyPart, mention: Mention) { delivery.evidence[0] }
    var path: String { delivery.path }

    /// Stable across reruns; with `fingerprint`, how a label finds its row again.
    var id: String { hex12(Data("\(session.logPath)\n\(first.part.line)\n\(path)".utf8)) }

    /// What a label judges: this reply naming this path. A rerun carries a label only while it holds.
    var fingerprint: String { hex12(Data("\(path)\n\(turn.reply)".utf8)) }
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

// A log folder that is missing or can't be listed is reported and skipped: the sheet covers the
// logs that could be read.
let sources = LogSources(claudeProjects: options.claudeRoot, codexHome: options.codexRoot)
let jobs: [(Provider, URL)] = Provider.allCases.flatMap { provider in
    let (source, files) = sources.logs(provider)
    let folder = sources.folder(provider).path
    switch source.folder {
    case .absent: FileHandle.standardError.write(Data("\(provider.rawValue): no log folder at \(folder)\n".utf8))
    case .unreadable(let reason): FileHandle.standardError.write(Data("\(provider.rawValue): can't list \(folder): \(reason)\n".utf8))
    case .listed: break
    }
    for unlisted in source.unlistedFolders {
        FileHandle.standardError.write(Data("\(provider.rawValue): can't list \(unlisted)\n".utf8))
    }
    return files.map { (provider, $0) }
}
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
        MentionExtractor.candidates(in: turn).map { Candidate(session: log.session, turn: turn, delivery: $0) }
    }
}

let paths = Array(Set(candidates.map(\.path)))
FileHandle.standardError.write(Data("observing \(paths.count) paths…\n".utf8))
let observed = Collector<(String, LocatorState)>()
DispatchQueue.concurrentPerform(iterations: paths.count) { index in
    observed.append((paths[index], Locator.observe(paths[index])))
}
let states = Dictionary(uniqueKeysWithValues: observed.items)
let repliesNamingPath = Dictionary(grouping: candidates, by: \.path).mapValues(\.count)

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

let home = NSHomeDirectory()

/// Shareable form: home directory shortened and secret-shaped strings masked.
func share(_ text: String?) -> String {
    guard let text else { return "" }
    return Redactor.redact(text.replacingOccurrences(of: home, with: "~"))
}

/// What a person entered on a previous sheet, read by column name from LF, CRLF or CR lines: the rows
/// that hold a label or note, and those that can't be read. Nil when the sheet isn't UTF-8, repeats a
/// column name, or has no id, label or note column.
struct Entered {
    var header: [String]
    var id: Int, label: Int, note: Int, fingerprint: Int?
    var rows: [[String]]

    init?(_ data: Data) {
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        let lines = text.split { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard let header = lines.first, Set(header).count == header.count, let id = header.firstIndex(of: "id"),
              let label = header.firstIndex(of: "label"), let note = header.firstIndex(of: "note") else { return nil }
        (self.header, self.id, self.label, self.note) = (header, id, label, note)
        fingerprint = header.firstIndex(of: "fingerprint")
        rows = lines.dropFirst().filter { $0.count != header.count || !$0[label].isEmpty || !$0[note].isEmpty }
    }
}

let header = [
    "id", "label", "note", "admitted", "provider", "project", "session_title", "delivered_at", "syntax", "anchors",
    "raw_targets", "path", "kind", "size", "sha256_12", "git", "occurrences", "replies_naming_path",
    "request", "evidence", "session_id", "fingerprint",
]

// A label carries to the candidate it was given for: the same id, with the same fingerprint. Any
// other is set aside with why. A sheet whose replacement would lose anything a person entered, a label
// set aside or a column of its own, is kept first.
let candidatesURL = options.out.appendingPathComponent("candidates.tsv")

/// Ends the run before it replaces anything, for a sheet whose labels it can't keep.
func stop(_ message: String) -> Never {
    FileHandle.standardError.write(Data("gleaner-spike: \(message) Nothing was replaced.\n".utf8))
    exit(1)
}

// Only a sheet that isn't there is no sheet: one that can't be opened may hold labels.
let previousSheet: Data?
do {
    previousSheet = try Data(contentsOf: candidatesURL)
} catch CocoaError.fileReadNoSuchFile {
    previousSheet = nil
} catch {
    stop("can't open \(candidatesURL.path) to keep its labels: \(error.localizedDescription)")
}
let previous = previousSheet.flatMap(Entered.init)
var carried: [String: (label: String, note: String)] = [:]
var setAside: [[String]] = []  // why, then the row as it was
if let previous {
    let now = Dictionary(candidates.map { ($0.id, $0.fingerprint) }, uniquingKeysWith: { first, _ in first })
    let rowsWithID = Dictionary(previous.rows.filter { $0.count == previous.header.count }.map { ($0[previous.id], 1) },
                                uniquingKeysWith: +)
    for row in previous.rows {
        let why: String
        if row.count != previous.header.count || row[previous.id].isEmpty || rowsWithID[row[previous.id]] != 1 {
            why = "unreadable"
        } else if let fingerprint = now[row[previous.id]] {
            if let column = previous.fingerprint, row[column] == fingerprint {
                carried[row[previous.id]] = (row[previous.label], row[previous.note])
                continue
            }
            why = "changed"
        } else {
            why = "gone"
        }
        setAside.append([why] + row)
    }
}
var kept: String?
if let previousSheet, previous?.header != header || !setAside.isEmpty {
    let folder = options.out.appendingPathComponent("replaced"), name = "candidates-\(hex12(previousSheet)).tsv"
    let copy = folder.appendingPathComponent(name)
    // A copy already there stands for the sheet only if it holds the sheet's bytes: an earlier run
    // may have stopped while writing it. A new copy appears whole or not at all.
    do {
        guard try Data(contentsOf: copy) == previousSheet else {
            stop("\(copy.path) doesn't hold the sheet's bytes; move it aside and run again.")
        }
    } catch CocoaError.fileReadNoSuchFile {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try previousSheet.write(to: copy, options: .atomic)
        } catch {
            stop("can't keep the sheet as \(copy.path): \(error.localizedDescription)")
        }
    } catch {
        stop("can't check \(copy.path): \(error.localizedDescription)")
    }
    kept = "replaced/" + name
}

var tsv = header.joined(separator: "\t") + "\n"
var locatorRows = ["id", "log", "lines", "path"].joined(separator: "\t") + "\n"
for candidate in candidates {
    let state = states[candidate.path]
    let evidence = candidate.delivery.evidence
    let labeled = carried[candidate.id]
    let row: [String?] = [
        candidate.id, labeled?.label, labeled?.note,
        // What the §9 rule decides, next to the label it is measured against.
        Admission.admits(candidate.delivery) ? "yes" : "no",
        candidate.session.provider.rawValue,
        projectName(candidate.first.part.cwd ?? candidate.session.cwd),
        share(candidate.session.title),
        candidate.first.part.at.map { $0.formatted(dateFormat) },
        Array(Set(evidence.map(\.mention.syntax.rawValue))).sorted().joined(separator: ","),
        share(evidence.compactMap(\.mention.anchor).joined(separator: " ")),
        share(evidence.map(\.mention.rawTarget).joined(separator: " ‖ ")),
        share(candidate.path),
        state?.kind.rawValue,
        state?.size.map(String.init),
        state?.sha256.map { String($0.prefix(12)) },
        state?.git.rawValue,
        String(evidence.count),
        String(repliesNamingPath[candidate.path] ?? 0),
        share(clip(candidate.turn.request, 300)),
        share(evidence.map(\.mention.excerpt).joined(separator: " ‖ ")),
        candidate.session.id,
        candidate.fingerprint,
    ]
    tsv += row.map(cell).joined(separator: "\t") + "\n"
    locatorRows += [candidate.id, candidate.session.logPath, evidence.map { String($0.part.line) }.joined(separator: ","), candidate.path]
        .map(cell).joined(separator: "\t") + "\n"
}
try tsv.write(to: candidatesURL, atomically: true, encoding: .utf8)
try ([["why"] + (previous?.header ?? header)] + setAside).map { $0.joined(separator: "\t") + "\n" }.joined()
    .write(to: options.out.appendingPathComponent("labels-not-carried.tsv"), atomically: true, encoding: .utf8)
try locatorRows.write(to: options.out.appendingPathComponent("locators.internal.tsv"), atomically: true, encoding: .utf8)

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
    let extracted = MentionExtractor.candidates(in: turn)
    recall += """
        ---

        ## \(index + 1). \(share(session.title ?? "(untitled)"))

        - provider: \(session.provider.rawValue) · project: \(projectName(turn.cwd ?? session.cwd)) · \(turn.deliveredAt.map { $0.formatted(dateFormat) } ?? "?")
        - log: `\(share(session.logPath)):\(turn.parts.map { String($0.line) }.joined(separator: ","))`
        - request: \(share(turn.request).replacingOccurrences(of: "\n", with: " "))

        <details><summary>Reply (\(turn.reply.count) chars)</summary>

        \(share(turn.reply))

        </details>

        Extracted:
        \(extracted.isEmpty ? "- (none)" : extracted.map { c in "- `\(share(c.path))` × \(c.evidence.count) [\(Set(c.evidence.map(\.mention.syntax.rawValue)).sorted().joined(separator: ","))] — \(states[c.path]?.kind.rawValue ?? "?")" }.joined(separator: "\n"))

        Missed:


        """
}
try recall.write(to: options.out.appendingPathComponent("recall-sample.md"), atomically: true, encoding: .utf8)

var summary = "Gleaner Spike A — \(Date().formatted(dateFormat))\n\n"
summary += "labels: \(carried.count) carried"
if !setAside.isEmpty {
    let whys = Dictionary(grouping: setAside, by: { $0[0] }).map { "\($0.value.count) \($0.key)" }.sorted()
    summary += ", \(setAside.count) set aside in labels-not-carried.tsv (\(whys.joined(separator: ", ")))"
}
if previousSheet != nil, previous == nil { summary += "; the previous candidates.tsv couldn't be read as a sheet" }
if let kept { summary += "; the sheet it replaced is kept as \(kept)" }
summary += "\n\n"
for provider in Provider.allCases {
    let providerLogs = logs.filter { $0.session.provider == provider }
    let turns = providerLogs.flatMap(\.turns)
    let providerCandidates = candidates.filter { $0.session.provider == provider }
    let skipped = parsed.items.filter { if case .skipped(provider, _) = $0 { true } else { false } }.count
    let failed = parsed.items.compactMap { if case .failed(provider, let path, let error) = $0 { "\(path): \(error)" } else { nil } }
    let unique = Set(providerCandidates.map(\.path))
    func tally<K: Hashable>(_ key: (LocatorState) -> K) -> [K: Int] {
        unique.compactMap { states[$0] }.reduce(into: [:]) { $0[key($1), default: 0] += 1 }
    }
    summary += """
        [\(provider.rawValue)]
        session files parsed: \(providerLogs.count)  skipped (sub-agent): \(skipped)  failed: \(failed.count)
        sessions with replies: \(providerLogs.filter { !$0.turns.isEmpty }.count)
        final replies: \(turns.count)  without request context: \(turns.filter { $0.request == nil }.count)
        replies with candidates: \(turns.filter { !MentionExtractor.candidates(in: $0).isEmpty }.count)
        candidates: \(providerCandidates.count)  unique paths: \(unique.count)
        by syntax: \(Dictionary(grouping: providerCandidates.flatMap(\.delivery.evidence), by: \.mention.syntax.rawValue).mapValues(\.count).sorted { $0.key < $1.key })
        with line anchor: \(providerCandidates.filter { $0.delivery.evidence.contains { $0.mention.anchor != nil } }.count)
        unique paths by kind: \(tally { $0.kind.rawValue }.sorted { $0.key < $1.key })
        unique paths by git: \(tally { $0.git.rawValue }.sorted { $0.key < $1.key })
        unknown record types: \(providerLogs.reduce(into: [String: Int]()) { acc, log in acc.merge(log.unknownRecordTypes, uniquingKeysWith: +) }.sorted { $0.key < $1.key })
        malformed lines: \(providerLogs.reduce(0) { $0 + $1.malformedLines })
        \(failed.map { "failed: \($0)" }.joined(separator: "\n"))

        """
}
try summary.write(to: options.out.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
print(summary)
print("wrote \(options.out.path)/{candidates.tsv,labels-not-carried.tsv,recall-sample.md,summary.txt}")
