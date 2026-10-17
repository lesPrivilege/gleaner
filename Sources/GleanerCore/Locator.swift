import CryptoKit
import Foundation

public enum GitState: String, Sendable {
    case committed
    case modified
    case untracked
    case ignored
    case notInRepo = "not_in_repo"
    /// The file is gone from disk but HEAD still has it.
    case recoverableFromHead = "recoverable_from_head"
    /// The file is gone and not in HEAD, but some commit on some ref has it.
    case recoverableFromHistory = "recoverable_from_history"
    /// The file is gone and no commit has it.
    case lost
}

public struct LocatorState: Sendable {
    public enum Kind: String, Sendable {
        /// `special` is anything that is neither a regular file nor a directory (FIFO, socket,
        /// device). It is never opened: reading a FIFO blocks forever.
        case file, directory, special, missing
    }

    public var kind: Kind
    public var size: Int64?
    public var modifiedAt: Date?
    public var sha256: String?
    public var repositoryRoot: String?
    public var git: GitState
}

/// Observes a path in place. Read-only: it never writes to the file or its repository.
public enum Locator {
    public static func observe(_ path: String) -> LocatorState {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDirectory)
        let root = repositoryRoot(for: path)

        guard exists else {
            var git = GitState.notInRepo
            if let root {
                let rel = relative(path, to: root)
                if run(["-C", root, "cat-file", "-e", "HEAD:\(rel)"]).status == 0 {
                    git = .recoverableFromHead
                } else if !run(["-C", root, "log", "--all", "-1", "--format=%H", "--", rel]).output.isEmpty {
                    git = .recoverableFromHistory
                } else {
                    git = .lost
                }
            }
            return LocatorState(kind: .missing, repositoryRoot: root, git: git)
        }

        let attributes = try? fm.attributesOfItem(atPath: (path as NSString).resolvingSymlinksInPath)
        let kind: LocatorState.Kind = switch attributes?[.type] as? FileAttributeType {
        case .typeRegular: .file
        case .typeDirectory: .directory
        default: .special
        }
        return LocatorState(
            kind: kind,
            size: kind == .file ? (attributes?[.size] as? NSNumber)?.int64Value : nil,
            modifiedAt: attributes?[.modificationDate] as? Date,
            sha256: kind == .file ? sha256(path) : nil,
            repositoryRoot: root,
            git: root.map { gitState(path, root: $0) } ?? .notInRepo)
    }

    public static func sha256(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The nearest ancestor holding `.git` (a directory, or a file for linked worktrees).
    static func repositoryRoot(for path: String) -> String? {
        var dir = (path as NSString).deletingLastPathComponent
        while dir != "/" && !dir.isEmpty {
            if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(".git")) {
                return dir
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    static func gitState(_ path: String, root: String) -> GitState {
        let result = run(["-C", root, "status", "--porcelain=v1", "--ignored", "--", relative(path, to: root)])
        guard result.status == 0 else { return .notInRepo }
        let lines = result.output.split(separator: "\n")
        if lines.isEmpty { return .committed }
        if lines.allSatisfy({ $0.hasPrefix("!!") }) { return .ignored }
        if lines.allSatisfy({ $0.hasPrefix("??") }) { return .untracked }
        return .modified
    }

    static func relative(_ path: String, to root: String) -> String {
        path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }

    static func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // Without this, `git status` refreshes and rewrites the index: not read-only.
        process.arguments = ["--no-optional-locks"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
