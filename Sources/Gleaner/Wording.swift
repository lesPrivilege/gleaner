import AppKit
import GleanerCore
import SwiftUI

/// Every status is a few words beside the thing it describes; the mark repeats them and never
/// carries meaning alone (Praxis kit, foundations/standing.md).
enum Mark {
    case solid, hollow, dashed, attention, cross

    var symbol: String {
        switch self {
        case .solid: "circle.fill"
        case .hollow: "circle"
        case .dashed: "circle.dashed"
        case .attention: "exclamationmark.triangle"
        case .cross: "xmark"
        }
    }

    var color: Color {
        switch self {
        case .solid, .hollow: .primary
        case .dashed: .secondary
        case .attention: Palette.attention
        case .cross: Palette.lost
        }
    }
}

/// Amber means "needs your look", red means gone, blue is selection (Praxis kit). Each color has
/// a light and a dark value, and a stronger one under Increase Contrast.
enum Palette {
    static let attention = dynamic(light: (0.54, 0.29, 0.0), dark: (1.0, 0.72, 0.36), contrast: (0.42, 0.21, 0.0))
    static let attentionFill = dynamic(light: (1.0, 0.96, 0.92), dark: (0.24, 0.16, 0.07), contrast: (1.0, 0.93, 0.85))
    static let lost = dynamic(light: (0.63, 0.17, 0.17), dark: (1.0, 0.52, 0.5), contrast: (0.5, 0.08, 0.08))
    static let lostFill = dynamic(light: (1.0, 0.96, 0.96), dark: (0.26, 0.1, 0.1), contrast: (1.0, 0.92, 0.92))
    /// Changed text, and only that (Courtwork's change language): the line colour, the solid block
    /// on new words, and the dark ink inside that block.
    static let change = dynamic(light: (0.63, 0.24, 0.21), dark: (0.89, 0.55, 0.51), contrast: (0.5, 0.14, 0.12))
    static let changeBlock = dynamic(light: (0.87, 0.44, 0.41), dark: (0.83, 0.41, 0.37), contrast: (0.75, 0.3, 0.27))
    static let changeInk = dynamic(light: (0.09, 0.13, 0.15), dark: (0.07, 0.09, 0.11), contrast: (0.0, 0.0, 0.0))
    static let selection = dynamic(light: (0.18, 0.37, 0.82), dark: (0.45, 0.63, 1.0), contrast: (0.1, 0.27, 0.7))

    private typealias RGB = (Double, Double, Double)

    private static func dynamic(light: RGB, dark: RGB, contrast: RGB) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let rgb = switch match {
            case .darkAqua?, .accessibilityHighContrastDarkAqua?: dark
            case .accessibilityHighContrastAqua?: contrast
            default: light
            }
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

struct Statement {
    var mark: Mark
    var title: String
    var detail: String
}

struct StatusLabel: View {
    var mark: Mark
    var text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: mark.symbol).font(.system(size: 9, weight: .bold)).accessibilityHidden(true)
        }
        .foregroundStyle(mark.color)
    }
}

enum Wording {
    static func date(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "unknown time"
    }

    static func onDisk(_ status: OnDisk, checked: Date) -> Statement {
        let when = "Checked \(checked.formatted(.relative(presentation: .named)))."
        switch status {
        case .same(let n):
            return Statement(mark: .solid, title: "Same as delivery \(n)", detail: "Hash matches. \(when)")
        case .unchangedSinceFirstSeen(let seen):
            return Statement(mark: .hollow, title: "Unchanged since Gleaner first saw it",
                             detail: "First seen \(date(seen)), after the delivery. It may not be what was delivered. \(when)")
        case .rolledBack(let k, let latest, nil):
            return Statement(mark: .attention, title: "Rolled back to delivery \(k)",
                             detail: "The file on disk is delivery \(k) again, not the latest delivery \(latest). \(when)")
        case .rolledBack(let k, let latest, let seen?):
            return Statement(mark: .attention, title: "Back to what Gleaner first saw for delivery \(k)",
                             detail: "The file on disk matches the bytes Gleaner first saw for delivery \(k) on \(date(seen)), after that delivery; it is not the latest delivery \(latest). \(when)")
        case .changed(let n):
            return Statement(mark: .attention, title: "Changed since delivery \(n)",
                             detail: "What is at this path now isn’t among the deliveries Gleaner found. \(when)")
        case .missingWithSavedCopy(let n, nil):
            return Statement(mark: .dashed, title: "Not on disk", detail: "Gleaner saved a copy of delivery \(n). \(when)")
        case .missingWithSavedCopy(let n, let seen?):
            return Statement(mark: .dashed, title: "Not on disk",
                             detail: "Gleaner saved a copy for delivery \(n), first seen \(date(seen)), after the delivery. It may not be what was delivered. \(when)")
        case .missingInGitHistory:
            return Statement(mark: .dashed, title: "Not on disk", detail: "Git history still has a file at this path. \(when)")
        case .lost:
            return Statement(mark: .cross, title: "Lost",
                             detail: "Not on disk, no saved copy, and not found in git at this path. The delivery record stays. \(when)")
        case .folder:
            return Statement(mark: .hollow, title: "Folder on disk",
                             detail: "Folders aren’t versioned yet; Gleaner shows the folder as it is now. \(when)")
        case .special:
            return Statement(mark: .cross, title: "Not a regular file",
                             detail: "Gleaner doesn’t open pipes, sockets, or devices. \(when)")
        case .unreadable:
            return Statement(mark: .attention, title: "Can’t be read",
                             detail: "Something is at this path, but Gleaner can’t open or read it, so it can’t tell which version it is. \(when)")
        }
    }

