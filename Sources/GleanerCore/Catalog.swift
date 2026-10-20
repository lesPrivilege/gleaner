import Foundation

/// Read-only queries over the library, for a local agent and for anything else outside the app
/// (docs/design/query-core.md): find the delivery a person means, select its exact version, read
/// only what is needed, and hand those bytes on. It opens the registry to read only, never
/// indexes, and never writes a project folder; a hand-off copy goes to Gleaner's own caches.
/// Every answer carries the index it is evidence of (`Index`) and names each delivery by its
/// identity fields (`Reference`).
public struct Catalog: Sendable {
    public let registry: Registry
    public let store: ContentStore
    /// Files over this size were tracked by hash only, as the app's indexer does (SPEC §6).
    public var saveLimit: Int64 = 64 << 20

    public init(registry: Registry, store: ContentStore) {
        self.registry = registry
        self.store = store
    }

    /// The library where the app keeps it (`LibraryFolders`). `home` stands in for the home folder,
    /// as the app's `-GleanerHome` does.
    public init(home: URL? = nil) throws {
        let folders = LibraryFolders(home: home)
        self.init(registry: try Registry(readingAt: folders.registry),
                  store: ContentStore(objects: folders.objects, staging: folders.staging))
    }

    /// How answers are written as JSON: snake_case keys, ISO 8601 dates, keys sorted, paths as they are.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Reads what `encoder` wrote.
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: Commands

extension Catalog {
    /// The works whose words match every term (SPEC §10), as the app's search finds and lists them
    /// (`Organization.search`), each by the delivery the search matched, in the file that holds it;
    /// at most `limit` of them. The library is the app's: without the agents turned off, files the
    /// person joined as one work, each work in the project the app shows it in and found by its
    /// collections' names, after the person's corrections. `project` names that project by its name as shown, or a derived one by its
    /// folder, in any form an agent may have it (`/private/tmp/app/` is `/tmp/app`); the project
    /// Gleaner found a file in, by its folder or name, finds it too, wherever the person put it.
    public func find(_ terms: [String], project: String? = nil, kind: Artifact.Kind? = nil, limit: Int = 20) throws -> Found {
        guard limit > 0 else { throw Failure.usage("The limit must be at least 1.") }
        let tokens = Search.tokens(terms.joined(separator: " "))
        let folder = project.flatMap { $0.hasPrefix("/") ? Paths.standard($0) : nil }
        let index = try registry.index()
        let organization = try organize(try shown().artifacts)
        func place(_ work: Work) -> Project {
            organization.project(work.project).map { Project(name: $0.name, folder: $0.folder) }
                ?? Project(name: work.latest.project, folder: work.latest.projectFolder)
        }
        let matches = organization.search(tokens, kind: kind) { work in
            guard let project else { return true }
            let shown = place(work)
            if let folder, folder == shown.folder || work.files.contains(where: { $0.projectFolder == folder }) { return true }
            return ([shown.name] + work.files.flatMap { [organization.projectName($0.projectFolder), $0.project] })
                .contains { $0.caseInsensitiveCompare(project) == .orderedSame }
        }
        let results = matches.prefix(limit).map { work, delivery in
            let artifact = work.file(of: delivery)
            return Hit(reference: reference(delivery, of: artifact, now: check(artifact), library: index.library),
                       project: place(work), kind: artifact.kind,
                       deliveredAt: delivery.deliveredAt, request: Self.excerpt(delivery.request))
        }
        return Found(index: index, total: matches.count, truncated: matches.count > limit, results: Array(results))
    }

