import Foundation
import UniformTypeIdentifiers

/// When Gleaner read a delivery's bytes, relative to the reply that handed them over (SPEC §5.1).
public enum Provenance: String, Sendable, Codable {
    case atDelivery = "at_delivery"
    case firstSeenAfterDelivery = "first_seen_after_delivery"
    case neverObserved = "never_observed"
}

/// What Gleaner recorded about a delivery's bytes when it first looked. One without a hash, other
/// than a folder's, is completed once, the first time Gleaner reads the file; one with a hash is
/// never rewritten (SPEC §5.1).
public struct Capture: Sendable, Equatable {
    public var sha256: String?
    public var size: Int64?
    public var modifiedAt: Date?
    public var observedAt: Date
    /// Set when the bytes are kept in the content store.
    public var savedAt: Date?
    public var provenance: Provenance
    /// What was at the path: a file Gleaner read (it has a hash) or a folder; or, with no hash and
    /// never observed, nothing, a file Gleaner couldn't read, or one that isn't a regular file.
    public var kind: LocatorState.Kind

    public var isDirectory: Bool { kind == .directory }

    public init(sha256: String?, size: Int64?, modifiedAt: Date?, observedAt: Date, savedAt: Date?,
                provenance: Provenance, kind: LocatorState.Kind) {
        self.sha256 = sha256
        self.size = size
        self.modifiedAt = modifiedAt
        self.observedAt = observedAt
        self.savedAt = savedAt
        self.provenance = provenance
        self.kind = kind
    }
}

/// One place in a reply that names the artifact.
public struct Evidence: Sendable, Codable, Equatable {
    public var line: Int
    public var syntax: String
    public var rawTarget: String
    public var anchor: String?
    public var excerpt: String
}

/// One reply that handed the artifact to the user.
public struct Delivery: Sendable, Identifiable {
    public var id: String
    /// 1 is the oldest delivery of this artifact.
    public var number: Int
    public var path: String
    public var deliveredAt: Date?
    /// The log line of the reply's first record, which every file that reply named shares with its
    /// log: one reply however many records it took. Nil until a log read before Gleaner recorded it
    /// is read again, and for good once that log is gone.
    public var replyLine: Int?
    /// Where the reply names this file among the files it names, from 0.
    public var replyRank = 0
    public var provider: Provider
    /// The agent's own id for the conversation, and the folder it started in.
    public var sessionID = ""
    public var sessionCwd: String?
    public var sessionTitle: String?
    public var request: String?
    public var cwd: String?
    public var evidence: [Evidence]
    public var logPath: String
    public var capture: Capture?

    public var sha256: String? { capture?.sha256 }
    /// Bytes Gleaner can vouch for as this delivery's.
    public var isTrusted: Bool { capture?.provenance == .atDelivery }
}

public struct Artifact: Sendable, Identifiable {
    /// What a person does with the file, not which field made it: a fixed set that unknown
    /// formats fall into through the system's type tree (rulings §7). The badge keeps the exact
    /// extension, so merging video and audio into media loses nothing.
    public enum Kind: String, Sendable, CaseIterable {
        case document, image, media, web, code, data, model, build, folder, other
    }

    public var path: String
    /// Newest first.
    public let deliveries: [Delivery]
    /// Each delivery's own words (request, session title, reply), and the file name and its folder,
    /// in the form search compares (`Search.form`), made once.
    let ownWords: [String]
    private(set) var searchPlace = ""
    /// What a project filter keys on: the main folder of the repository the file belongs to, or
    /// outside git the folder its agent worked in (see `Projects`).
    public var projectFolder: String
    /// False when no repository was found, at delivery or now: the project is only a folder.
    public var inRepository: Bool
    /// The checkout holding the file; nil when the file is in no repository.
    public var checkout: Checkout?

