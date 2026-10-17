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

enum Palette {
    static let attention = Color(red: 0.54, green: 0.29, blue: 0.0)
    static let attentionFill = Color(red: 1.0, green: 0.96, blue: 0.92)
    static let lost = Color(red: 0.63, green: 0.17, blue: 0.17)
    static let lostFill = Color(red: 1.0, green: 0.96, blue: 0.96)
    static let selection = Color(red: 0.18, green: 0.37, blue: 0.82)
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
        case .rolledBack(let k, let latest):
            return Statement(mark: .attention, title: "Rolled back to delivery \(k)",
                             detail: "The file on disk is delivery \(k) again, not the latest delivery \(latest). \(when)")
        case .changed(let n):
            return Statement(mark: .attention, title: "Changed since delivery \(n)",
                             detail: "Edited after the last delivery. No agent handed you this version. \(when)")
        case .missingWithSavedCopy(let n):
            return Statement(mark: .dashed, title: "Not on disk", detail: "Gleaner saved a copy of delivery \(n). \(when)")
        case .missingInGitHistory:
            return Statement(mark: .dashed, title: "Not on disk", detail: "Git history still has a file at this path. \(when)")
        case .lost:
            return Statement(mark: .cross, title: "Lost",
                             detail: "Not on disk, no saved copy, not in git. The delivery record stays. \(when)")
        case .folder:
            return Statement(mark: .hollow, title: "Folder on disk",
                             detail: "Folders aren’t versioned yet; Gleaner shows the folder as it is now. \(when)")
        case .special:
            return Statement(mark: .cross, title: "Not a regular file",
                             detail: "Gleaner doesn’t open pipes, sockets, or devices. \(when)")
        }
    }

    static func handoff(_ plan: Handoff, delivery n: Int, onDisk: OnDisk) -> Statement {
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
            return Statement(mark: .attention, title: "Delivery \(n) is no longer available",
                             detail: "The file on disk is delivery \(k) again, and Gleaner didn’t save a copy of delivery \(n).")
        case .unavailable(nil, _):
            return Statement(mark: .attention, title: "Delivery \(n) is no longer available",
                             detail: "The file has changed and Gleaner didn’t save a copy: large files are saved only when you choose to. You can hand off the current file, but no agent handed you that version.")
        case .restoreFromGit:
            return Statement(mark: .dashed, title: "Restore it from git first",
                             detail: "Git history has a file at this path. Gleaner can’t confirm it is the delivered version, and doesn’t write to your repository.")
        case .lost:
            return Statement(mark: .cross, title: "Delivery \(n) is lost",
                             detail: "It isn’t on disk, Gleaner didn’t save a copy, and git has no record of it. The delivery record stays so you can see it existed.")
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

    static func storage(_ delivery: Delivery, hasSaved: Bool, current: String?, checked: Bool) -> (Mark, String) {
        guard let capture = delivery.capture, !capture.isDirectory else { return (.hollow, "Folder · not versioned") }
        guard let sha = capture.sha256 else { return (.cross, "Not saved") }
        let size = capture.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        if hasSaved {
            return capture.provenance == .firstSeenAfterDelivery
                ? (.hollow, "Saved copy of what Gleaner first saw (\(size))")
                : (.solid, "Saved copy (\(size))")
        }
        guard checked else { return (.hollow, "Not saved · large file (\(size)), checking…") }
        return current == sha
            ? (.hollow, "Not saved · large file (\(size)), checked by hash")
            : (.cross, "Not saved · this version no longer exists")
    }

    static func kindLabel(_ kind: Artifact.Kind, path: String) -> String {
        let ext = (path as NSString).pathExtension.uppercased()
        return kind == .folder ? "FOLDER" : (ext.isEmpty ? "FILE" : String(ext.prefix(5)))
    }
}
