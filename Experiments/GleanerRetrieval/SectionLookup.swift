import Foundation
import GleanerCore

/// A report-local identifier experiment. Both policies use Catalog.outline's verified source
/// headings; neither indexes document contents globally or joins findings across reports.
public enum SectionLookup {
    public enum Policy: String, Codable, CaseIterable, Sendable {
        case titleSubstring = "title_substring"
        case exactIdentifier = "exact_identifier"
    }

    public struct Result: Codable, Sendable {
        public var policy: Policy
        public var query: String
        public var index: Catalog.Index
        public var reference: Catalog.Reference
        public var sections: [Catalog.Section]
        public var outlineRequests: Int
    }

    public static func evaluate(catalog: Catalog, delivery: String, query: String, policy: Policy) throws -> Result {
        // Page through the shared outline to avoid changing its normal bound or building another
        // parser. Each page re-verifies the same immutable delivery version.
        let terms = policy == .titleSubstring ? [query] : []
        var page = try catalog.outline(delivery, terms: terms, limit: Catalog.pageLimit)
        let index = page.index, reference = page.reference
        var sections = page.sections, requests = 1
        while let next = page.nextOffset {
            page = try catalog.outline(delivery, terms: terms, limit: Catalog.pageLimit, offset: next)
            sections += page.sections
            requests += 1
        }
        let selected: [Catalog.Section]
        switch policy {
        case .titleSubstring:
            selected = sections
        case .exactIdentifier:
            let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !wanted.isEmpty, wanted.unicodeScalars.allSatisfy(identifierCharacter) else {
                throw Catalog.Failure.usage("An experimental section identifier contains only letters, numbers, underscore or hyphen.")
            }
            selected = sections.filter { leadingIdentifier($0.title) == wanted }
        }
        return Result(policy: policy, query: query, index: index, reference: reference, sections: selected, outlineRequests: requests)
    }

    /// Conservative convention: the first lexical token is the report-local identifier. This
    /// intentionally leaves numbering inside prose/formatting ambiguous rather than inventing it.
    private static func leadingIdentifier(_ title: String) -> String {
        String(String.UnicodeScalarView(title.trimmingCharacters(in: .whitespaces).unicodeScalars.prefix(while: identifierCharacter))).lowercased()
    }

    private static func identifierCharacter(_ character: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(character) || character == "_" || character == "-"
    }
}