    /// The delivery `id` with every delivery of its file, the file on disk now, what handing it on
    /// would give, and the request and reply that made it.
    public func show(_ id: String) throws -> Shown {
        let (artifacts, artifact, delivery) = try lookup(id)
        let index = try registry.index()
        let now = check(artifact)
        return Shown(
            index: index, reference: reference(delivery, of: artifact, now: now, library: index.library),
            number: delivery.number, deliveredAt: delivery.deliveredAt, request: delivery.request,
            reply: delivery.evidence.first?.excerpt,
            handoff: Plan(artifact.handoff(delivery, now: now, hasSaved: store.has), in: artifact, now: now),
            project: project(of: artifact, in: try organize(artifacts)), kind: artifact.kind,
            deliveries: artifact.deliveries.map {
                Version(reference: reference($0, of: artifact, now: now, library: index.library),
                        number: $0.number, deliveredAt: $0.deliveredAt)
            },
            onDisk: Disk(kind: now.state.kind, sha256: now.state.sha256, checkedAt: now.checkedAt))
    }

    /// The text of the delivery's exact bytes: its saved copy, or the original only while it hashes
    /// to the capture, never what is at the path instead. `span` selects lines or bytes (all of
    /// them when nil), and at most `max` bytes come back. A cut never splits a character. However
    /// large the version, only what can come back is held.
    public func read(_ id: String, span: Span? = nil, max: Int = 16 << 10) throws -> Text {
        switch span {
        case .lines(let first, let last)? where first < 1 || last < first:
            throw Failure.usage("Lines are counted from 1, and a range of them ends where it starts or later.")
        case .bytes(let start, let end)? where start < 0 || end < start:
            throw Failure.usage("Bytes are counted from 0, and a range of them ends where it starts or later.")
        default:
            break
        }
        guard max > 0 else { throw Failure.usage("The most to read must be at least 1 byte.") }
        let (_, artifact, delivery) = try lookup(id)
        let index = try registry.index()
        let now = check(artifact)
        guard case .ready(let sha, _, _) = artifact.handoff(delivery, now: now, hasSaved: store.has) else {
            throw Failure.unavailable(reason(delivery))
        }
        // The saved copy whenever there is one, as a hand-off copy is made: unlike the original, no
        // one rewrites it while it is read. A saved copy damaged on disk falls back to the original
        // while that still hashes to the version, as handing it on does.
        let ends = (store.has(sha) ? [Comparison.End(title: artifact.name, source: "saved copy", sha: sha, url: store.objectURL(sha))] : [])
            + [Comparison.End(title: artifact.name, source: "file on disk", sha: sha, url: URL(fileURLWithPath: artifact.path))]
        // One pass per end, and the version is never held whole: all of it is hashed and checked to
        // be text, while the selection's ends are found and only the bytes from its start that the
        // answer can hold are kept, with a few more to end it between characters.
        var lower: Int?, upper: Int?, newlines = 0, offset = 0, kept = Data(), text = Comparison.TextCheck()
        let room = Swift.min(max, Int.max - 8) + 8
        func pass(_ end: Comparison.End) -> Int64? {
            (lower, upper, newlines, offset, kept, text) = (0, nil, 0, 0, Data(), Comparison.TextCheck())
            switch span {
            case .lines(let first, _)?: lower = first == 1 ? 0 : nil
            case .bytes(let start, let end)?: (lower, upper) = (start, end)
            case nil: break
            }
            let read = Comparison.read(end) { piece in
                text.add(piece)
                if case .lines(let first, let last)? = span, upper == nil {
                    var from = piece.startIndex
                    while upper == nil, let newline = piece[from...].firstIndex(of: UInt8(ascii: "\n")) {
                        newlines += 1
                        let after = offset + (newline - piece.startIndex) + 1
                        if newlines == first - 1 { lower = after }
                        if newlines == last { upper = after }
                        from = newline + 1
                    }
                }
                if let lower, kept.count < room, lower < offset + piece.count {
                    let start = piece.startIndex + Swift.max(lower - offset, 0)
                    kept.append(piece[start...].prefix(room - kept.count))
                }
                offset += piece.count
            }
            return try? read.get()
        }
        guard let length = ends.lazy.compactMap(pass).first else { throw Failure.changed }
        guard text.isText else { throw Failure.notText }

        let size = Int(length)
        let selection = Swift.min(lower ?? size, size)..<Swift.min(upper ?? size, size)
        // Off UTF-8 continuation bytes (10xxxxxx), so each end falls between characters. Only kept
        // bytes are looked at: one before the selection is before its start, which is where an end
        // moved back to it stops, and one past them is past the most the answer can hold.
        func boundary(_ offset: Int, forward: Bool) -> Int {
            var offset = offset
            while offset > 0, offset < size, kept.indices.contains(offset - selection.lowerBound),
                  kept[offset - selection.lowerBound] & 0xC0 == 0x80 { offset += forward ? 1 : -1 }
            return offset
        }
        let start = boundary(selection.lowerBound, forward: true)
        let wanted = Swift.max(start, boundary(selection.upperBound, forward: false))
        let cut = boundary(start + Swift.min(wanted - start, max), forward: false)
        return Text(index: index, reference: reference(delivery, of: artifact, now: now, library: index.library),
                    text: String(decoding: kept[(start - selection.lowerBound)..<(cut - selection.lowerBound)], as: UTF8.self),
                    range: start..<cut, size: size, truncated: cut < wanted)
    }

