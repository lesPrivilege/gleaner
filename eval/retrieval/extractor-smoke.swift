import Foundation

@main struct CaptureSmoke {
    static func main() throws {
        let cases: [(String, String, [String])] = [
            ("relative_folder", "Outputs: `out/`", ["/work/series/out"]),
            ("brace_range", "Outputs: `out/part{01..03}.md`", (1...3).map { "/work/series/out/part0\($0).md" }),
            ("repeated_stem_range", "Outputs: `out/shot07–shot09.png`", (7...9).map { "/work/series/out/shot0\($0).png" }),
            ("wildcard", "Outputs: `out/*.md`", []),
            ("literal_year_span", "[report](out/forecast2024–2025.pdf)", ["/work/series/out/forecast2024–2025.pdf"]),
            ("ambiguous_relative_kept", "[report](series/out/report.md)", ["/work/series/series/out/report.md"]),
            ("anchor_is_not_glob", "[report](out/report.md#questions?open)", ["/work/series/out/report.md"]),
            ("nul_rejected", "[report](out/r%00.md)", []),
            ("bounded_range", "Outputs: `out/part{1..257}.md`", []),
            ("encoded_literal", "[literal](out/star%2A.md)", ["/work/series/out/star*.md"]),
        ]
        let results = cases.map { name, text, expected -> [String: Any] in
            let actual = MentionExtractor.extract(from: text, cwd: "/work/series").map(\.path)
            return ["case": name, "passed": actual == expected, "expected_count": expected.count, "actual_count": actual.count]
        }
        let output = try JSONSerialization.data(withJSONObject: ["kind": "extractor_only_smoke", "cases": results], options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: output, as: UTF8.self))
    }
}
