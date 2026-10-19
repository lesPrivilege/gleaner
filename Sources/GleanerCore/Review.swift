import Foundation

/// A file's size, dates and inode, as `stat` gives them without reading its bytes: what tells
/// whether a file is still as it was when its bytes were read, as a listed file is matched (SPEC
/// §5.4).
public struct FileStat: Sendable, Equatable {
    public var size: Int64
    public var createdAt: Date?
    public var modifiedAt: Date
    public var inode: Int64

    public init(size: Int64, createdAt: Date?, modifiedAt: Date, inode: Int64) {
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.inode = inode
    }

    /// The regular file at `path`, a link followed as a delivered link is (SPEC §6); nil for
    /// anything else, or nothing. Reads no bytes.
    public init?(_ path: String) {
        var info = Darwin.stat()
        // stat(2), following a link, by the name `Locator.stat` uses: the struct's name hides the function's.
        guard fstatat(AT_FDCWD, path, &info, 0) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        func date(_ time: timespec) -> Date { Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1e9) }
        let born = info.st_birthtimespec
        self.init(size: Int64(info.st_size), createdAt: born.tv_sec > 0 ? date(born) : nil, modifiedAt: date(info.st_mtimespec),
                  inode: Int64(bitPattern: UInt64(info.st_ino)))
    }

    /// Dates are compared as the library stores them, in seconds since 1970: a date made again
    /// from those can differ from the one read from the disk in its last bit.
    public static func == (a: FileStat, b: FileStat) -> Bool {
        a.size == b.size && a.inode == b.inode && a.modifiedAt.timeIntervalSince1970 == b.modifiedAt.timeIntervalSince1970
            && a.createdAt?.timeIntervalSince1970 == b.createdAt?.timeIntervalSince1970
    }
}

/// The person's verdict on a file's bytes, or their mark that those bytes were published
/// (docs/design/review.md). Each holds for the exact bytes Gleaner hashed when it was made, at the
/// person's action, never for the path: when the bytes change it stays in the history, and is
/// never carried to the new bytes. Bytes that match its hash keep it, at any revision. None is
/// rewritten or removed by a later one; each can be undone.
public struct Review: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case approved
        case changesRequested = "changes_requested"
        case rejected
        /// Not a verdict: the person's mark that these bytes were published. Nothing completes one
        /// state for another, so a published file need not be reviewed, nor a reviewed one published.
        case published

        public var isVerdict: Bool { self != .published }
    }

    public var id: Int64
    public var kind: Kind
    /// The file it was made on: one of a work's files.
    public var path: String
    /// A verdict's note; a published mark's place, in words or a link. Optional.
    public var note: String?
    /// The hash of the bytes it was made on, and the file as it was when they were read.
    public var sha256: String
    public var file: FileStat
    public var madeAt: Date

    /// Why a verdict or a mark couldn't be made.
    public enum Failure: Error, Equatable {
        /// No regular file Gleaner can read is at the path: it is gone, a folder, not a regular file,
        /// or can't be read. Which, as `Locator.stat` says it.
        case notAFile(LocatorState.Kind)
        /// The file isn't as it was when the person was shown it: it may not be what they judged.
        case changedSinceShown
        /// The file changed while Gleaner read it.
        case changedWhileRead
    }

    /// What the person's verdicts, or published marks, on a work's files say of its file now:
    /// `records` are one kind's, newest first. A record made on the bytes there now holds, the
    /// newest such, matched by hash once the file was read, else by its size, dates and inode while
    /// they are still as when it was made. Otherwise the newest record may have been made on other
    /// bytes until the file is read, and was once it is.
    public static func standing(_ records: [Review], now: Present) -> Standing {
        guard let latest = records.first else { return .none }
        switch now {
        case .read(let sha):
            return records.first { $0.sha256 == sha }.map(Standing.current) ?? .changed(latest)
        case .listed(let file):
            return records.first { $0.file == file }.map(Standing.current) ?? .mayHaveChanged(latest)
        case .absent:
            return .unavailable(latest)
        }
    }
}

