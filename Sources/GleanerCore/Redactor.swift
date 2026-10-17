import Foundation

/// Masks secret-shaped strings before an excerpt is stored.
public enum Redactor {
    static let patterns: [NSRegularExpression] = [
        #"sk-[A-Za-z0-9_\-]{16,}"#,
        #"gh[pousr]_[A-Za-z0-9]{20,}"#,
        #"github_pat_[A-Za-z0-9_]{20,}"#,
        #"AKIA[0-9A-Z]{16}"#,
        #"xox[abprs]-[A-Za-z0-9\-]{10,}"#,
        #"AIza[0-9A-Za-z_\-]{30,}"#,
        #"(?i)bearer\s+[A-Za-z0-9._\-+/=]{16,}"#,
        #"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#,
        #"(?i)["']?\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|token|secret|client[_-]?secret|password|passwd|pwd)\b["']?\s*[=:]\s*(?:"[^"\n]*"|'[^'\n]*'|[^\s,;}\]]+)"#,
        #"://[^/\s:@]+:[^/\s@]+@"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    /// Long base64-like runs mixing cases and digits. Lowercase hex (hashes, ids) is left alone.
    static let opaqueRun = try! NSRegularExpression(pattern: #"[A-Za-z0-9+_\-]{40,}={0,2}"#)

    public static func redact(_ text: String) -> String {
        var result = text
        for pattern in patterns {
            result = pattern.stringByReplacingMatches(
                in: result, range: NSRange(location: 0, length: (result as NSString).length),
                withTemplate: "[REDACTED]")
        }
        let ns = result as NSString
        for match in opaqueRun.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
            let run = ns.substring(with: match.range)
            let mixed = run.contains(where: \.isUppercase) && run.contains(where: \.isLowercase)
                && run.contains(where: \.isNumber)
            if mixed {
                result = (result as NSString).replacingCharacters(in: match.range, with: "[REDACTED]")
            }
        }
        return result
    }
}
