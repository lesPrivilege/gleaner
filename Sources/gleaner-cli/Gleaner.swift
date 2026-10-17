import ArgumentParser
import Foundation
import GleanerCore

/// The `gleaner` command: the catalog's answers as JSON, for a local shell agent
/// (docs/design/query-core.md "Commands"). It reads the library the app keeps and never indexes,
/// never writes the library, and never writes a project folder; `handoff` stages its copy in
/// Gleaner's own caches.
@main
struct Gleaner: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gleaner",
        abstract: "Find what coding agents delivered, select its exact version, and hand those bytes on.",
        discussion: """
            Each command writes one JSON object to stdout. Exit codes: 0 success; 1 not found, or no \
            bytes for that version; 2 usage; 3 no library, or the wrong version (open Gleaner).
            """,
        subcommands: [Find.self, Show.self, Read.self, Resolve.self, Handoff.self, Verify.self])

    /// Runs the command as `ParsableCommand.main` does, with the contract's exit codes: a catalog
    /// failure exits with its own, and a usage error with 2, where ArgumentParser would give 64.
    static func main() {
        do {
            var command = try parseAsRoot()
            try command.run()
        } catch let failure as Catalog.Failure {
            fail("Error: \(failure)", status: failure.exitCode)
        } catch let error where exitCode(for: error) == .validationFailure {
            fail(fullMessage(for: error), status: 2)
        } catch {
            exit(withError: error)
        }
    }

    private static func fail(_ message: String, status: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        Foundation.exit(status)
    }
}

extension Gleaner {
    struct Find: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Find the files whose words match every term, newest first, each by the delivery that matched.")

        @Argument(help: "Words to find together in one delivery's request, reply or session, or in the file's name or project.")
        var terms: [String]
        @Option(help: "Only this project, by its name or folder.")
        var project: String?
        @Option(help: "Only this kind of file.")
        var kind: Artifact.Kind?
        @Option(help: "The most files to list.")
        var limit = 20
        @OptionGroup var library: Library

        func run() throws {
            try write(library.catalog().find(terms, project: project, kind: kind, limit: limit))
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show a delivery with every delivery of its file, the file on disk now, what handing it on would give, and the request and reply that made it.")

        @Argument(help: "The delivery's id.")
        var delivery: String
        @OptionGroup var library: Library

        func run() throws {
            try write(library.catalog().show(delivery))
        }
    }

    struct Read: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Read the text of a delivery's exact bytes: its saved copy, or the original only while it still holds them.")

        @Argument(help: "The delivery's id.")
        var delivery: String
        @Option(help: ArgumentHelp("Lines A through B, counted from 1.", valueName: "A:B"))
        var lines: Bounds?
        @Option(help: ArgumentHelp("Bytes from A up to, not including, B, counted from 0.", valueName: "A:B"))
        var bytes: Bounds?
        @Option(help: "The most bytes to give.")
        var max = 16 << 10
        @OptionGroup var library: Library

        func validate() throws {
            if lines != nil, bytes != nil { throw ValidationError("Give --lines or --bytes, not both.") }
        }

        func run() throws {
            let span = lines.map { Catalog.Span.lines($0.start, $0.end) } ?? bytes.map { .bytes($0.start, $0.end) }
            try write(library.catalog().read(delivery, span: span, max: max))
        }
    }

    struct Resolve: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Give a delivery's reference, as the app's Copy Reference copies it.")

        @Argument(help: "The delivery's id.")
        var delivery: String
        @OptionGroup var library: Library

        func run() throws {
            try write(library.catalog().resolve(delivery))
        }
    }

    struct Handoff: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stage a verified, read-only copy of a delivery's exact bytes in Gleaner's caches, and give its path.")

        @Argument(help: "The delivery's id.")
        var delivery: String
        @OptionGroup var library: Library

        func run() throws {
            try write(library.catalog().handoff(delivery))
        }
    }

    struct Verify: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Hash the original and Gleaner's saved copy again, and say which still hold a reference's bytes.",
            discussion: "Exits 1 when neither does.")

        @Argument(help: "A delivery's id, or a file holding a reference: resolve's answer, or its reference alone.")
        var reference: String
        @OptionGroup var library: Library

        func run() throws {
            let catalog = try library.catalog()
            let verified: Catalog.Verified
            if FileManager.default.fileExists(atPath: reference) {
                guard let kept = try? Catalog.decoder.decode(Catalog.Kept.self, from: Data(contentsOf: URL(fileURLWithPath: reference))) else {
                    throw ValidationError("\(reference) holds no reference as resolve writes it.")
                }
                verified = try catalog.verify(kept)
            } else {
                verified = try catalog.verify(reference)
            }
            try write(verified)
            // Neither: there are no bytes for that version now.
            if !verified.original, !verified.savedCopy { throw ExitCode.failure }
        }
    }
}

/// Where the library is: the app's folders in the home folder, or in the one `--home` names.
struct Library: ParsableArguments {
    @Option(help: ArgumentHelp("A folder to take for the home folder, as the app's -GleanerHome does.", valueName: "folder"))
    var home: String?

    func catalog() throws -> Catalog {
        try Catalog(home: home.map { URL(fileURLWithPath: $0, isDirectory: true) })
    }
}

/// `A:B`, as `read --lines` and `--bytes` take a range.
struct Bounds: ExpressibleByArgument {
    var start: Int
    var end: Int

    init?(argument: String) {
        let parts = argument.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]) else { return nil }
        (self.start, self.end) = (start, end)
    }
}

extension Artifact.Kind: ExpressibleByArgument {}

/// Writes an answer to stdout as one JSON object and a newline.
func write(_ answer: some Encodable) throws {
    FileHandle.standardOutput.write(try Catalog.encoder.encode(answer) + Data("\n".utf8))
}