/// What is at a work's file now, as far as Gleaner knows without reading it again.
public enum Present: Sendable, Equatable {
    /// Read, and still as it was then: these bytes, by hash.
    case read(String)
    /// Not read since it last changed: its size, dates and inode.
    case listed(FileStat)
    /// No regular file is there to read: gone, a folder, not a regular file, or unreadable.
    case absent
}

/// What verdicts, or published marks, say of a work's file now (`Review.standing`).
public enum Standing: Sendable, Equatable {
    /// None was made on any of the work's bytes.
    case none
    /// This one, the newest made on the bytes there now.
    case current(Review)
    /// The file isn't as it was when this one, the newest, was made, and hasn't been read since: it
    /// may have changed.
    case mayHaveChanged(Review)
    /// Read since: none was made on these bytes. This one, the newest, was made on other bytes.
    case changed(Review)
    /// No file is there to read: this one, the newest, was made on bytes not there now. A reviewed
    /// file need not be on this Mac.
    case unavailable(Review)

    /// The record it names; nil for none.
    public var review: Review? {
        switch self {
        case .none: nil
        case .current(let r), .mayHaveChanged(let r), .changed(let r), .unavailable(let r): r
        }
    }
}

/// Every verdict and published mark, by the file each was made on, newest first.
public struct Reviews: Sendable {
    private var byPath: [String: [Review]] = [:]

    public init(_ reviews: [Review]) {
        for review in reviews.sorted(by: Self.newestFirst) { byPath[review.path, default: []].append(review) }
    }

    static func newestFirst(_ a: Review, _ b: Review) -> Bool {
        a.madeAt != b.madeAt ? a.madeAt > b.madeAt : a.id > b.id
    }

    /// The work's history: every verdict and mark on any of its files, newest first. A work is one
    /// piece of work whichever file holds it, so bytes that match a verdict's hash keep it at any of
    /// its revisions.
    public func history(of work: Work) -> [Review] {
        guard work.files.count > 1 else { return byPath[work.files[0].path] ?? [] }
        return work.files.flatMap { byPath[$0.path] ?? [] }.sorted(by: Self.newestFirst)
    }

    /// The work's verdicts, newest first.
    public func verdicts(of work: Work) -> [Review] { history(of: work).filter(\.kind.isVerdict) }

    /// The work's published marks, newest first.
    public func published(of work: Work) -> [Review] { history(of: work).filter { $0.kind == .published } }

    /// Whether any verdict or mark was made on the work.
    public func any(_ work: Work) -> Bool { work.files.contains { byPath[$0.path] != nil } }
}

extension Registry {
    /// Every verdict and published mark, oldest first.
    public func reviews() throws -> [Review] {
        try db.rows("""
            SELECT id, path, kind, note, sha256, size, created_at, modified_at, inode, made_at FROM reviews ORDER BY made_at, id
            """).compactMap { row in
            guard let kind = Review.Kind(rawValue: row["kind"] as? String ?? ""), let sha = row["sha256"] as? String,
                  let modified = row["modified_at"] as? Double else { return nil }
            return Review(id: row["id"] as! Int64, kind: kind, path: row["path"] as! String, note: row["note"] as? String, sha256: sha,
                          file: FileStat(size: row["size"] as? Int64 ?? 0,
                                         createdAt: (row["created_at"] as? Double).map(Date.init(timeIntervalSince1970:)),
                                         modifiedAt: Date(timeIntervalSince1970: modified), inode: row["inode"] as? Int64 ?? 0),
                          madeAt: Date(timeIntervalSince1970: row["made_at"] as? Double ?? 0))
        }
    }

