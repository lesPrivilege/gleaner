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
    /// The key of the work unit it is in; nil in none. A work is in at most one.
    public var unit: String? = nil

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
    /// the newest delivery of a file whose name, folder, project or collection did. `collections`
    /// names the collection holding the work and the one that is inside, matched as the project is
    /// (SPEC §5.5). Each delivery is matched with its own file's name; words from different
    /// deliveries never combine.
    public func match(_ tokens: [String], project: String, collections: [String] = []) -> Delivery? {
        let shared = ([project] + collections).joined(separator: " ")
        let found = files.compactMap { file in
            file.matches(tokens, project: shared).map { (file.deliveries[$0.index], $0.ownWords) }
        }
        func newest(_ list: [(Delivery, Bool)]) -> Delivery? {
            list.max { ($0.0.deliveredAt ?? .distantPast) < ($1.0.deliveredAt ?? .distantPast) }?.0
        }
        return newest(found.filter(\.1)) ?? newest(found)
    }
}

/// The library as the person sees it: projects, the work units and works in each, and the joins
/// Gleaner suggests. Built from what Gleaner found (artifacts, with their repositories and folders)
/// and the person's corrections, which win. Nothing here reads the disk.
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
            /// In one folder, with names that differ only by a version mark (`v2`, `draft`, `final`, `(1)`).
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
    /// Files observed during sessions and handed over in none, newest first (docs/design/capture.md).
    /// A file the person detached from every session it was observed during isn't one.
    public private(set) var candidates: [Candidate] = []
    public let corrections: [Correction]
    public let userProjects: [UserProject]
    /// The work units the person made and hasn't deleted, as shown: by their latest name, in the
    /// project their own is shown in. By project, then in natural order of names, each followed by
    /// the units inside it.
    public private(set) var units: [WorkUnit] = []
    private var unitIndex: [String: Int] = [:]
    /// Every unit made, deleted or not, by its latest name.
    private var unitNames: [String: String] = [:]
    /// Each unit's own works, as indices into `works`, in list order.
    private var unitWorks: [String: [Int]] = [:]
    /// The decision that put each work in its unit, by work.
    private var unitDecisions: [String: Correction] = [:]
    private var workIndex: [String: Int] = [:]
    private var projectIndex: [String: Int] = [:]
    private var candidateIndex: [String: Int] = [:]
    /// A handed-over file's observations, kept beside its deliveries, never one of them.
    private var observedDeliveries: [String: [Observed]] = [:]
    private var placements: [String: Placement] = [:]
    private var derivedNames: [String: String] = [:]

    /// `observed` holds each file observed during sessions, newest first (`Candidate.files`), made
    /// once when the observations load rather than each time the person corrects something.
    /// `units` holds the work units as made (`Registry.units`). `missing` holds the paths last
    /// found gone from disk.
    public init(artifacts: [Artifact], observed: [Candidate] = [], corrections: [Correction] = [],
                projects userProjects: [UserProject] = [], units made: [WorkUnit] = [], missing: Set<String> = []) {
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
            return Work(files: files, deliveries: Self.newestFirst(files), project: "")
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

        // Work units the person made and hasn't deleted, nor the unit they are inside, by their
        // latest name, shown in the project their own is shown in.
        func later(_ a: Correction, _ b: Correction) -> Bool { (a.madeAt, a.id) > (b.madeAt, b.id) }
        let deleted = Set(corrections.filter { $0.kind == .unitDeleted }.map(\.subject))
        var named: [String: Correction] = [:]
        for c in corrections where c.kind == .unitName && named[c.subject].map({ later(c, $0) }) ?? true { named[c.subject] = c }
        let stored = Dictionary(made.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var live: [String: WorkUnit] = [:]
        for unit in made {
            unitNames[unit.key] = named[unit.key]?.target ?? unit.name
            guard !deleted.contains(unit.key), isProject(unit.project) else { continue }
            if let parent = unit.parent {
                guard let above = stored[parent], above.parent == nil, !deleted.contains(parent) else { continue }
            }
            var shown = unit
            shown.name = unitNames[unit.key]!
            shown.project = resolve(unit.project).key
            live[unit.key] = shown
        }
        // A work is in the unit the latest decision about any of its files put it in, while that
        // unit is shown in the work's project: a work moved to another project leaves it, and comes
        // back with the move undone. Taken out, or its unit deleted, it is in none.
        var decided: [String: Correction] = [:]
        for c in corrections where (c.kind == .unit || c.kind == .outOfUnit) && decided[c.subject].map({ later(c, $0) }) ?? true {
            decided[c.subject] = c
        }
        for index in works.indices {
            guard let decision = works[index].files.compactMap({ decided[$0.path] }).max(by: { later($1, $0) }),
                  decision.kind == .unit, let unit = live[decision.target], unit.project == works[index].project else { continue }
            works[index].unit = unit.key
            unitDecisions[works[index].id] = decision
        }

        works.sort { date($0.deliveries[0]) != date($1.deliveries[0]) ? date($0.deliveries[0]) > date($1.deliveries[0]) : $0.id < $1.id }
        self.works = works
        for (index, work) in works.enumerated() {
            for file in work.files { workIndex[file.path] = index }
        }
        for (key, members) in Dictionary(grouping: works.indices.filter({ works[$0].unit != nil }), by: { works[$0].unit! }) {
            let order = Dictionary(Self.listed(members.map { works[$0] }).enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
            unitWorks[key] = members.sorted { order[works[$0].id]! < order[works[$1].id]! }
        }

        // Projects: each derived folder by its name, told apart from another of the same name. A
        // project holding a unit is listed with it, works or not.
        let derived = Set((works.map(\.project) + combine.keys + live.values.map(\.project)).filter { !yours.contains($0) })
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
        for key in Set(live.values.map(\.project)) where !projects.contains(where: { $0.key == key }) {
            projects.append(Project(key: key, name: derivedNames[key] ?? Projects.name(key),
                                    origin: inRepository.contains(key) ? .repository : .folder, works: [], combined: []))
        }
        projects.sort {
            let (a, b) = ($0.latest ?? .distantPast, $1.latest ?? .distantPast)
            return a != b ? a > b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for (index, project) in projects.enumerated() { projectIndex[project.key] = index }
        let tops = live.values.filter { $0.parent == nil }.sorted(by: WorkUnit.ordered)
        let inner = Dictionary(grouping: live.values.filter { $0.parent != nil }, by: { $0.parent! }).mapValues { $0.sorted(by: WorkUnit.ordered) }
        units = projects.flatMap { project in tops.filter { $0.project == project.key }.flatMap { [$0] + (inner[$0.key] ?? []) } }
        for (index, unit) in units.enumerated() { unitIndex[unit.key] = index }
        for (folder, c) in combine {
            let into = resolve(folder).key
            guard into != folder, let index = projectIndex[into] else { continue }
            projects[index].combined.append((folder, derivedNames[folder] ?? Projects.name(folder), c))
        }
        self.projects = projects
        suggestions = Self.suggest(works: works, workIndex: workIndex, corrections: corrections, missing: missing)

        // What was observed: beside a handed-over file's deliveries, else a candidate in the project
        // its repository or workspace gives, shown inside another as its works are.
        let detached = Dictionary(grouping: corrections.filter { $0.kind == .notFromSession }, by: \.subject)
            .mapValues { Set($0.map(\.target)) }
        var candidates: [Candidate] = []
        for file in observed {
            guard let file = detached[file.path].map({ logs in file.keeping { !logs.contains($0.logPath) } }) ?? file else { continue }
            if workIndex[file.path] != nil {
                observedDeliveries[file.path] = file.observations
            } else {
                var candidate = file
                candidate.project = resolve(candidate.projectFolder).key
                candidates.append(candidate)
            }
        }
        // A file detached from, or hidden with, its latest session moves.
        candidates.sort(by: Candidate.newestFirst)
        self.candidates = candidates
        for (index, candidate) in candidates.enumerated() { candidateIndex[candidate.path] = index }
    }

    /// Every delivery of the files, newest first.
    private static func newestFirst(_ files: [Artifact]) -> [Delivery] {
        func date(_ d: Delivery) -> Date { d.deliveredAt ?? .distantPast }
        return files.flatMap(\.deliveries).sorted {
            date($0) != date($1) ? date($0) > date($1) : ($0.path, $0.number) > ($1.path, $1.number)
        }
    }

    /// The organization with `artifact` in place of the file at its path, in its work wherever the
    /// work is listed: what a first read of the file or a saved copy of it changes, its captures,
    /// and nothing that places a work. Suggestions stay as they were made.
    public func replacing(_ artifact: Artifact) -> Organization {
        guard let index = workIndex[artifact.path] else { return self }
        var organization = self
        var work = works[index]
        work.files = work.files.map { $0.path == artifact.path ? artifact : $0 }
        work.deliveries = Self.newestFirst(work.files)
        organization.works[index] = work
        if let project = projectIndex[work.project], let at = projects[project].works.firstIndex(where: { $0.id == work.id }) {
            organization.projects[project].works[at] = work
        }
        return organization
    }

    public func work(containing path: String) -> Work? { workIndex[path].map { works[$0] } }

    /// The unit `key`, while it is shown.
    public func unit(_ key: String) -> WorkUnit? { unitIndex[key].map { units[$0] } }

    /// The unit's latest name, shown or deleted.
    public func unitName(_ key: String) -> String { unitNames[key] ?? "" }

    /// The units at the top of the project `key`, in natural order of names.
    public func units(in project: String) -> [WorkUnit] {
        units.filter { $0.project == project && $0.parent == nil }
    }

    /// The units inside the unit `key`, in natural order of names.
    public func units(inside key: String) -> [WorkUnit] {
        units.filter { $0.parent == key }
    }

    /// The unit's own works, in list order: what a person opens first, then newest (`Listing`).
    /// With `inner`, the works of the units inside it follow, unit by unit.
    public func works(in key: String, inner: Bool = false) -> [Work] {
        let own = (unitWorks[key] ?? []).map { works[$0] }
        return inner ? own + units(inside: key).flatMap { works(in: $0.key) } : own
    }

    /// The first image among the unit's works and those of the units inside it, in list order: what
    /// stands for it in a list.
    public func poster(of key: String) -> Work? {
        works(in: key, inner: true).first { $0.kind == .image }
    }

    /// The names of the unit holding the work and of the one it is inside, as a search matches
    /// them; none for a work in no unit.
    public func unitNames(of work: Work) -> [String] {
        guard let key = work.unit, let unit = unit(key) else { return [] }
        return [unit.name] + (unit.parent.map { [unitName($0)] } ?? [])
    }

    /// The unit holding the work, with the decision that put it there.
    public func unit(of work: Work) -> (unit: WorkUnit, decision: Correction)? {
        guard let key = work.unit, let unit = unit(key), let decision = unitDecisions[work.id] else { return nil }
        return (unit, decision)
    }

    /// Works in list order (`Listing.ordered`).
    static func listed(_ works: [Work]) -> [Work] {
        Listing.ordered(works.map(Listing.Entry.work)).compactMap { if case .work(let work) = $0 { work } else { nil } }
    }

    public func candidate(_ path: String) -> Candidate? { candidateIndex[path].map { candidates[$0] } }

    /// The candidates shown in the project `key`, newest first. A project may have candidates and
    /// no work yet; it is listed in `projects` only once something was handed over in it.
    public func candidates(in key: String) -> [Candidate] {
        candidates.filter { $0.project == key }
    }

    /// What was observed of the work's files during sessions, newest first: beside their
    /// deliveries, never counted as one.
    public func observations(of work: Work) -> [Observed] {
        work.files.flatMap { observedDeliveries[$0.path] ?? [] }
            .sorted { $0.modifiedAt != $1.modifiedAt ? $0.modifiedAt > $1.modifiedAt : $0.id < $1.id }
    }

    /// The candidates the person related to the work, newest first.
    public func related(to work: Work) -> [Candidate] {
        let paths = Set(corrections.filter { $0.kind == .related && work.contains($0.target) }.map(\.subject))
        return candidates.filter { paths.contains($0.path) }
    }

    /// The person's decisions relating the observed file at `path` to works, so each can be undone.
    public func relations(of path: String) -> [Correction] {
        corrections.filter { $0.kind == .related && $0.subject == path }
    }

    /// The sessions the person said the file at `path` isn't from: kept in view, not in effect,
    /// as the pairs kept apart are.
    public func detachments(of path: String) -> [Correction] {
        corrections.filter { $0.kind == .notFromSession && $0.subject == path }
    }

    public func project(_ key: String) -> Project? { projectIndex[key].map { projects[$0] } }

    /// The project as shown, for `key`; a derived folder's name when no work is shown in it now.
    public func projectName(_ key: String) -> String {
        project(key)?.name ?? userProjects.first { $0.key == key }?.name ?? derivedNames[key] ?? Projects.name(key)
    }

    public func placement(of work: Work) -> Placement { placements[work.id] ?? .found }

    /// The person's decisions joining the work's files, oldest first, also those through a file no
    /// longer in the library, so each can be undone.
    public func links(of work: Work) -> [Correction] {
        corrections.filter { $0.kind == .sameWork && (work.contains($0.subject) || work.contains($0.target)) }
    }

    /// The pairs the person said are not one work, with one of this work's files: kept in view,
    /// not in effect (`kit/design/foundations/standing.md`, rule 7).
    public func declines(of work: Work) -> [Correction] {
        corrections.filter { $0.kind == .notSameWork && (work.contains($0.subject) || work.contains($0.target)) }
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
        func first(_ file: Artifact) -> Date { file.deliveries.last?.deliveredAt ?? .distantPast }
        func last(_ file: Artifact) -> Date { file.latest.deliveredAt ?? .distantPast }
        let files = works.flatMap(\.files)
        // Not the Same ends suggestions for the later file of the two, and between their works.
        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        var declined = Set<String>(), apartWorks = Set<[Int]>()
        for c in corrections where c.kind == .notSameWork {
            guard let a = byPath[c.subject], let b = byPath[c.target] else { continue }
            declined.insert(first(a) > first(b) ? a.path : b.path)
            if let x = workIndex[a.path], let y = workIndex[b.path] { apartWorks.insert([min(x, y), max(x, y)]) }
        }
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
            return x != y && works[x].project == works[y].project && !apartWorks.contains([min(x, y), max(x, y)])
        }
        /// The nearest file before `date` in `group` (sorted by `key`) that passes `ok`.
        func nearest(in group: [Artifact], before date: Date, by key: (Artifact) -> Date, _ ok: (Artifact) -> Bool) -> Artifact? {
            var low = 0, high = group.count
            while low < high { let mid = (low + high) / 2; if key(group[mid]) < date { low = mid + 1 } else { high = mid } }
            return group[..<low].reversed().prefix(64).first(where: ok)
        }
        var suggestions: [Suggestion] = []
        for later in files where !declined.contains(later.path) {
            let arrived = first(later)
            let moved = (later.deliveries.last?.sha256).flatMap { bySha[$0] }.flatMap { group in
                nearest(in: group, before: arrived, by: last) { missing.contains($0.path) && apart($0, later) }
            }
            let renamed = versionKey(later.path).flatMap { byName[$0] }.flatMap { group in
                nearest(in: group, before: arrived, by: first) { $0.name != later.name && apart($0, later) }
            }
            let (earlier, reason): (Artifact?, Suggestion.Reason) = moved != nil ? (moved, .moved) : (renamed, .versionName)
            guard let earlier else { continue }
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
