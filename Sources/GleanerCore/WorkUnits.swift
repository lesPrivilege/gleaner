import Foundation

/// A unit of review the person makes, because evidence can't (docs/design/review.md): a group of
/// works in one project, called a collection in the window. It may sit inside one other unit, one
/// level deep, and holds works, each in at most one unit. Files stay where they are on disk; a unit
/// is the person's knowledge of which works go together, never a same-work join: its works keep
/// their own revisions and verdicts.
public struct WorkUnit: Sendable, Equatable, Identifiable {
    /// `unit:` and an id of its own.
    public var key: String
    /// The key of the project it belongs to: as made, in the registry; as shown, in an `Organization`.
    public var project: String
    /// The unit it sits inside; nil at the top of its project.
    public var parent: String?
    /// As made, in the registry; the latest the person gave it, in an `Organization`.
    public var name: String
    public var createdAt: Date

    public var id: String { key }

    /// Natural order of names ("2" before "10"), then oldest first.
    static func ordered(_ a: WorkUnit, _ b: WorkUnit) -> Bool {
        switch a.name.localizedStandardCompare(b.name) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: (a.createdAt, a.key) < (b.createdAt, b.key)
        }
    }
}

extension Registry {
    /// Why a unit can't be made where the person asked.
    public enum UnitFailure: Error, Equatable {
        /// The unit to put it inside isn't there.
        case noSuchUnit
        /// The unit to put it inside is itself inside another: units nest one level deep.
        case tooDeep
    }

    /// Every work unit the person made, oldest first, as made: renames and deletions are
    /// corrections (`Correction.Kind.unitName`, `.unitDeleted`), applied by `Organization`.
    public func units() throws -> [WorkUnit] {
        try db.rows("SELECT key, project, parent, name, created_at FROM units ORDER BY created_at, key").map {
            WorkUnit(key: $0["key"] as! String, project: $0["project"] as! String, parent: $0["parent"] as? String,
                     name: $0["name"] as! String, createdAt: Date(timeIntervalSince1970: $0["created_at"] as? Double ?? 0))
        }
    }

    /// Makes a unit in the project `project`, or inside the unit `parent`, which gives its project.
    /// A unit inside another holds no units of its own.
    @discardableResult
    public func addUnit(named name: String, in project: String, inside parent: String? = nil, at date: Date) throws -> WorkUnit {
        try writing { try db.transaction {
            var unit = WorkUnit(key: "unit:" + UUID().uuidString, project: project, parent: parent, name: name, createdAt: date)
            if let parent {
                guard let row = try db.rows("SELECT project, parent FROM units WHERE key = ?", [parent]).first else {
                    throw UnitFailure.noSuchUnit
                }
                guard row["parent"] == nil else { throw UnitFailure.tooDeep }
                unit.project = row["project"] as! String
            }
            try db.run("INSERT INTO units (key, project, parent, name, created_at) VALUES (?, ?, ?, ?, ?)",
                       [unit.key, unit.project, unit.parent, name, date])
            return unit
        } }
    }

    /// Takes back making the unit `key`: it goes, with the units inside it and every decision that
    /// names them, as if never made. What undoing New Collection does; deleting a unit is a
    /// decision of its own (`Correction.Kind.unitDeleted`), which can be undone. No file is touched.
    public func removeUnit(_ key: String) throws {
        try writing { try db.transaction { try removeUnits([key]) } }
    }

    /// Removes the units `keys`, those inside them, and every decision naming them.
    func removeUnits(_ keys: [String]) throws {
        guard !keys.isEmpty else { return }
        let marks = Array(repeating: "?", count: keys.count).joined(separator: ", ")
        let all = keys + (try db.rows("SELECT key FROM units WHERE parent IN (\(marks))", keys).compactMap { $0["key"] as? String })
        let allMarks = Array(repeating: "?", count: all.count).joined(separator: ", ")
        try db.run("""
            DELETE FROM corrections WHERE (kind IN ('unit', 'out_of_unit') AND target IN (\(allMarks)))
                OR (kind IN ('unit_name', 'unit_deleted') AND subject IN (\(allMarks)))
            """, all + all)
        try db.run("DELETE FROM units WHERE key IN (\(allMarks))", all)
    }
}