    /// Records a verdict or a mark, returned with its id and its time as `reviews` reads it back.
    func record(_ review: Review) throws -> Review {
        try db.run("""
            INSERT INTO reviews (path, kind, note, sha256, size, created_at, modified_at, inode, made_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [review.path, review.kind.rawValue, review.note, review.sha256, review.file.size, review.file.createdAt,
                  review.file.modifiedAt, review.file.inode, review.madeAt])
        var recorded = review
        recorded.id = try db.rows("SELECT last_insert_rowid() AS id").first?["id"] as? Int64 ?? 0
        recorded.madeAt = Date(timeIntervalSince1970: review.madeAt.timeIntervalSince1970)
        return recorded
    }

    /// Undoes verdicts and marks, whole or not at all. The others stay: none is removed by a later one.
    public func undoReviews(_ ids: [Review.ID]) throws {
        try writing { try db.transaction { for id in ids { try db.run("DELETE FROM reviews WHERE id = ?", [id]) } } }
    }
}

extension Indexer {
    /// Makes a verdict or a published mark on the file at `path`, on the bytes there now: reads
    /// them, the person's action, saves a small file's bytes as a first read does, and records their
    /// hash with the file's size, dates and inode. `shown` is the file as the person was shown it;
    /// when it isn't so now, nothing is made, since they may not have judged these bytes. Nothing is
    /// made either when the file changes while it is read. The read completes what a first read of
    /// the file completes (`completeCaptures`).
    public func review(_ path: String, as kind: Review.Kind, note: String? = nil, shown: FileStat? = nil, at now: Date) throws -> Review {
        guard let before = FileStat(path) else {
            let kind = Locator.stat(path).kind
            throw Review.Failure.notAFile(kind == .file ? .unreadable : kind)
        }
        if let shown, shown != before { throw Review.Failure.changedSinceShown }
        let file = Workspace.file(at: path)
        let read = capture(path, deliveredAt: nil, now: now)
        guard let sha = read.sha256 else { throw Review.Failure.notAFile(.unreadable) }
        guard read.size == before.size, FileStat(path) == before else { throw Review.Failure.changedWhileRead }
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try registry.transaction {
            try registry.complete(capturesOf: path, with: read)
            try completeMembers(of: path, with: read, file: file)
            return try registry.record(Review(id: 0, kind: kind, path: path, note: note?.isEmpty == false ? note : nil, sha256: sha,
                                              file: before, madeAt: now))
        }
    }
}

extension Organization {
    /// Works waiting on the person's review, grouped: one unit's, or, for works in none, one
    /// project's.
    public struct ReviewGroup: Sendable, Identifiable {
        public var project: String
        /// Nil for the works in no unit.
        public var unit: String?
        /// In list order (`Listing.ordered`).
        public var works: [Work]

        public var id: String { unit ?? project }
    }

    /// What is left to review (docs/design/review.md, To Review), drawn from the person's own acts,
    /// never from everything delivered: the works in units with no verdict on their bytes, and the
    /// works anywhere whose newest verdict was made on other bytes or may have been, until the file
    /// is read. A work nobody put in a unit and nobody reviewed is never in it, nor a folder, which
    /// has no bytes to judge. `present` says what is at a work's file now; it is asked only of works
    /// in units or with a verdict or mark. Grouped by unit, as the sidebar lists them, then the works
    /// in none, by project.
    public func toReview(_ reviews: Reviews, present: (Work) -> Present) -> [ReviewGroup] {
        var waiting: [String: [Work]] = [:]
        for work in works where work.unit != nil || reviews.any(work) {
            guard work.kind != .folder else { continue }
            let waits = switch Review.standing(reviews.verdicts(of: work), now: present(work)) {
            case .none: work.unit != nil
            case .changed, .mayHaveChanged: true
            case .current, .unavailable: false
            }
            if waits { waiting[work.unit ?? work.project, default: []].append(work) }
        }
        var groups: [ReviewGroup] = []
        func add(_ key: String, project: String, unit: String?) {
            guard let list = waiting[key] else { return }
            groups.append(ReviewGroup(project: project, unit: unit, works: Self.listed(list)))
        }
        for project in projects {
            for unit in units(in: project.key) {
                add(unit.key, project: project.key, unit: unit.key)
                for inner in units(inside: unit.key) { add(inner.key, project: project.key, unit: inner.key) }
            }
        }
        for project in projects { add(project.key, project: project.key, unit: nil) }
        return groups
    }
}
