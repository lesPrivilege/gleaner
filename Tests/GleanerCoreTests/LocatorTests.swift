import Foundation
import Testing
@testable import GleanerCore

@Suite struct LocatorTests {
    let root: String

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gleaner-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root + "/out", withIntermediateDirectories: true)
        try "v1".write(toFile: root + "/out/committed.md", atomically: true, encoding: .utf8)
        try "v1".write(toFile: root + "/out/gone.md", atomically: true, encoding: .utf8)
        try "v1".write(toFile: root + "/out/moved.md", atomically: true, encoding: .utf8)
        try "*.log\n".write(toFile: root + "/.gitignore", atomically: true, encoding: .utf8)
        let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm"]
        for args in [["init", "-q"], ["add", "."], commit + ["init"], ["rm", "-q", "out/moved.md"], commit + ["rm"]] {
            #expect(Locator.run(["-C", root] + args).status == 0)
        }
        try FileManager.default.removeItem(atPath: root + "/out/gone.md")
        try "new".write(toFile: root + "/out/untracked.md", atomically: true, encoding: .utf8)
        try "log".write(toFile: root + "/out/build.log", atomically: true, encoding: .utf8)
    }

    @Test func worktreesResolveToTheirRepository() throws {
        let worktree = root + "/.claude/worktrees/ch3"
        #expect(Locator.run(["-C", root, "worktree", "add", "-q", worktree]).status == 0)
        #expect(Projects.repository(path: worktree + "/out/report.md", cwd: worktree) == root)
        #expect(Projects.repository(path: root + "/out/committed.md", cwd: "/elsewhere") == root)

        // A deleted worktree resolves through the folder that held it.
        try FileManager.default.removeItem(atPath: worktree)
        #expect(Projects.repository(path: worktree + "/out/report.md", cwd: worktree) == root)
    }

    @Test func committedFileIsHashed() {
        let state = Locator.observe(root + "/out/committed.md")
        #expect(state.kind == .file)
        #expect(state.size == 2)
        #expect(state.git == .committed)
        #expect(state.repositoryRoot == root)
        // sha256("v1")
        #expect(state.sha256 == "3bfc269594ef649228e9a74bab00f042efc91d5acc6fbee31a382e80d42388fe")
    }

    @Test func modifiedUntrackedIgnored() throws {
        try "v2".write(toFile: root + "/out/committed.md", atomically: true, encoding: .utf8)
        #expect(Locator.observe(root + "/out/committed.md").git == .modified)
        #expect(Locator.observe(root + "/out/untracked.md").git == .untracked)
        #expect(Locator.observe(root + "/out/build.log").git == .ignored)
    }

    @Test func missingFiles() {
        #expect(Locator.observe(root + "/out/gone.md").git == .recoverableFromHead)
        #expect(Locator.observe(root + "/out/moved.md").git == .recoverableFromHistory)
        #expect(Locator.observe(root + "/out/never.md").git == .lost)
        #expect(Locator.observe(root + "/out/never.md").kind == .missing)
    }

    /// Runs `/bin/sh` with `arguments`, as the person would.
    func sh(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func theRestoreCommandNamesACommitThatHasTheFile() throws {
        let fm = FileManager.default
        let repo = root + "/Bob's Project"
        try fm.createDirectory(atPath: repo + "/out", withIntermediateDirectories: true)
        try "notes".write(toFile: repo + "/notes [1].md", atomically: true, encoding: .utf8)
        try "other".write(toFile: repo + "/notes 1.md", atomically: true, encoding: .utf8)
        let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm"]
        for args in [["init", "-q"], ["add", "."], commit + ["init"], ["checkout", "-q", "-b", "side"]] {
            #expect(Locator.run(["-C", repo] + args).status == 0)
        }
        try "from side".write(toFile: repo + "/out/report.md", atomically: true, encoding: .utf8)
        for args in [["add", "."], commit + ["report"], ["checkout", "-q", "-"]] {
            #expect(Locator.run(["-C", repo] + args).status == 0)
        }

        // Only another branch has the file; the commit before the one that added it does not.
        let report = Locator.observe(repo + "/out/report.md")
        #expect(report.git == .recoverableFromHistory)
        let command = try #require(report.restoreCommand)
        #expect(try sh(["-n", "-c", command]) == 0)
        #expect(try sh(["-c", command]) == 0)
        #expect(try String(contentsOfFile: repo + "/out/report.md", encoding: .utf8) == "from side")

        try fm.removeItem(atPath: repo + "/notes [1].md")
        try "edited".write(toFile: repo + "/notes 1.md", atomically: true, encoding: .utf8)
        let notes = Locator.observe(repo + "/notes [1].md")
        #expect(notes.git == .recoverableFromHead)
        #expect(try sh(["-c", try #require(notes.restoreCommand)]) == 0)
        #expect(try String(contentsOfFile: repo + "/notes [1].md", encoding: .utf8) == "notes")
        // A file name is not a pattern: the neighbour it would match keeps its edits.
        #expect(try String(contentsOfFile: repo + "/notes 1.md", encoding: .utf8) == "edited")

        #expect(Locator.observe(repo + "/out/never.md").restoreCommand == nil)
    }

    /// `out/report.md` committed on branch ch3 in a worktree, and the checkout found while the
    /// worktree is there, as the indexer records it at delivery.
    func reportCommittedInAWorktree() throws -> (worktree: String, report: String, checkout: Checkout) {
        let worktree = root + "/.claude/worktrees/ch3", report = worktree + "/out/report.md"
        #expect(Locator.run(["-C", root, "worktree", "add", "-q", "-b", "ch3", worktree]).status == 0)
        try "from ch3".write(toFile: report, atomically: true, encoding: .utf8)
        let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm"]
        for args in [["add", "out/report.md"], commit + ["report"]] {
            #expect(Locator.run(["-C", worktree] + args).status == 0)
        }
        let checkout = try #require(Projects.checkout(path: report))
        #expect(checkout == Checkout(folder: worktree, repository: root))
        return (worktree, report, checkout)
    }

    @Test func aRemovedWorktreesCommittedFileIsRestoredFromItsBranch() throws {
        let (worktree, report, checkout) = try reportCommittedInAWorktree()
        #expect(Locator.run(["-C", root, "worktree", "remove", worktree]).status == 0)

        let state = Locator.observe(report, checkout: checkout)
        #expect(state.git == .recoverableFromHistory)
        #expect(Locator.observe(worktree + "/out/never.md", checkout: checkout).git == .lost)
        let command = try #require(state.restoreCommand)
        #expect(try sh(["-c", command]) == 0)
        #expect(try String(contentsOfFile: report, encoding: .utf8) == "from ch3")
        // Back on disk, it is checked in the checkout holding it now, whatever was recorded.
        try "edited".write(toFile: report, atomically: true, encoding: .utf8)
        #expect(Locator.observe(report, checkout: Checkout(folder: root, repository: root)).git == .modified)
    }

    @Test func aWorktreeFolderDeletedWithoutGitIsRestoredFromItsBranch() throws {
        let (worktree, report, checkout) = try reportCommittedInAWorktree()
        // Deleted as a folder, not with `git worktree remove`: git still has the worktree registered.
        try FileManager.default.removeItem(atPath: worktree)

        let state = Locator.observe(report, checkout: checkout)
        #expect(state.git == .recoverableFromHistory)
        #expect(try sh(["-c", try #require(state.restoreCommand)]) == 0)
        #expect(try String(contentsOfFile: report, encoding: .utf8) == "from ch3")
    }

    @Test func specialFilesAreNeverOpened() {
        let fifo = root + "/out/pipe.mp4"
        #expect(mkfifo(fifo, 0o600) == 0)
        let state = Locator.observe(fifo)
        #expect(state.kind == .special)
        #expect(state.sha256 == nil)
    }

    @Test func aFileThatCannotBeReadIsUnreadableNeverMissing() throws {
        let fm = FileManager.default
        let denied = root + "/out/denied.md"
        try "v1".write(toFile: denied, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: denied)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: denied) }
        let file = Locator.observe(denied)
        #expect(file.kind == .unreadable)
        #expect(file.sha256 == nil)

        // A folder that can't be searched hides its files: Gleaner can't say they are gone.
        let locked = root + "/locked"
        try fm.createDirectory(atPath: locked, withIntermediateDirectories: true)
        try "v1".write(toFile: locked + "/inside.md", atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked) }
        #expect(Locator.stat(locked + "/inside.md").kind == .unreadable)
        #expect(Locator.observe(locked + "/inside.md").kind == .unreadable)
    }

    @Test func aLinkToNothingIsMissing() throws {
        try FileManager.default.createSymbolicLink(atPath: root + "/out/link.md", withDestinationPath: root + "/out/nothing.md")
        #expect(Locator.stat(root + "/out/link.md").kind == .missing)
        #expect(Locator.observe(root + "/out/link.md").kind == .missing)
    }

    @Test func observingDoesNotWriteTheIndex() throws {
        let index = root + "/.git/index"
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: root + "/out/committed.md")
        let before = try Data(contentsOf: URL(fileURLWithPath: index))
        _ = Locator.observe(root + "/out/committed.md")
        #expect(try Data(contentsOf: URL(fileURLWithPath: index)) == before)
    }

    @Test func observingRunsNoCommandTheRepositoryConfigures() throws {
        let hook = root + "/hook.sh", ran = root + "/hook-ran"
        try "#!/bin/sh\ntouch \(Locator.quoted(ran))\n".write(toFile: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook)
        // An fsmonitor hook, and a signature checker `git log` runs for each signed commit it shows.
        for (key, value) in [("core.fsmonitor", hook), ("log.showSignature", "true"), ("gpg.program", hook)] {
            #expect(Locator.run(["-C", root, "config", key, value]).status == 0)
        }
        // A signed commit on another branch brings moved.md back.
        func rev(_ name: String) -> String {
            Locator.run(["-C", root, "rev-parse", name]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let object = root + "/.git/signed-commit"
        try ["tree \(rev("HEAD~1^{tree}"))", "parent \(rev("HEAD"))", "author t <t@t> 1 +0000", "committer t <t@t> 1 +0000",
             "gpgsig -----BEGIN PGP SIGNATURE-----", " ", " abc", " -----END PGP SIGNATURE-----", "", "signed", ""]
            .joined(separator: "\n").write(toFile: object, atomically: true, encoding: .utf8)
        let signed = Locator.run(["-C", root, "hash-object", "-t", "commit", "-w", object]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(Locator.run(["-C", root, "update-ref", "refs/heads/signed", signed]).status == 0)

        for file in ["committed.md", "untracked.md", "gone.md", "moved.md"] { _ = Locator.observe(root + "/out/" + file) }
        #expect(!FileManager.default.fileExists(atPath: ran), "git ran a command the repository configures")
    }

    @Test func observingAPartialCloneNeverFetchesWhatItLacks() throws {
        let origin = root + "/partial/origin", clone = root + "/partial/clone", ran = root + "/partial/fetched"
        try FileManager.default.createDirectory(atPath: origin + "/out", withIntermediateDirectories: true)
        try "r1".write(toFile: origin + "/out/report.md", atomically: true, encoding: .utf8)
        let commit = ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm"]
        for args in [["init", "-q"], ["add", "."], commit + ["report"], ["config", "uploadpack.allowFilter", "true"]] {
            #expect(Locator.run(["-C", origin] + args).status == 0)
        }
        // A clone without file contents: each is fetched from the remote when first read.
        #expect(Locator.run(["clone", "-q", "--filter=blob:none", "--no-checkout", "file://" + origin, clone]).status == 0)
        let fetch = root + "/partial/upload-pack.sh"
        try "#!/bin/sh\ntouch \(Locator.quoted(ran))\nexec git-upload-pack \"$@\"\n".write(toFile: fetch, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fetch)
        #expect(Locator.run(["-C", clone, "config", "remote.origin.uploadpack", fetch]).status == 0)

        let state = Locator.observe(clone + "/out/report.md")
        #expect(!FileManager.default.fileExists(atPath: ran), "git fetched from the remote")
        #expect(state.git == .recoverableFromHead)
        #expect(state.restoreCommand != nil)
    }

    @Test func directoryHasNoHash() {
        let state = Locator.observe(root + "/out")
        #expect(state.kind == .directory)
        #expect(state.sha256 == nil)
    }

    @Test func aReadErrorIsNoHashNotTheHashOfWhatWasRead() {
        // An unconnected socket opens and then fails to read: that is not an empty file.
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        defer { close(socket) }
        #expect(Locator.sha256("/dev/fd/\(socket)") == nil)
    }
}
