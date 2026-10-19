import AppKit
import GleanerCore
import GleanerUI
import SwiftUI

enum Wording {
    static func date(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown time"
    }

    /// A list's date, as Mail writes it: the time today, "Yesterday", the day this year, the
    /// full date before.
    static func shortDate(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return date.formatted(.dateTime.day().month(.abbreviated)) }
        return date.formatted(date: .numeric, time: .omitted)
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

    /// A revision as a label names it: "Delivery 2", or "Kept file" for one the person kept from
    /// what a session was observed doing, which no reply delivered (docs/design/review.md). Either
    /// keeps "first seen later".
    static func revision(_ delivery: Delivery) -> String {
        guard delivery.kept != nil else { return "Delivery \(number(delivery))" }
        return "Kept file" + (delivery.capture?.provenance == .firstSeenAfterDelivery ? " (first seen later)" : "")
    }

    /// A revision inside a sentence: "delivery 2", or "the kept file".
    static func revisionInText(_ delivery: Delivery) -> String {
        delivery.kept != nil ? "the " + revision(delivery).lowercased() : "delivery \(number(delivery))"
    }

    /// Revision `n` of `artifact` inside a sentence, as `revisionInText` names it.
    static func revision(_ n: Int, in artifact: Artifact) -> String {
        artifact.deliveries.first { $0.number == n }.map(revisionInText) ?? "delivery \(n)"
    }

    /// "On disk", from what the check `now` found.
    static func onDisk(_ status: OnDisk, in artifact: Artifact, now: FileObservation) -> Statement {
        let when = "Checked \(now.checkedAt.formatted(.relative(presentation: .named)))."
        let latest = artifact.latest
        // Revision `n` where the sentence says "first seen later" itself, and what it came by.
        func plain(_ n: Int) -> String { kept(n) ? "the kept file" : "delivery \(n)" }
        func kept(_ n: Int) -> Bool { artifact.deliveries.first { $0.number == n }?.kept != nil }
        func after(_ n: Int) -> String { kept(n) ? "after the write observed" : "after the delivery" }
        switch status {
        case .same(let n):
            return Statement(mark: .solid, title: "Same as \(revision(n, in: artifact))", detail: "The hash matches. \(when)")
        case .unchangedSinceFirstSeen(let seen):
            return Statement(mark: .hollow, title: "As first seen",
                             detail: "Unchanged since Gleaner first saw it on \(date(seen)), \(after(latest.number)). \(when)")
        case .rolledBack(let k, let latest, nil):
            return Statement(mark: .attention, title: "Back to \(plain(k))",
                             detail: "Not the latest, \(revision(latest, in: artifact)). \(when)")
        case .rolledBack(let k, let latest, let seen?):
            return Statement(mark: .attention, title: "Back to \(plain(k)) as first seen",
                             detail: "Matches what Gleaner first saw for \(plain(k)) on \(date(seen)), \(kept(k) ? "after the write observed" : "after that delivery"). Not the latest, \(revision(latest, in: artifact)). \(when)")
        case .changed(let n) where now.state.kind == .file && latest.capture?.provenance == .listed && kept(n):
            return Statement(mark: .attention, title: "Can’t verify",
                             detail: "You kept this file as a session left it, and Gleaner never read it. It isn’t as observed now: its size, dates or identity differ, so Gleaner can’t tell whether it is the file you kept. \(when)")
        case .changed(let n) where now.state.kind == .file && latest.capture?.provenance == .listed:
            return Statement(mark: .attention, title: "Can’t verify",
                             detail: "Gleaner listed delivery \(n) with its folder and never read it, and this file isn’t as listed: its size, dates or identity differ, so Gleaner can’t tell whether it is that delivery. \(when)")
        case .changed(let n) where now.state.kind == .file && latest.sha256 == nil && latest.capture?.isDirectory != true:
            return Statement(mark: .attention, title: "Can’t verify",
                             detail: "Gleaner never read \(plain(n)), so it can’t tell whether this file is it. \(when)")
        case .changed(let n):
            let what = now.state.kind == .directory ? "A folder is at this path now."
                : artifact.deliveries.allSatisfy({ $0.kept != nil }) ? "Not the bytes Gleaner read of the file you kept."
                : "Not among the deliveries Gleaner found."
            return Statement(mark: .attention, title: "Changed", detail: "\(what) Changed since \(revision(n, in: artifact)). \(when)")
        case .missingWithSavedCopy(let n, nil):
            return Statement(mark: .dashed, title: "Not on disk", detail: "Gleaner has a saved copy of \(plain(n)). \(when)")
        case .missingWithSavedCopy(let n, let seen?):
            return Statement(mark: .dashed, title: "Not on disk",
                             detail: "Gleaner has a saved copy of \(plain(n)), first seen \(date(seen)), \(after(n)). \(when)")
        case .missingInGitHistory:
            return Statement(mark: .dashed, title: "Not on disk", detail: "Git still has a file at this path. \(when)")
        case .lost:
            // Git isn't asked about a folder: nothing in it shows which folder was delivered.
            let why = latest.capture?.isDirectory == true ? "Not on disk. Folders aren’t versioned, so Gleaner has no copy."
                : now.state.git == .notInRepo ? "Not on disk, no saved copy, and not in a git repository."
                : "Not on disk, no saved copy, and not in git at this path."
            return Statement(mark: .cross, title: "Lost", detail: "\(why) \(when)")
        case .folder:
            return Statement(mark: .na, title: "Folder", detail: "Folders aren’t versioned; this is the folder as it is now. \(when)")
        case .special:
            return Statement(mark: .attention, title: "Not a file", detail: "Gleaner doesn’t open pipes, sockets or devices. \(when)")
        case .unreadable:
            return Statement(mark: .failed, title: "Can’t read",
                             detail: "Something is at this path, but Gleaner can’t read it, so it can’t tell which version it is. \(when)")
        }
    }