    /// The delivery's reference, as the app's Copy Reference copies it.
    public func resolve(_ id: String) throws -> Resolved {
        let (_, artifact, delivery) = try lookup(id)
        let index = try registry.index()
        return Resolved(index: index, reference: reference(delivery, of: artifact, now: check(artifact), library: index.library))
    }

    /// Stages a verified, read-only copy of the delivery's exact bytes in Gleaner's hand-off folder
    /// (`ContentStore.stage`): from its saved copy, or from the original while it still holds them.
    public func handoff(_ id: String) throws -> HandedOff {
        let (_, artifact, delivery) = try lookup(id)
        let index = try registry.index()
        let now = check(artifact)
        guard case .ready(let sha, _, _) = artifact.handoff(delivery, now: now, hasSaved: store.has) else {
            throw Failure.unavailable(reason(delivery))
        }
        do {
            let copy = try store.stage(sha: sha, name: artifact.name, source: artifact.path)
            return HandedOff(index: index, reference: reference(delivery, of: artifact, now: now, library: index.library),
                             copy: copy.path)
        } catch ContentStore.Failure.changed {
            throw Failure.changed
        }
    }

    /// Hashes the original and Gleaner's saved copy again, and says which, if either, still holds
    /// the delivery's bytes; its reference says where they are from the same hashes. Neither means
    /// there are no bytes for that version now: the answer says why (exit 1).
    public func verify(_ id: String) throws -> Verified {
        let (_, artifact, delivery) = try lookup(id)
        let index = try registry.index()
        let now = check(artifact)
        let original = delivery.sha256 != nil && now.state.sha256 == delivery.sha256
        let savedCopy = delivery.sha256.map { Locator.sha256(store.objectURL($0).path) == $0 } ?? false
        var reference = reference(delivery, of: artifact, now: now, library: index.library)
        reference.availability = original ? Availability(state: .original)
            : savedCopy ? Availability(state: .savedCopy)
            : Availability(state: .unavailable, reason: reason(delivery))
        return Verified(index: index, reference: reference, original: original, savedCopy: savedCopy,
                        error: original || savedCopy ? nil : .unavailable(reason(delivery)))
    }

    /// `verify(_:)` for the delivery a kept reference names, which must be of this library.
    public func verify(_ kept: Kept) throws -> Verified {
        guard kept.library == (try registry.index().library) else { throw Failure.otherLibrary(kept.library) }
        return try verify(kept.delivery)
    }

    /// Every artifact shown, and the one holding the delivery `id`. A delivery of an agent turned
    /// off is there, but not shown: it is refused as the app refuses a link to it.
    private func lookup(_ id: String) throws -> (artifacts: [Artifact], artifact: Artifact, delivery: Delivery) {
        let (artifacts, library) = try shown()
        for artifact in artifacts {
            if let delivery = artifact.deliveries.first(where: { $0.id == id }) { return (artifacts, artifact, delivery) }
        }
        if let hidden = library.lazy.flatMap(\.deliveries).first(where: { $0.id == id }) { throw Failure.sourceOff(id, hidden.provider) }
        throw Failure.notFound(id)
    }

