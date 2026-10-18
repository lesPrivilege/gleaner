import Foundation

/// One piece of work as the person knows it: a file, or several files the person said are versions
/// of one work (a report renamed from draft to final). Gleaner never joins files on its own: same
/// bytes, names, folders or sessions don't make one work (SPEC §5.2). It may suggest a join, with
/// its reason, and the person decides.
public struct Work: Sendable, Identifiable {
    /// Oldest first delivery first.
    public var files: [Artifact]
    /// Every file's deliveries, newest first.
    public var deliveries: [Delivery]
    /// The key of the project it is shown in.
    public var project: String

    /// The path of its first-delivered file.
    public var id: String { files[0].path }
    /// The file holding its newest delivery.
    public var latest: Artifact { file(of: deliveries[0]) }
    public var name: String { latest.name }
    public var kind: Artifact.Kind { latest.kind }

    public func file(of delivery: Delivery) -> Artifact {
        files.first { $0.path == delivery.path } ?? files[0]
    }

    public func contains(_ path: String) -> Bool { files.contains { $0.path == path } }

    /// For a search (SPEC §10), across its files: the newest delivery whose own words matched, else
    /// the newest delivery of a file whose name, folder or project did. Each delivery is matched
    /// with its own file's name; words from different deliveries never combine.
    public func match(_ tokens: [String], project: String) -> Delivery? {
        let found = files.compactMap { file in
            file.matches(tokens, project: project).map { (file.deliveries[$0.index], $0.ownWords) }
        }
        func newest(_ list: [(Delivery, Bool)]) -> Delivery? {
            list.max { ($0.0.deliveredAt ?? .distantPast) < ($1.0.deliveredAt ?? .distantPast) }?.0
        }
        return newest(found.filter(\.1)) ?? newest(found)
    }
}

/// The library as the person sees it: projects, the works in each, and the joins Gleaner suggests.
/// Built from what Gleaner found (artifacts, with their repositories and folders) and the person's
/// corrections, which win. Nothing here reads the disk.
public struct Organization: Sendable {
    public struct Project: Sendable, Identifiable {
        public enum Origin: Sendable, Equatable {
            /// A git repository's main folder, with every worktree folded in (SPEC §5).
            case repository
            /// Outside git: the folder the agent worked in.
            case folder
            /// Made by the person.
            case yours
        }

        /// A derived project's folder, or a project the person made (`user:` …).
        public var key: String
        /// As shown: a name two folders share carries its parent folder's.
        public var name: String
        public var origin: Origin
        /// Newest first.
        public var works: [Work]
        /// Projects Gleaner derived that the person showed inside this one, with that decision.
        public var combined: [(folder: String, name: String, correction: Correction)]

        public var id: String { key }
        /// The folder on disk a derived project is; nil for one the person made.
        public var folder: String? { origin == .yours ? nil : key }
        public var latest: Date? { works.first?.deliveries.first?.deliveredAt }
    }

    /// Two files Gleaner thinks may be versions of one work, never joined until the person says so.
    public struct Suggestion: Sendable, Equatable, Identifiable {
        public enum Reason: Sendable, Equatable {
            /// The later file first came with the bytes the earlier one last had, and the earlier
            /// one is gone from its path: it may have been renamed or moved.
            case moved
            /// In one folder, with names that differ only by a version mark (`v1`, `draft`, `final`, a date).
            case versionName
        }

        public var earlier: String
        public var later: String
        public var reason: Reason

        public var id: String { earlier + "\n" + later }
    }

    /// Why a work is in the project it is shown in.
    public enum Placement: Sendable, Equatable {
        /// Where Gleaner found it: its repository, or the folder its agent worked in.
        case found
        /// The person moved it there.
        case moved(Correction)
        /// The project Gleaner found for it is shown inside another one.
        case combined(from: String, Correction)
    }

    /// Newest activity first; projects the person made and left empty last.
    public private(set) var projects: [Project] = []
    /// Newest delivery first.
    public private(set) var works: [Work] = []
    public private(set) var suggestions: [Suggestion] = []
    public let corrections: [Correction]
    public let userProjects: [UserProject]
    private var workIndex: [String: Int] = [:]
    private var projectIndex: [String: Int] = [:]
    private var placements: [String: Placement] = [:]
    private var derivedNames: [String: String] = [:]

