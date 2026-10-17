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

    @Test func directoryHasNoHash() {
        let state = Locator.observe(root + "/out")
        #expect(state.kind == .directory)
        #expect(state.sha256 == nil)
    }
}