    /// `large` says the delivery was over the save limit, the one reason Gleaner chose not to
    /// keep its bytes.
    static func handoff(_ plan: Handoff, delivery: Delivery, onDisk: OnDisk, large: Bool) -> Statement {
        let n = delivery.number
        switch plan {
        case .ready(_, .original, nil):
            return Statement(mark: .solid, title: "Ready: the file on disk is delivery \(n)",
                             detail: "Dragging hands over a copy Gleaner verified after copying; later edits can’t slip in.")
        case .ready(_, .savedCopy, nil):
            let why = if case .missingWithSavedCopy = onDisk { "The file is no longer on disk." } else { "The file on disk has changed since." }
            return Statement(mark: .solid, title: "Ready: Gleaner’s saved copy of delivery \(n)",
                             detail: "\(why) Gleaner hands over the copy it saved, hash-checked.")
        case .ready(_, _, let seen?):
            return Statement(mark: .hollow, title: "Ready, with a caveat",
                             detail: "Gleaner first saw these bytes on \(date(seen)), after the delivery. They may not be exactly what was delivered.")
        case .unavailable(let k?, _):
            let again = if case .rolledBack(_, _, _?) = onDisk { "matches what Gleaner first saw for delivery \(k)" } else { "is delivery \(k) again" }
            return Statement(mark: .attention, title: "Delivery \(n) is no longer available",
                             detail: "The file on disk \(again), and Gleaner didn’t save a copy of delivery \(n).")
        case .unavailable(nil, let current):
            let unsaved = large ? "Gleaner didn’t save a copy: large files are saved only when you choose to"
                : "Gleaner has no saved copy of delivery \(n)"
            let why = if delivery.capture?.isDirectory == true {
                "Delivery \(n) was a folder, and something else is at this path now. Folders aren’t versioned, so Gleaner has no copy of it."
            } else if current == nil {
                "Something else is at this path now, and \(unsaved)."
            } else {
                "The file has changed and \(unsaved)."
            }
            let offer = current == nil ? "" : " You can hand off the current file, but it isn’t among the deliveries Gleaner found."
            return Statement(mark: .attention, title: "Delivery \(n) is no longer available", detail: why + offer)
        case .restoreFromGit:
            return Statement(mark: .dashed, title: "Restore it from git first",
                             detail: "Git history has a file at this path. Gleaner can’t confirm it is the delivered version, and doesn’t write to your repository.")
        case .lost:
            let why = delivery.capture?.isDirectory == true
                ? "It was a folder and it isn’t on disk. Folders aren’t versioned, so Gleaner has no copy of it."
                : "It isn’t on disk, Gleaner didn’t save a copy, and git has nothing at this path."
            return Statement(mark: .cross, title: "Delivery \(n) is lost",
                             detail: why + " The delivery record stays so you can see it existed.")
        case .folder:
            return Statement(mark: .hollow, title: "Folder",
                             detail: "Dragging hands over the folder as it is now. Folders aren’t verified by hash yet.")
        }
    }

    static func provenance(_ capture: Capture?) -> (Mark, String) {
        guard let capture else { return (.dashed, "Not captured") }
        switch capture.provenance {
        case .atDelivery: return (.solid, "Seen at delivery")
        case .firstSeenAfterDelivery: return (.hollow, "First seen \(date(capture.observedAt)), after delivery · may differ from what was delivered")
        case .neverObserved: return (.dashed, "Never seen · the file was gone before Gleaner looked")
        }
    }

    static func storage(_ delivery: Delivery, hasSaved: Bool, large: Bool, current: String?, checked: Bool) -> (Mark, String) {
        guard let capture = delivery.capture, !capture.isDirectory else { return (.hollow, "Folder · not versioned") }
        guard let sha = capture.sha256 else { return (.cross, "Not saved") }
        let size = capture.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        if hasSaved {
            return capture.provenance == .firstSeenAfterDelivery
                ? (.hollow, "Saved copy of what Gleaner first saw (\(size))")
                : (.solid, "Saved copy (\(size))")
        }
        let what = large ? "large file (\(size))" : size
        guard checked else { return (.hollow, "Not saved · \(what), checking…") }
        return current == sha
            ? (.hollow, "Not saved · \(what), checked by hash")
            : (.cross, "Not saved · this version no longer exists")
    }

