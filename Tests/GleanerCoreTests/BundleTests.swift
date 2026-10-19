import Foundation
import Testing
@testable import GleanerCore

/// A reply that names a folder hands over what is in it (SPEC §5.4), on a synthetic machine, in
/// several kinds of work: each file a delivery of its own, traceable to the reply through the
/// folder, listed by metadata only and by what its dates show, and read when the person acts on it.
@Suite struct BundleTests {
    let root: URL
    /// The synthetic home: its folders are where the work is.
    let home: URL
    let indexer: Indexer
    /// Twenty minutes ago. Files are written now, so a reply after now (`minutes(60)`, say) comes
    /// after every file's inode last changed, as a reply after the work that made them does.
    let t0 = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 20 * 60).rounded(.down))

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("gleaner-bundle-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        for folder in [home, root.appendingPathComponent("claude"), root.appendingPathComponent("codex/sessions")] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("registry.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("objects"), staging: root.appendingPathComponent("staging")),
            sources: LogSources(claudeProjects: root.appendingPathComponent("claude"), codexHome: root.appendingPathComponent("codex")))
        indexer.home = home.path
    }

    // MARK: helpers

    func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    /// A Claude Code session working in `cwd`, asked at `asked` and answering with `reply` at
    /// `replied`; then each of `more` asked and answered in turn.
    @discardableResult
    func session(_ id: String, in cwd: URL, asked: Date, replied: Date, reply: String, request: String = "Make the next part",
                 title: String? = nil, more: [(asked: Date, replied: Date, reply: String)] = []) throws -> String {
        let folder = root.appendingPathComponent("claude/\(id)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func line(_ object: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) }
        let stamp = { (date: Date) in date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
        var lines: [String] = []
        for turn in [(asked: asked, replied: replied, reply: reply)] + more {
            lines.append(try line(["type": "user", "sessionId": id, "cwd": cwd.path, "timestamp": stamp(turn.asked), "origin": ["kind": "human"],
                                   "message": ["role": "user", "content": request]]))
            lines.append(try line(["type": "assistant", "sessionId": id, "cwd": cwd.path, "timestamp": stamp(turn.replied),
                                   "message": ["role": "assistant", "model": "m", "content": [["type": "text", "text": turn.reply]]]]))
        }
        if let title { lines.append(try line(["type": "custom-title", "sessionId": id, "customTitle": title])) }
        let log = folder.appendingPathComponent("\(id).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: log, atomically: false, encoding: .utf8)
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent == log.lastPathComponent }?.path ?? log.path
    }

    static func date(_ path: String, created: Date, modified: Date) throws {
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: path)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path)
    }

    /// A file at `relative` in `folder`, written now; with `created`, dated then (and `modified`).
    @discardableResult
    func file(_ relative: String, in folder: URL, created: Date? = nil, modified: Date? = nil, text: String = "x") throws -> String {
        let url = folder.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if let created { try Self.date(url.path, created: created, modified: modified ?? created) }
        return url.path
    }

    func folder(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func organization(corrections: [Correction] = [], projects: [UserProject] = []) throws -> Organization {
        Organization(artifacts: try indexer.registry.artifacts(), observed: Candidate.files(try indexer.registry.observations()),
                     corrections: corrections, projects: projects)
    }

    func artifact(_ path: String) throws -> Artifact {
        try #require(try indexer.registry.artifacts().first { $0.path == path })
    }

    /// The works handed over in a folder only, by file name.
    func inFolders(_ organization: Organization) -> [String] {
        names(organization.works.filter { $0.deliveries.allSatisfy { $0.member != nil } }.map(\.latest.path))
    }

    func names(_ paths: some Sequence<String>) -> [String] { paths.map { ($0 as NSString).lastPathComponent }.sorted() }

    /// The works a search finds, by file name (SPEC §10).
    func search(_ query: String, in organization: Organization) -> [String] {
        let tokens = query.split(separator: " ").map(String.init)
        return names(organization.works.filter { $0.match(tokens, project: organization.projectName($0.project)) != nil }.map(\.latest.path))
    }

    func members(of folder: String) throws -> Int {
        Int(try indexer.registry.db.rows("SELECT COUNT(*) AS n FROM members m JOIN deliveries d ON d.id = m.delivery_id WHERE d.path = ?",
                                         [folder]).first?["n"] as? Int64 ?? -1)
    }

    // MARK: kinds of work

    @Test func aMediaPipelineHandsOverItsSegmentsButNeverItsHiddenFiles() throws {
        let series = try folder("Projects/series")
        let out = series.appendingPathComponent("out")
        for n in 0..<300 { try file(String(format: "segments/%02d/seg-%03d.ts", n / 100, n), in: out, created: minutes(10 + Double(n) / 20)) }
        try file("ep00.mp4", in: out, created: minutes(40))
        try file("ep00.mix.wav", in: out, created: minutes(41))
        try file(".env", in: out, created: minutes(5), text: "API_KEY=synthetic")
        try file(".DS_Store", in: out, created: minutes(5))
        try file(".cache/frame.bin", in: out, created: minutes(5))
        try file("node_modules/pkg/index.js", in: out, created: minutes(5))
        try file("scripts/render.py", in: series, created: minutes(2))
        let log = try session("series", in: series, asked: t0, replied: minutes(60), reply: "Everything is in [out](out/).",
                              request: "Render episode zero with every segment", title: "Pipeline")
        let report = try indexer.run()
        #expect(report.sources[.claudeCode]?.folderProblems == [] && report.sources[.claudeCode]?.foldersNotUnpacked == [])

        let organization = try organization()
        // Each regular file in it, nested or not; no hidden file, nothing in a hidden folder or a cache.
        #expect(inFolders(organization).count == 302)
        let hidden = ["env", "DS_Store", "frame.bin", "index.js"]
        #expect(!organization.works.contains { work in hidden.contains { work.name.contains($0) } })
        let video = try artifact(out.path + "/ep00.mp4")
        let folder = try artifact(out.path)
        #expect(folder.latest.unpacking?.members == 302 && folder.latest.unpacking?.notUnpacked == nil)
        // The folder's reply, session, request, time and evidence, through the folder's delivery.
        let delivery = video.latest
        #expect(video.deliveries.count == 1 && delivery.number == 1)
        #expect(delivery.member == Membership(folderDelivery: folder.latest.id, folder: out.path))
        #expect(delivery.request == "Render episode zero with every segment" && delivery.sessionTitle == "Pipeline")
        #expect(delivery.deliveredAt == folder.latest.deliveredAt && delivery.logPath == log)
        #expect(delivery.evidence.map(\.rawTarget) == ["out/"] && delivery.replyLine == folder.latest.replyLine)
        // Listed, not read: size and dates, no hash, nothing saved.
        #expect(delivery.capture?.provenance == .listed && delivery.capture?.sha256 == nil && delivery.capture?.size == 1)
        #expect(delivery.capture?.kind == .file && delivery.capture?.savedAt == nil)
        // Its observation stays beside it; the hidden files observed in the workspace stay candidates,
        // never searched or listed as works.
        let work = try #require(organization.work(containing: video.path))
        #expect(organization.observations(of: work).map(\.kind) == [.appeared])
        #expect(names(organization.candidates.map(\.path)) == [".DS_Store", ".env", "render.py"])
        #expect(search("env", in: organization).isEmpty && search("API_KEY", in: organization).isEmpty)
        // A delivered folder's files aren't the reply's siblings: they are reached through the folder.
        #expect(Artifact.deliveredWith(try indexer.registry.artifacts()).isEmpty)
    }

    @Test func aReportFolderIsFoundByItsFilesNamesAndFolders() throws {
        let project = try folder("Projects/q3")
        let report = project.appendingPathComponent("report")
        for name in ["report.md", "report.pdf", "charts/revenue.png", "charts/costs.png", "charts/make_charts.py", "data/q3.csv"] {
            try file(name, in: report, created: minutes(20))
        }
        try session("q3", in: project, asked: t0, replied: minutes(60), reply: "The [quarterly report](report/) is ready.",
                    request: "Write the quarterly board report", title: "Quarterly")
        _ = try indexer.run()

        let organization = try organization()
        #expect(inFolders(organization) == ["costs.png", "make_charts.py", "q3.csv", "report.md", "report.pdf", "revenue.png"])
        // A file is found by its name and its folder; the reply's words find the folder.
        #expect(search("revenue", in: organization) == ["revenue.png"])
        #expect(search("charts", in: organization) == ["costs.png", "make_charts.py", "revenue.png"])
        #expect(search("board quarterly", in: organization) == ["report"])
        #expect(search("q3", in: organization).count == 7)
        // All in the project of the folder the session worked in.
        #expect(organization.works.allSatisfy { $0.project == project.path })
        #expect(organization.projects.count == 1 && organization.projects[0].works.count == 7)
    }

    @Test func aStaticSiteNamedWithItsPageDeliversThePageOnce() throws {
        let site = try folder("Projects/site")
        for name in ["index.html", "css/style.css", "js/app.js", "assets/logo.svg", "assets/fonts/inter.woff2"] {
            try file(name, in: site.appendingPathComponent("public"), created: minutes(20))
        }
        try session("site", in: site, asked: t0, replied: minutes(60),
                    reply: "The [site](public/) is built; open [index.html](public/index.html).")
        _ = try indexer.run()

        let organization = try organization()
        // The page the reply named itself keeps that one delivery; the folder's other files come with it.
        let page = try artifact(site.path + "/public/index.html")
        #expect(page.deliveries.count == 1 && page.latest.member == nil && page.latest.sha256 != nil)
        #expect(inFolders(organization) == ["app.js", "inter.woff2", "logo.svg", "style.css"])
        #expect(Artifact.deliveredWith(try indexer.registry.artifacts())[page.latest.id]?.map(\.path) == [site.path + "/public"])
        #expect(try members(of: site.path + "/public") == 5)
    }

    @Test func aDataAnalysisOutputIsOrderedByWhatAPersonOpens() throws {
        let analysis = try folder("Projects/churn")
        let output = analysis.appendingPathComponent("output")
        for name in ["figures/fig1.png", "figures/fig2.png", "tables/summary.csv", "model.pkl", "findings.md"] {
            try file(name, in: output, created: minutes(30))
        }
        try file("analysis.ipynb", in: analysis, created: minutes(5))
        try session("churn", in: analysis, asked: t0, replied: minutes(60),
                    reply: "Open the [notebook](analysis.ipynb); results are in [output](output/).")
        _ = try indexer.run()

        let organization = try organization()
        let entries = organization.works.map(Listing.Entry.work)
        // Handed over, named or in the folder alike; what a person opens first, then newest; the
        // reply's files share its time, so then by path.
        #expect(Listing.ordered(entries).map(\.name) == ["output", "fig1.png", "fig2.png", "findings.md", "analysis.ipynb", "model.pkl", "summary.csv"])
    }

    @Test func aCodeChangeNamingASubfolderOfTheRepositoryHandsOverItsFiles() throws {
        let repo = try folder("Projects/app")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try file("Package.swift", in: repo, created: minutes(-500))
        try file("Sources/Feature/Search.swift", in: repo, created: minutes(10))
        try file("Sources/Feature/Index.swift", in: repo, created: minutes(-500), modified: minutes(12))
        try file("Sources/App/App.swift", in: repo, created: minutes(-500))
        try session("code", in: repo.appendingPathComponent("Sources"), asked: t0, replied: minutes(60),
                    reply: "I added [the feature](Feature/).")
        _ = try indexer.run()

        let organization = try organization()
        #expect(inFolders(organization) == ["Index.swift", "Search.swift"])
        let search = try #require(organization.work(containing: repo.path + "/Sources/Feature/Search.swift"))
        #expect(search.project == repo.path && search.latest.inRepository && search.latest.checkout?.folder == repo.path)
    }

    // MARK: folders not unpacked

    @Test func aProjectsOwnFolderTheHomeOrAFolderDirectlyInItIsNotUnpacked() throws {
        let repo = try folder("work/app")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try file("README.md", in: repo, created: minutes(10))
        let clients = try folder("work/clients")
        try FileManager.default.createDirectory(at: clients.appendingPathComponent("beta/app/.git"), withIntermediateDirectories: true)
        try file("beta/app/main.swift", in: clients, created: minutes(10))
        try file("brief.md", in: clients, created: minutes(10))
        let desktop = try folder("Desktop")
        try file("today.png", in: desktop, created: minutes(10))
        // Outside git, the folder a conversation worked in is its project, and so is one holding it.
        let site = try folder("work/site")
        try file("index.html", in: site, created: minutes(10))
        let essays = try folder("work/essays")
        let draft = try folder("work/essays/draft")
        try file("essay.md", in: draft, created: minutes(10))
        let links = [repo, clients, desktop, home].map { "[\($0.lastPathComponent)](\($0.path))" }.joined(separator: ", ")
        try session("repo", in: repo, asked: t0, replied: minutes(60), reply: "Handed over: \(links).")
        try session("site", in: site, asked: t0, replied: minutes(60), reply: "The [site](\(site.path)) is done.")
        try session("essay", in: draft, asked: t0, replied: minutes(60), reply: "All the [essays](\(essays.path)).")
        let report = try indexer.run()

        let reasons = Dictionary(uniqueKeysWithValues: try [repo, clients, desktop, home, site, essays].map { url in
            (url.lastPathComponent, try artifact(url.path).latest.unpacking?.notUnpacked)
        })
        #expect(reasons["app"] == "a Git checkout’s folder")
        #expect(reasons["clients"] == "a folder holding a Git repository")
        #expect(reasons["Desktop"] == "a folder directly in the home")
        #expect(reasons["home"] == "the home folder or a folder holding it")
        #expect(reasons["site"] == "the folder its conversation worked in")
        #expect(reasons["essays"] == "a folder holding the one its conversation worked in")
        #expect(try indexer.registry.db.rows("SELECT 1 FROM members").isEmpty)
        // Said in Sources, under the agent, and not as a problem.
        #expect(report.sources[.claudeCode]?.foldersNotUnpacked.count == 6)
        #expect(report.sources[.claudeCode]?.foldersNotUnpacked.contains("\(desktop.path): not unpacked, a folder directly in the home") == true)
        #expect(report.sources[.claudeCode]?.hasProblems == false)
    }

    /// The reasons each delivered folder at `paths` isn't unpacked, by its last two path components,
    /// after a reply in `cwd` names them all; and that no file was listed.
    func notUnpacked(_ paths: [String], cwd: URL) throws -> [String: String?] {
        let links = paths.map { "[\(($0 as NSString).lastPathComponent)](<\($0)/>)" }.joined(separator: ", ")
        try session("handed", in: cwd, asked: t0, replied: minutes(60), reply: "Handed over: \(links).")
        _ = try indexer.run()
        #expect(try indexer.registry.db.rows("SELECT path FROM members").isEmpty)
        return Dictionary(uniqueKeysWithValues: try paths.map { path in
            (((path as NSString).pathComponents.suffix(2)).joined(separator: "/"), try artifact(path).latest.unpacking?.notUnpacked)
        })
    }

    /// A folder inside a hidden folder holds what Finder hides, settings and their tokens among
    /// them; one inside a cache, what a tool rebuilds. Neither is unpacked, however deep. Counted
    /// from the repository holding the folder, an agent's worktree kept in a hidden folder is
    /// unpacked as any of its repository's folders.
    @Test func aFolderInsideAHiddenFolderOrACacheIsNotUnpacked() throws {
        let gh = try folder(".config/gh")
        try file("hosts.yml", in: gh, created: minutes(10), text: "oauth_token: synthetic")
        let repo = try folder("Projects/tool")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let release = repo.appendingPathComponent(".build/release")
        try file("tool", in: release, created: minutes(10))
        try file("CACHEDIR.TAG", in: repo.appendingPathComponent("target"), created: minutes(10))
        let cargo = repo.appendingPathComponent("target/release")
        try file("deps/libserde-1234.rlib", in: cargo, created: minutes(10))
        let widget = repo.appendingPathComponent("node_modules/widget/dist")
        try file("widget.js", in: widget, created: minutes(10))
        let worktree = repo.appendingPathComponent(".claude/worktrees/x")
        try file(".git", in: worktree, created: minutes(10), text: "gitdir: \(repo.path)/.git/worktrees/x")
        let dist = worktree.appendingPathComponent("dist")
        try file("app.js", in: dist, created: minutes(10))

        let reasons = try notUnpacked([gh.path, release.path, cargo.path, widget.path], cwd: repo)
        #expect(reasons == [".config/gh": "inside a hidden folder", ".build/release": "inside a hidden folder",
                            "target/release": "inside a cache a tool left", "widget/dist": "inside a cache a tool left"])
        let organization = try organization()
        #expect(search("hosts", in: organization).isEmpty && search("oauth", in: organization).isEmpty)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: indexer.store.objects.path)) ?? []).isEmpty)

        try session("worktree", in: worktree, asked: t0, replied: minutes(60), reply: "Built into [dist](dist/).")
        _ = try indexer.run()
        #expect(try members(of: dist.path) == 1)
    }

    /// A volume and a cloud drive hold a person's things, as the home does: neither they nor a
    /// folder directly in one is unpacked, by depth; a folder deeper in is. A link isn't followed,
    /// to another volume or anywhere.
    @Test func aCloudDriveAFolderDirectlyInOneOrALinkIsNotUnpacked() throws {
        let dropbox = try folder("Library/CloudStorage/Dropbox")
        try file("Family/photo.jpg", in: dropbox, created: minutes(10))
        let taxes = try folder("Library/CloudStorage/Dropbox/Taxes")
        try file("2024.pdf", in: taxes, created: minutes(10))
        let icloud = try folder("Library/Mobile Documents/com~apple~CloudDocs")
        let personal = try folder("Library/Mobile Documents/com~apple~CloudDocs/Personal")
        try file("passport.pdf", in: personal, created: minutes(10))
        let deck = try folder("Library/CloudStorage/Dropbox/Taxes/deck")
        try file("deck.pdf", in: deck, created: minutes(10))
        let project = try folder("Projects/site")
        let builds = try folder("Projects/site/builds/v2")
        try file("new-build.png", in: builds, created: minutes(10))
        let out = project.appendingPathComponent("out")
        try FileManager.default.createSymbolicLink(atPath: out.path, withDestinationPath: builds.path)

        let reasons = try notUnpacked([dropbox.path, taxes.path, icloud.path, personal.path, out.path], cwd: project)
        #expect(reasons == ["CloudStorage/Dropbox": "a cloud drive", "Dropbox/Taxes": "a folder directly in a cloud drive",
                            "Mobile Documents/com~apple~CloudDocs": "a cloud drive",
                            "com~apple~CloudDocs/Personal": "a folder directly in a cloud drive", "site/out": "a link"])
        try session("deck", in: project, asked: t0, replied: minutes(60), reply: "The [deck](\(deck.path)/) is in your Dropbox.")
        _ = try indexer.run()
        #expect(try members(of: deck.path) == 1)
    }

    /// The folder a conversation worked in is its project's, inside a repository as outside one,
    /// and so is a folder holding it; a bare repository is a repository's own folder.
    @Test func theFolderAConversationWorkedInOrABareRepositoryIsNotUnpacked() throws {
        let mono = try folder("work/mono")
        try FileManager.default.createDirectory(at: mono.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let web = mono.appendingPathComponent("packages/web")
        try file("src/App.tsx", in: web, created: minutes(-5000))
        let site = try folder("work/git/site.git")
        try file("HEAD", in: site, created: minutes(10), text: "ref: refs/heads/main")
        try file("config", in: site, created: minutes(10), text: "url = https://user:synthetic@example.com/site")
        try file("objects/ab/cdef", in: site, created: minutes(10))
        try file("refs/heads/main", in: site, created: minutes(10))
        let git = site.deletingLastPathComponent()

        let reasons = try notUnpacked([web.path, web.deletingLastPathComponent().path, site.path, git.path], cwd: web)
        #expect(reasons == ["packages/web": "the folder its conversation worked in",
                            "mono/packages": "a folder holding the one its conversation worked in",
                            "git/site.git": "a Git repository", "work/git": "a folder holding a Git repository"])
    }

    /// A folder gone, or one Gleaner can't read, isn't listed now and waits: the next run that can
    /// list it does, claiming only what the dates show, and until then each run says why.
    @Test func aFolderGoneOrUnreadableIsListedOnceItCanBe() throws {
        let project = try folder("Projects/later")
        let shut = project.appendingPathComponent("shut"), out = shut.appendingPathComponent("out")
        let locked = project.appendingPathComponent("locked"), gone = project.appendingPathComponent("gone")
        try file("a.png", in: out, created: minutes(10))
        try file("b.png", in: locked, created: minutes(10))
        try file("c.png", in: gone, created: minutes(10))
        let log = try session("later", in: project, asked: t0, replied: minutes(60), reply: "In [out](shut/out/), [locked](locked/) and [gone](gone/).")
        // Captured as folders; then one's parent can't be searched, one can't be listed, one is gone.
        _ = try indexer.ingest(try #require(try ClaudeCodeAdapter.parse(URL(fileURLWithPath: log))), isComplete: true, now: minutes(61))
        try FileManager.default.removeItem(at: gone)
        #expect(chmod(shut.path, 0) == 0 && chmod(locked.path, 0) == 0)
        defer { chmod(shut.path, 0o755); chmod(locked.path, 0o755) }
        var report = try indexer.run()
        #expect(try indexer.registry.pendingFolders().map(\.path).sorted() == [gone.path, locked.path, out.path])
        #expect(report.sources[.claudeCode]?.folderProblems.sorted() == ["\(locked.path): not listed yet, couldn’t be read",
                                                                          "\(out.path): not listed yet, couldn’t be read"])
        #expect(report.sources[.claudeCode]?.foldersNotUnpacked == ["\(gone.path): not listed yet, no longer there"])
        #expect(try artifact(out.path).latest.unpacking == nil)
        // Each run says so again until it can list them.
        #expect(try indexer.run().sources[.claudeCode]?.folderProblems.count == 2)

        #expect(chmod(shut.path, 0o755) == 0 && chmod(locked.path, 0o755) == 0)
        try file("c.png", in: gone, created: minutes(10))
        report = try indexer.run()
        #expect(try indexer.registry.pendingFolders().isEmpty)
        #expect(try members(of: out.path) == 1 && members(of: locked.path) == 1 && members(of: gone.path) == 1)
        #expect(report.sources[.claudeCode]?.folderProblems == [] && report.sources[.claudeCode]?.foldersNotUnpacked == [])
    }

    /// A reply that names a folder and the file in it in another spelling delivers the file once,
    /// as named; another reply's delivery of the folder numbers with it.
    @Test func aFileNamedInAnotherSpellingIsDeliveredOnceAsNamed() throws {
        let project = try folder("Projects/docs")
        let out = project.appendingPathComponent("out")
        try file("readme.md", in: out, created: minutes(10))
        try file("index.html", in: out, created: minutes(10))
        // On a volume that tells case apart, the two spellings are two files.
        guard FileManager.default.fileExists(atPath: out.path + "/README.md") else { return }
        try session("docs", in: project, asked: t0, replied: minutes(60),
                    reply: "Everything is in [out](out/); start with [the readme](out/README.md).",
                    more: [(minutes(70), minutes(80), "The [docs](out/) again.")])
        _ = try indexer.run()

        let artifacts = try indexer.registry.artifacts()
        #expect(names(artifacts.map(\.path)) == ["README.md", "index.html", "out"])
        let readme = try artifact(out.path + "/README.md")
        #expect(readme.deliveries.map { $0.member == nil } == [false, true] && readme.deliveries.map(\.number) == [2, 1])
    }

    /// A reply that names a folder and a later one naming a file in it, read in one run: the file's
    /// bytes, read for the second, complete the folder's listing as they would on two runs.
    @Test func aFileNamedLaterInTheSameRunCompletesItsFoldersListing() throws {
        let project = try folder("Projects/film")
        let cut = try file("out/cut.mp4", in: project, created: minutes(10))
        try session("film", in: project, asked: t0, replied: minutes(60), reply: "Everything is in [out](out/).",
                    more: [(minutes(60.5), minutes(61), "The [cut](out/cut.mp4).")])
        _ = try indexer.run(now: { self.minutes(62) })
        let artifact = try artifact(cut)
        #expect(artifact.deliveries.map { $0.member == nil } == [true, false])
        #expect(artifact.deliveries.allSatisfy { $0.capture?.provenance == .atDelivery } && artifact.deliveries[1].sha256 == artifact.deliveries[0].sha256)
    }

    /// The registry's artifact at one path is the one it reads with every other: what the window
    /// puts in place after a first read. A file handed over in a folder is in its folder's project.
    @Test func oneArtifactReadAloneIsTheOneReadWithTheRest() throws {
        let project = try folder("work/clips")
        let outside = try folder("work/renders")
        try file("a.mov", in: outside, created: minutes(10))
        try file("sub/b.mov", in: outside, created: minutes(10))
        try file("notes.md", in: project, created: minutes(10))
        try session("clips", in: project, asked: t0, replied: minutes(60), reply: "The [renders](\(outside.path)/) and [notes](notes.md).",
                    more: [(minutes(70), minutes(80), "Again: [renders](\(outside.path)/) and [a](\(outside.path)/a.mov).")])
        _ = try indexer.run()
        #expect(try indexer.completeCaptures(of: outside.path + "/sub/b.mov", now: minutes(81)))
        let all = try indexer.registry.artifacts()
        func described(_ a: Artifact) -> String {
            "\(a.path) \(a.projectFolder) \(a.inRepository) \(a.checkout?.folder ?? "") "
                + a.deliveries.map { "\($0.id) \($0.number) \($0.capture?.provenance.rawValue ?? "") \($0.sha256 ?? "") \($0.member?.folder ?? "")" }
                .joined(separator: ",")
        }
        for artifact in all {
            #expect(try indexer.registry.artifact(at: artifact.path).map(described) == described(artifact))
        }
        let folder = try #require(all.first { $0.path == outside.path })
        #expect(all.filter { $0.latest.member != nil }.allSatisfy { $0.projectFolder == folder.projectFolder })
        #expect(try indexer.registry.artifact(at: project.path + "/nothing.md") == nil)
    }

    /// A volume mounted again may give its files another device number; what was listed is
    /// matched by its inode, dates and size on the path, and is still read as listed.
    @Test func aListedFileIsReadAsListedWhateverItsDeviceNumberNow() throws {
        let project = try folder("Projects/disk")
        let clip = try file("out/clip.mov", in: project, created: minutes(10))
        try session("disk", in: project, asked: t0, replied: minutes(60), reply: "On the disk: [out](out/).")
        _ = try indexer.run()
        try indexer.registry.db.execute("UPDATE members SET device = device + 4")
        #expect(try indexer.completeCaptures(of: clip, now: minutes(61)))
        #expect(try artifact(clip).latest.capture?.provenance == .atDelivery)
    }

    // MARK: membership by time

    /// Read as the agent replies: what was there by then, unchanged, was handed over. What came
    /// after wasn't, nor what changed after: a file edited, or moved, linked or copied in keeping
    /// a creation date from before the reply, isn't shown to have been there, and is missed rather
    /// than claimed.
    @Test func membershipByTimeOnALiveRead() throws {
        indexer.clockTolerance = 0
        let project = try folder("Projects/film")
        let out = project.appendingPathComponent("out")
        let kept = try file("cut.mp4", in: out)
        let edited = try file("notes.md", in: out)
        let elsewhere = try folder("Archive")
        let moved = try file("moved.mov", in: elsewhere, created: Date().addingTimeInterval(-86_400))
        let linked = try file("linked.mov", in: elsewhere, created: Date().addingTimeInterval(-86_400))
        let copied = try file("copied.mov", in: elsewhere, created: Date().addingTimeInterval(-86_400))
        Thread.sleep(forTimeInterval: 0.05)
        let replied = Date()
        Thread.sleep(forTimeInterval: 0.05)
        try file("later.wav", in: out)
        try Data("edited after the reply".utf8).write(to: URL(fileURLWithPath: edited))
        let fm = FileManager.default
        try fm.moveItem(atPath: moved, toPath: out.path + "/moved.mov")
        try fm.linkItem(atPath: linked, toPath: out.path + "/linked.mov")
        try fm.copyItem(atPath: copied, toPath: out.path + "/copied.mov")
        try Self.date(out.path + "/copied.mov", created: replied.addingTimeInterval(-86_400), modified: replied.addingTimeInterval(-86_400))
        for name in ["moved.mov", "linked.mov", "copied.mov"] {
            #expect(try #require(fm.attributesOfItem(atPath: out.path + "/" + name)[.creationDate] as? Date) < replied)
        }
        try session("film", in: project, asked: replied.addingTimeInterval(-600), replied: replied, reply: "The [cut](out/).")
        _ = try indexer.run(now: { replied.addingTimeInterval(1) })

        #expect(names(try indexer.registry.artifacts().filter { $0.latest.member != nil }.map(\.path)) == ["cut.mp4"])
        #expect(try artifact(kept).latest.capture?.provenance == .listed)
        #expect(try artifact(out.path).latest.unpacking?.members == 1)
    }

    /// Read long after the reply: a file unchanged since is handed over, and read then, it was
    /// first seen after the delivery; one changed after the reply, whatever its dates say, isn't.
    @Test func membershipByTimeOnABackfill() throws {
        indexer.clockTolerance = 0
        let project = try folder("Projects/archive")
        let out = project.appendingPathComponent("out")
        let old = try file("old.pdf", in: out, created: Date().addingTimeInterval(-1800))
        Thread.sleep(forTimeInterval: 0.05)
        let replied = Date()
        Thread.sleep(forTimeInterval: 0.05)
        try file("copied.pdf", in: out, created: replied.addingTimeInterval(-7200), modified: replied.addingTimeInterval(-7000))
        try file("touched.pdf", in: out, created: replied.addingTimeInterval(-1800), modified: replied.addingTimeInterval(-60))
        try file("new.pdf", in: out)
        try session("archive", in: project, asked: replied.addingTimeInterval(-600), replied: replied, reply: "In [out](out/).")
        let later = replied.addingTimeInterval(3 * 3600)
        _ = try indexer.run(now: { later })

        #expect(names(try indexer.registry.artifacts().filter { $0.latest.member != nil }.map(\.path)) == ["old.pdf"])
        #expect(try indexer.completeCaptures(of: old, now: later))
        #expect(try artifact(old).latest.capture?.provenance == .firstSeenAfterDelivery)
    }

    @Test func aFolderDeliveredTwiceListsItsFilesAtEachDelivery() throws {
        let project = try folder("Projects/deck")
        let out = project.appendingPathComponent("out")
        let deck = try file("deck.pdf", in: out, created: minutes(10))
        // Created after the first reply's time: handed over by the second only.
        let appendix = try file("appendix.pdf", in: out, created: minutes(90))
        try session("deck", in: project, asked: t0, replied: minutes(60), reply: "The [deck](out/).",
                    more: [(minutes(80), minutes(120), "The [deck](out/), with its appendix.")])
        _ = try indexer.run()

        let first = try artifact(deck), second = try artifact(appendix)
        #expect(first.deliveries.map(\.number) == [2, 1] && first.deliveries.map(\.deliveredAt) == [minutes(120), minutes(60)])
        #expect(Set(first.deliveries.compactMap(\.member?.folderDelivery)).count == 2)
        #expect(second.deliveries.count == 1 && second.latest.deliveredAt == minutes(120))
        // One row per folder delivery and file.
        #expect(try indexer.registry.db.rows("SELECT COUNT(*) AS n FROM members").first?["n"] as? Int64 == 3)
    }

    @Test func aFileAlsoNamedItselfKeepsThoseDeliveriesNumberedWithItsFolders() throws {
        let project = try folder("Projects/film")
        let out = project.appendingPathComponent("out")
        let cut = try file("cut.mp4", in: out, created: minutes(10))
        try file("poster.png", in: out, created: minutes(10))
        let log = try session("film", in: project, asked: t0, replied: minutes(60), reply: "Everything is in [out](out/).")
        _ = try indexer.run()
        #expect(try artifact(cut).latest.capture?.provenance == .listed)

        // A later reply names the file itself: Gleaner reads it, and the listing it still matches
        // is completed with those bytes, at delivery, since they were read within the live window
        // and the file hasn't changed since the reply.
        try session("film", in: project, asked: t0, replied: minutes(60), reply: "Everything is in [out](out/).",
                    more: [(minutes(70), minutes(75), "The [cut](out/cut.mp4) again.")])
        _ = try indexer.run()
        let artifact = try artifact(cut)
        #expect(artifact.deliveries.map(\.number) == [2, 1] && artifact.deliveries.map { $0.member != nil } == [false, true])
        #expect(artifact.deliveries[1].sha256 == artifact.deliveries[0].sha256 && artifact.deliveries[1].sha256 != nil)
        #expect(artifact.deliveries[1].capture?.provenance == .atDelivery && artifact.deliveries[1].logPath == log)
    }

    // MARK: with layer 1

    /// A candidate whose folder a later reply names is handed over: it stops being a candidate, and
    /// its observation stays beside its delivery.
    @Test func aCandidateInAFolderALaterReplyNamesIsHandedOver() throws {
        let project = try folder("Projects/voice")
        let line = try file("out/line-1.wav", in: project, created: minutes(10))
        try session("voice", in: project, asked: t0, replied: minutes(30), reply: "Recorded the lines.",
                    more: [(minutes(40), minutes(60), "The lines are in [out](out/).")])
        try session("early", in: project, asked: t0, replied: minutes(30), reply: "Recorded the lines.")
        _ = try indexer.run()
        let organization = try organization()
        let work = try #require(organization.work(containing: line))
        #expect(organization.candidate(line) == nil && work.deliveries.first?.member != nil)
        #expect(organization.observations(of: work).count == 2)
    }

    // MARK: existing libraries, rereads and relaunches

    @Test func anExistingLibraryListsItsDeliveredFoldersOnTheNextRun() throws {
        let project = try folder("Projects/old")
        try file("out/a.png", in: project, created: minutes(10))
        try file("out/b.png", in: project, created: minutes(10))
        try session("old", in: project, asked: t0, replied: minutes(60), reply: "In [out](out/).")
        _ = try indexer.run()
        // A library from before folders were listed has neither table.
        try indexer.registry.db.execute("DROP TABLE listings; DROP TABLE members;")
        let reopened = Indexer(registry: try Registry(path: indexer.registry.path), store: indexer.store, sources: indexer.sources)
        reopened.home = indexer.home
        #expect(try reopened.registry.artifacts().count == 1)
        let report = try reopened.run()
        #expect(report.logsRead == 0)
        #expect(names(try reopened.registry.artifacts().map(\.path)) == ["a.png", "b.png", "out"])
        // Listed once: a later run lists nothing again.
        #expect(try reopened.registry.pendingFolders().isEmpty)
    }

    @Test func aRereadAndARelaunchFindTheSameDeliveriesAsListed() throws {
        let project = try folder("Projects/again")
        let a = try file("out/a.md", in: project, created: minutes(10))
        try file("out/sub/b.md", in: project, created: minutes(10))
        try session("again", in: project, asked: t0, replied: minutes(60), reply: "In [out](out/).")
        _ = try indexer.run()
        func snapshot(_ registry: Registry) throws -> [String] {
            try registry.artifacts().flatMap { a in
                a.deliveries.map { "\(a.path) \($0.id) \($0.number) \($0.capture?.provenance.rawValue ?? "") \($0.member?.folder ?? "")" }
            }.sorted()
        }
        let first = try snapshot(indexer.registry)

        // Changed after it was listed: the listing stands, never rewritten.
        try Data("edited".utf8).write(to: URL(fileURLWithPath: a))
        try indexer.registry.db.execute("PRAGMA user_version = 1")
        let reread = Indexer(registry: try Registry(path: indexer.registry.path), store: indexer.store, sources: indexer.sources)
        reread.home = indexer.home
        #expect(try reread.run().logsRead == 1)
        #expect(try snapshot(reread.registry) == first)
        #expect(try snapshot(try Registry(path: indexer.registry.path)) == first)
        // Changed since it was listed, it isn't the delivered file: reading it completes nothing.
        #expect(try !reread.completeCaptures(of: a, now: Date()))
    }

    // MARK: corrections

    @Test func correctionsApplyToAFilesWorkAsToAnyAndUndo() throws {
        let project = try folder("Projects/episode")
        let cut = try file("out/cut.mp4", in: project, created: minutes(10))
        let poster = try file("out/poster.png", in: project, created: minutes(10))
        let draft = try file("draft.mp4", in: project, created: minutes(5))
        try session("episode", in: project, asked: t0, replied: minutes(60), reply: "The [draft](draft.mp4) and [out](out/).")
        _ = try indexer.run()
        let registry = indexer.registry

        let mine = try registry.addProject(named: "Episode one", at: minutes(100), moving: [poster])
        try registry.correct(.sameWork, subject: draft, target: cut, at: minutes(101))
        var organization = try organization(corrections: try registry.corrections(), projects: try registry.userProjects())
        #expect(organization.work(containing: poster)?.project == mine.key)
        let joined = try #require(organization.work(containing: cut))
        #expect(joined.files.map(\.path) == [draft, cut] && joined.deliveries.count == 2)

        try registry.undoAllCorrections()
        organization = try self.organization(corrections: try registry.corrections(), projects: try registry.userProjects())
        #expect(organization.work(containing: poster)?.project == project.path)
        #expect(organization.work(containing: cut)?.files.count == 1)
    }

    // MARK: reading

    @Test func listingReadsNoBytes() throws {
        let project = try folder("Projects/media")
        let out = project.appendingPathComponent("out")
        let clips = try (0..<4).map { try file("clip-\($0).mov", in: out, text: "frames \($0)") }
        let locked = try file("locked.wav", in: out)
        let large = out.appendingPathComponent("render.mp4")
        #expect(FileManager.default.createFile(atPath: large.path, contents: nil))
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 742 << 20)
        try handle.close()
        #expect(mkfifo(out.appendingPathComponent("pipe").path, 0o600) == 0)
        let replied = minutes(60)
        try session("media", in: project, asked: t0, replied: replied, reply: "Rendered: [out](out/).")

        // A read would move each file's access time, set before its modification time, to now.
        let accessed = minutes(-60)
        for path in clips + [large.path] {
            var times = [timespec(tv_sec: Int(accessed.timeIntervalSince1970), tv_nsec: 0), timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT))]
            #expect(utimensat(AT_FDCWD, path, &times, 0) == 0)
        }
        #expect(chmod(locked, 0) == 0)
        defer { chmod(locked, 0o644) }
        _ = try indexer.run()

        let listed = try indexer.registry.artifacts().filter { $0.latest.member != nil }
        // The pipe isn't a regular file: not one of its files, and never opened.
        #expect(names(listed.map(\.path)) == ["clip-0.mov", "clip-1.mov", "clip-2.mov", "clip-3.mov", "locked.wav", "render.mp4"])
        #expect(listed.first { $0.path == large.path }?.latest.capture?.size == 742 << 20)
        for path in clips + [large.path] {
            var info = Darwin.stat()
            #expect(lstat(path, &info) == 0)
            #expect(info.st_atimespec.tv_sec == Int(accessed.timeIntervalSince1970), "\(path) was read")
        }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: indexer.store.objects.path)) ?? []).isEmpty)

        // The person's first read completes it: at delivery, read within the live window of a reply
        // that came after the file's last write. One Gleaner can't read stays listed.
        #expect(try indexer.completeCaptures(of: clips[0], now: minutes(61)))
        let clip = try artifact(clips[0]).latest
        #expect(clip.capture?.provenance == .atDelivery && clip.sha256 != nil && clip.capture?.savedAt != nil)
        #expect(try !indexer.completeCaptures(of: locked, now: minutes(61)))
        #expect(try artifact(locked).latest.capture?.provenance == .listed)
        // Read later than that, it was first seen after the delivery.
        #expect(try indexer.completeCaptures(of: clips[1], now: minutes(80)))
        #expect(try artifact(clips[1]).latest.capture?.provenance == .firstSeenAfterDelivery)
    }

    @Test func aListingStopsAtTheBoundAndSaysSoOnEveryRun() throws {
        let project = try folder("Projects/crowd")
        let out = project.appendingPathComponent("out")
        for n in 0..<100 { try file(String(format: "f%03d.txt", n), in: out, created: minutes(10)) }
        try session("crowd", in: project, asked: t0, replied: minutes(60), reply: "In [out](out/).")
        indexer.walkLimit = 40
        let report = try indexer.run()
        let problems = try #require(report.sources[.claudeCode]?.folderProblems)
        #expect(problems == ["\(out.path): stopped after 40 entries"])
        #expect(report.sources[.claudeCode]?.hasProblems == true && report.sources[.claudeCode]?.isIncomplete == false)
        #expect(try members(of: out.path) == 40)
        #expect(try artifact(out.path).latest.unpacking?.problems == problems)
        #expect(try indexer.run().sources[.claudeCode]?.folderProblems == problems)
    }

    // MARK: the synthetic home

    /// `scripts/acceptance-home.py <home> bundle`, read as the app reads it with `-GleanerHome`.
    @Test func theSyntheticHomesBundlePhase() throws {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/acceptance-home.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", script.path, home.path, "bundle"]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let indexer = Indexer(
            registry: try Registry(path: root.appendingPathComponent("home.sqlite").path),
            store: ContentStore(objects: root.appendingPathComponent("home-objects"), staging: root.appendingPathComponent("home-staging")),
            sources: LogSources(claudeProjects: home.appendingPathComponent(".claude/projects"), codexHome: home.appendingPathComponent(".codex")))
        indexer.home = home.path
        let report = try indexer.run()

        let site = home.path + "/work/launch/site", app = home.path + "/work/launch/app"
        let artifacts = try indexer.registry.artifacts()
        let organization = Organization(artifacts: artifacts, observed: Candidate.files(try indexer.registry.observations()))
        // The site's files, handed over with it; never its hidden settings.
        let siteFiles = artifacts.filter { $0.latest.member?.folder == site }
        #expect(names(siteFiles.map(\.path)) == ["app.js", "hero.png", "index.html", "style.css"])
        #expect(artifacts.first { $0.path == site }?.deliveries.count == 2)
        // Written after the first reply, whatever their dates say: only the second hands them over.
        #expect(artifacts.first { $0.path == site + "/index.html" }?.deliveries.count == 1)
        #expect(artifacts.first { $0.path == site + "/assets/hero.png" }?.deliveries.count == 1)
        #expect(!artifacts.contains { $0.name == ".env" })
        // The project folder handed over stands alone, and says why.
        #expect(artifacts.first { $0.path == app }?.latest.unpacking?.notUnpacked == "a Git checkout’s folder")
        #expect(report.sources[.claudeCode]?.foldersNotUnpacked == ["\(app): not unpacked, a Git checkout’s folder"])
        #expect(organization.projects.contains { $0.name == "launch" })
    }
}
