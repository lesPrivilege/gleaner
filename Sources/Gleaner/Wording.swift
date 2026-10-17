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

    /// A delivery's number as every label names it: with "first seen later" when Gleaner first
    /// read its bytes after the delivery, so they may not be what was delivered (rulings §9).
    static func number(_ delivery: Delivery) -> String {
        "\(delivery.number)" + (delivery.capture?.provenance == .firstSeenAfterDelivery ? " (first seen later)" : "")
    }

    /// Delivery `n` of `artifact`, named as `number(_:)` names it.
    static func number(_ n: Int, in artifact: Artifact) -> String {
        artifact.deliveries.first { $0.number == n }.map(number) ?? "\(n)"
    }

    /// "On disk now", from what the check `now` found: only that, with why when it matters.
    static func onDisk(_ status: OnDisk, in artifact: Artifact, now: FileObservation) -> Statement {
        let when = "Checked \(now.checkedAt.formatted(.relative(presentation: .named)))."
        let latest = artifact.latest
        switch status {
        case .same(let n):
            return Statement(mark: .solid, title: "Same as delivery \(number(n, in: artifact))", detail: "Hash matches. \(when)")
        case .unchangedSinceFirstSeen(let seen):
            return Statement(mark: .hollow, title: "Unchanged since Gleaner first saw it",
                             detail: "First seen \(date(seen)), after the delivery. It may not be what was delivered. \(when)")
        case .rolledBack(let k, let latest, nil):
            return Statement(mark: .attention, title: "Rolled back to delivery \(k)",
                             detail: "The file on disk is delivery \(k) again, not the latest delivery \(number(latest, in: artifact)). \(when)")
        case .rolledBack(let k, let latest, let seen?):
            return Statement(mark: .attention, title: "Back to what Gleaner first saw for delivery \(k)",
                             detail: "The file on disk matches the bytes Gleaner first saw for delivery \(k) on \(date(seen)), after that delivery; it is not the latest delivery \(number(latest, in: artifact)). \(when)")
        case .changed(let n) where now.state.kind == .file && latest.sha256 == nil && latest.capture?.isDirectory != true:
            return Statement(mark: .attention, title: "Not among the deliveries Gleaner found",
                             detail: "Gleaner never read delivery \(n)’s bytes, so it can’t tell whether this file is it. \(when)")
        case .changed(let n):
            let what = now.state.kind == .directory ? "A folder is at this path now." : "What is at this path now isn’t among the deliveries Gleaner found."
            return Statement(mark: .attention, title: "Changed since delivery \(number(n, in: artifact))", detail: "\(what) \(when)")
        case .missingWithSavedCopy(let n, nil):
            return Statement(mark: .dashed, title: "Not on disk", detail: "Gleaner saved a copy of delivery \(n). \(when)")
        case .missingWithSavedCopy(let n, let seen?):
            return Statement(mark: .dashed, title: "Not on disk",
                             detail: "Gleaner saved a copy for delivery \(n), first seen \(date(seen)), after the delivery. It may not be what was delivered. \(when)")
        case .missingInGitHistory:
            return Statement(mark: .dashed, title: "Not on disk", detail: "Git history still has a file at this path. \(when)")
        case .lost:
            // Git isn't asked about a folder: nothing in it shows which folder was delivered.
            let why = latest.capture?.isDirectory == true ? "Not on disk. Folders aren’t versioned, so Gleaner has no copy of it."
                : now.state.git == .notInRepo ? "Not on disk, no saved copy, and not in a git repository."
                : "Not on disk, no saved copy, and not found in git at this path."
            return Statement(mark: .cross, title: "Lost", detail: "\(why) The delivery record stays. \(when)")
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

    /// What the check `now` found at a path that doesn't hold `delivery`'s bytes.
    static func atPath(_ now: LocatorState, delivery: Delivery) -> String {
        switch now.kind {
        case .file: delivery.sha256 == nil ? "A file is at this path now." : "The file on disk has changed since."
        case .directory: "A folder is at this path now."
        case .special: "What is at this path now isn’t a regular file."
        case .unreadable: "Something is at this path, but Gleaner can’t read it, so it can’t tell which version it is."
        case .missing: "The file is no longer on disk."
        }
    }

    /// Why Gleaner keeps none of `delivery`'s bytes, from what it recorded when it first looked:
    /// never seen, not a regular file, unreadable, a folder, too large to have been saved, or a
    /// save that failed; or a copy it saved that its store no longer holds. `large` says the
    /// delivery was over the save limit.
    static func noCopy(_ delivery: Delivery, large: Bool) -> String {
        let n = number(delivery)
        switch delivery.capture?.kind {
        case nil:
            return "Gleaner has no record of delivery \(n)’s bytes."
        case .directory?:
            return "Delivery \(n) was a folder. Folders aren’t versioned, so Gleaner has no copy of it."
        case .special?:
            return "Gleaner never read delivery \(n): it wasn’t a regular file when Gleaner first looked."
        case .unreadable?:
            return "Gleaner never read delivery \(n): it couldn’t be read when Gleaner first looked."
        case .missing?:
            return "Gleaner never saw delivery \(n): nothing was at this path when it first looked."
        case .file? where delivery.capture?.savedAt != nil:
            return "Gleaner saved a copy of delivery \(n), but it is no longer in Gleaner’s store."
        case .file?:
            return large
                ? "Gleaner didn’t save a copy of delivery \(n): it was too large to have been saved, and large files are saved only when you choose to."
                : "Saving a copy of delivery \(n) failed when Gleaner read it."
        }
    }

    /// What a drag of `delivery` hands over, from what the check `now` found. When there is
    /// nothing, it says why, and offers only what the panel can do.
    static func handoff(_ plan: Handoff, delivery: Delivery, in artifact: Artifact, now: LocatorState, large: Bool) -> Statement {
        let n = number(delivery)
        // "No longer" only for bytes Gleaner had: not for a delivery it never read, nor for a file
        // it can't read now.
        let unavailable = now.kind == .unreadable ? "Delivery \(n) isn’t available now"
            : delivery.sha256 == nil && delivery.capture?.isDirectory != true ? "Delivery \(n) isn’t available"
            : "Delivery \(n) is no longer available"
        switch plan {
        case .ready(_, .original, nil):
            return Statement(mark: .solid, title: "Ready: the file on disk is delivery \(n)",
                             detail: "Dragging hands over a copy Gleaner verified after copying; later edits can’t slip in.")
        case .ready(_, .savedCopy, nil):
            return Statement(mark: .solid, title: "Ready: Gleaner’s saved copy of delivery \(n)",
                             detail: "\(atPath(now, delivery: delivery)) Gleaner hands over the copy it saved, hash-checked.")
        case .ready(_, _, let seen?):
            return Statement(mark: .hollow, title: "Ready, with a caveat",
                             detail: "Gleaner first saw these bytes on \(date(seen)), after the delivery. They may not be exactly what was delivered.")
        case .unavailable(let k?, _):
            let firstSeen = artifact.deliveries.first { $0.number == k }?.capture?.provenance == .firstSeenAfterDelivery
            let again = firstSeen ? "matches what Gleaner first saw for delivery \(k)" : "is delivery \(number(k, in: artifact)) again"
            return Statement(mark: .attention, title: unavailable,
                             detail: "The file on disk \(again). \(noCopy(delivery, large: large))")
        case .unavailable(nil, let current):
            let offer = current == nil ? "" : " You can hand off the current file, but it isn’t among the deliveries Gleaner found."
            return Statement(mark: .attention, title: unavailable,
                             detail: "\(atPath(now, delivery: delivery)) \(noCopy(delivery, large: large))" + offer)
        case .restoreFromGit:
            return Statement(mark: .dashed, title: "Restore it from git first",
                             detail: "Git history has a file at this path. Gleaner can’t confirm it is the delivered version, and doesn’t write to your repository.")
        case .lost:
            // Git isn't asked about a folder: nothing in it shows which folder was delivered.
            let git = delivery.capture?.isDirectory == true ? ""
                : now.git == .notInRepo ? ", and it isn’t in a git repository" : ", and git has nothing at this path"
            return Statement(mark: .cross, title: "Delivery \(n) is lost",
                             detail: "It isn’t on disk\(git). \(noCopy(delivery, large: large)) The delivery record stays so you can see it existed.")
        case .folder:
            return Statement(mark: .hollow, title: "Folder",
                             detail: "Dragging hands over the folder as it is now. Folders aren’t verified by hash yet.")
        }
    }

    static func provenance(_ capture: Capture?) -> (Mark, String) {
        guard let capture else { return (.dashed, "Not captured") }
        switch (capture.provenance, capture.kind) {
        case (.atDelivery, _): return (.solid, "Seen at delivery")
        case (.firstSeenAfterDelivery, _): return (.hollow, "First seen \(date(capture.observedAt)), after delivery · may differ from what was delivered")
        case (.neverObserved, .special): return (.dashed, "Never read · not a regular file when Gleaner first looked")
        case (.neverObserved, .unreadable): return (.dashed, "Never read · it couldn’t be read when Gleaner first looked")
        case (.neverObserved, _): return (.dashed, "Never seen · nothing was at this path when Gleaner first looked")
        }
    }

    /// Where `delivery`'s bytes are kept; when they aren't, why, and what the check `now` found
    /// (nil until the file is checked).
    static func storage(_ delivery: Delivery, hasSaved: Bool, large: Bool, now: LocatorState?) -> (Mark, String) {
        guard let capture = delivery.capture else { return (.dashed, "Not saved · not captured") }
        if capture.isDirectory { return (.hollow, "Folder · not versioned") }
        guard let sha = capture.sha256 else { return (.cross, "Not saved · Gleaner never read it") }
        let size = capture.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        if hasSaved {
            return capture.provenance == .firstSeenAfterDelivery
                ? (.hollow, "Saved copy of what Gleaner first saw (\(size))")
                : (.solid, "Saved copy (\(size))")
        }
        let state = capture.savedAt != nil ? "Saved copy no longer in Gleaner’s store (\(size))"
            : large ? "Not saved · too large to have been saved (\(size))" : "Not saved · saving it failed (\(size))"
        guard let now else { return (.hollow, "\(state), checking…") }
        if now.sha256 == sha { return (.hollow, "\(state) · the file on disk still holds it, checked by hash") }
        switch now.kind {
        case .missing: return (.cross, "\(state) · not on disk")
        case .unreadable: return (.attention, "\(state) · the file on disk can’t be read")
        default: return (.cross, "\(state) · the file on disk no longer holds it")
        }
    }

    static func openFailed(_ error: Error) -> String {
        "Couldn’t open it: \(error.localizedDescription)"
    }

    static func saveFailed(_ error: Error, delivery: Delivery) -> String {
        let n = number(delivery)
        return switch error {
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
        switch (capture?.provenance, capture?.kind) {
        case (.atDelivery?, _): (.solid, "Seen at delivery")
        case (.firstSeenAfterDelivery?, _): (.hollow, "First seen later")
        case (.neverObserved?, .special?): (.dashed, "Never read · not a regular file")
        case (.neverObserved?, .unreadable?): (.dashed, "Never read · couldn’t be read")
        case (.neverObserved?, _), (nil, _): (.dashed, "Never seen")
        }
    }

    /// What a list row says beside the date of the delivery it shows (rulings §5): at most one
    /// mark, only when something needs a look, and the delivery's number when the file has several.
    /// `now` is what is at the path as far as the library knows without reading the disk (a check
    /// this session, or gone when the library loaded), nil when neither says; `changed` is true
    /// when a check this session found bytes no delivery had. "First seen later" is the mark when
    /// nothing else needs a look, and otherwise stays with the number.
    static func row(_ delivery: Delivery, latest: Int, now: LocatorState.Kind?, changed: Bool, available: Bool)
        -> (mark: (Mark, String)?, number: String?) {
        let number = latest > 1 ? "Delivery \(delivery.number) of \(latest)" : nil
        let attention: (Mark, String)? = if !available {
            (.attention, "Not available · " + unavailable(delivery, now: now))
        } else if now == .missing {
            (.dashed, "Not on disk")
        } else if changed {
            (.attention, "Changed")
        } else {
            nil
        }
        guard delivery.capture?.provenance == .firstSeenAfterDelivery else { return (attention, number) }
        guard let attention else { return ((.hollow, "First seen later"), number) }
        return (attention, number.map { $0 + " · first seen later" })
    }

    /// Why a row has nothing to hand over, in a few words.
    private static func unavailable(_ delivery: Delivery, now: LocatorState.Kind?) -> String {
        if delivery.sha256 == nil, delivery.capture?.isDirectory != true {
            return delivery.capture?.kind == .missing ? "never seen" : "never read"
        }
        return switch now {
        case .missing?: "not on disk"
        case .unreadable?: "can’t be read"
        case .special?: "not a regular file"
        case .directory?: "a folder is there now"
        case .file?, nil: "changed"
        }
    }

    /// Said where Show Folder was pressed when the folder is gone as well.
    static func folderGone(_ folder: String) -> String {
        "Its folder isn’t on disk either: \((folder as NSString).abbreviatingWithTildeInPath)"
    }

    /// A delivery as one end of a comparison, keeping "first seen later" (SPEC §6).
    static func compareTitle(_ delivery: Delivery) -> String {
        "Delivery \(number(delivery))"
    }

    /// The hand-off panel's heading.
    static func handoffHeading(_ delivery: Delivery) -> String {
        "Hand off delivery \(number(delivery))"
    }

    /// The version the drag tile carries, as its caption and its accessible name say it: a
    /// delivery Gleaner vouches for with these bytes, this delivery, or the current file the
    /// person chose to hand over instead. `staged` is nil until a copy is ready.
    static func tileVersion(staged sha: String?, plan: Handoff, delivery: Delivery, in artifact: Artifact) -> String {
        guard let sha else { return plan == .folder ? "folder as it is now" : "delivery \(number(delivery))" }
        if let trusted = artifact.deliveries.first(where: { $0.sha256 == sha && $0.isTrusted }) { return "delivery \(trusted.number)" }
        return sha == delivery.sha256 ? "delivery \(number(delivery))" : "current file · not a found delivery"
    }

    /// A line of the deliveries list, as VoiceOver reads it. `sameAs` is an earlier delivery with
    /// the same bytes.
    static func deliveryLine(_ delivery: Delivery, sameAs: Delivery?) -> String {
        ["Delivery \(delivery.number)", date(delivery.deliveredAt), provider(delivery.provider),
         provenanceShort(delivery.capture).1.lowercased(),
         sameAs.map { "same content as delivery \(number($0))" }].compactMap { $0 }.joined(separator: ", ")
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
            source.shortenedLogs.isEmpty ? nil : count(source.shortenedLogs.count, "log") + " found shorter than when read before",
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

    /// The badge keeps the exact extension (rulings §7a): the kind groups formats, the badge tells
    /// them apart.
    static func kindLabel(_ kind: Artifact.Kind, path: String) -> String {
        let ext = (path as NSString).pathExtension.uppercased()
        return kind == .folder ? "FOLDER" : (ext.isEmpty ? "FILE" : ext)
    }
}