    /// `repository` and `checkout` are the ones recorded at delivery. They win over what can be
    /// found now, which is worse once a worktree is gone.
    public init(path: String, deliveries: [Delivery], repository: String? = nil, checkout: Checkout? = nil) {
        self.path = path
        self.deliveries = deliveries
        let cwd = deliveries.first?.cwd
        let root = repository ?? Projects.repository(path: path, cwd: cwd)
        projectFolder = root ?? Projects.folder(path: path, cwd: cwd)
        inRepository = root != nil
        self.checkout = checkout ?? Projects.checkout(path: path)
        // One line each: a search word holds no whitespace, so it never reads across two of them.
        ownWords = deliveries.map { d in
            Search.form([d.request ?? "", d.sessionTitle ?? "", d.evidence.map(\.excerpt).joined(separator: " ")].joined(separator: "\n"))
        }
        // The file name and its folder, not the whole path: words like "users" or "projects" in
        // every path would otherwise match everything.
        let folder = folder
        let place = folder.hasPrefix("~") || folder.hasPrefix("/")
            ? (folder as NSString).pathComponents.suffix(2).joined(separator: "/") : folder
        searchPlace = Search.form(name + " " + place)
    }

    /// The project's name, its folder's. Two projects can share one.
    public var project: String { Projects.name(projectFolder) }

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var latest: Delivery { deliveries[0] }

    public var kind: Kind {
        if deliveries.contains(where: { $0.capture?.isDirectory == true }) { return .folder }
        return Self.kind(ofExtension: (path as NSString).pathExtension)
    }

    /// Checks run from specific to general: source code and JSON are also text, so they are
    /// matched before documents.
    public static func kind(ofExtension ext: String) -> Kind {
        let ext = ext.lowercased()
        if let kind = byExtension[ext] { return kind }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
        let checks: [(UTType, Kind)] = [
            (.html, .web), (.audiovisualContent, .media), (.image, .image), (.threeDContent, .model),
            (.sourceCode, .code), (.script, .code), (.json, .data), (.commaSeparatedText, .data),
            (.tabSeparatedText, .data), (.spreadsheet, .data), (.database, .data), (.xml, .data),
            (.diskImage, .build), (.archive, .build), (.application, .build), (.executable, .build),
            (.pdf, .document), (.presentation, .document), (.text, .document), (.compositeContent, .document),
        ]
        return checks.first { type.conforms(to: $0.0) }?.1 ?? .other
    }

    /// Formats the system doesn't type, or types too generally to place.
    static let byExtension: [String: Kind] = [
        "md": .document, "markdown": .document, "pages": .document, "key": .document, "numbers": .data,
        "ts": .code, "tsx": .code, "jsx": .code, "mjs": .code, "vue": .code, "svelte": .code, "rs": .code,
        "go": .code, "kt": .code, "css": .code, "scss": .code, "less": .code, "patch": .code, "diff": .code, "ipynb": .code,
        "yaml": .data, "yml": .data, "toml": .data, "parquet": .data, "sqlite": .data, "jsonl": .data, "ndjson": .data,
        "stl": .model, "obj": .model, "step": .model, "stp": .model, "iges": .model, "igs": .model, "dwg": .model,
        "dxf": .model, "fbx": .model, "glb": .model, "gltf": .model, "blend": .model, "3mf": .model, "skp": .model,
        "f3d": .model, "sldprt": .model, "usdz": .model, "usd": .model,
        "pkg": .build, "ipa": .build, "apk": .build, "app": .build,
    ]

    /// Where the file lives: a worktree, named after its folder wherever it is kept, or the
    /// repository's main folder.
    public var place: String {
        guard let checkout, checkout.folder != checkout.repository else { return "main folder" }
        return "worktree " + (checkout.folder as NSString).lastPathComponent
    }

    /// True when the file lives in a worktree rather than the project's own folder.
    public var inWorktree: Bool { place != "main folder" }

    /// The folder holding the file, relative to where the agent worked when that is an ancestor.
    public var folder: String {
        let directory = (path as NSString).deletingLastPathComponent
        let cwd = latest.cwd.map(standardPath)
        if let cwd, directory == cwd { return "." }
        if let cwd, directory.hasPrefix(cwd + "/") { return String(directory.dropFirst(cwd.count + 1)) }
        return (directory as NSString).abbreviatingWithTildeInPath
    }
}

/// The file as Gleaner found it just now.
public struct FileObservation: Sendable {
    public var state: LocatorState
    public var checkedAt: Date

    public init(state: LocatorState, checkedAt: Date) {
        self.state = state
        self.checkedAt = checkedAt
    }
}