    /// The library as the app shows it (`Artifact.shown`), and all of it.
    private func shown() throws -> (artifacts: [Artifact], library: [Artifact]) {
        let library = try registry.artifacts()
        return (Artifact.shown(library, without: try registry.sourcesOff()), library)
    }

    /// Projects, collections and works as the app shows them: what Gleaner found and observed, with
    /// the person's corrections (`Organization(shown:registry:)`).
    private func organize(_ artifacts: [Artifact]) throws -> Organization {
        try Organization(shown: artifacts, registry: registry)
    }

    /// The project the app shows `artifact` in. The organization holds every artifact it was made
    /// from, each in a work in a project; one it doesn't hold is where Gleaner found it.
    func project(of artifact: Artifact, in organization: Organization) -> Project {
        guard let work = organization.work(containing: artifact.path), let project = organization.project(work.project) else {
            return Project(name: artifact.project, folder: artifact.projectFolder)
        }
        return Project(name: project.name, folder: project.folder)
    }

    /// The file as it is now, checked on each call.
    private func check(_ artifact: Artifact) -> FileObservation {
        FileObservation(state: Locator.observe(artifact.path, checkout: artifact.checkout), checkedAt: Date())
    }

    func reference(_ delivery: Delivery, of artifact: Artifact, now: FileObservation, library: String) -> Reference {
        let availability = switch artifact.handoff(delivery, now: now, hasSaved: store.has) {
        case .ready(_, .original, _): Availability(state: .original)
        case .ready(_, .savedCopy, _): Availability(state: .savedCopy)
        default: Availability(state: .unavailable, reason: reason(delivery))
        }
        return Reference(
            library: library, delivery: delivery.id, name: artifact.name, sha256: delivery.sha256, path: delivery.path,
            evidence: LogLine(log: delivery.logPath, line: delivery.evidence.first?.line),
            provenance: Seen(state: delivery.capture?.provenance ?? .neverObserved, observedAt: delivery.capture?.observedAt),
            availability: availability)
    }

    /// Why Gleaner holds none of `delivery`'s bytes, from what it recorded when it first looked.
    func reason(_ delivery: Delivery) -> Availability.Reason {
        guard let capture = delivery.capture else { return .neverSeen }
        switch capture.kind {
        case .missing: return .neverSeen
        case .special: return .notARegularFile
        case .unreadable: return .unreadable
        case .directory: return .folder
        case .file:
            if capture.savedAt != nil { return .savedCopyMissing }
            return (capture.size ?? 0) > saveLimit ? .tooLargeToHaveBeenSaved : .saveFailed
        }
    }

    /// The start of a request, for a list of results: cut at a space, and marked as cut.
    static func excerpt(_ text: String?, length: Int = 200) -> String? {
        guard let text, text.count > length else { return text }
        let start = text.prefix(length)
        return String(start[..<(start.lastIndex(where: \.isWhitespace) ?? start.endIndex)]) + "…"
    }
}

// MARK: Answers

extension Catalog {
    /// Why the catalog can't answer, each with the exit code the `gleaner` command gives it.
    public enum Failure: Error, Equatable, CustomStringConvertible, Encodable {
        /// No library at this path: Gleaner never ran with this home.
        case noLibrary(String)
        /// A library is at this path, but it can't be opened to read as it is.
        case unreadableLibrary(String, reason: String)
        /// The library at this path is of an earlier version of Gleaner. There is no compatibility mode.
        case wrongVersion(String, found: Int)
        /// A later Gleaner last opened the library at this path; this one doesn't know its tables or
        /// readings, as the app refuses it (`Registry.Failure.newer`).
        case newerLibrary(String, found: Int)
        /// No delivery has this id in this library.
        case notFound(String)
        /// The delivery is in this library, from an agent the person turned off in Gleaner's
        /// Sources: like the app, the catalog leaves its deliveries out.
        case sourceOff(String, Provider)
        /// A kept reference is of the library named, not this one: its delivery id names nothing here.
        case otherLibrary(String)
        /// Gleaner holds none of the version's bytes now.
        case unavailable(Availability.Reason)
        /// The version's bytes aren't text.
        case notText
        /// The bytes changed, or couldn't be read, while Gleaner read them.
        case changed
        /// What was asked can't be answered as asked: a range, a limit.
        case usage(String)
        /// Anything else that stopped an answer, with what it was: the library couldn't be queried,
        /// or a hand-off copy couldn't be written.
        case failed(String)

