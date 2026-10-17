import Foundation
import UniformTypeIdentifiers

/// When Gleaner read a delivery's bytes, relative to the reply that handed them over (SPEC §5.1).
public enum Provenance: String, Sendable, Codable {
    case atDelivery = "at_delivery"
    case firstSeenAfterDelivery = "first_seen_after_delivery"
    case neverObserved = "never_observed"
}

/// What Gleaner recorded about a delivery's bytes when it first looked.
public struct Capture: Sendable, Equatable {
    public var sha256: String?
    public var size: Int64?
    public var modifiedAt: Date?
    public var observedAt: Date
    /// Set when the bytes are kept in the content store.
    public var savedAt: Date?
    public var provenance: Provenance
    public var isDirectory: Bool

    public init(sha256: String?, size: Int64?, modifiedAt: Date?, observedAt: Date, savedAt: Date?,
                provenance: Provenance, isDirectory: Bool) {
        self.sha256 = sha256
        self.size = size
        self.modifiedAt = modifiedAt
        self.observedAt = observedAt
        self.savedAt = savedAt
        self.provenance = provenance
        self.isDirectory = isDirectory
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
    public var provider: Provider
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
    public var deliveries: [Delivery]
    /// See `Projects.project(path:cwd:)`.
    public var project: String

    public init(path: String, deliveries: [Delivery]) {
        self.path = path
        self.deliveries = deliveries
        project = Projects.project(path: path, cwd: deliveries.first?.cwd)
    }

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

    /// Where the file lives: a named worktree, or the project's own folder.
    public var place: String {
        for marker in ["/.claude/worktrees/", "/.worktrees/", "/.codex/worktrees/"] {
            if let range = path.range(of: marker) {
                let rest = path[range.upperBound...]
                return "worktree " + (rest.split(separator: "/").first.map(String.init) ?? "")
            }
        }
        return "main folder"
    }

    /// True when the file lives in a worktree rather than the project's own folder.
    public var inWorktree: Bool { place != "main folder" }

    /// The folder holding the file, relative to where the agent worked when that is an ancestor.
    public var folder: String {
        let directory = (path as NSString).deletingLastPathComponent
        if let cwd = latest.cwd, directory == cwd { return "." }
        if let cwd = latest.cwd, directory.hasPrefix(cwd + "/") { return String(directory.dropFirst(cwd.count + 1)) }
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
        case .missing:
            if let saved = deliveries.first(where: { $0.sha256.map(hasSaved) == true }) {
                let firstSeen = saved.capture?.provenance == .firstSeenAfterDelivery ? saved.capture?.observedAt : nil
                return .missingWithSavedCopy(of: saved.number, firstSeen: firstSeen)
            }
            if now.state.git == .recoverableFromHead || now.state.git == .recoverableFromHistory {
                return .missingInGitHistory
            }
            return .lost
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
    /// stands at the path, and a folder delivery is the live folder only while it is still one.
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
            return recoverable ? .restoreFromGit : .lost
        }
        // Something else is at the path: a changed or unreadable file, a folder, a pipe.
        let others = deliveries.filter { $0.id != delivery.id && current != nil && $0.sha256 == current }
        let match = others.first(where: \.isTrusted) ?? others.first
        return .unavailable(alternative: match?.number, currentSha: current)
    }

    /// For a search: nil unless every token appears in the file name, the project, or one
    /// delivery's own words (request, session title, reply). Words from different deliveries don't
    /// combine (SPEC §10). Otherwise the index of the newest delivery whose own words matched, or
    /// 0 when the name or project alone matched.
    public func match(_ tokens: [String]) -> (deliveryIndex: Int, fields: [String])? {
        guard !tokens.isEmpty else { return (0, []) }
        // The file name and its folder, not the whole path: words like "users" or "projects" in
        // every path would otherwise match everything.
        let place = folder.hasPrefix("~") || folder.hasPrefix("/")
            ? (folder as NSString).pathComponents.suffix(2).joined(separator: "/") : folder
        let name = (self.name + " " + place).lowercased()
        let projectName = project.lowercased()
        func fields(_ d: Delivery) -> [(String, String)] {
            [("file name", name), ("project", projectName),
             ("your request", d.request?.lowercased() ?? ""),
             ("session title", d.sessionTitle?.lowercased() ?? ""),
             ("reply", d.evidence.map(\.excerpt).joined(separator: " ").lowercased())]
        }
        let matching = deliveries.indices.filter { i in
            let all = fields(deliveries[i]).map(\.1).joined(separator: " ")
            return tokens.allSatisfy { all.contains($0) }
        }
        guard let first = matching.first else { return nil }
        let index = matching.first { i in
            fields(deliveries[i]).dropFirst(2).contains { field in tokens.contains { field.1.contains($0) } }
        } ?? first
        let hit = fields(deliveries[index]).filter { field in tokens.contains { field.1.contains($0) } }.map(\.0)
        return (index, hit)
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