    static func openFailed(_ error: Error) -> String {
        "Couldn’t open it: \(error.localizedDescription)"
    }

    static func saveFailed(_ error: Error, delivery n: Int) -> String {
        switch error {
        case ContentStore.Failure.changed:
            "The file changed before Gleaner could save it; it no longer holds delivery \(n)."
        case ContentStore.Failure.unavailable:
            "Gleaner couldn’t read delivery \(n)’s bytes at this path."
        default:
            "Couldn’t save a copy: \(error.localizedDescription)"
        }
    }

    /// A few words for a one-line delivery row; the full sentence is under Details.
    static func provenanceShort(_ capture: Capture?) -> (Mark, String) {
        switch capture?.provenance {
        case .atDelivery?: (.solid, "Seen at delivery")
        case .firstSeenAfterDelivery?: (.hollow, "First seen later")
        case .neverObserved?, nil: (.dashed, "Never seen")
        }
    }

    /// A delivery as one end of a comparison, keeping "first seen later" (SPEC §6).
    static func compareTitle(_ delivery: Delivery) -> String {
        "Delivery \(delivery.number)" + (delivery.capture?.provenance == .firstSeenAfterDelivery ? " (first seen later)" : "")
    }

    /// Names the bytes on screen and in the drag tile, so the preview never speaks for another version.
    static func bytesCaption(_ plan: Handoff?, staged sha: String?, delivery: Delivery) -> String? {
        switch plan {
        case .folder?:
            return "Folder as it is now · not versioned"
        case .ready(_, let from, let seen)?:
            guard sha != nil else { return nil }
            let source = from == .original ? "file on disk" : "Gleaner’s saved copy"
            return "Delivery \(delivery.number) · \(source)" + (seen == nil ? "" : " · first seen later, may differ")
        case .unavailable(_, let current?)? where sha == current:
            return "Current file · not among the deliveries Gleaner found"
        default:
            return nil
        }
    }

    static func provider(_ provider: Provider) -> String {
        provider == .codex ? "Codex" : "Claude Code"
    }

    /// One agent's log folder as last read (SPEC §8): not on this Mac, unreadable, read with
    /// problems, or read.
    static func source(_ source: Indexer.Report.Source) -> (Mark, String) {
        switch source.folder {
        case .absent: (.dashed, "Not on this Mac")
        case .unreadable: (.cross, "Can’t be read")
        case .listed where source.hasProblems: (.attention, "Read with problems")
        case .listed: (.solid, "Read")
        }
    }

    /// What went wrong reading a listed folder, counted; nil when nothing did.
    static func problems(_ source: Indexer.Report.Source) -> String? {
        let parts = [
            source.unknownRecordTypes.isEmpty ? nil : count(source.unknownRecordTypes.count, "unknown record type"),
            source.partialLogs.isEmpty ? nil : count(source.partialLogs.count, "log") + " with malformed lines",
            source.shortenedLogs.isEmpty ? nil : count(source.shortenedLogs.count, "log") + " shorter than when last read",
            source.failures.isEmpty ? nil : count(source.failures.count, "log") + " couldn’t be read",
            source.unlistedFolders.isEmpty ? nil : count(source.unlistedFolders.count, "folder") + " couldn’t be listed",
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The fuller story for Settings: why a folder can't be read, or which record types are new.
    static func sourceDetail(_ source: Indexer.Report.Source) -> String? {
        if case .unreadable(let reason) = source.folder { return reason }
        guard let problems = problems(source) else { return nil }
        let types = source.unknownRecordTypes.keys.sorted()
        return problems + (types.isEmpty ? "" : ". Unknown record types: " + types.joined(separator: ", "))
    }

    /// The sources that need a look, in one line; nil when each read cleanly or isn't on this Mac.
    static func sourcesLine(_ sources: [Provider: Indexer.Report.Source]) -> String? {
        let lines = Provider.allCases.compactMap { provider -> String? in
            guard let source = sources[provider] else { return nil }
            let state = "\(self.provider(provider)): \(self.source(source).1.lowercased())"
            switch source.folder {
            case .absent: return nil
            case .unreadable: return state
            case .listed: return problems(source).map { state + " (\($0))" }
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// A project as shown. When no repository was found for the file, that is said rather than
    /// guessed (SPEC §5).
    static func project(_ name: String, inRepository: Bool) -> String {
        inRepository ? name : name + " · outside git"
    }

    static func kindName(_ kind: Artifact.Kind) -> String {
        switch kind {
        case .document: "Documents"
        case .image: "Images"
        case .media: "Video & Audio"
        case .web: "Web Pages"
        case .code: "Code"
        case .data: "Data"
        case .model: "3D & CAD"
        case .build: "Builds & Archives"
        case .folder: "Folders"
        case .other: "Other"
        }
    }

    static func kindLabel(_ kind: Artifact.Kind, path: String) -> String {
        let ext = (path as NSString).pathExtension.uppercased()
        return kind == .folder ? "FOLDER" : (ext.isEmpty ? "FILE" : String(ext.prefix(5)))
    }
}