        /// 1: not found, no bytes for that version, or another failure; 2: usage; 3: no library, or
        /// the wrong version.
        public var exitCode: Int32 {
            switch self {
            case .notFound, .sourceOff, .otherLibrary, .unavailable, .notText, .changed, .failed: 1
            case .usage: 2
            case .noLibrary, .unreadableLibrary, .wrongVersion, .newerLibrary: 3
            }
        }

        public var description: String {
            switch self {
            case .noLibrary(let path):
                "There is no Gleaner library at \(path). Open Gleaner to make one."
            case .unreadableLibrary(let path, let reason):
                "The Gleaner library at \(path) can’t be opened to read (\(reason)). Open Gleaner, then try again."
            case .wrongVersion(let path, let found):
                "The Gleaner library at \(path) is version \(found); this reads version \(Registry.extractorVersion). Open Gleaner to update it."
            case .newerLibrary(let path, let found):
                "A newer Gleaner last opened the library at \(path) (library version \(found); this reads version \(Registry.extractorVersion)). "
                    + "Nothing in it was changed. Use the gleaner command of that newer Gleaner."
            case .notFound(let id):
                "No delivery \(id) in this library."
            case .sourceOff(let id, let provider):
                "Delivery \(id) is from \(provider.name), which is off in Gleaner’s Sources. Turn it on there to use its deliveries."
            case .otherLibrary(let library):
                "The reference is of another Gleaner library, \(library). A delivery id names a delivery only in its own library."
            case .unavailable(let reason):
                "Gleaner holds none of this version’s bytes: \(reason.rawValue.replacingOccurrences(of: "_", with: " "))."
            case .notText:
                "This version isn’t text."
            case .changed:
                "The bytes changed, or couldn’t be read, while Gleaner read them. Try again."
            case .usage(let message):
                message
            case .failed(let what):
                "Gleaner couldn’t answer: \(what)"
            }
        }

        /// Which failure it is, as an answer names it.
        public var kind: String {
            switch self {
            case .noLibrary: "no_library"
            case .unreadableLibrary: "unreadable_library"
            case .wrongVersion: "wrong_version"
            case .newerLibrary: "newer_library"
            case .notFound: "not_found"
            case .sourceOff: "source_off"
            case .otherLibrary: "other_library"
            case .unavailable: "unavailable"
            case .notText: "not_text"
            case .changed: "changed"
            case .usage: "usage"
            case .failed: "failed"
            }
        }

        private enum CodingKeys: CodingKey { case kind, message, reason }

        /// As an answer writes it: its kind, what it says, and for unavailable, why.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(description, forKey: .message)
            if case .unavailable(let reason) = self { try container.encode(reason, forKey: .reason) }
        }
    }

    /// A delivery as every answer names it (query-core "Identity in every result"): its fields
    /// kept apart, never one string. The path locates the file; it doesn't identify the version.
    public struct Reference: Codable, Equatable, Sendable {
        /// The library's namespace (`Index.library`).
        public var library: String
        /// The delivery's id, stable within the library while its log path is unchanged.
        public var delivery: String
        /// The file's name.
        public var name: String
        /// The capture's hash; nil when Gleaner never read the bytes.
        public var sha256: String?
        /// Where the file was delivered.
        public var path: String
        /// The reply record that named it.
        public var evidence: LogLine
        public var provenance: Seen
        /// Where the version's bytes are now, checked on each call.
        public var availability: Availability