    /// What the check `now` found at a path that doesn't hold `delivery`'s bytes.
    static func atPath(_ now: LocatorState, delivery: Delivery) -> String {
        switch now.kind {
        case .file: delivery.sha256 == nil ? "A file is at this path now." : "The file on disk has changed since."
        case .directory: "A folder is at this path now."
        case .special: "What is at this path now isn’t a regular file."
        case .unreadable: "Something is at this path, but Gleaner can’t read it."
        case .missing: "The file is no longer on disk."
        }
    }

    /// Why Gleaner keeps none of `delivery`'s bytes, from what it recorded when it first looked:
    /// never seen, not a regular file, unreadable, a folder, too large to have been saved, or a
    /// save that failed; or a copy it saved that its store no longer holds. `large` says the
    /// delivery was over the save limit.
    static func noCopy(_ delivery: Delivery, large: Bool) -> String {
        let r = revisionInText(delivery), R = revision(delivery)
        if delivery.capture?.provenance == .listed {
            return delivery.kept != nil ? "You kept the file as a session left it, and Gleaner hasn’t read it."
                : "Gleaner listed \(r) with its folder and hasn’t read it."
        }
        switch delivery.capture?.kind {
        case nil:
            return "Gleaner has no record of \(r)’s bytes."
        case .directory?:
            return "\(R) was a folder. Folders aren’t versioned."
        case .special?:
            return "Gleaner never read \(r): it wasn’t a regular file then."
        case .unreadable?:
            return "Gleaner never read \(r): it couldn’t be read then."
        case .missing?:
            return "Gleaner never saw \(r): nothing was at this path then."
        case .file? where delivery.capture?.savedAt != nil:
            return "Gleaner’s saved copy of \(r) is no longer in its store."
        case .file?:
            return large ? "\(R) was too large to save without asking." : "Saving \(r) failed when Gleaner read it."
        }
    }

    /// What a drag of `delivery` hands over, from what the check `now` found. When there is
    /// nothing, it says why, and offers only what the panel can do.
    static func handoff(_ plan: Handoff, delivery: Delivery, in artifact: Artifact, now: LocatorState, large: Bool) -> Statement {
        let r = revisionInText(delivery), R = revision(delivery)
        // "No longer" only for bytes Gleaner had: not for a delivery it never read, nor for a file
        // it can't read now.
        let unavailable = now.kind == .unreadable ? "\(R) isn’t available now"
            : delivery.sha256 == nil && delivery.capture?.isDirectory != true ? "\(R) isn’t available"
            : "\(R) is no longer available"
        switch plan {
        case .ready(_, .original, nil):
            return Statement(mark: .solid, title: "Verified",
                             detail: "The file on disk is \(r). Gleaner hands over a copy it checked, so later edits can’t slip in.")
        case .ready(_, .savedCopy, nil):
            return Statement(mark: .solid, title: "Verified",
                             detail: "\(atPath(now, delivery: delivery)) Gleaner hands over its saved copy of \(r), checked by hash.")
        case .ready(_, _, let seen?) where delivery.kept != nil:
            return Statement(mark: .hollow, title: "First seen later",
                             detail: "Gleaner first saw these bytes on \(date(seen)), after the write observed. They may differ from the file as the session left it.")
        case .ready(_, _, let seen?):
            return Statement(mark: .hollow, title: "First seen later",
                             detail: "Gleaner first saw these bytes on \(date(seen)), after the delivery. They may differ from what was delivered.")
        case .unavailable(let k?, _):
            let other = artifact.deliveries.first { $0.number == k }
            let firstSeen = other?.capture?.provenance == .firstSeenAfterDelivery
            let again = firstSeen ? "matches what Gleaner first saw for \(other?.kept != nil ? "the kept file" : "delivery \(k)")"
                : "is \(revision(k, in: artifact)) again"
            return Statement(mark: .attention, title: unavailable,
                             detail: "The file on disk \(again). \(noCopy(delivery, large: large))")
        case .unavailable(nil, let current):
            let found = artifact.deliveries.allSatisfy { $0.kept != nil } ? "the file you kept" : "a delivery Gleaner found"
            let offer = current == nil ? "" : " You can hand off the current file instead; it isn’t \(found)."
            return Statement(mark: .attention, title: unavailable,
                             detail: "\(atPath(now, delivery: delivery)) \(noCopy(delivery, large: large))" + offer)
        case .restoreFromGit:
            return Statement(mark: .dashed, title: "Restore from git first",
                             detail: "Git has a file at this path, but Gleaner can’t confirm it’s \(delivery.kept != nil ? "the file you kept" : "this delivery"), and never writes to your repository.")
        case .lost:
            // Git isn't asked about a folder: nothing in it shows which folder was delivered.
            let git = delivery.capture?.isDirectory == true ? ""
                : now.git == .notInRepo ? ", and it isn’t in a git repository" : ", and git has nothing at this path"
            return Statement(mark: .cross, title: "\(R) is lost",
                             detail: "It isn’t on disk\(git). \(noCopy(delivery, large: large))")
        case .folder:
            return Statement(mark: .na, title: "Folder", detail: "Dragging hands over the folder as it is now. Folders aren’t verified.")
        }
    }

