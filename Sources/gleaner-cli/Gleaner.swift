import ArgumentParser
import Foundation
import GleanerCore

/// The `gleaner` command: the catalog's answers as JSON, for a local shell agent
/// (docs/design/query-core.md "Commands"), and `gleaner mcp`, the same answers as MCP tools
/// (`Serve`). It reads the library the app keeps and never indexes, never writes the library, and
/// never writes a project folder; `handoff` stages its copy in Gleaner's own caches.
@main
struct Gleaner: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gleaner",
        abstract: "Find what coding agents delivered, select its exact version, and hand those bytes on.",
        discussion: """
            Each command writes one JSON object to stdout, with the index it is evidence of. So does \
            each failure: {"error": {"kind", "message"}}, with the index when a library was open, and \
            the message on stderr too. Exit codes: 0 success; 1 not found, no bytes for that version, \
            or another failure; 2 usage; 3 no library, or the wrong version (open Gleaner).
            """,
        subcommands: [Find.self, Show.self, Read.self, Resolve.self, Handoff.self, Verify.self, Serve.self])

    /// Runs the command as `AsyncParsableCommand.main` does, with the contract's exit codes: a
    /// failure exits with its own, and a usage error with 2, where ArgumentParser would give 64. A
    /// refusal's answer is written by the command refused (`write(_:)`); a usage error is refused
    /// before any library is open, so it is written here, without an index.
    static func main() async {
        do {
            var command = try parseAsRoot()
            if var serving = command as? AsyncParsableCommand {
                try await serving.run()
            } else {
                try command.run()
            }
        } catch let refusal as Refusal {
            fail("Error: \(refusal.failure)", status: refusal.failure.exitCode)
        } catch let error where exitCode(for: error) == .validationFailure {
            // Written as any refusal is, but said on stderr in ArgumentParser's words, with the usage.
            try? write(Answer(refusing: Catalog.Failure.usage(message(for: error)), index: nil))
            fail(fullMessage(for: error), status: 2)
        } catch {
            // Help, and the like: not a failure.
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
        /// The most files listed unless asked, here and by `gleaner_find`.
        static let limit = 20

        @Argument(help: "Words to find together in one delivery's request, reply or session, or in the file's name or project.")
        var terms: [String]
        @Option(help: "Only this project, by its name or folder.")
        var project: String?
        @Option(help: "Only this kind of file.")
        var kind: Artifact.Kind?
        @Option(help: "The most files to list.")
        var limit = Find.limit
        @OptionGroup var library: Library

        func run() throws {
            try write(library.answer { try $0.find(terms, project: project, kind: kind, limit: limit) })
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show a delivery with every delivery of its file, the file on disk now, what handing it on would give, and the request and reply that made it.")

        @Argument(help: "The delivery's id.")
        var delivery: String
        @OptionGroup var library: Library

        func run() throws {
            try write(library.answer { try $0.show(delivery) })
        }
    }

    struct Read: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Read the text of a delivery's exact bytes: its saved copy, or the original only while it still holds them.")
        /// The most bytes given unless asked, here and by `gleaner_read`.
        static let max = 16 << 10

        @Argument(help: "The delivery's id.")
        var delivery: String
        @Option(help: ArgumentHelp("Lines A through B, counted from 1.", valueName: "A:B"))
        var lines: Bounds?
        @Option(help: ArgumentHelp("Bytes from A up to, not including, B, counted from 0.", valueName: "A:B"))
        var bytes: Bounds?
        @Option(help: "The most bytes to give.")
        var max = Read.max
        @OptionGroup var library: Library

        func validate() throws {
            if lines != nil, bytes != nil { throw ValidationError("Give --lines or --bytes, not both.") }
        }

        func run() throws {
            try write(library.answer { try $0.read(delivery, span: Bounds.span(lines: lines, bytes: bytes), max: max) })
        }
    }

    struct Resolve: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Give a delivery's reference, as the app's Copy Reference copies it.")

        @Argument(help: "The delivery's id.")
        var delivery: String
        @OptionGroup var library: Library

        func run() throws {
            try write(library.answer { try $0.resolve(delivery) })
        }
    }

    struct Handoff: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stage a verified, read-only copy of a delivery's exact bytes in Gleaner's caches, and give its path.")

        @Argument(help: "The delivery's id.")
        var delivery: String
        @OptionGroup var library: Library

        func run() throws {
            try write(library.answer { try $0.handoff(delivery) })
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
            let kept = FileManager.default.fileExists(atPath: reference) ? try keptReference() : nil
            try write(library.answer { catalog in try kept.map(catalog.verify) ?? catalog.verify(reference) })
        }

        /// The reference the file `reference` holds.
        private func keptReference() throws -> Catalog.Kept {
            guard let kept = try? Catalog.decoder.decode(Catalog.Kept.self, from: Data(contentsOf: URL(fileURLWithPath: reference))) else {
                throw ValidationError("\(reference) holds no reference as resolve writes it.")
            }
            return kept
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

    /// The catalog's answer, or why there is none, beside the index that is evidence of once the
    /// library is open. Each call opens the library afresh.
    func answer(_ body: (Catalog) throws -> some Encodable) -> Answer {
        let catalog: Catalog
        do {
            catalog = try self.catalog()
        } catch {
            return Answer(refusing: error, index: nil)
        }
        do {
            let answer = try body(catalog)
            // verify answers in full either way. When neither copy holds the bytes, there are none
            // for that version now, and the answer says why.
            return Answer(answer, failure: (answer as? Catalog.Verified)?.error)
        } catch {
            return Answer(refusing: error, index: try? catalog.registry.index())
        }
    }
}

/// A call's answer, as the command writes it and its tool returns it: one JSON object, and the
/// failure it reports, if any, which the command exits with and the tool marks as an error.
struct Answer {
    var object: any Encodable
    var failure: Catalog.Failure?

    init(_ object: any Encodable, failure: Catalog.Failure? = nil) {
        self.object = object
        self.failure = failure
    }

    /// Why there is no answer, as a failure the catalog names, beside `index`.
    init(refusing error: Error, index: Catalog.Index?) {
        let failure = error as? Catalog.Failure ?? .failed(Self.words(error))
        self.init(Catalog.Refused(index: index, error: failure), failure: failure)
    }

    /// The object, as `Catalog.encoder` writes it.
    func json() throws -> Data {
        try Catalog.encoder.encode(object)
    }

    /// What went wrong, in words: Foundation's own for a file system error, else the error's.
    private static func words(_ error: Error) -> String {
        let ns = error as NSError
        return [NSCocoaErrorDomain, NSPOSIXErrorDomain].contains(ns.domain) ? ns.localizedDescription : "\(error)"
    }
}

/// A failure whose answer is on stdout: the command says why on stderr too, and exits with its code.
struct Refusal: Error {
    var failure: Catalog.Failure
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

    /// What `read` selects: these lines, or these bytes, or when neither is given, all of it.
    static func span(lines: Bounds?, bytes: Bounds?) -> Catalog.Span? {
        lines.map { .lines($0.start, $0.end) } ?? bytes.map { .bytes($0.start, $0.end) }
    }
}

extension Artifact.Kind: ExpressibleByArgument {}

/// Writes an answer to stdout as one JSON object and a newline. A failure's answer is written too,
/// and the failure then thrown, so that the command says why on stderr and exits with its code.
func write(_ answer: Answer) throws {
    FileHandle.standardOutput.write(try answer.json() + Data("\n".utf8))
    if let failure = answer.failure { throw Refusal(failure: failure) }
}
