import Foundation

/// A project the person made, to hold work that no repository or folder groups the way they want.
public struct UserProject: Sendable, Equatable, Identifiable {
    /// `user:` and an id of its own, never a folder's path.
    public var key: String
    public var name: String
    public var createdAt: Date

    public var id: String { key }
}

/// A person's decision about how the library is organized. It is kept apart from what Gleaner
/// observed (review-rulings §3, foundation 2): no correction changes a delivery, a capture, a hash
/// or a status, and reading the logs again never undoes one.
public struct Correction: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        /// The work holding the file `subject` belongs to the project `target`.
        case project
        /// The project derived from the folder `subject` is shown inside the project `target`.
        case combine
        /// The files `subject` and `target` are versions of one work.
        case sameWork = "same_work"
        /// The files `subject` and `target` are not one work: Gleaner stops suggesting it.
        case notSameWork = "not_same_work"
    }

    public var id: Int64
    public var kind: Kind
    public var subject: String
    public var target: String
    public var madeAt: Date
}

extension Registry {
    public func userProjects() throws -> [UserProject] {
        try db.rows("SELECT key, name, created_at FROM projects ORDER BY created_at").map {
            UserProject(key: $0["key"] as! String, name: $0["name"] as! String,
                        createdAt: Date(timeIntervalSince1970: $0["created_at"] as? Double ?? 0))
        }
    }

    @discardableResult
    public func addProject(named name: String, at date: Date) throws -> UserProject {
        try addProject(named: name, at: date, moving: [])
    }

    /// Makes a project and moves the files `moving` into it, whole or not at all.
    @discardableResult
    public func addProject(named name: String, at date: Date, moving subjects: [String]) throws -> UserProject {
        let project = UserProject(key: "user:" + UUID().uuidString, name: name, createdAt: date)
        try db.transaction {
            try db.run("INSERT INTO projects (key, name, created_at) VALUES (?, ?, ?)", [project.key, name, date])
            try record(.project, subjects: subjects, target: project.key, at: date)
        }
        return project
    }

    public func renameProject(_ key: String, to name: String) throws {
        try db.run("UPDATE projects SET name = ? WHERE key = ?", [name, key])
    }

    /// Removes a project the person made, with every correction that put work or projects in it:
    /// that work goes back to where Gleaner would put it. No file is touched.
    public func removeProject(_ key: String) throws {
        try db.transaction {
            try db.run("DELETE FROM corrections WHERE kind IN ('project', 'combine') AND target = ?", [key])
            try db.run("DELETE FROM projects WHERE key = ?", [key])
        }
    }

    public func corrections() throws -> [Correction] {
        try db.rows("SELECT id, kind, subject, target, made_at FROM corrections ORDER BY made_at, id").compactMap { row in
            guard let kind = Correction.Kind(rawValue: row["kind"] as? String ?? "") else { return nil }
            return Correction(id: row["id"] as! Int64, kind: kind, subject: row["subject"] as! String,
                              target: row["target"] as! String, madeAt: Date(timeIntervalSince1970: row["made_at"] as? Double ?? 0))
        }
    }

    /// Records a decision. A file's work, or a folder's project, has one place: a new one replaces
    /// the last. Two files are one work or not, so saying one replaces the other.
    public func correct(_ kind: Correction.Kind, subject: String, target: String, at date: Date) throws {
        try correct(kind, subjects: [subject], target: target, at: date)
    }

    /// The same decision for each of `subjects`, made whole or not at all.
    public func correct(_ kind: Correction.Kind, subjects: [String], target: String, at date: Date) throws {
        try db.transaction { try record(kind, subjects: subjects, target: target, at: date) }
    }

    private func record(_ kind: Correction.Kind, subjects: [String], target: String, at date: Date) throws {
        for subject in subjects {
            let (subject, target) = kind == .sameWork || kind == .notSameWork
                ? (min(subject, target), max(subject, target)) : (subject, target)
            switch kind {
            case .project, .combine:
                try db.run("DELETE FROM corrections WHERE kind = ? AND subject = ?", [kind.rawValue, subject])
            case .sameWork, .notSameWork:
                try db.run("DELETE FROM corrections WHERE kind IN ('same_work', 'not_same_work') AND subject = ? AND target = ?",
                           [subject, target])
            }
            try db.run("INSERT INTO corrections (kind, subject, target, made_at) VALUES (?, ?, ?, ?)",
                       [kind.rawValue, subject, target, date])
        }
    }

    /// Undoes several decisions, made whole or not at all.
    public func undo(_ corrections: [Correction.ID]) throws {
        try db.transaction { for id in corrections { try undo(id) } }
    }

    public func undo(_ correction: Correction.ID) throws {
        try db.run("DELETE FROM corrections WHERE id = ?", [correction])
    }

    /// Undoes every correction and removes the projects the person made: the library is organized
    /// as Gleaner found it. No file is touched.
    public func undoAllCorrections() throws {
        try db.transaction { try db.execute("DELETE FROM corrections; DELETE FROM projects;") }
    }
}
