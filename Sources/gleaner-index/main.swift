import ArgumentParser
import Foundation
import GleanerCore

/// `gleaner-index`: a development tool that indexes a synthetic home once, as the app does when it
/// opens with `-GleanerHome`, so an agent can then query it with `gleaner` and `gleaner mcp` without
/// the window (docs/design/headless-indexing.md). Never bundled or released. It refuses to run
/// without `--home`, and on the person's own home: it never writes their library or reads their logs.
struct GleanerIndex: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gleaner-index",
        abstract: "Index a synthetic home once, as Gleaner does with -GleanerHome, and print the library's index.",
        discussion: """
            Writes one JSON object to stdout: the library's index after the run, and what the run \
            read and added. A failure is {"error": {"message"}}, with the message on stderr too. \
            Exit codes: 0 success; 1 the library couldn't be opened or the run failed; 2 usage.
            """)

    @Option(help: ArgumentHelp("The folder to take for the home folder. Never your own.", valueName: "folder"))
    var home: String

    @Option(help: ArgumentHelp("The run's clock, in ISO 8601 (2026-10-19T12:00:00Z), for runs that repeat.", valueName: "time"))
    var now: String?

    /// The run's report as the tool writes it, beside the index the run recorded.
    struct Answer: Encodable {
        var index: Catalog.Index
        var logsRead: Int
        var newDeliveries: Int
        var newObservations: Int
    }

    var folder: URL { URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath() }

    func validate() throws {
        let own = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard folder.path != own.path else {
            throw ValidationError("--home is your own home folder; gleaner-index only indexes a synthetic one.")
        }
        if let now, Self.date(now) == nil { throw ValidationError("--now must be an ISO 8601 time, such as 2026-10-19T12:00:00Z.") }
    }

    static func date(_ text: String) -> Date? { try? Date(text, strategy: .iso8601) }

    func run() throws {
        let clock = now.flatMap(Self.date)
        let answer: Answer
        do {
            let indexer = try Indexer(folders: LibraryFolders(home: folder))
            // As the app's run: every agent's logs but those turned off in Sources.
            let report = try indexer.run(providers: Set(Provider.allCases).subtracting(indexer.registry.sourcesOff()),
                                         now: { clock ?? Date() })
            answer = Answer(index: try indexer.registry.index(), logsRead: report.logsRead,
                            newDeliveries: report.newDeliveries, newObservations: report.newObservations)
        } catch {
            Self.fail("\(error)", status: 1)
        }
        FileHandle.standardOutput.write(try Catalog.encoder.encode(answer) + Data("\n".utf8))
    }

    /// Runs the command with the exit codes above: ArgumentParser would give 64 for usage.
    static func main() {
        do {
            var command = try parseAsRoot()
            try command.run()
        } catch let error where exitCode(for: error) == .validationFailure {
            fail(message(for: error), status: 2, usage: fullMessage(for: error))
        } catch {
            exit(withError: error)
        }
    }

    static func fail(_ message: String, status: Int32, usage: String? = nil) -> Never {
        let json = (try? Catalog.encoder.encode(["error": ["message": message]])) ?? Data()
        FileHandle.standardOutput.write(json + Data("\n".utf8))
        FileHandle.standardError.write(Data(((usage ?? "Error: " + message) + "\n").utf8))
        Foundation.exit(status)
    }
}

GleanerIndex.main()