    /// A revision's bytes, as recorded: seen when it came, first seen later, never read, or listed
    /// and not read yet. A file the person `kept` came as a session left it, not with a reply.
    static func provenance(_ capture: Capture?, kept: Bool = false) -> (Mark, String) {
        guard let capture else { return (.dashed, "Not captured") }
        switch (capture.provenance, capture.kind) {
        case (.atDelivery, _): return (.solid, kept ? "Seen as observed" : "Seen at delivery")
        case (.firstSeenAfterDelivery, _):
            return (.hollow, "First seen \(date(capture.observedAt)), after " + (kept ? "the write observed" : "delivery"))
        case (.neverObserved, .special): return (.dashed, "Never read: not a regular file")
        case (.neverObserved, .unreadable): return (.dashed, "Never read: couldn’t be read")
        case (.neverObserved, _): return (.dashed, "Never seen: nothing at this path")
        case (.listed, _) where kept: return (.dashed, "Kept as observed, not read yet")
        case (.listed, _): return (.dashed, "Listed with its folder \(date(capture.observedAt)), not read yet")
        }
    }

    /// Where `delivery`'s bytes are kept; when they aren't, why, and what the check `now` found
    /// (nil until the file is checked).
    static func storage(_ delivery: Delivery, hasSaved: Bool, large: Bool, now: LocatorState?) -> (Mark, String) {
        guard let capture = delivery.capture else { return (.dashed, "Not saved: not captured") }
        if capture.isDirectory { return (.na, "Folder: not versioned") }
        if capture.provenance == .listed { return (.dashed, delivery.kept != nil ? "Not saved: kept, not read yet" : "Not saved: listed, not read yet") }
        guard let sha = capture.sha256 else { return (.cross, "Not saved: never read") }
        let size = capture.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        if hasSaved {
            return capture.provenance == .firstSeenAfterDelivery
                ? (.hollow, "Saved copy of what Gleaner first saw, \(size)")
                : (.solid, "Saved copy, \(size)")
        }
        let state = capture.savedAt != nil ? "Saved copy gone from Gleaner’s store, \(size)"
            : large ? "Not saved: too large, \(size)" : "Not saved: saving failed, \(size)"
        guard let now else { return (.running, "\(state); checking…") }
        if now.sha256 == sha { return (.hollow, "\(state); the file on disk still holds it") }
        switch now.kind {
        case .missing: return (.cross, "\(state); not on disk")
        case .unreadable: return (.failed, "\(state); the file on disk can’t be read")
        default: return (.cross, "\(state); the file on disk no longer holds it")
        }
    }

    static func openFailed(_ error: Error) -> String {
        "Couldn’t open it: \(error.localizedDescription)"
    }

    static func saveFailed(_ error: Error, delivery: Delivery) -> String {
        let r = revisionInText(delivery)
        return switch error {
        case ContentStore.Failure.changed:
            "The file changed before Gleaner could save it; it no longer holds \(r)."
        case ContentStore.Failure.unavailable:
            "Gleaner couldn’t read \(r)’s bytes at this path."
        default:
            "Couldn’t save a copy: \(error.localizedDescription)"
        }
    }

    /// A version row's mark and words: the mark alone when Gleaner saw the bytes at delivery,
    /// which is the rule; words for the exception.
    static func provenanceShort(_ capture: Capture?, kept: Bool = false) -> (Mark, String) {
        switch (capture?.provenance, capture?.kind) {
        case (.atDelivery?, _): (.solid, kept ? "Seen as observed" : "Seen at delivery")
        case (.firstSeenAfterDelivery?, _): (.hollow, "First seen later")
        case (.neverObserved?, .special?): (.dashed, "Never read")
        case (.neverObserved?, .unreadable?): (.dashed, "Never read")
        case (.neverObserved?, _), (nil, _): (.dashed, "Never seen")
        case (.listed?, _): (.dashed, kept ? "Kept, not read" : "Listed, not read")
        }
    }

    /// What a list row says beside the date of the delivery it shows (rulings §5): at most one
    /// mark, only when something needs a look, and the delivery's number when it is not the file's
    /// newest: the row's count already says how many there are.
    /// `now` is what is at the path as far as the library knows without reading the disk (a check
    /// this session, or gone when the library loaded), nil when neither says; `changed` is true
    /// when a check this session found bytes no delivery had. "First seen later" is the mark when
    /// nothing else needs a look, and otherwise stays with the number.
    static func row(_ delivery: Delivery, latest: Int, now: LocatorState.Kind?, changed: Bool, available: Bool)
        -> (mark: (Mark, String)?, number: String?) {
        let name = delivery.kept != nil ? "Kept file" : "Delivery \(delivery.number)"
        let number = delivery.number != latest ? name + " of \(latest)" : nil
        let attention: (Mark, String)? = available ? fileState(now: now, changed: changed) : (.attention, "Unavailable · " + unavailable(delivery, now: now))
        guard delivery.capture?.provenance == .firstSeenAfterDelivery else { return (attention, number) }
        guard let attention else { return ((.hollow, "First seen later"), number) }
        return (attention, (number ?? name) + " · first seen later")
    }

    /// What a row says of the file itself, whichever delivery it names: gone, or holding bytes no
    /// delivery had. An open work's row says only this; its revisions say the rest.
    static func fileState(now: LocatorState.Kind?, changed: Bool) -> (Mark, String)? {
        if now == .missing { return (.dashed, "Not on disk") }
        return changed ? (.attention, "Changed") : nil
    }