/// "On disk now" (SPEC §5.2): the current file compared with every known delivery.
public enum OnDisk: Equatable, Sendable {
    case same(as: Int)
    case unchangedSinceFirstSeen(Date)
    /// `firstSeen` is set when delivery k's bytes were first seen after it was delivered.
    case rolledBack(to: Int, latest: Int, firstSeen: Date?)
    case changed(since: Int)
    /// `firstSeen` is set when the saved bytes were captured after that delivery.
    case missingWithSavedCopy(of: Int, firstSeen: Date?)
    case missingInGitHistory
    case lost
    case folder
    case special
    /// Something is at the path, but Gleaner can't read it, so it can't say which version it is.
    case unreadable
}

/// What a drag would hand over for one delivery (SPEC §6).
public enum Handoff: Equatable, Sendable {
    public enum Source: Equatable, Sendable { case original, savedCopy }
    /// `firstSeen` is set when the bytes were captured after the delivery and may differ from it.
    case ready(sha: String, from: Source, firstSeen: Date?)
    /// The delivery's bytes are gone. `alternative` is another delivery the current file matches;
    /// nil means the current file was never delivered.
    case unavailable(alternative: Int?, currentSha: String?)
    case restoreFromGit
    case lost
    /// Folders are not versioned in v0.1: a delivered folder is handed over as it is now, and
    /// only while its path is still a folder.
    case folder

    /// The bytes a hand-off copy must hash to: the delivery's, or the current file's when the
    /// person chooses to hand that over instead.
    public var sha: String? {
        switch self {
        case .ready(let sha, _, _): sha
        case .unavailable(_, let current): current
        default: nil
        }
    }
}

extension Artifact {
    /// The path compared by hash with every delivery. It reads as a folder only when the latest
    /// delivery was one and the path still is; anything else at the path is matched by its bytes.
    public func onDisk(_ now: FileObservation, hasSaved: (String) -> Bool) -> OnDisk {
        switch now.state.kind {
        case .directory where latest.capture?.isDirectory == true: return .folder
        case .special: return .special
        case .unreadable: return .unreadable
        case .missing:
            if let saved = deliveries.first(where: { $0.sha256.map(hasSaved) == true }) {
                let firstSeen = saved.capture?.provenance == .firstSeenAfterDelivery ? saved.capture?.observedAt : nil
                return .missingWithSavedCopy(of: saved.number, firstSeen: firstSeen)
            }
            // Folders aren't versioned: what git holds at a delivered folder's path is not shown to be it.
            let recoverable = now.state.git == .recoverableFromHead || now.state.git == .recoverableFromHistory
            return recoverable && latest.capture?.isDirectory != true ? .missingInGitHistory : .lost
        case .file, .directory:
            break
        }
        guard let current = now.state.sha256 else { return .changed(since: latest.number) }
        if current == latest.sha256 {
            if latest.capture?.provenance == .firstSeenAfterDelivery, let seen = latest.capture?.observedAt {
                return .unchangedSinceFirstSeen(seen)
            }
            return .same(as: latest.number)
        }
        let older = deliveries.dropFirst()
        if let match = older.first(where: { $0.isTrusted && $0.sha256 == current }) {
            return .rolledBack(to: match.number, latest: latest.number, firstSeen: nil)
        }
        if let match = older.first(where: { $0.sha256 == current }) {
            return .rolledBack(to: match.number, latest: latest.number, firstSeen: match.capture?.observedAt)
        }
        return .changed(since: latest.number)
    }

    /// Decided by how `delivery` was captured, not by what the path is today: a file delivery is
    /// its hash (the original while it matches, else the saved copy), even when a folder now
    /// stands at the path, and a folder delivery is the live folder only while it is still one,
    /// never what git holds at its path.
    public func handoff(_ delivery: Delivery, now: FileObservation, hasSaved: (String) -> Bool) -> Handoff {
        if delivery.capture?.isDirectory == true, now.state.kind == .directory { return .folder }
        let current = now.state.kind == .file ? now.state.sha256 : nil

        if let sha = delivery.sha256 {
            let firstSeen = delivery.capture?.provenance == .firstSeenAfterDelivery ? delivery.capture?.observedAt : nil
            if current == sha { return .ready(sha: sha, from: .original, firstSeen: firstSeen) }
            if hasSaved(sha) { return .ready(sha: sha, from: .savedCopy, firstSeen: firstSeen) }
        }
        if now.state.kind == .missing {
            let recoverable = now.state.git == .recoverableFromHead || now.state.git == .recoverableFromHistory
            return recoverable && delivery.capture?.isDirectory != true ? .restoreFromGit : .lost
        }
        // Something else is at the path: a changed or unreadable file, a folder, a pipe.
        let others = deliveries.filter { $0.id != delivery.id && current != nil && $0.sha256 == current }
        let match = others.first(where: \.isTrusted) ?? others.first
        return .unavailable(alternative: match?.number, currentSha: current)
    }

