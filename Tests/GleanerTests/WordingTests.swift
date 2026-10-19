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

    // MARK: Reviewing (docs/design/review.md): four states, each said as itself

    /// A verdict or mark made on the bytes with hash 3f2a9c1b….
    func review(_ kind: Review.Kind, note: String? = nil) -> Review {
        Review(id: 1, kind: kind, path: "/p/out/demo.mp4", note: note, sha256: "3f2a9c1b77e0",
               file: FileStat(size: 1, createdAt: nil, modifiedAt: delivered, inode: 1), madeAt: delivered)
    }

    func words(_ statement: Statement) -> String { (statement.title + " " + statement.detail).lowercased() }

    @Test func eachVerdictStateIsSaidAsItselfAndNeverAsAnother() {
        // No verdict: in a collection it waits on the person, in the one accent; elsewhere it doesn't.
        let waiting = Wording.verdict(.none, inUnit: true), none = Wording.verdict(.none, inUnit: false)
        #expect(waiting.mark == .awaiting && waiting.title == "To review")
        #expect(none.mark == .dashed && none.title == "Not reviewed")
        var said = [waiting, none]
        for (kind, mark, name) in [(Review.Kind.approved, Mark.done, "Approved"), (.changesRequested, .revise, "Changes requested"),
                                   (.rejected, .declined, "Rejected")] {
            let current = Wording.verdict(.current(review(kind, note: "Trim the intro")), inUnit: true)
            #expect(current.mark == mark && current.title == name)
            // Bound to the bytes hashed when it was made, never the path (A17).
            #expect(current.detail.contains("Bound to the bytes hashed when it was made, 3f2a9c1b."))
            #expect(current.detail.contains("“Trim the intro”"))
            #expect(!current.detail.contains("/p/out"))
            said.append(current)
        }
        // Not read since the file's size or dates moved: it may have changed, never that it did.
        let may = Wording.verdict(.mayHaveChanged(review(.approved)), inUnit: true)
        #expect(may.mark == .attention && may.title == "May have changed since review")
        #expect(!may.detail.contains("other bytes") && may.detail.contains("hasn’t read it since"))
        let changed = Wording.verdict(.changed(review(.approved)), inUnit: true)
        #expect(changed.mark == .attention && changed.title == "Changed since review" && changed.detail.contains("other bytes"))
        // With no file Gleaner can read, the verdict stands as made, and nothing is called gone (A20, A22).
        let unavailable = Wording.verdict(.unavailable(review(.rejected)), inUnit: true)
        #expect(unavailable.title == "Rejected" && unavailable.detail.contains("stands as made"))
        for claim in ["gone", "not on disk", "missing", "deleted", "changed"] {
            #expect(!words(unavailable).contains(claim), "\(claim)")
        }
        // A verdict never says the file was published, nor where it is (A22).
        for statement in said + [may, changed, unavailable] {
            #expect(!words(statement).contains("publish") && !words(statement).contains("on this mac"), "\(statement.title)")
        }
        // Waiting is never said as changed.
        #expect(!words(waiting).contains("changed") && !words(none).contains("changed"))
    }

    @Test func publishedIsSaidOnItsOwnNeverAsAVerdict() {
        let states = [Wording.publishedState(.none), Wording.publishedState(.current(review(.published, note: "the channel"))),
                      Wording.publishedState(.mayHaveChanged(review(.published))), Wording.publishedState(.changed(review(.published))),
                      Wording.publishedState(.unavailable(review(.published)))]
        #expect(states.map(\.title) == ["Not published", "Published", "May have changed since published", "Changed since published", "Published"])
        #expect(states.map(\.mark) == [.dashed, .published, .attention, .attention, .published])
        #expect(states[1].detail.contains("at the channel") && states[1].detail.contains("bytes hashed when it was made, 3f2a9c1b"))
        #expect(!states[2].detail.contains("other bytes") && states[3].detail.contains("other bytes"))
        for statement in states {
            for claim in ["review", "approved", "rejected", "verdict", "gone", "not on disk"] {
                #expect(!words(statement).contains(claim), "\(statement.title): \(claim)")
            }
        }
    }

    @Test func whatWaitsIsSaidOnlyWhenSomethingDoes() {
        #expect(Wording.waiting(.none, inUnit: true).map { [$0.0 == .awaiting ? "accent" : "", $0.1] } == ["accent", "To review"])
        #expect(Wording.waiting(.none, inUnit: false) == nil)
        #expect(Wording.waiting(.current(review(.rejected)), inUnit: true) == nil)
        #expect(Wording.waiting(.unavailable(review(.approved)), inUnit: true) == nil)
        #expect(Wording.waiting(.mayHaveChanged(review(.approved)), inUnit: false)?.1 == "May have changed since review")
        #expect(Wording.waiting(.changed(review(.approved)), inUnit: false)?.1 == "Changed since review")
        #expect(Wording.toReview(3) == "3 to review")
    }

    @Test func onThisMacSaysEachStateAsItselfA20() {
        let there = Wording.onThisMac(.file, changed: false), unknown = Wording.onThisMac(nil, changed: false)
        #expect(there.title == "On this Mac" && there.mark == .done && unknown.title == "On this Mac")
        #expect(Wording.onThisMac(.file, changed: true).title == "Changed")
        #expect(Wording.onThisMac(.missing, changed: false).title == "Not on disk")
        #expect(Wording.onThisMac(.directory, changed: false).title == "Folder")
        #expect(Wording.onThisMac(.special, changed: false).title == "Not a file")
        let unreadable = Wording.onThisMac(.unreadable, changed: false)
        #expect(unreadable.title == "Can’t read" && unreadable.mark == .failed)
        for claim in ["gone", "not on disk", "missing", "changed", "nothing is"] {
            #expect(!words(unreadable).contains(claim), "\(claim)")
        }
        // Where the file is says nothing of its review or publishing, nor of how it came.
        for kind in [LocatorState.Kind.file, .missing, .directory, .special, .unreadable] {
            let statement = Wording.onThisMac(kind, changed: false)
            for claim in ["review", "publish", "deliver", "approved"] { #expect(!words(statement).contains(claim), "\(kind): \(claim)") }
        }
    }

    /// Delivery 1 of /p/out/demo.mp4, kept by the person from what a session was observed doing.
    func kept(_ provenance: Provenance, sha: String? = nil) -> Delivery {
        var kept = delivery(1, .file, sha: sha, provenance: provenance)
        kept.sessionTitle = "Reading list series"
        kept.kept = Keeping(keptAt: delivered, observed: .appeared)
        return kept
    }

    @Test func generatedSaysHowTheFileCame() {
        #expect(Wording.generated(delivery(1, .file, sha: "a")).title == "Named in a reply")
        var member = delivery(1, .file, sha: "a")
        member.member = Membership(folderDelivery: "d0", folder: "/p/out")
        #expect(Wording.generated(member).title == "Handed over in out/")
        let generated = Wording.generated(kept(.listed))
        #expect(generated.title == "Kept by you, observed during Reading list series")
        #expect(generated.detail.contains("appeared while Reading list series was working") && generated.detail.contains("No reply handed it over."))
        // How a file came says nothing of its review, its publishing or where it is.
        for text in [generated.title, generated.detail, Wording.generated(member).detail] {
            for claim in ["review", "publish", "approved", "on this mac"] { #expect(!text.lowercased().contains(claim), "\(claim)") }
        }
    }

    @Test func aKeptRevisionIsNeverCalledADeliveryOrListedWithAFolder() {
        let listed = kept(.listed), read = kept(.atDelivery, sha: "a"), later = kept(.firstSeenAfterDelivery, sha: "a")
        let file = Artifact(path: "/p/out/demo.mp4", deliveries: [listed])
        #expect(Wording.revision(listed) == "Kept file" && Wording.revision(later) == "Kept file (first seen later)")
        #expect(Wording.revisionInText(listed) == "the kept file")
        #expect(Wording.provenance(listed.capture, kept: true).1 == "Kept as observed, not read yet")
        #expect(Wording.provenanceShort(listed.capture, kept: true).1 == "Kept, not read")
        #expect(Wording.provenanceShort(read.capture, kept: true).1 == "Seen as observed")
        #expect(Wording.storage(listed, hasSaved: false, large: false, now: nil).1 == "Not saved: kept, not read yet")
        #expect(Wording.noCopy(listed, large: false) == "You kept the file as a session left it, and Gleaner hasn’t read it.")
        let changed = FileObservation(state: state(.file, sha: "c"), checkedAt: delivered)
        let texts = [
            Wording.revision(listed), Wording.compareTitle(read), Wording.bytesCaption(nil, staged: nil, delivery: listed),
            Wording.bytesCaption(.ready(sha: "a", from: .original, firstSeen: nil), staged: "a", delivery: read),
            Wording.tileVersion(staged: nil, plan: .ready(sha: "a", from: .original, firstSeen: nil), delivery: read, in: file),
            Wording.deliveryLine(read, sameAs: nil), words(Wording.onDisk(.changed(since: 1), in: file, now: changed)),
            words(handoff(listed, in: file, now: changed.state)), words(handoff(later, in: file, now: changed.state)),
            Wording.row(listed, latest: 1, now: .file, changed: false, available: true).number ?? "",
            Wording.saveFailed(ContentStore.Failure.changed(expected: "a", found: "b"), delivery: read),
        ]
        for text in texts {
            for claim in ["delivery", "delivered", "reply", "listed with its folder"] {
                #expect(!text.lowercased().contains(claim), "\(claim): \(text)")
            }
        }
        #expect(words(handoff(later, in: file, now: state(.file, sha: "a"))).contains("first seen"))
    }

    @Test func collectionsAreCountedAndNamedInside() {
        #expect(Wording.unitCounts(works: 3, units: 0) == "3 works")
        #expect(Wording.unitCounts(works: 1, units: 2) == "2 collections · 1 work")
        let series = WorkUnit(key: "unit:a", project: "/p", parent: nil, name: "Series", createdAt: delivered)
        let part = WorkUnit(key: "unit:b", project: "/p", parent: "unit:a", name: "Part 2", createdAt: delivered)
        let organization = Organization(artifacts: [], units: [series, part])
        #expect(Wording.unitPath(series, in: organization) == "Series")
        #expect(Wording.unitPath(part, in: organization) == "Series › Part 2")
        #expect(Wording.historyLine(review(.changesRequested, note: "Trim"), file: "demo.mp4")
                == "Changes requested, \(Wording.date(delivered)), demo.mp4, hash 3f2a9c1b, Trim")
    }

    @Test func aVerdictRefusedSaysWhyAndNeverCallsAnUnreadableFileGone() {
        let unreadable = Wording.reviewFailed(Review.Failure.notAFile(.unreadable), name: "demo.mp4").lowercased()
        #expect(unreadable.contains("can’t be read"))
        for claim in ["gone", "isn’t on this mac", "changed"] { #expect(!unreadable.contains(claim), "\(claim)") }
        #expect(Wording.reviewFailed(Review.Failure.notAFile(.missing), name: "demo.mp4") == "demo.mp4 isn’t on this Mac, so there are no bytes to judge.")
        #expect(Wording.reviewFailed(Review.Failure.changedWhileRead, name: "demo.mp4").hasSuffix("Look at it again, then decide."))
    }
}