    /// Why a row has nothing to hand over, in a sentence, for its help tag and VoiceOver: what is
    /// at the path, as the library knows it without reading the disk, then why Gleaner keeps no copy.
    static func unavailableReason(_ delivery: Delivery, now: LocatorState.Kind?, large: Bool) -> String {
        if delivery.sha256 == nil, delivery.capture?.isDirectory != true { return noCopy(delivery, large: large) }
        let at = switch now {
        case .missing?: delivery.capture?.isDirectory == true ? "The folder is no longer on disk." : "The file is no longer on disk."
        case .unreadable?: "Something is at this path, but Gleaner can’t read it."
        case .special?: "What is at this path now isn’t a regular file."
        case .directory?: "A folder is at this path now."
        case .file?, nil: "The file on disk has changed since."
        }
        return at + " " + noCopy(delivery, large: large)
    }

    /// Why a row has nothing to hand over, in a few words.
    private static func unavailable(_ delivery: Delivery, now: LocatorState.Kind?) -> String {
        if delivery.sha256 == nil, delivery.capture?.isDirectory != true {
            return delivery.capture?.provenance == .listed ? "not read" : delivery.capture?.kind == .missing ? "never seen" : "never read"
        }
        return switch now {
        case .missing?: "not on disk"
        case .unreadable?: "can’t read"
        case .special?: "not a file"
        case .directory?: "a folder now"
        case .file?, nil: "changed"
        }
    }

    /// Said where Show Folder was pressed when the folder is gone as well.
    static func folderGone(_ folder: String) -> String {
        "Its folder is gone too: \(tilde(folder))"
    }

    /// A delivery as one end of a comparison, keeping "first seen later" (SPEC §6).
    static func compareTitle(_ delivery: Delivery) -> String {
        revision(delivery)
    }

    /// The version the drag tile carries, as its caption and its accessible name say it: a
    /// delivery Gleaner vouches for with these bytes, this delivery, or the current file the
    /// person chose to hand over instead. `staged` is nil until a copy is ready.
    static func tileVersion(staged sha: String?, plan: Handoff, delivery: Delivery, in artifact: Artifact) -> String {
        guard let sha else { return plan == .folder ? "folder as it is now" : revisionInText(delivery) }
        if let trusted = artifact.deliveries.first(where: { $0.sha256 == sha && $0.isTrusted }) {
            return trusted.kept != nil ? "the kept file" : "delivery \(trusted.number)"
        }
        return sha == delivery.sha256 ? revisionInText(delivery) : "current file · not a found delivery"
    }

    /// A line of the versions list, as VoiceOver reads it. `sameAs` is an earlier delivery with
    /// the same bytes.
    static func deliveryLine(_ delivery: Delivery, sameAs: Delivery?) -> String {
        [delivery.kept != nil ? "Kept file" : "Delivery \(delivery.number)", date(delivery.deliveredAt), provider(delivery.provider),
         provenanceShort(delivery.capture, kept: delivery.kept != nil).1.lowercased(),
         sameAs.map { "same content as \(revisionInText($0))" }].compactMap { $0 }.joined(separator: ", ")
    }

    /// Names the bytes on screen and in the drag tile, so the preview never speaks for another
    /// version: the header's caption, under the file's name.
    static func bytesCaption(_ plan: Handoff?, staged sha: String?, delivery: Delivery) -> String {
        switch plan {
        case .folder?:
            return "Folder as it is now"
        case .ready(_, let from, let seen)?:
            let source = from == .original ? "file on disk" : "saved copy"
            return (delivery.kept != nil ? "Kept file" : "Delivery \(delivery.number)") + " · \(source)" + (seen == nil ? "" : " · first seen later")
        case .unavailable(_, let current?)? where sha == current:
            return "Current file · not a found delivery"
        default:
            return revision(delivery)
        }
    }

    static func provider(_ provider: Provider) -> String {
        AgentMark.Agent(provider).name
    }

    /// One agent's log folder as last read (SPEC §8): not on this Mac, unreadable, read with
    /// problems, or read.
    static func source(_ source: Indexer.Report.Source) -> (Mark, String) {
        switch source.folder {
        case .absent: (.dashed, "Not on this Mac")
        case .unreadable: (.failed, "Can’t read")
        case .listed where source.hasProblems: (.attention, "Read with problems")
        case .listed: (.done, "Read")
        }
    }