    /// The other files each reply named, keyed by delivery id, as their deliveries from that reply
    /// in the order it names them: a sibling delivered again later is still offered as the
    /// occurrence that came with this one.
    public static func deliveredWith(_ artifacts: [Artifact]) -> [Delivery.ID: [Delivery]] {
        var byReply: [String: [Delivery]] = [:]
        for artifact in artifacts {
            for d in artifact.deliveries {
                guard let line = d.replyLine else { continue }
                byReply["\(d.logPath)|\(line)", default: []].append(d)
            }
        }
        var result: [Delivery.ID: [Delivery]] = [:]
        for group in byReply.values where group.count > 1 {
            let ordered = group.sorted { $0.replyRank < $1.replyRank }
            for delivery in ordered {
                result[delivery.id] = ordered.filter { $0.id != delivery.id }
            }
        }
        return result
    }

    /// For a search: nil unless every token appears in the file name, the project, or one
    /// delivery's own words (request, session title, reply). Words from different deliveries don't
    /// combine (SPEC §10). Otherwise the index of the newest delivery whose own words matched, or
    /// 0 when the name or project alone matched.
    public func match(_ tokens: [String]) -> Int? {
        matches(tokens, project: project)?.index
    }

    /// `match`, with the project as the library shows it, and whether the delivery's own words
    /// matched or only the name or project did.
    public func matches(_ tokens: [String], project: String) -> (index: Int, ownWords: Bool)? {
        guard !tokens.isEmpty else { return (0, false) }
        let tokens = tokens.map(Search.form)
        let shared = searchPlace + " " + Search.form(project)
        let matching = deliveries.indices.filter { i in
            tokens.allSatisfy { token in Search.has(shared, token) || Search.has(ownWords[i], token) }
        }
        guard let first = matching.first else { return nil }
        let byOwnWords = matching.first { i in tokens.contains { Search.has(ownWords[i], $0) } }
        return byOwnWords.map { ($0, true) } ?? (first, false)
    }
}

/// Which candidates enter the library until Gate 1 labels say otherwise (SPEC §9): links and
/// images always; inline code and bare paths only when they name a directory path without a
/// line anchor, which filters out most code references like `App.tsx` or `src/a.ts:42`.
public enum Admission {
    public static func admits(_ candidate: DeliveryCandidate) -> Bool {
        // A placeholder (`build/<name>.zip`, `out/{id}.md`) names a pattern, not a file.
        if candidate.path.contains(where: { "<>{}".contains($0) }) { return false }
        return candidate.evidence.contains { item in
            switch item.mention.syntax {
            case .link, .image: return !isLineAnchor(item.mention.anchor)
            case .code, .bare: return item.mention.anchor == nil && item.mention.rawTarget.dropFirst().contains("/")
            }
        }
    }

    /// `:42`, `:42:7` or `#L42` point at a line of code; a heading anchor (`#usage`) points at a
    /// section of a document that may itself be the delivery.
    static func isLineAnchor(_ anchor: String?) -> Bool {
        guard let anchor else { return false }
        return anchor.range(of: #"^(:\d|#L\d)"#, options: .regularExpression) != nil
    }
}

/// How search compares words: lowercased and in one Unicode form (NFC), so an accent typed one
/// way finds it stored the other, compared as plain text, which is fast enough to run on every
/// keystroke over a large library.
enum Search {
    static func form(_ text: String) -> String {
        text.lowercased().precomposedStringWithCanonicalMapping
    }

    static func has(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: .literal) != nil
    }
}