        // `sha256` is written as null, not left out, when Gleaner never read the bytes.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(library, forKey: .library)
            try container.encode(delivery, forKey: .delivery)
            try container.encode(name, forKey: .name)
            try container.encode(sha256, forKey: .sha256)
            try container.encode(path, forKey: .path)
            try container.encode(evidence, forKey: .evidence)
            try container.encode(provenance, forKey: .provenance)
            try container.encode(availability, forKey: .availability)
        }
    }

    /// What `verify` reads of a kept reference, as `resolve` writes it or its `reference` alone: the
    /// delivery it names, and in which library. Nothing else in it is read; the library has the
    /// delivery's hash and path, and a capture, once hashed, is never rewritten.
    public struct Kept: Decodable, Equatable, Sendable {
        public var library: String
        public var delivery: String

        public init(library: String, delivery: String) {
            self.library = library
            self.delivery = delivery
        }

        enum CodingKeys: CodingKey { case reference, library, delivery }

        public init(from decoder: Decoder) throws {
            let answer = try decoder.container(keyedBy: CodingKeys.self)
            let fields = answer.contains(.reference) ? try answer.nestedContainer(keyedBy: CodingKeys.self, forKey: .reference) : answer
            library = try fields.decode(String.self, forKey: .library)
            delivery = try fields.decode(String.self, forKey: .delivery)
        }
    }

    /// A line of an agent's log.
    public struct LogLine: Codable, Equatable, Sendable {
        public var log: String
        /// From 1.
        public var line: Int?
    }

    /// When Gleaner read a delivery's bytes, relative to the reply that handed them over (SPEC §5.1).
    public struct Seen: Codable, Equatable, Sendable {
        public var state: Provenance
        /// When Gleaner first looked at the path.
        public var observedAt: Date?
    }

    /// Where a version's bytes are now: the original while it hashes to the capture, else Gleaner's
    /// saved copy, else none, with why (SPEC §6).
    public struct Availability: Codable, Equatable, Sendable {
        public enum State: String, Codable, Sendable {
            case original
            case savedCopy = "saved_copy"
            case unavailable = "none"
        }

        /// Why Gleaner holds none of a version's bytes, from what it recorded when it first looked
        /// (rulings A3).
        public enum Reason: String, Codable, Sendable {
            /// Nothing was at the path.
            case neverSeen = "never_seen"
            /// Something was, but not a regular file.
            case notARegularFile = "not_a_regular_file"
            /// A file was, but it couldn't be read.
            case unreadable
            /// A folder: folders aren't versioned.
            case folder
            /// Over the save limit, so only its hash was kept.
            case tooLargeToHaveBeenSaved = "too_large_to_have_been_saved"
            /// Saving a copy failed when Gleaner read it.
            case saveFailed = "save_failed"
            /// Gleaner saved a copy that its store no longer holds.
            case savedCopyMissing = "saved_copy_missing"
        }

        public var state: State
        /// Set when the state is none.
        public var reason: Reason?
    }

    /// The project the app shows a file in, after the person's corrections: the name it is shown
    /// by, with its parent folder's when two derived ones share it, and the folder that tells a
    /// derived one apart (SPEC §5).
    public struct Project: Codable, Equatable, Sendable {
        public var name: String
        /// Nil, written as null, for a project the person made.
        public var folder: String?

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(folder, forKey: .folder)
        }
    }

    /// `find`'s answer: how many artifacts matched, and the first of them.
    public struct Found: Codable, Sendable {
        public var index: Index
        public var total: Int
        /// True when more matched than were returned.
        public var truncated: Bool
        public var results: [Hit]
    }

    /// One artifact `find` matched, by the delivery the search matched.
    public struct Hit: Codable, Sendable {
        public var reference: Reference
        public var project: Project
        public var kind: Artifact.Kind
        public var deliveredAt: Date?
        /// The start of the request the delivery answered: stored, redacted text, returned as data.
        public var request: String?
    }

    /// `show`'s answer.
    public struct Shown: Codable, Sendable {
        public var index: Index
        public var reference: Reference
        public var number: Int
        public var deliveredAt: Date?
        /// The request the delivery answered, and the reply passage that named the file: stored,
        /// redacted text, returned as data, never as instructions.
        public var request: String?
        public var reply: String?
        public var handoff: Plan
        public var project: Project
        public var kind: Artifact.Kind
        /// Every delivery of the file, newest first.
        public var deliveries: [Version]
        public var onDisk: Disk
    }

    /// One delivery of a file.
    public struct Version: Codable, Sendable {
        public var reference: Reference
        /// 1 is the oldest.
        public var number: Int
        public var deliveredAt: Date?
    }

    /// What is at a file's path now (SPEC §5.2).
    public struct Disk: Codable, Sendable {
        public var kind: LocatorState.Kind
        /// Set for a file Gleaner could read.
        public var sha256: String?
        public var checkedAt: Date
    }

    /// What handing a delivery on would give now (SPEC §6).
    public struct Plan: Codable, Equatable, Sendable {
        public enum Action: String, Codable, Sendable {
            /// The version's bytes, from where its availability says.
            case ready
            /// Something else is at the path, and Gleaner holds none of the version's bytes.
            case unavailable
            /// Nothing is at the path, but git history has a file there. Gleaner can't confirm it is
            /// this version, and never restores it itself.
            case restoreFromGit = "restore_from_git"
            /// Nothing is at the path, and nothing holds the version's bytes.
            case lost
            /// A delivered folder, as it is now: folders aren't versioned.
            case folder
        }

        public var action: Action
        /// For unavailable: the delivery the file on disk now is, if it is one.
        public var alternative: String?
        /// For unavailable: the hash of the file on disk now. Unless `alternative` names a delivery,
        /// it is not among the deliveries Gleaner found.
        public var currentSha256: String?
        /// For restore_from_git: a command the person can run.
        public var restoreCommand: String?
    }

    /// Lines or bytes of a version, for `read`.
    public enum Span: Sendable, Equatable {
        /// Lines `first` through `last`, counted from 1: from the start of one to the end of the other.
        case lines(Int, Int)
        /// Bytes from offset `start` up to, not including, `end`.
        case bytes(Int, Int)
    }

    /// `read`'s answer.
    public struct Text: Codable, Sendable {
        public var index: Index
        public var reference: Reference
        /// The bytes read, exactly: they are UTF-8.
        public var text: String
        /// Where `text`'s bytes are in the version, the end not included; a cut selection goes on from its end.
        public var range: Range<Int>
        /// The version's size in bytes.
        public var size: Int
        /// True when the selection was longer than the most asked for.
        public var truncated: Bool
    }

    /// `resolve`'s answer, and what the app's Copy Reference copies.
    public struct Resolved: Codable, Sendable {
        public var index: Index
        public var reference: Reference
    }

    /// `handoff`'s answer.
    public struct HandedOff: Codable, Sendable {
        public var index: Index
        public var reference: Reference
        /// The verified, read-only copy: its bytes hash to the reference's `sha256`.
        public var copy: String
    }

    /// `verify`'s answer: which bytes still hash to the reference's.
    public struct Verified: Encodable, Sendable {
        public var index: Index
        public var reference: Reference
        /// The file at the reference's path.
        public var original: Bool
        /// Gleaner's saved copy.
        public var savedCopy: Bool
        /// Set, and the command exits 1, when neither holds the bytes: there are none for that
        /// version now, and this says why.
        public var error: Failure?
    }

    /// The answer when there is none (exits 1, 2 and 3): why, beside the index the refusal is
    /// evidence of when a library was open. A delivery not found in a stale or partial index, or by
    /// an id from another library, may yet be found where it is.
    public struct Refused: Encodable, Sendable {
        /// Nil, and left out, when no library was open: it couldn't be, or the refusal came first.
        public var index: Index?
        public var error: Failure

        public init(index: Index?, error: Failure) {
            self.index = index
            self.error = error
        }
    }

    /// What an answer is evidence of (query-core "Freshness"): the library, and its last completed
    /// run. An empty answer is not evidence of absence before the first run (generation 0), from a
    /// stale run, or for a source that couldn't be read, was read with problems, or is off.
    public struct Index: Codable, Equatable, Sendable {
        /// The namespace of every delivery id.
        public var library: String
        /// Completed runs of the indexer; 0 before the first.
        public var generation: Int
        /// When the last completed run finished; nil before the first.
        public var scannedAt: Date?
        /// How each agent's logs read in that run, by provider (`claude-code`, `codex`), and each
        /// agent turned off then or now as `off`; empty when that run was another version of
        /// Gleaner's, while this version reads every log again.
        public var sources: [String: Source]

        // `scanned_at` is written as null, not left out, before the first run.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(library, forKey: .library)
            try container.encode(generation, forKey: .generation)
            try container.encode(scannedAt, forKey: .scannedAt)
            try container.encode(sources, forKey: .sources)
        }
    }

    /// One agent's log folder as a run read it (SPEC §8), with what went wrong counted. What the
    /// library holds from a source that is unreadable or read with problems may be incomplete.
    public struct Source: Codable, Equatable, Sendable {
        public enum State: String, Codable, Sendable {
            /// Not on this Mac.
            case absent
            /// There, but it couldn't be listed (`reason`).
            case unreadable
            case read
            /// Listed, but not everything in it could be read or understood.
            case readWithProblems = "read_with_problems"
            /// Turned off in Gleaner's Sources, now or when that run read the logs: its logs weren't
            /// read, and while it is off its deliveries are left out of every answer.
            case off
        }

        public var state: State
        /// Why the folder couldn't be listed.
        public var reason: String?
        /// Record types the adapter doesn't recognize, with counts.
        public var unknownRecordTypes: [String: Int] = [:]
        /// Keys the adapter doesn't know inside the record types it does, as "type.key", with counts.
        public var unknownFields: [String: Int] = [:]
        /// Logs with malformed lines.
        public var partialLogs = 0
        /// Logs found shorter than when Gleaner read them: records were lost.
        public var shortenedLogs = 0
        /// Logs where the assistant answered in a closed turn but no final reply was found anywhere,
        /// the open last turn included. Neither that turn nor one the person interrupted counts as
        /// answered.
        public var logsWithoutFinalReply = 0
        /// Logs whose last complete read found fewer final replies of closed turns than the one before it.
        public var logsWithFewerReplies = 0
        /// Logs that couldn't be read or stored.
        public var failures = 0
        /// Folders in it that couldn't be listed.
        public var unlistedFolders = 0
    }
}