    /// `missing` holds the paths last found gone from disk.
    public init(artifacts: [Artifact], corrections: [Correction] = [], projects userProjects: [UserProject] = [],
                missing: Set<String> = []) {
        self.corrections = corrections
        self.userProjects = userProjects
        let byPath = Dictionary(artifacts.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let yours = Set(userProjects.map(\.key))
        func isProject(_ key: String) -> Bool { yours.contains(key) || key.hasPrefix("/") }

        // Files the person joined, as groups.
        var parent: [String: String] = [:]
        func root(_ path: String) -> String {
            var p = path
            while let up = parent[p], up != p { p = up }
            return p
        }
        // Every join counts, also through a file no longer in the library: a work joined through a
        // file a reread dropped stays one work.
        for c in corrections where c.kind == .sameWork {
            let (a, b) = (root(c.subject), root(c.target))
            if a != b { parent[b] = a }
        }
        var groups: [String: [Artifact]] = [:]
        for artifact in artifacts { groups[root(artifact.path), default: []].append(artifact) }

        // A folder's project shown inside another, followed to the end, never round a loop.
        var combine: [String: Correction] = [:]
        func resolve(_ key: String) -> (key: String, first: Correction?) {
            var key = key, seen: Set<String> = [key], first: Correction?
            while let c = combine[key], !seen.contains(c.target) {
                first = first ?? c
                key = c.target
                seen.insert(key)
            }
            return (key, first)
        }
        // Applied in the order they were made: one that would lead back to its own folder replaces
        // the older decisions it would loop through.
        for c in corrections.sorted(by: { $0.madeAt < $1.madeAt }) where c.kind == .combine && isProject(c.target) {
            if resolve(c.target).key == c.subject {
                var key = c.target
                while key != c.subject, let next = combine.removeValue(forKey: key) { key = next.target }
            }
            combine[c.subject] = c
        }
        var moves: [String: Correction] = [:]
        for c in corrections where c.kind == .project && isProject(c.target) { moves[c.subject] = c }

        func date(_ d: Delivery) -> Date { d.deliveredAt ?? .distantPast }
        var works: [Work] = groups.values.map { files in
            let files = files.sorted { (date($0.deliveries.last!), $0.path) < (date($1.deliveries.last!), $1.path) }
            let deliveries = files.flatMap(\.deliveries).sorted {
                date($0) != date($1) ? date($0) > date($1) : ($0.path, $0.number) > ($1.path, $1.number)
            }
            return Work(files: files, deliveries: deliveries, project: "")
        }
        for index in works.indices {
            let work = works[index]
            // The latest move of any of its files wins; else the project found for its newest file.
            if let move = work.files.compactMap({ moves[$0.path] }).max(by: { $0.madeAt < $1.madeAt }) {
                works[index].project = resolve(move.target).key
                placements[work.id] = .moved(move)
            } else {
                let found = work.latest.projectFolder
                let (key, first) = resolve(found)
                works[index].project = key
                placements[work.id] = first.map { .combined(from: found, $0) } ?? .found
            }
        }
        works.sort { date($0.deliveries[0]) != date($1.deliveries[0]) ? date($0.deliveries[0]) > date($1.deliveries[0]) : $0.id < $1.id }
        self.works = works
        for (index, work) in works.enumerated() {
            for file in work.files { workIndex[file.path] = index }
        }

        // Projects: each derived folder by its name, told apart from another of the same name.
        let derived = Set(works.map(\.project).filter { !yours.contains($0) } + combine.keys.filter { !yours.contains($0) })
        derivedNames = Projects.names(derived)
        let inRepository = Set(artifacts.filter(\.inRepository).map(\.projectFolder))
        var projects: [Project] = []
        for (key, members) in Dictionary(grouping: works, by: \.project) {
            let user = userProjects.first { $0.key == key }
            projects.append(Project(
                key: key, name: user?.name ?? derivedNames[key] ?? Projects.name(key),
                origin: user != nil ? .yours : inRepository.contains(key) ? .repository : .folder,
                works: members, combined: []))
        }
        for user in userProjects where !projects.contains(where: { $0.key == user.key }) {
            projects.append(Project(key: user.key, name: user.name, origin: .yours, works: [], combined: []))
        }
        projects.sort {
            let (a, b) = ($0.latest ?? .distantPast, $1.latest ?? .distantPast)
            return a != b ? a > b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for (index, project) in projects.enumerated() { projectIndex[project.key] = index }
        for (folder, c) in combine {
            let into = resolve(folder).key
            guard into != folder, let index = projectIndex[into] else { continue }
            projects[index].combined.append((folder, derivedNames[folder] ?? Projects.name(folder), c))
        }
        self.projects = projects
        suggestions = Self.suggest(works: works, workIndex: workIndex, corrections: corrections, missing: missing)
    }

    public func work(containing path: String) -> Work? { workIndex[path].map { works[$0] } }

    public func project(_ key: String) -> Project? { projectIndex[key].map { projects[$0] } }

    /// The project as shown, for `key`; a derived folder's name when no work is shown in it now.
    public func projectName(_ key: String) -> String {
        project(key)?.name ?? userProjects.first { $0.key == key }?.name ?? derivedNames[key] ?? Projects.name(key)
    }

    public func placement(of work: Work) -> Placement { placements[work.id] ?? .found }

    /// The person's decisions joining the work's files, oldest first.
    public func links(of work: Work) -> [Correction] {
        corrections.filter { $0.kind == .sameWork && work.contains($0.subject) && work.contains($0.target) }
    }

    /// The joins Gleaner suggests for the work, to an earlier or a later file.
    public func suggestions(for work: Work) -> [Suggestion] {
        suggestions.filter { work.contains($0.earlier) || work.contains($0.later) }
    }

    public func suggestions(in project: Project) -> [Suggestion] {
        suggestions.filter { self.work(containing: $0.later)?.project == project.key }
    }

    /// At most one suggestion per file, for the file it most likely continues: one whose last bytes
    /// it first came with after that file was delivered, now gone from its path, else the one
    /// before it in its folder whose name differs only by a version mark. Only within a project,
    /// never for files already joined, and none once the person said the pair is not one work:
    /// Gleaner doesn't offer the next likeliest instead. Each file's search looks back from it
    /// among files sorted by date, so a folder of hundreds of versions costs little.
    static func suggest(works: [Work], workIndex: [String: Int], corrections: [Correction], missing: Set<String>) -> [Suggestion] {
        let rejected = Set(corrections.filter { $0.kind == .notSameWork }.map {
            min($0.subject, $0.target) + "\n" + max($0.subject, $0.target)
        })
        func first(_ file: Artifact) -> Date { file.deliveries.last?.deliveredAt ?? .distantPast }
        func last(_ file: Artifact) -> Date { file.latest.deliveredAt ?? .distantPast }
        let files = works.flatMap(\.files)
        // Empty files share one hash and say nothing about where a file came from.
        var bySha: [String: [Artifact]] = [:], byName: [String: [Artifact]] = [:]
        for file in files {
            if let sha = file.latest.sha256, (file.latest.capture?.size ?? 1) > 0 { bySha[sha, default: []].append(file) }
            if let key = versionKey(file.path) { byName[key, default: []].append(file) }
        }
        for key in bySha.keys { bySha[key]!.sort { last($0) < last($1) } }
        for key in byName.keys { byName[key]!.sort { first($0) < first($1) } }
        func apart(_ a: Artifact, _ b: Artifact) -> Bool {
            guard let x = workIndex[a.path], let y = workIndex[b.path] else { return false }
            return x != y && works[x].project == works[y].project
        }
        /// The nearest file before `date` in `group` (sorted by `key`) that passes `ok`.
        func nearest(in group: [Artifact], before date: Date, by key: (Artifact) -> Date, _ ok: (Artifact) -> Bool) -> Artifact? {
            var low = 0, high = group.count
            while low < high { let mid = (low + high) / 2; if key(group[mid]) < date { low = mid + 1 } else { high = mid } }
            return group[..<low].reversed().prefix(64).first(where: ok)
        }
        var suggestions: [Suggestion] = []
        for later in files {
            let arrived = first(later)
            let moved = (later.deliveries.last?.sha256).flatMap { bySha[$0] }.flatMap { group in
                nearest(in: group, before: arrived, by: last) { missing.contains($0.path) && apart($0, later) }
            }
            let renamed = versionKey(later.path).flatMap { byName[$0] }.flatMap { group in
                nearest(in: group, before: arrived, by: first) { $0.name != later.name && apart($0, later) }
            }
            let (earlier, reason): (Artifact?, Suggestion.Reason) = moved != nil ? (moved, .moved) : (renamed, .versionName)
            guard let earlier, !rejected.contains(min(earlier.path, later.path) + "\n" + max(earlier.path, later.path)) else { continue }
            suggestions.append(Suggestion(earlier: earlier.path, later: later.path, reason: reason))
        }
        return suggestions
    }

    /// The folder, extension and name of `path` without the version marks people and agents add
    /// (`report-v2`, `deck_final`, `brief (1)`); nil when nothing is left. A bare number
    /// (`chapter2`, `receipt-10293847`) or a date (`standup 2026-10-18`) is not a version mark: it
    /// usually names another part, or another day's document.
    static func versionKey(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        var stem = (name as NSString).deletingPathExtension.lowercased()
        let mark = #"([\s._-]+(v\d+([._]\d+)*|rev\s?\d+|r\d+|version\s?\d+|draft\d*|final|wip|copy(\s?\d+)?|old|new|latest)|\s*\(\d+\))$"#
        while let range = stem.range(of: mark, options: .regularExpression), !range.isEmpty {
            stem.removeSubrange(range)
        }
        stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: " ._-"))
        guard !stem.isEmpty else { return nil }
        return (path as NSString).deletingLastPathComponent + "\n" + stem + "\n" + ext
    }
}
