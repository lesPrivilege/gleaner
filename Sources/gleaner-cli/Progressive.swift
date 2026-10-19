import ArgumentParser
import GleanerCore

extension Gleaner {
    struct Projects: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Discover project identities, origins and work counts as the app shows them.")
        @Option(help: "The most projects to list, between 1 and 1000.") var limit = 20
        @Option(help: "Skip this many projects; continue at next_offset.") var offset = 0
        @Option(help: "Require this completed index generation when continuing a page.") var generation: Int?
        @OptionGroup var library: Library

        func run() throws {
            try write(library.answer { try $0.projects(limit: limit, offset: offset, generation: generation) })
        }
    }

    struct Outline: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List Markdown-style headings of one verified text version, with exact section identities and byte ranges.")
        @Argument(help: "The delivery's id.") var delivery: String
        @Argument(help: "Optional words to match in heading titles within this document.") var terms: [String] = []
        @Option(help: "The most headings to list, between 1 and 1000.") var limit = 20
        @Option(help: "Skip this many matched headings; continue at next_offset.") var offset = 0
        @OptionGroup var library: Library

        func run() throws {
            try write(library.answer { try $0.outline(delivery, terms: terms, limit: limit, offset: offset) })
        }
    }

    struct Section: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Read a section from an outline's exact version, including its heading and nested sections.")
        @Argument(help: "The delivery's id.") var delivery: String
        @Argument(help: "The exact section id from outline, not a heading title.") var section: String
        @Option(help: "The most UTF-8 bytes to return, between 1 and 1048576. Continue through read using the returned range.")
        var max = Read.max
        @OptionGroup var library: Library

        func run() throws {
            try write(library.answer { try $0.readSection(delivery, section: section, max: max) })
        }
    }
}
