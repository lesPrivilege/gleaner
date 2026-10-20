import Foundation
import Testing

/// The skill in `extensions/gleaner`, which Claude Code, Codex and the DeepSeek Harness read
/// (docs/design/extensions.md "Verification"), shows only commands the built `gleaner` takes, so a
/// command or option renamed in the executable fails here before an agent meets it.
extension CommandTests {
    /// The skill's folder, in the repository this file is in.
    static let skill = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("extensions/gleaner")

    /// Every `gleaner …` invocation the skill shows: each line of a fenced block, and each code
    /// span, that starts with `gleaner `.
    static func invocations(in text: String) -> [String] {
        var shown: [String] = [], fenced = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```") {
                fenced.toggle()
            } else if fenced {
                if line.hasPrefix("gleaner ") { shown.append(String(line)) }
            } else {
                shown += line.matches(of: /`(gleaner [^`]+)`/).map { String($0.output.1) }
            }
        }
        return shown
    }

    /// The words of an invocation as a shell would split it, with double quotes.
    static func words(_ invocation: String) -> [String] {
        invocation.matches(of: /"([^"]*)"|(\S+)/).map { String($0.output.1 ?? $0.output.2 ?? "") }
    }

    @Test func theSkillIsInTheFormEveryHostReads() throws {
        // Agent Skills frontmatter: first line `---`, a name that is its folder's, and a description
        // of at most 1024 characters.
        let text = try String(contentsOf: Self.skill.appendingPathComponent("SKILL.md"), encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == "---")
        let header = lines.dropFirst().prefix { $0 != "---" }
        #expect(header.contains { $0 == "name: \(Self.skill.lastPathComponent)" })
        let description = try #require(header.first { $0.hasPrefix("description: ") }).dropFirst("description: ".count)
        #expect(!description.isEmpty && description.count <= 1024)
    }

    @Test func everyCommandTheSkillShowsParses() throws {
        try index()
        let shown = Self.invocations(in: try String(contentsOf: Self.skill.appendingPathComponent("SKILL.md"), encoding: .utf8))
        #expect(Set(shown.map { Self.words($0)[1] }) == ["find", "show", "read", "outline", "resolve", "handoff", "verify"])
        for invocation in shown {
            let words = Self.words(invocation)
            if invocation.contains("<") || invocation.contains("[") {
                // A template: its command exists, and takes every option the template names.
                let help = try gleaner([words[1], "--help"])
                let usage = try #require(String(decoding: help.output, as: UTF8.self)
                    .components(separatedBy: "\n\n").first { $0.hasPrefix("USAGE: ") }, "\(invocation)")
                #expect(help.status == 0 && usage.hasPrefix("USAGE: gleaner \(words[1]) "), "\(invocation)")
                let takes = Set(usage.matches(of: /--[a-z-]+/).map { String($0.output) })
                let named = Set(invocation.matches(of: /--[a-z-]+/).map { String($0.output) })
                #expect(named.isSubset(of: takes), "\(invocation): \(usage)")
            } else {
                // An example: it runs on the synthetic home, and answers or refuses as the contract
                // says, not as a wrong usage.
                let run = try gleaner(Array(words.dropFirst()))
                #expect([0, 1].contains(run.status), "\(invocation): \(run.error)")
                #expect(try JSONSerialization.jsonObject(with: run.output) is [String: Any], "\(invocation)")
            }
        }
    }
}