extension Catalog.Source {
    init(_ source: Indexer.Report.Source) {
        switch source.folder {
        case .absent: state = .absent
        case .unreadable(let why): state = .unreadable; reason = why
        case .listed: state = source.hasProblems ? .readWithProblems : .read
        }
        unknownRecordTypes = source.unknownRecordTypes
        unknownFields = source.unknownFields
        partialLogs = source.partialLogs.count
        shortenedLogs = source.shortenedLogs.count
        logsWithoutFinalReply = source.logsWithoutFinalReply.count
        logsWithFewerReplies = source.logsWithFewerReplies.count
        failures = source.failures.count
        unlistedFolders = source.unlistedFolders.count
    }
}

extension Catalog.Plan {
    init(_ handoff: Handoff, in artifact: Artifact, now: FileObservation) {
        switch handoff {
        case .ready: action = .ready
        case .unavailable(let number, let current):
            action = .unavailable
            alternative = number.flatMap { n in artifact.deliveries.first { $0.number == n }?.id }
            currentSha256 = current
        case .restoreFromGit:
            action = .restoreFromGit
            restoreCommand = now.state.restoreCommand
        case .lost: action = .lost
        case .folder: action = .folder
        }
    }
}

extension Artifact.Kind: Codable {}
extension LocatorState.Kind: Codable {}
