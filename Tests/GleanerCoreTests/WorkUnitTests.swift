import Foundation
import Testing
@testable import GleanerCore

/// Work units, collections in the window (docs/design/review.md): made by the person in one
/// project, nested one level, each work in at most one, every change a decision appended to the
/// corrections, undone by taking it back, and kept as the library is read again.
@Suite struct WorkUnitTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let registry: Registry

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-units-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        registry = try Registry(path: folder.appendingPathComponent("registry.sqlite").path)
    }

    func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3600) }

    /// A file delivered at each of `hours`, newest last.
    func file(_ path: String, _ hours: [Double], repository: String? = nil) -> Artifact {
        let deliveries = hours.enumerated().map { i, h in
            Delivery(id: "\(path)#\(i + 1)", number: i + 1, path: path, deliveredAt: at(h), replyLine: i + 1, provider: .claudeCode,
                     sessionTitle: nil, request: nil, cwd: (path as NSString).deletingLastPathComponent, evidence: [],
                     logPath: "/logs/s.jsonl",
                     capture: Capture(sha256: "\(path)\(i)", size: 1, modifiedAt: nil, observedAt: at(h), savedAt: nil,
                                      provenance: .atDelivery, kind: .file))
        }
        return Artifact(path: path, deliveries: deliveries.reversed(), repository: repository)
    }

    /// The library organized as the registry holds the person's decisions now.
    func organize(_ artifacts: [Artifact]) throws -> Organization {
        Organization(artifacts: artifacts, corrections: try registry.corrections(), projects: try registry.userProjects(),
                     units: try registry.units())
    }

    func decide(_ kind: Correction.Kind, _ subjects: [String], _ target: String, at hours: Double) throws {
        try registry.correct(kind, subjects: subjects, target: target, at: at(hours))
    }

    func latest(_ kind: Correction.Kind) throws -> Correction {
        try #require(try registry.corrections().last { $0.kind == kind })
    }

    // MARK: making them

    @Test func unitsNestOneLevelInTheirProjectInNaturalOrder() throws {
        let video = file("/w/series/out/ep02.mp4", [1], repository: "/w/series")
        let series = try registry.addUnit(named: "Series", in: "/w/series", at: at(0))
        // Made inside the series, an episode is in the series' project, whatever it is asked for.
        let ten = try registry.addUnit(named: "Episode 10", in: "/elsewhere", inside: series.key, at: at(0.1))
        let two = try registry.addUnit(named: "Episode 2", in: "/w/series", inside: series.key, at: at(0.2))
        #expect(ten.project == "/w/series")
        #expect(throws: Registry.UnitFailure.tooDeep) { try registry.addUnit(named: "Part", in: "/w/series", inside: two.key, at: at(1)) }
        #expect(throws: Registry.UnitFailure.noSuchUnit) { try registry.addUnit(named: "Part", in: "/w/series", inside: "unit:gone", at: at(1)) }

        let organization = try organize([video])
        #expect(organization.units(in: "/w/series").map(\.name) == ["Series"])
        // "2" before "10", as Finder sorts names.
        #expect(organization.units(inside: series.key).map(\.name) == ["Episode 2", "Episode 10"])
        #expect(organization.units.map(\.name) == ["Series", "Episode 2", "Episode 10"])
        #expect(organization.unit(two.key)?.parent == series.key)
        // Making units moves no work: the video is in none.
        #expect(organization.works.allSatisfy { $0.unit == nil })
        #expect(try registry.corrections().isEmpty)
    }

    @Test func aProjectHoldingAUnitIsListedWithItAndAUnitFollowsItsProjectShownInside() throws {
        let site = file("/w/site/index.html", [1], repository: "/w/site")
        let brand = try registry.addUnit(named: "Brand kit", in: "/w/brand", at: at(0))
        var organization = try organize([site])
        // No work is in /w/brand, but the unit made there keeps it in the list.
        #expect(organization.project("/w/brand")?.works.isEmpty == true)
        #expect(organization.units(in: "/w/brand").map(\.key) == [brand.key])

        try decide(.combine, ["/w/brand"], "/w/site", at: 1)
        organization = try organize([site])
        #expect(organization.unit(brand.key)?.project == "/w/site")
        #expect(organization.units(in: "/w/site").map(\.name) == ["Brand kit"])
    }

    // MARK: what is in them

    @Test func aWorkIsInOneUnitAndTheLatestDecisionPlacesIt() throws {
        let video = file("/w/series/out/ep01.mp4", [1], repository: "/w/series")
        let one = try registry.addUnit(named: "Episode 1", in: "/w/series", at: at(0))
        let two = try registry.addUnit(named: "Episode 2", in: "/w/series", at: at(0))
        try decide(.unit, [video.path], one.key, at: 1)
        try decide(.unit, [video.path], two.key, at: 2)
        var organization = try organize([video])
        #expect(organization.work(containing: video.path)?.unit == two.key)
        #expect(organization.works(in: one.key).isEmpty && organization.works(in: two.key).map(\.id) == [video.path])
        #expect(organization.unit(of: try #require(organization.work(containing: video.path)))?.decision.target == two.key)

        // Undone, the decision before it stands again (A19).
        try registry.undo(try latest(.unit).id)
        organization = try organize([video])
        #expect(organization.work(containing: video.path)?.unit == one.key)

        // Taken out, it is in none; that too is a decision, and undone it is back.
        try decide(.outOfUnit, [video.path], one.key, at: 3)
        organization = try organize([video])
        #expect(organization.work(containing: video.path)?.unit == nil)
        try registry.undo(try latest(.outOfUnit).id)
        #expect(try organize([video]).work(containing: video.path)?.unit == one.key)
        // Nothing about the file changed.
        #expect(try organize([video]).work(containing: video.path)?.deliveries.map(\.id) == video.deliveries.map(\.id))
    }

    @Test func aWorkOfSeveralFilesIsPlacedByTheLatestDecisionAboutAnyOfThem() throws {
        let draft = file("/w/board/board-draft.md", [1])
        let final = file("/w/board/board-final.md", [2])
        let unit = try registry.addUnit(named: "Board", in: "/w/board", at: at(0))
        try decide(.sameWork, [final.path], draft.path, at: 0.5)
        try decide(.unit, [draft.path, final.path], unit.key, at: 1)
        var organization = try organize([draft, final])
        #expect(organization.works.count == 1 && organization.works[0].unit == unit.key)
        // A later decision about one file places the whole work.
        try decide(.outOfUnit, [final.path], unit.key, at: 2)
        organization = try organize([draft, final])
        #expect(organization.works[0].unit == nil)
    }

    @Test func aUnitListsItsOwnWorksWhatAPersonOpensFirstThenNewest() throws {
        let video = file("/w/series/out/ep01.mp4", [1], repository: "/w/series")
        let inputs = file("/w/series/out/ep01.inputs.json", [3], repository: "/w/series")
        let cover = file("/w/series/covers/ov-4x3.png", [2], repository: "/w/series")
        let logo = file("/w/series/logo.png", [0.5], repository: "/w/series")
        let series = try registry.addUnit(named: "Series", in: "/w/series", at: at(0))
        let one = try registry.addUnit(named: "Episode 1", in: "/w/series", inside: series.key, at: at(0))
        try decide(.unit, [video.path, inputs.path, cover.path], one.key, at: 4)
        try decide(.unit, [logo.path], series.key, at: 4)
        let organization = try organize([video, inputs, cover, logo])
        #expect(organization.works(in: one.key).map(\.name) == ["ov-4x3.png", "ep01.mp4", "ep01.inputs.json"])
        #expect(organization.works(in: series.key).map(\.name) == ["logo.png"])
        #expect(organization.works(in: series.key, inner: true).map(\.name) == ["logo.png", "ov-4x3.png", "ep01.mp4", "ep01.inputs.json"])
        #expect(organization.poster(of: one.key)?.name == "ov-4x3.png")
        #expect(organization.poster(of: series.key)?.name == "logo.png")
    }

    @Test func aWorkFromAnotherProjectIsMovedWithItAndLeavesWhenMovedOn() throws {
        let cover = file("/w/design/ov-4x3.png", [1], repository: "/w/design")
        let video = file("/w/series/out/ep01.mp4", [1], repository: "/w/series")
        let unit = try registry.addUnit(named: "Episode 1", in: "/w/series", at: at(0))
        // Added from another project, it is moved to the unit's with it, as one decision.
        try registry.correct([(.unit, cover.path, unit.key), (.project, cover.path, "/w/series")], at: at(1))
        var organization = try organize([cover, video])
        var work = try #require(organization.work(containing: cover.path))
        #expect(work.project == "/w/series" && work.unit == unit.key)
        if case .moved = organization.placement(of: work) {} else { Issue.record("not said to be moved") }
        // Undone as one, it is back where it was.
        try registry.undo(try registry.corrections().map(\.id))
        work = try #require(try organize([cover, video]).work(containing: cover.path))
        #expect(work.project == "/w/design" && work.unit == nil)

        // Moved on to a project of the person's own, it leaves the unit, which stays in its project.
        try registry.correct([(.unit, cover.path, unit.key), (.project, cover.path, "/w/series")], at: at(2))
        let mine = try registry.addProject(named: "Covers", at: at(3), moving: [cover.path])
        organization = try organize([cover, video])
        work = try #require(organization.work(containing: cover.path))
        #expect(work.project == mine.key && work.unit == nil)
        #expect(organization.units(in: "/w/series").map(\.key) == [unit.key])
        // Moved back, the decision that put it in the unit stands again.
        try decide(.project, [cover.path], "/w/series", at: 4)
        #expect(try organize([cover, video]).work(containing: cover.path)?.unit == unit.key)
    }

    @Test func undoingAMoveReturnsTheWorkToTheProjectBeforeItAndToItsUnitThere() throws {
        let video = file("/w/series/out/ep01.mp4", [1], repository: "/w/series")
        // In a project of the person's own, and a unit there.
        let channel = try registry.addProject(named: "Channel", at: at(0), moving: [video.path])
        let series = try registry.addUnit(named: "Series", in: channel.key, at: at(0.5))
        try decide(.unit, [video.path], series.key, at: 1)
        let archive = try registry.addProject(named: "Archive", at: at(1.5))
        try decide(.project, [video.path], archive.key, at: 2)
        var work = try #require(try organize([video]).work(containing: video.path))
        #expect(work.project == archive.key && work.unit == nil)
        // Undone, the move before it stands again, and the unit with it (A19).
        try registry.undo(try latest(.project).id)
        work = try #require(try organize([video]).work(containing: video.path))
        #expect(work.project == channel.key && work.unit == series.key)
        if case .moved(let move) = try organize([video]).placement(of: work) { #expect(move.target == channel.key) } else {
            Issue.record("not said to be moved")
        }

        // Added from where Gleaner found it to a unit of the person's project, moved on, and undone.
        let other = file("/w/series/out/ep02.mp4", [1], repository: "/w/series")
        try registry.correct([(.unit, other.path, series.key), (.project, other.path, channel.key)], at: at(3))
        try decide(.project, [other.path], archive.key, at: 4)
        try registry.undo(try latest(.project).id)
        work = try #require(try organize([video, other]).work(containing: other.path))
        #expect(work.project == channel.key && work.unit == series.key)
        // Put Back takes back every move: the work is where Gleaner found it, in no unit there.
        try registry.undo(try registry.corrections().filter { $0.kind == .project && $0.subject == other.path }.map(\.id))
        work = try #require(try organize([video, other]).work(containing: other.path))
        #expect(work.project == "/w/series" && work.unit == nil)
    }

    // MARK: changing them

    @Test func renamingIsAppendedAndUndoneToThePreviousName() throws {
        let unit = try registry.addUnit(named: "Ep 1", in: "/w/series", at: at(0))
        try decide(.unitName, [unit.key], "Episode 1", at: 1)
        try decide(.unitName, [unit.key], "Episode 01", at: 2)
        #expect(try organize([]).unit(unit.key)?.name == "Episode 01")
        try registry.undo(try latest(.unitName).id)
        #expect(try organize([]).unit(unit.key)?.name == "Episode 1")
        // As made, in the registry, it keeps the name it was made with.
        #expect(try registry.units().map(\.name) == ["Ep 1"])
    }

    @Test func deletingAUnitReturnsItsWorksAndUndoBringsItBackAsItWas() throws {
        let video = file("/w/series/out/ep01.mp4", [1], repository: "/w/series")
        let logo = file("/w/series/logo.png", [2], repository: "/w/series")
        let series = try registry.addUnit(named: "Series", in: "/w/series", at: at(0))
        let one = try registry.addUnit(named: "Episode 1", in: "/w/series", inside: series.key, at: at(0))
        try decide(.unit, [video.path], one.key, at: 1)
        try decide(.unit, [logo.path], series.key, at: 1)

        // Deleting the series deletes the episode inside it; their works go back to the project.
        try decide(.unitDeleted, [series.key], "", at: 2)
        var organization = try organize([video, logo])
        #expect(organization.units.isEmpty)
        #expect(organization.works.allSatisfy { $0.unit == nil && $0.project == "/w/series" })
        // Its name stays, for the corrections that name it.
        #expect(organization.unitName(series.key) == "Series")

        try registry.undo(try latest(.unitDeleted).id)
        organization = try organize([video, logo])
        #expect(organization.units.map(\.name) == ["Series", "Episode 1"])
        #expect(organization.work(containing: video.path)?.unit == one.key && organization.work(containing: logo.path)?.unit == series.key)

        // Deleting only the episode leaves the series and what is in it.
        try decide(.unitDeleted, [one.key], "", at: 3)
        organization = try organize([video, logo])
        #expect(organization.units.map(\.name) == ["Series"])
        #expect(organization.work(containing: video.path)?.unit == nil && organization.work(containing: logo.path)?.unit == series.key)
    }

    @Test func takingBackMakingAUnitRemovesItWithWhatWasDecidedAboutIt() throws {
        let video = file("/w/series/out/ep01.mp4", [1], repository: "/w/series")
        let series = try registry.addUnit(named: "Series", in: "/w/series", at: at(0))
        let one = try registry.addUnit(named: "Episode 1", in: "/w/series", inside: series.key, at: at(0))
        let other = try registry.addUnit(named: "Other", in: "/w/series", at: at(0))
        try decide(.unit, [video.path], one.key, at: 1)
        try decide(.unitName, [series.key], "The series", at: 1)
        try decide(.unit, [video.path], other.key, at: 0.5)
        try registry.removeUnit(series.key)
        #expect(try registry.units().map(\.key) == [other.key])
        // Only decisions naming another unit stay.
        #expect(try registry.corrections().map(\.target) == [other.key])
        #expect(try organize([video]).work(containing: video.path)?.unit == other.key)
    }

    @Test func undoAllAndDeletingTheProjectRemoveUnits() throws {
        let mine = try registry.addProject(named: "Launch", at: at(0))
        let unit = try registry.addUnit(named: "Teaser", in: mine.key, at: at(0))
        try decide(.unitName, [unit.key], "Trailer", at: 1)
        try registry.removeProject(mine.key)
        #expect(try registry.units().isEmpty && registry.corrections().isEmpty)

        try registry.addUnit(named: "Series", in: "/w/series", at: at(2))
        try registry.undoAllCorrections()
        #expect(try registry.units().isEmpty)
    }

    @Test func unitsAndTheirDecisionsSurviveAnotherConnectionToTheLibrary() throws {
        let video = file("/w/series/out/ep01.mp4", [1], repository: "/w/series")
        let unit = try registry.addUnit(named: "Episode 1", in: "/w/series", at: at(0))
        try decide(.unit, [video.path], unit.key, at: 1)
        try decide(.unitName, [unit.key], "Pilot", at: 2)
        let again = try Registry(path: registry.path)
        let organization = Organization(artifacts: [video], corrections: try again.corrections(), units: try again.units())
        #expect(organization.unit(unit.key)?.name == "Pilot")
        #expect(organization.work(containing: video.path)?.unit == unit.key)
    }
}