    /// What went wrong reading a listed folder, counted; nil when nothing did.
    static func problems(_ source: Indexer.Report.Source) -> String? {
        let parts = [
            source.unknownRecordTypes.isEmpty ? nil : count(source.unknownRecordTypes.count, "unknown record type"),
            source.partialLogs.isEmpty ? nil : count(source.partialLogs.count, "log") + " with malformed lines",
            source.shortenedLogs.isEmpty ? nil : count(source.shortenedLogs.count, "log") + " shorter than before",
            source.failures.isEmpty ? nil : count(source.failures.count, "log") + " unreadable",
            source.unlistedFolders.isEmpty ? nil : count(source.unlistedFolders.count, "folder") + " unlisted",
            source.workspaceProblems.isEmpty ? nil : count(source.workspaceProblems.count, "workspace problem"),
            source.folderProblems.isEmpty ? nil : count(source.folderProblems.count, "delivered folder problem"),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
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

    static func count(_ n: Int, _ noun: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? noun : plural)"
    }

    // MARK: Projects, works and corrections

    /// A project's origin as a mark: a repository, a folder outside git, or the person's own.
    static func projectGlyph(_ origin: Organization.Project.Origin) -> Glyph {
        switch origin {
        case .repository: .repository
        case .folder: .folder
        case .yours: .person
        }
    }

    /// What a project is, in words, for VoiceOver and anywhere its mark stands alone.
    static func projectOrigin(_ origin: Organization.Project.Origin) -> String {
        switch origin {
        case .repository: "Git repository"
        case .folder: "Folder outside git"
        case .yours: "Your project"
        }
    }

    /// What a project holds, in one line: its works, its deliveries, its latest.
    static func projectCounts(_ project: Organization.Project) -> String {
        let deliveries = project.works.map(\.deliveries.count).reduce(0, +)
        return [count(project.works.count, "work"), count(deliveries, "delivery", "deliveries"),
                project.latest.map { "latest \(shortDate($0))" }].compactMap { $0 }.joined(separator: " · ")
    }

    /// Why a work is in the project it is shown in: a short label, and the sentence behind it.
    static func placement(_ placement: Organization.Placement, of work: Work, organization: Organization) -> Statement {
        let file = work.latest
        let found: String
        if file.inRepository, let checkout = file.checkout {
            let place = checkout.folder == checkout.repository ? "" : ", worktree \((checkout.folder as NSString).lastPathComponent)"
            found = "Found in the git repository at \(tilde(checkout.repository))\(place)."
        } else if file.inRepository {
            found = "Its agent worked in the git repository at \(tilde(file.projectFolder)); the file is outside it."
        } else {
            found = "Outside git. Grouped by the folder its agent worked in, \(tilde(file.projectFolder))."
        }
        switch placement {
        case .found:
            return Statement(mark: .solid, title: "Found here", detail: found)
        case .moved(let correction):
            return Statement(mark: .solid, title: "Moved here by you",
                             detail: "You moved it here on \(date(correction.madeAt)). Gleaner found it in \(organization.projectName(file.projectFolder)).")
        case .combined(let folder, let correction):
            return Statement(mark: .solid, title: "Shown inside",
                             detail: "\(found) You show \(organization.projectName(folder)) inside this project, since \(date(correction.madeAt)).")
        }
    }

    /// Gleaner's reason in a few words, and in full naming the deliveries it compared: "latest"
    /// is not a version.
    static func suggestionReason(_ suggestion: Organization.Suggestion, in organization: Organization) -> (short: String, full: String) {
        let name = { (path: String) in (path as NSString).lastPathComponent }
        let earlier = organization.work(containing: suggestion.earlier)?.files.first { $0.path == suggestion.earlier }
        let later = organization.work(containing: suggestion.later)?.files.first { $0.path == suggestion.later }
        switch suggestion.reason {
        case .moved:
            let last = earlier.map { " delivery \($0.latest.number)" } ?? "", first = later?.deliveries.last.map { " delivery \($0.number)" } ?? ""
            return ("Same bytes, earlier file gone",
                    "\(name(suggestion.later))\(first) has the exact bytes of \(name(suggestion.earlier))\(last), which is no longer at its path: it may have been renamed or moved.")
        case .versionName:
            return ("Names differ by a version mark",
                    "They share a folder, and their names differ only by a version mark such as v2 or final.")
        }
    }

    /// Where a sibling link goes.
    static func siblingHelp(_ delivery: Delivery) -> String {
        "\((delivery.path as NSString).lastPathComponent), delivery \(number(delivery))"
    }

    static func resume(_ resume: Resume) -> String {
        switch resume {
        case .command: ""
        case .logGone: "Can’t resume: its log is gone."
        case .folderGone(let folder): "Can’t resume: \(tilde(folder)) is gone."
        case .folderUnknown: "Can’t resume: the log doesn’t name its folder."
        }
    }

    // MARK: Sources

    /// How one agent's logs last read, with when.
    static func sourceStatement(_ source: Indexer.Report.Source?, indexed: Bool) -> Statement {
        guard let source else {
            return indexed ? Statement(mark: .dashed, title: "Not read", detail: "The last read stopped before this source.")
                : Statement(mark: .running, title: "Reading…", detail: "Gleaner is reading the logs.")
        }
        let state = self.source(source)
        let detail: String = switch source.folder {
        case .absent: "No such folder on this Mac."
        case .unreadable(let reason): "Gleaner couldn’t list the folder: \(reason). The library keeps what it holds."
        case .listed: problems(source).map { $0.prefix(1).uppercased() + $0.dropFirst() + "." } ?? "Every log read whole."
        }
        return Statement(mark: state.0, title: state.1, detail: detail)
    }

    /// What Gleaner takes from an agent's logs, as label and value.
    static func reads(_ provider: Provider) -> [(String, String)] {
        switch provider {
        case .claudeCode: [
            ("Replies", "The text after the last tool call of each turn"),
            ("Files", "Named in a reply by a link, an image or a path with a folder"),
            ("Copies", "Each file read at once, saved up to 64 MB"),
            folders,
            workspaces,
        ]
        case .codex: [
            ("Replies", "Final answers (phase final_answer)"),
            ("Titles", "From session_index.jsonl"),
            ("Files", "Named in an answer by a link, an image or a path with a folder"),
            ("Copies", "Each file read at once, saved up to 64 MB"),
            folders,
            workspaces,
        ]
        }
    }

    /// What Gleaner reads of a folder a reply handed over.
    private static let folders = ("Folders", "Names, sizes and dates of the files in a delivered folder, each read when you act on it")

    /// What Gleaner reads of the folders conversations worked in.
    private static let workspaces = ("Workspaces", "Names, sizes and dates of the files that appeared or changed during a conversation, never their contents")

    // MARK: Review

    /// The name of a verdict or a mark on Edit › Undo, as its control names it.
    static func reviewAction(_ kind: Review.Kind) -> String {
        switch kind {
        case .approved: "Approve"
        case .changesRequested: "Request Changes"
        case .rejected: "Reject"
        case .published: "Mark Published"
        }
    }

    /// What making verdicts or marks did, for VoiceOver.
    static func reviewed(_ kind: Review.Kind, count n: Int) -> String {
        let what = switch kind {
        case .approved: "Approved"
        case .changesRequested: "Requested changes to"
        case .rejected: "Rejected"
        case .published: "Marked published"
        }
        return "\(what) \(count(n, "work"))"
    }

    /// In place of a video or audio AVFoundation finds nothing to play in.
    static let unplayable = "Gleaner can’t play this file here, so it is judged on its own Review menu, not with Review All."

    /// A note sheet's title: the verdict or mark about to be made, and on what, one work by its name
    /// or several by their count ("Request Changes to “script.md”", "Mark 3 Works Published").
    static func reviewTitle(_ kind: Review.Kind, names: [String]) -> String {
        let what = names.count == 1 ? "“\(names[0])”" : count(names.count, "Work")
        return switch kind {
        case .approved: "Approve \(what)"
        case .changesRequested: "Request Changes to \(what)"
        case .rejected: "Reject \(what)"
        case .published: "Mark \(what) Published"
        }
    }

    /// Verdicts or marks asked for together that weren't all made: how many were, then why each
    /// other wasn't. "Nothing recorded" only when none was.
    static func refusal(_ refusal: ReviewRefusal) -> Statement {
        let title = refusal.made == 0 ? "Nothing recorded"
            : "\(reviewed(refusal.kind, count: refusal.made)), \(refusal.refused.count) not recorded"
        return Statement(mark: .attention, title: title, detail: refusal.refused.map(\.reason).joined(separator: " "))
    }

    /// What deleting a project of the person's own does, said before it is done: its work goes
    /// back, and the collections made in it go with it, for good.
    static func deletingProject(units: Int) -> String {
        guard units > 0 else { return "Its work goes back where Gleaner found it. No file changes." }
        return "Its work goes back where Gleaner found it, and its \(count(units, "collection")) \(units == 1 ? "is" : "are") deleted. "
            + "You can’t undo this. No file changes."
    }

    /// Why a verdict or a mark wasn't made on the file `name`. Unreadable is never said as gone.
    static func reviewFailed(_ error: Error, name: String) -> String {
        switch error {
        case Review.Failure.notAFile(.missing): "\(name) isn’t on this Mac, so there are no bytes to judge."
        case Review.Failure.notAFile(.directory): "\(name) is a folder, which has no bytes of its own to judge."
        case Review.Failure.notAFile(.special): "\(name) isn’t a regular file, so Gleaner doesn’t read it."
        case Review.Failure.notAFile: "\(name) can’t be read, so Gleaner can’t tell which bytes you judged."
        case Review.Failure.changedSinceShown: "\(name) changed since it was shown. Look at it again, then decide."
        case Review.Failure.changedWhileRead: "\(name) changed while Gleaner read it. Look at it again, then decide."
        default: "Couldn’t record that for \(name): \(error.localizedDescription)"
        }
    }

    /// A verdict or a mark by its name, as its state says it.
    static func reviewName(_ kind: Review.Kind) -> String {
        switch kind {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .rejected: "Rejected"
        case .published: "Published"
        }
    }

    /// A verdict's or a mark's own mark: the check, the open arrow, the crossed circle, the tray.
    static func reviewMark(_ kind: Review.Kind) -> Mark {
        switch kind {
        case .approved: .done
        case .changesRequested: .revise
        case .rejected: .declined
        case .published: .published
        }
    }

    /// A verdict or a mark as made: when, its note or place, and the bytes it binds to, those
    /// hashed when it was made, never the path nor what was shown before.
    static func made(_ review: Review) -> String {
        let note = review.note.map { review.kind == .published ? ", at \($0)" : ": “\($0)”" } ?? ""
        return "\(reviewName(review.kind)) \(date(review.madeAt))\(note). Bound to the bytes hashed when it was made, \(review.sha256.prefix(8))."
    }

    /// The Reviewed state of a work's current file (docs/design/review.md, The four states): the
    /// newest verdict on these bytes, or why none holds. In a collection, a file with none waits on
    /// the person, in the one accent, unless no file Gleaner can read is there (`noFile`): that
    /// can't be reviewed, and needs a look instead. "Changed" only once the bytes were read; a file
    /// Gleaner can't read keeps its verdict as made, and is never called gone.
    static func verdict(_ standing: Standing, inUnit: Bool, noFile: Bool = false) -> Statement {
        switch standing {
        case .none:
            !inUnit ? Statement(mark: .dashed, title: "Not reviewed", detail: "No verdict on any of its bytes.")
                : noFile ? Statement(mark: .attention, title: "Can’t be reviewed",
                                     detail: "No verdict yet, and no file Gleaner can read is at its path to judge. It waits in its collection until the file is back or you remove it.")
                : Statement(mark: .awaiting, title: "To review", detail: "No verdict on these bytes yet. It waits in its collection.")
        case .current(let review):
            Statement(mark: reviewMark(review.kind), title: reviewName(review.kind), detail: made(review))
        case .mayHaveChanged(let review):
            Statement(mark: .attention, title: "May have changed since review",
                      detail: "\(made(review)) The file isn’t as it was then, and Gleaner hasn’t read it since, so it can’t tell whether these are the bytes judged.")
        case .changed(let review):
            Statement(mark: .attention, title: "Changed since review",
                      detail: "\(made(review)) Gleaner read other bytes there since, and no verdict was made on them.")
        case .unavailable(let review):
            Statement(mark: reviewMark(review.kind), title: reviewName(review.kind),
                      detail: "\(made(review)) No file Gleaner can read is at its path now; the verdict stands as made.")
        }
    }

    /// The Published state of a work's current file, read as verdicts are, on its own: published
    /// says nothing of a verdict, nor a verdict of publishing.
    static func publishedState(_ standing: Standing) -> Statement {
        switch standing {
        case .none:
            Statement(mark: .dashed, title: "Not published", detail: "You haven’t marked these bytes published.")
        case .current(let mark):
            Statement(mark: .published, title: "Published", detail: made(mark))
        case .mayHaveChanged(let mark):
            Statement(mark: .attention, title: "May have changed since published",
                      detail: "\(made(mark)) The file isn’t as it was then, and Gleaner hasn’t read it since, so it can’t tell whether these are the bytes marked.")
        case .changed(let mark):
            Statement(mark: .attention, title: "Changed since published",
                      detail: "\(made(mark)) Gleaner read other bytes there since; they aren’t marked published.")
        case .unavailable(let mark):
            Statement(mark: .published, title: "Published",
                      detail: "\(made(mark)) No file Gleaner can read is at its path now; the mark stands as made.")
        }
    }

    /// What waits on the person, on a work's row: nothing when nothing does.
    static func waiting(_ standing: Standing, inUnit: Bool, noFile: Bool = false) -> (Mark, String)? {
        switch standing {
        case .none: !inUnit ? nil : noFile ? (.attention, "Can’t be reviewed") : (.awaiting, "To review")
        case .mayHaveChanged: (.attention, "May have changed since review")
        case .changed: (.attention, "Changed since review")
        case .current, .unavailable: nil
        }
    }

    /// The Generated state of a work's current file: how it came, as recorded. A kept file came as
    /// a session left it, by the person's decision, never by a reply.
    static func generated(_ delivery: Delivery) -> (title: String, detail: String) {
        if let kept = delivery.kept {
            let during = session(delivery.sessionTitle)
            return ("Kept by you, observed during \(during)",
                    "You kept it \(date(kept.keptAt)). It \(kept.observed == .appeared ? "appeared" : "changed") while \(during) was working. No reply handed it over.")
        }
        if let member = delivery.member {
            return ("Handed over in \(folderName(member))",
                    "\(provider(delivery.provider))’s reply named the folder \(folderName(member)) \(date(delivery.deliveredAt)), and the file was in it.")
        }
        return ("Named in a reply", "\(provider(delivery.provider))’s reply named it \(date(delivery.deliveredAt)).")
    }

    /// The On this Mac state of a work's current file, as the library knows it without reading:
    /// there, changed, gone, unreadable, a folder or not a regular file, each said as itself (A20).
    /// Unreadable is never said as gone or changed.
    static func onThisMac(_ now: LocatorState.Kind?, changed: Bool) -> Statement {
        switch now {
        case .missing?: Statement(mark: .dashed, title: "Not on disk", detail: "Nothing is at its path on this Mac now.")
        case .unreadable?: Statement(mark: .failed, title: "Can’t read", detail: "Something is at its path, but Gleaner can’t read it.")
        case .special?: Statement(mark: .attention, title: "Not a file", detail: "What is at its path isn’t a regular file.")
        case .directory?: Statement(mark: .na, title: "Folder", detail: "A folder, as it is now, with no bytes of its own to judge.")
        case .file?, nil:
            changed ? Statement(mark: .attention, title: "Changed", detail: "The file on disk holds bytes no revision had.")
                : Statement(mark: .done, title: "On this Mac", detail: "The file is at its path.")
        }
    }

    /// A collection as a list names it: inside another, after it ("Launch › Assets").
    static func unitPath(_ unit: WorkUnit, in organization: Organization) -> String {
        unit.parent.map { organization.unitName($0) + " › " + unit.name } ?? unit.name
    }

    /// What a collection holds, in one line: the collections inside it, then its own works.
    static func unitCounts(works: Int, units: Int) -> String {
        [units > 0 ? count(units, "collection") : nil, count(works, "work")].compactMap { $0 }.joined(separator: " · ")
    }

    /// How many works wait on the person: "3 to review".
    static func toReview(_ n: Int) -> String { "\(n) to review" }

    /// A line of a work's review history, as VoiceOver reads it: what, when, which file and bytes.
    static func historyLine(_ review: Review, file: String?) -> String {
        [reviewName(review.kind), date(review.madeAt), file, "hash \(review.sha256.prefix(8))", review.note]
            .compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: Observations

    /// A conversation as an observation names it.
    static func session(_ title: String?) -> String {
        title ?? "an untitled conversation"
    }

    /// What was observed of a file during a conversation, in the three tiers (window-polish.md,
    /// Fewer words): the observed mark; "Appeared during …" or "Changed during …"; and the sentence
    /// saying what that shows and what it doesn't. Never "made": a date in a span doesn't say who
    /// wrote the file, nor, for a modification date, that its contents changed. The time shown is
    /// the stretch the date falls in, from a request to the last reply answering it, not the whole
    /// conversation, which may have been resumed days later.
    static func observed(_ observation: Observed) -> Statement {
        let during = session(observation.sessionTitle)
        let stretch = observation.stretch.map { " (\(($0.start..<$0.end).formatted(date: .abbreviated, time: .shortened)))" } ?? ""
        let place = "in \(tilde(observation.workspace))"
        return switch observation.kind {
        case .appeared:
            Statement(mark: .observed, title: "Appeared during \(during)",
                      detail: "Its creation date, \(date(observation.createdAt)), falls while \(during) was working\(stretch), \(place). "
                          + "That says when it appeared, not who wrote it. Gleaner hasn’t read its contents.")
        case .changed:
            Statement(mark: .observed, title: "Changed during \(during)",
                      detail: "Its modification date, \(date(observation.modifiedAt)), falls while \(during) was working\(stretch), \(place). "
                          + "That says when it was last written, not who wrote it or what changed. Gleaner hasn’t read its contents.")
        }
    }

    /// A folder's observed files of one kind, folded into one row: "out/voice · 211 files".
    static func folded(_ folder: String, count n: Int) -> String {
        "\(self.folder(folder)) · \(count(n, "file"))"
    }

    /// Files of one kind folded into one row under their folder's heading: "Video & Audio · 211 files".
    static func folded(_ kind: Artifact.Kind, count n: Int) -> String {
        "\(kindName(kind)) · \(count(n, "file"))"
    }

    // MARK: Folders handed over

    /// The folder a file was handed over in, as its link names it: "out/".
    static func folderName(_ member: Membership) -> String {
        (member.folder as NSString).lastPathComponent + "/"
    }

    /// What listing a delivered folder's files found, for its detail: how many were handed over in
    /// it, or why they aren't listed, and what the listing couldn't see.
    static func unpacking(_ unpacking: Unpacking?) -> Statement {
        guard let unpacking else {
            return Statement(mark: .dashed, title: "Not listed yet",
                             detail: "Gleaner lists a delivered folder’s files the next time it reads the logs while the folder is there and can be read.")
        }
        if let reason = unpacking.notUnpacked {
            let project = unpacking.pointsAtProject ? " Handing over a project’s own folder points at the project; what changed there is observed instead." : ""
            return Statement(mark: .na, title: "Not unpacked", detail: "Gleaner doesn’t list its files as handed over: it is \(reason).\(project)")
        }
        let listed = "Listed \(date(unpacking.listedAt)) by name, size and dates, without reading them: the files their dates show were in it, unchanged, when the reply named it, hidden ones left out and a package as one. Each file is read when you select, open, compare or hand it on."
            + without(unpacking.repositories)
        guard unpacking.problems.isEmpty else {
            return Statement(mark: .attention, title: "\(count(unpacking.members, "file")), listed in part",
                             detail: listed + " The listing couldn’t see everything: " + unpacking.problems.map(tilde).joined(separator: "; ") + ".")
        }
        return Statement(mark: .done, title: count(unpacking.members, "file"), detail: listed)
    }

    /// The repositories a folder's listing left out, each another project, named by where they are in it.
    private static func without(_ repositories: [String]) -> String {
        switch repositories.count {
        case 0: ""
        case 1: " It was listed without the Git repository inside it, \(repositories[0]), which is another project."
        default: " It was listed without the Git repositories inside it, which are other projects: \(repositories.joined(separator: ", "))."
        }
    }

    /// Before Gleaner reads two deliveries' bytes, all it can say is that their size and dates match:
    /// "dates" when both recorded the file's creation date with its modification date, else the
    /// modification date alone.
    static func sameSizeAndDates(_ earlier: Delivery, as delivery: Delivery, named: Bool) -> String {
        let dates = earlier.capture?.createdAt != nil && delivery.capture?.createdAt != nil ? "dates" : "modification date"
        return "Same size and \(dates) as " + (named ? (earlier.path as NSString).lastPathComponent + " " : "") + number(earlier)
    }

    /// Delivered folders that are gone, folded into one row in Sources.
    static func foldersGone(_ n: Int) -> String {
        count(n, "folder") + " gone"
    }

    /// What the adapter leaves out: these aren't replies to the person (SPEC §8).
    static func skips(_ provider: Provider) -> [String] {
        switch provider {
        case .claudeCode: [
            "Sub-agent transcripts and side chains",
            "Messages before a turn’s last tool call",
            "Fenced code, line references and placeholder paths",
        ]
        case .codex: [
            "Sub-agent threads",
            "Messages a fork copied from its parent",
            "Fenced code, line references and placeholder paths",
        ]
        }
    }

    /// The window's subtitle: what the library holds.
    static func library(works: Int, deliveries: Int) -> String {
        "\(count(works, "work")) · \(count(deliveries, "delivery", "deliveries"))"
    }

    static let preparedCopyChanged = "Another app changed Gleaner’s prepared copy. It’s being prepared again; try once more in a moment."

    static func tilde(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    /// A folder as the outline names it: "Top level" for the agent's own.
    static func folder(_ folder: String) -> String { folder == "." || folder.isEmpty ? "Top level" : folder }

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

    /// The exact extension (rulings §7a), for where the file's own icon is read aloud or hovered:
    /// the kind groups formats, the extension tells them apart.
    static func kindLabel(_ kind: Artifact.Kind, path: String) -> String {
        let ext = (path as NSString).pathExtension.uppercased()
        return kind == .folder ? "FOLDER" : (ext.isEmpty ? "FILE" : ext)
    }
}
