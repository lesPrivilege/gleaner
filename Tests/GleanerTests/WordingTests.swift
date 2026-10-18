import Foundation
import GleanerUI
import Testing
@testable import Gleaner
@testable import GleanerCore

@Suite struct WordingTests {
    let delivered = Date(timeIntervalSince1970: 1_790_000_000)

    /// Delivery `number` of /p/out/demo.mp4, as Gleaner recorded it when it first looked.
    func delivery(_ number: Int, _ kind: LocatorState.Kind, sha: String? = nil, saved: Bool = false,
                  provenance: Provenance? = nil) -> Delivery {
        let read = sha != nil || kind == .directory
        let capture = Capture(sha256: sha, size: sha == nil ? nil : 4_000_000, modifiedAt: nil, observedAt: delivered,
                              savedAt: saved ? delivered : nil, provenance: provenance ?? (read ? .atDelivery : .neverObserved),
                              kind: kind)
        return Delivery(id: "d\(number)", number: number, path: "/p/out/demo.mp4", deliveredAt: delivered, provider: .claudeCode,
                        sessionTitle: nil, request: nil, cwd: "/p", evidence: [], logPath: "/logs/s.jsonl", capture: capture)
    }

    /// The artifact, newest delivery first.
    func artifact(_ deliveries: Delivery...) -> Artifact {
        Artifact(path: "/p/out/demo.mp4", deliveries: deliveries.sorted { $0.number > $1.number })
    }

    func state(_ kind: LocatorState.Kind, sha: String? = nil, git: GitState = .notInRepo) -> LocatorState {
        LocatorState(kind: kind, sha256: sha, git: git)
    }

    /// The hand-off statement for `d`, the plan worked out as the detail pane does.
    func handoff(_ d: Delivery, in artifact: Artifact, now: LocatorState, large: Bool = false, saved: Set<String> = []) -> Statement {
        let plan = artifact.handoff(d, now: FileObservation(state: now, checkedAt: delivered), hasSaved: saved.contains)
        return Wording.handoff(plan, delivery: d, in: artifact, now: now, large: large)
    }

    // MARK: Saying what was checked, with a reason (A2, A3)

    @Test func anUnavailableDeliverySaysWhyGleanerHasNoCopy() {
        let changed = state(.file, sha: "c")
        func detail(_ d: Delivery, large: Bool = false) -> String { handoff(d, in: artifact(d), now: changed, large: large).detail }
        #expect(detail(delivery(1, .missing)).contains("Gleaner never saw delivery 1: nothing was at this path then."))
        #expect(detail(delivery(1, .special)).contains("Gleaner never read delivery 1: it wasn’t a regular file then."))
        #expect(detail(delivery(1, .unreadable)).contains("Gleaner never read delivery 1: it couldn’t be read then."))
        #expect(detail(delivery(1, .directory)).contains("Delivery 1 was a folder."))
        #expect(detail(delivery(1, .file, sha: "a"), large: true).contains("too large to save"))
        #expect(detail(delivery(1, .file, sha: "a")).contains("Saving delivery 1 failed"))
        // Gleaner never read delivery 1, so it can't say the file changed, or that the delivery was
        // ever available; the current file is offered by name.
        let unread = detail(delivery(1, .missing))
        #expect(!unread.contains("changed"))
        #expect(unread.contains("You can hand off the current file"))
        #expect(handoff(delivery(1, .missing), in: artifact(delivery(1, .missing)), now: changed).title == "Delivery 1 isn’t available")
    }

