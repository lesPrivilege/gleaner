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

    @Test func specialFilesAreNeverOpened() {
        let fifo = root + "/out/pipe.mp4"
        #expect(mkfifo(fifo, 0o600) == 0)
        let state = Locator.observe(fifo)
        #expect(state.kind == .special)
        #expect(state.sha256 == nil)
    }

    @Test func observingDoesNotWriteTheIndex() throws {
        let index = root + "/.git/index"
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: root + "/out/committed.md")
        let before = try Data(contentsOf: URL(fileURLWithPath: index))
        _ = Locator.observe(root + "/out/committed.md")
        #expect(try Data(contentsOf: URL(fileURLWithPath: index)) == before)
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
