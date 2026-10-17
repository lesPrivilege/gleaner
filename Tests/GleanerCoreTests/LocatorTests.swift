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
        let name = (root as NSString).lastPathComponent
        #expect(Projects.project(path: worktree + "/out/report.md", cwd: worktree) == name)
        #expect(Projects.project(path: root + "/out/committed.md", cwd: "/elsewhere") == name)

        // A deleted worktree resolves through the folder that held it.
        try FileManager.default.removeItem(atPath: worktree)
        #expect(Projects.project(path: worktree + "/out/report.md", cwd: worktree) == name)
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