    @Test func aSavedCopyGoneFromTheStoreIsNeverCalledAFailedSave() {
        let saved = delivery(2, .file, sha: "a", saved: true)
        let changed = state(.file, sha: "c")
        for large in [false, true] {
            let detail = handoff(saved, in: artifact(saved), now: changed, large: large).detail
            #expect(detail.contains("Gleaner’s saved copy of delivery 2 is no longer in its store."))
            #expect(!detail.contains("failed") && !detail.contains("too large"))
        }
        #expect(Wording.storage(saved, hasSaved: false, large: false, now: changed).1
                == "Saved copy gone from Gleaner’s store, 4 MB; the file on disk no longer holds it")
    }

    @Test func anUnreadablePathIsNeverCalledChangedGoneOrSeen() {
        let unreadable = state(.unreadable)
        let large = delivery(1, .file, sha: "a")
        for statement in [handoff(large, in: artifact(large), now: unreadable, large: true),
                          handoff(large, in: artifact(large), now: unreadable, saved: ["a"]),
                          handoff(delivery(1, .unreadable), in: artifact(delivery(1, .unreadable)), now: unreadable)] {
            let text = (statement.title + " " + statement.detail).lowercased()
            for claim in ["changed", "gone", "something else", "missing", "not on disk", "seen", "no longer"] {
                #expect(!text.contains(claim), "\(claim): \(text)")
            }
            // Nothing on screen offers a file it can't read.
            #expect(!text.contains("hand off the current file"))
        }
        let storage = Wording.storage(large, hasSaved: false, large: true, now: unreadable).1.lowercased()
        #expect(!storage.contains("no longer") && !storage.contains("exist"))
        for text in [Wording.provenance(delivery(1, .unreadable).capture).1, Wording.provenanceShort(delivery(1, .unreadable).capture).1] {
            #expect(!text.lowercased().contains("seen") && !text.lowercased().contains("gone"))
        }
    }

    @Test func aDeliveryNeverReadSaysWhatWasAtThePath() {
        #expect(Wording.provenance(delivery(1, .missing).capture).1 == "Never seen: nothing at this path")
        #expect(Wording.provenance(delivery(1, .special).capture).1 == "Never read: not a regular file")
        #expect(Wording.provenanceShort(delivery(1, .special).capture).1 == "Never read")
        #expect(Wording.storage(delivery(1, .missing), hasSaved: false, large: false, now: nil).1 == "Not saved: never read")
        let small = delivery(1, .file, sha: "a")
        #expect(Wording.storage(small, hasSaved: false, large: false, now: state(.file, sha: "b")).1
                == "Not saved: saving failed, 4 MB; the file on disk no longer holds it")
    }

    @Test func lostSaysWhatGitWasAskedAndNeverAsksItAboutAFolder() {
        let gone = FileObservation(state: state(.missing), checkedAt: delivered)
        let file = artifact(delivery(1, .file, sha: "a"))
        #expect(Wording.onDisk(.lost, in: file, now: gone).detail.hasPrefix("Not on disk, no saved copy, and not in a git repository."))
        let folder = artifact(delivery(1, .directory))
        let inGit = FileObservation(state: state(.missing, git: .recoverableFromHead), checkedAt: delivered)
        #expect(!Wording.onDisk(.lost, in: folder, now: inGit).detail.contains("git"))
        #expect(!handoff(folder.latest, in: folder, now: inGit.state).detail.contains("git"))
    }

    @Test func aFolderAtAFilesPathIsNamedAsOne() {
        let saved = delivery(1, .file, sha: "a", saved: true)
        let now = FileObservation(state: state(.directory), checkedAt: delivered)
        #expect(Wording.onDisk(.changed(since: 1), in: artifact(saved), now: now).detail.hasPrefix("A folder is at this path now."))
        #expect(handoff(saved, in: artifact(saved), now: now.state, saved: ["a"]).detail.hasPrefix("A folder is at this path now."))
    }

    @Test func aFailedSaveSaysWhyInWords() {
        #expect(Wording.saveFailed(ContentStore.Failure.changed(expected: "a", found: "b"), delivery: delivery(2, .file, sha: "a"))
                == "The file changed before Gleaner could save it; it no longer holds delivery 2.")
        // The path is no longer a regular file, or its bytes couldn't be read.
        #expect(Wording.saveFailed(ContentStore.Failure.unavailable, delivery: delivery(2, .file, sha: "a"))
                == "Gleaner couldn’t read delivery 2’s bytes at this path.")
    }

    @Test func aLogFoundShorterThanWhenReadBeforeIsNamedAsSuch() {
        // Still true once the log has grown again: the records it lost stay lost.
        let source = Indexer.Report.Source(folder: .listed, shortenedLogs: ["/logs/a.jsonl"])
        #expect(Wording.sourcesLine([.claudeCode: source]) == "Claude Code: read with problems (1 log shorter than before)")
    }

    // MARK: "First seen later" (A9)

    @Test func statementsNamingADeliveryKeepFirstSeenLater() {
        let later = delivery(1, .file, sha: "a", provenance: .firstSeenAfterDelivery)
        let changed = FileObservation(state: state(.file, sha: "c"), checkedAt: delivered)
        #expect(handoff(later, in: artifact(later), now: changed.state, large: true).title == "Delivery 1 (first seen later) is no longer available")
        #expect(Wording.onDisk(.changed(since: 1), in: artifact(later), now: changed).detail.contains("Changed since delivery 1 (first seen later)."))
        let gone = state(.missing, git: .lost)
        #expect(handoff(later, in: artifact(later), now: gone, large: true).title == "Delivery 1 (first seen later) is lost")
    }

    @Test func everyLabelNamingADeliveryKeepsFirstSeenLater() {
        let later = delivery(1, .file, sha: "a", provenance: .firstSeenAfterDelivery)
        let again = delivery(2, .file, sha: "a")
        let both = artifact(later, again)
        // The header names the bytes it shows and hands over.
        #expect(Wording.bytesCaption(nil, staged: nil, delivery: later) == "Delivery 1 (first seen later)")
        #expect(Wording.bytesCaption(.ready(sha: "a", from: .original, firstSeen: delivered), staged: "a", delivery: later)
                == "Delivery 1 · file on disk · first seen later")
        // The tile names what it carries, before and after its copy is ready.
        let plan = Handoff.ready(sha: "a", from: .original, firstSeen: delivered)
        #expect(Wording.tileVersion(staged: nil, plan: plan, delivery: later, in: artifact(later)) == "delivery 1 (first seen later)")
        #expect(Wording.tileVersion(staged: "a", plan: plan, delivery: later, in: artifact(later)) == "delivery 1 (first seen later)")
        #expect(Wording.tileVersion(staged: "a", plan: plan, delivery: later, in: both) == "delivery 2")
        #expect(Wording.tileVersion(staged: "c", plan: .unavailable(alternative: nil, currentSha: "c"), delivery: later, in: both)
                == "current file · not a found delivery")
        // The deliveries list, as read aloud.
        #expect(Wording.deliveryLine(again, sameAs: later).hasSuffix("same content as delivery 1 (first seen later)"))
        #expect(Wording.saveFailed(ContentStore.Failure.changed(expected: "a", found: "b"), delivery: later)
                == "The file changed before Gleaner could save it; it no longer holds delivery 1 (first seen later).")
    }

    // MARK: The type badge (A17)

    @Test func theTypeBadgeKeepsTheExactExtension() {
        #expect(Wording.kindLabel(.model, path: "/p/out/bracket.SLDPRT") == "SLDPRT")
        #expect(Wording.kindLabel(.document, path: "/p/out/notes.markdown") == "MARKDOWN")
        #expect(Wording.kindLabel(.folder, path: "/p/out/site") == "FOLDER")
    }

    // MARK: Observations (docs/design/capture.md)

    func observed(_ kind: Observed.Kind, title: String?) -> Observed {
        Observed(path: "/p/out/voice/line-1.wav", kind: kind, logPath: "/logs/s.jsonl", sessionID: "s", provider: .claudeCode,
                 sessionTitle: title, stretch: DateInterval(start: delivered, duration: 3600), workspace: "/p", size: 1,
                 createdAt: delivered.addingTimeInterval(60), modifiedAt: delivered.addingTimeInterval(120), device: 1, inode: 1,
                 repository: nil, checkout: nil, observedAt: delivered)
    }

    @Test func anObservationSaysWhenTheFileAppearedOrChangedNeverWhoMadeIt() {
        let appeared = Wording.observed(observed(.appeared, title: "Reading list series"))
        let changed = Wording.observed(observed(.changed, title: nil))
        #expect(appeared.mark == .observed && changed.mark == .observed)
        #expect(appeared.title == "Appeared during Reading list series")
        #expect(changed.title == "Changed during an untitled conversation")
        #expect(appeared.detail.hasPrefix("Its creation date, \(Wording.date(delivered.addingTimeInterval(60))), falls while Reading list series was working"))
        #expect(changed.detail.hasPrefix("Its modification date, \(Wording.date(delivered.addingTimeInterval(120))),"))
        for statement in [appeared, changed] {
            #expect(!statement.title.lowercased().contains("made") && !statement.detail.lowercased().contains("made"))
            #expect(!statement.title.lowercased().contains("deliver") && statement.detail.contains("not who wrote it"))
            #expect(statement.detail.contains("hasn’t read its contents"))
        }
        // A modification date isn't new content (A18).
        #expect(changed.detail.contains("not who wrote it or what changed"))
    }

    @Test func aFoldedFolderSaysItsCount() {
        #expect(Wording.folded("out/voice", count: 211) == "out/voice · 211 files")
        #expect(Wording.folded("", count: 1) == "Top level · 1 file")
        var source = Indexer.Report.Source(folder: .listed)
        source.workspaceProblems = ["/p: stopped after 100000 entries"]
        #expect(Wording.problems(source) == "1 workspace problem")
        #expect(Wording.source(source).1 == "Read with problems")
    }
}
