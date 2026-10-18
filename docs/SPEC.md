# Gleaner — Specification

Gleaner finds what your agents delivered, wherever they left it.

It is a local macOS library of the artifacts that local coding agents (Claude Code, Codex) explicitly handed to the user: videos, HTML pages, documents, images, reports. It lets a person search, preview, tell versions apart, and drag a delivered file into another app, without reopening the original conversation and without calling a model.

This document records the decisions ratified for v0.1, and for the release after 0.1.0. Implementation details not covered here are the implementer's call, provided they keep the three invariants in §1.

## 1. Invariants

1. **Delivery messages are the evidence.** An item enters the library only because an assistant reply to the user named it, naming a folder names what is in it (§5.4), or because the person kept a file observed during a session (§5.5). Every item can be traced back to that reply, or to that decision and the session.
2. **The source stays where it is.** Gleaner never moves, rewrites, or deletes files in project folders. It keeps its own index and its own snapshots.
3. **Humans operate it directly.** Finding, previewing, and handing off an artifact need no model call, no session ID, no branch name, and no remembered path.

### 1.1 Product boundary

Gleaner's domain is **agent deliverable discovery, preservation, and handoff**: what an agent handed to a human, found again, identified by version, and passed on. It is not session memory, observability, or harness management.

- **Independent.** Own repository, data model, desktop app, and release. No runtime dependency on another session indexer, and Gleaner is not built as a plugin of another product.
- **Runtime-agnostic.** No runtime (Claude Code, Codex, DSH, Pi, …) owns an artifact's identity, versions, or review state. Switching runtimes never forks them.
- **Connection is never an admission gate.** A runtime with no extension is still indexed passively from its logs.
- **Sessions are evidence, not the product.** Adapters parse only what delivery discovery needs.
- **Prior art is a reference corpus, not a dependency graph.** Projects such as Obelisk and agentsview are studied per engineering question (adapter normalization, incremental cursors, SQLite concurrency, fixture strategy). Each study yields: a method to adopt, a hypothesis to verify, or a design that does not apply. Another project having a feature does not add it to Gleaner's scope.

## 2. Product contract

> Find a delivery from an old session → preview it → confirm its source and version → drag it into another app.

P0 acceptance scenario: three weeks ago a Claude Code session compiled a demo video. The session is closed, and another agent has since modified the same file. The user remembers only the project and roughly the topic. They open Gleaner, type a keyword, find the delivery, read the delivery message, see that the current file differs from what was delivered, choose an available version, and drag it into another agent's composer. No model call, no project file modified.

## 3. Scope

In v0.1:

- Read-only adapters for Claude Code (`~/.claude/projects`) and Codex (`~/.codex/sessions`).
- Delivery extraction from user-facing final replies.
- Registry of sessions, deliveries (mentions) and captures in SQLite. Locator state (git, availability) is recomputed when a file is checked, not stored.
- Observations of what appeared or changed in each session's workspace during its span, kept beside the deliveries, never as deliveries (§5.3).
- The files of a delivered folder, each delivered by the reply that named the folder, listed by metadata and read when the person acts on one (§5.4).
- Content-addressed snapshots under a size policy.
- What only the person adds (§5.5): work units, files they keep from what a session was observed doing, and verdicts and published marks bound to the bytes they were made on, with the queue of what is left to review, each listed in the window.
- Library window: projects and the works in each, search, preview (Quick Look, text, Markdown), compare versions, reveal in Finder, copy path, drag out, and a Sources page for what Gleaner reads, the person's corrections and what it keeps (§5.1a).

Deferred: comments, timecoded notes, MCP or `artifact://` resolvers, agent-initiated submission, remote-agent handoff, cross-device sync, cloud deliveries (ChatGPT, claude.ai), automatic HTML dependency bundling, Claude Code hooks as a capture path, runtime extensions and model reasoning (§14), release groups (§15).

The core is a library (`GleanerCore`), not logic inside the UI, so that the Spike A CLI today and extensions later (§14) use the same API as the app.

## 4. Platform

- **SwiftUI + AppKit + SQLite**, macOS only.
- SwiftUI for the library, search, and cards; AppKit for system drag (`NSFilePromiseProvider` or file URL pasteboard items); Quick Look for preview of video, PDF, images. Text and Markdown have their own views (rulings §7). An HTML page is previewed by Quick Look as the single staged file, without the files it references; an interactive HTML preview is deferred.
- Drag-out always uses **copy** semantics. A drag must never let Finder move the source file.
- Distribution decides sandboxing. If the app is sandboxed, project folders are reached through security-scoped bookmarks granted by the user.

## 5. Data model

Four core objects, recorded from the logs and the files. Projects and works, which the person sees and may correct, are built over them (§5.1a). Observations, a second kind of evidence, are kept apart from them (§5.3). A delivered folder's files are deliveries of their own, made by the reply that named the folder (§5.4). Work units, kept files, verdicts and published marks are the person's, kept apart from all of these (§5.5).

| Object | Holds |
|---|---|
| **Session** | provider, provider session ID, title, cwd, log file location |
| **Delivery Mention** | the reply excerpt that names the artifact, the raw target as written, the user request that started the turn, position in the log (its own log file and line), its place in the reply (the line where the reply starts, which every file the reply named shares, and the order the reply names them in), `delivered_at` |
| **Locator** | resolved path, worktree / repository root, git state (`committed`, `modified`, `untracked`, `ignored`, `not_in_repo`; when missing: `recoverable_from_head`, `recoverable_from_history`, `lost`), availability (`file`, `directory`, `special`, `unreadable`, `missing`), last verified time |
| **Capture** | `observed_at`, sha256, size, optional snapshot reference (`captured_at`), the capture's provenance, and what was at the path (a file, a folder, or, without a hash, nothing, an unreadable file, not a regular file, or a file listed with its folder and not read yet) |

Artifact identity in v0.1 is the path. A renamed or moved file appears as a separate artifact until the person joins it to the work it continues (§5.1a); Gleaner never joins files across paths by itself. Paths keep one spelling whether or not they exist: `/private/var`, `/private/tmp` and `/private/etc` read as `/var`, `/tmp` and `/etc`, and the folder an agent worked in is compared in that spelling. A project is the git repository holding the file (every worktree folds into its repository), else the one its cwd belongs to, else the folder name (rulings §2). Projects are told apart by the repository's main folder (for a bare repository, its own folder, named without `.git`) and shown by its name. Each delivery records, with its capture, the repository it resolved to and the checkout it was in (the main folder or a worktree's own folder), only while the file's folder is there to show them. The record outlives a reread that drops the delivery, and the earliest one wins over any later resolution: a deleted worktree keeps its project and its name, and a file committed on its branch is still looked up in the repository's history at its path within that checkout. A delivery never resolved stays explicitly outside any repository.

### 5.1 Time semantics

Three fields, never conflated:

- `delivered_at` — when the assistant reply that names the file was written.
- `observed_at` — when Gleaner read the file and computed its hash.
- `captured_at` — when Gleaner stored a snapshot of those bytes.

When history is backfilled, these can be months apart. A capture records its provenance:

- `at_delivery` — observed within 10 minutes of `delivered_at`, and the file's mtime is no later than `delivered_at` plus 2 seconds of clock granularity.
- `first_seen_after_delivery` — observed during backfill or after the file's mtime moved past the delivery. The UI must say plainly that this may not be the delivered version.
- `never_observed` — Gleaner never read the file's bytes: when it first looked, the path was missing, unreadable, or not a regular file. The capture has no hash and records which. It is completed once, the first time Gleaner reads the file (checking it, or capturing a later delivery of it), as `first_seen_after_delivery`.
- `listed` — one of a delivered folder's files, listed with the folder by its size and dates, whose bytes Gleaner hasn't read yet (§5.4). It has no hash, and is completed once, by the rules above, the first time Gleaner reads the file while it is still as listed.

A capture with a hash is never rewritten. A file that is there but cannot be opened or read is `unreadable`, with its own wording: it is never described as missing, gone, changed, or seen.

Gleaner never labels a file "latest" unconditionally. It shows the time of the last verification.

When the latest delivery's capture is `first_seen_after_delivery`, the on-disk status reads "unchanged since first seen", never "same as delivery N". A match with a capture made after delivery is not a match with the delivery.

### 5.1a Projects, works and corrections

What the person navigates is built over the four objects, never stored in them (review-rulings §3, foundation 2; `docs/design/projects-and-works.md`):

- **Project:** the one derived above, or one the person made. The person can move a work into another project, and show a derived project inside another. Each work says why it is in its project. A work's moves are appended, the latest placing it, so undoing one returns it to the project before it; Put Back undoes them all.
- **Work:** a file, or several files the person said are versions of one work. Its revisions are its files' deliveries, numbered per file. Gleaner may suggest a join, with its reason (the later file first came, after the earlier one's last delivery, with the bytes that one last had, and that one is no longer at its path; or the two names in one folder differ only by a version mark such as `v2` or `final`, never a date or a bare number), and never joins files itself.
- **Corrections** are kept in their own tables. They never change a delivery, a capture or a status; rereading the logs and relaunching keep them; each can be undone, and all can be undone at once.

### 5.2 Versions

Versions follow **delivery events**, not file saves. Twenty-five rebuilds between two deliveries produce two version nodes, not twenty-five.

| Event | Behavior |
|---|---|
| Same path delivered again, same bytes | Append a delivery; its capture repeats the hash, no new saved bytes, and the UI marks it "same as N" |
| Same path delivered again, new bytes | New capture → new version node |
| Source changed silently since last capture | Mark "changed since delivery"; no version node until the next delivery or an explicit pin |
| Source matches an older delivery, not the latest | Mark "rolled back to delivery k". It is a delivered version, never labeled "not delivered". When delivery k's bytes were first seen later, say "back to what Gleaner first saw for delivery k" |
| Identical bytes at two paths | One content hash, two locators; review context stays per locator |
| Source missing, snapshot exists | Offer the snapshot, label the source unavailable |
| Source missing, no snapshot | Keep the entry and its history; say it cannot be recovered |

Same bytes do not imply the same logical artifact.

### 5.3 Observations

What a session gives besides its replies is where and when it worked (`docs/design/capture.md`). Gleaner keeps what it finds there apart from the deliveries:

- **Span.** When the session was working: one stretch per request, from the request's record to the last reply answering it, widened by a minute each way for the clocks of the log's writer and the disk, and joined where stretches meet. A reply to a task notification answers the request before it, so a background job between the two is inside. The time between a reply and the next request is not: a conversation resumed days later wasn't working in between. A session without a reply time has no span, so an interrupted turn, or a title appended later, gives none. The adapters give each reply's request time (§8).
- **Workspace.** The git checkout holding each folder the session's records name (a worktree's own folder, or the main one), else the folder. Not walked, with the reason kept and shown in Sources under the session's agent (not a problem): a folder that is gone; the home folder or a folder holding it; the home's Library, except inside iCloud Drive (`Library/Mobile Documents`) and cloud storage (`Library/CloudStorage`), where documents are kept; a system folder; a hidden folder (`~/.claude`, `~/.codex`); and a folder that is, holds or is inside the agents' log folders or Gleaner's library, so Gleaner never observes transcripts or itself. These are compared as the disk has them, links followed and case as on disk, so another spelling of a folder is skipped as it is. An agent's worktree with a name of its own (`.claude/worktrees/<name>`, `~/.codex/worktrees/<id>/<repo>`) is walked.
- **Walk.** A session's workspaces are walked when its span or workspaces have moved since they were last walked, or when the last walk came before its span ended; otherwise reading its log again (for a title appended, say) walks nothing. The span is recorded with the log's reading, and the session marked walked only once all its observations are recorded, so a walk a quit cut off, or whose observations couldn't be written, is made again next run and reported until it is. Each workspace is walked once per run, for every session waiting on it, one workspace at a time, and only for the agents being read. It reads names, sizes, creation, modification and inode change dates and file identity (device and inode), never contents. A package, a folder whose extension the system declares a package (`UTType.package`: an app, an Xcode project, an RTFD document, a bundle), is one entry, as Finder shows it as one file: the walk reads its own dates and never enters it. That is structure the system gives, not a type Gleaner picks. It doesn't list hidden files (`.env`, `.DS_Store`), as a delivered folder's listing doesn't (§5.4), so none is ever a candidate; nor does it enter hidden folders (`.git`, `.build` and `.venv` among them), the dependency caches tools leave (`node_modules`, `__pycache__`, `DerivedData`), a folder its tool marked as a cache with a `CACHEDIR.TAG` file (Cargo's `target`, for one), or a folder on another volume, and doesn't follow links. No file type is skipped, and no output folder: `dist` or `build` may hold what was asked for. It stops after 100,000 entries. A walk cut short and a folder it couldn't list are reported with their reason under the session's agent, on every run until the session is walked again.
- **Observation.** A regular file, or a package as one entry, whose creation date falls in a stretch *appeared* during the session; one whose modification date does, and creation date doesn't, *changed* during it. Either only when the file's inode last changed before that stretch ended: a copy that kept older dates (`cp -p`, `rsync -a`, Finder, an archive), or dates `touch` set, made after the stretch isn't placed in it, on the session's first reading or a later one. A file renamed or given new permissions after the stretch is left out too. Gleaner records the file, with its size, dates, identity and the repository and checkout it was in, the first time it sees it during that session (its own `observed_at`, which unlike a capture's (§5.1) reads no bytes), and never rewrites it. Another session's observation of the file is recorded beside it. A file that a reply named in another spelling (another case, or through a linked folder) is recorded under the name the reply gave it, matched by device and inode: the replies of the sessions walked, and any naming a path in the workspace.
- **What it shows.** That the file appeared or changed while the session was working, in its workspace: not that the session made it, since parallel sessions, a copy made during the stretch and background jobs fall inside spans too, and, for a modification date, not that the contents changed. Nothing is labeled "made by". An observation is a candidate: it never becomes a delivery, a capture, a version or a work by itself. Only the person keeping it admits it (§5.5). A delivered file keeps its delivery, with its observation beside it.
- **Corrections** (§5.1a). *Not from this session* detaches a file from one session it was observed during; *related* puts an observed file with a work, shown with it and never one of its versions. Both are appended to the corrections, never applied to the observations, and each can be undone.
- **Order and grouping.** Type, stem and folder order and group a list, and never decide what enters it or which files are one work: handed over (named, or in a folder a reply named, §5.4) before observed; within each, what a person opens (documents, images, audio and video, pages, models, installers, folders) before what a program reads (data, code, formats Gleaner can't place); then newest first. A folder's files of one kind that no reply named itself fold into one row with their count from twelve, those handed over in a folder apart from those observed; a file a reply named never folds. Files in one folder whose names share a stem (the name before its first dot) are shown together, which claims nothing.
- **Reread.** Spans are derived from the logs, so the extractor version moved to 15 and every log is read once more. A session observed for the first time then, long after it worked, is matched against the disk as it is now: files changed since are left out, and nothing is placed in it that the rules above don't. Reading a log again keeps what was recorded as first seen; a walk may add files it couldn't see before (a stretch that grew, a walk that saw more), never remove or rewrite one.

### 5.4 Bundles

A reply that names a folder names what is in it (`docs/design/capture.md`, layer 2). The folder stays one delivery, listed and not versioned (§6); each file in it is a delivery of its own.

- **Members.** A regular file anywhere under the folder, or a package (§5.3) as one entry, found as a workspace walk finds them (§5.3): names, sizes, creation, modification and inode change dates and file identity, never contents; no link followed and no other volume entered; no hidden folder, dependency cache (`node_modules`, `__pycache__`, `DerivedData`) or folder marked with `CACHEDIR.TAG` entered; and the walk's bound, 100,000 entries, a listing cut short reported with its reason in Sources under the folder's agent on every run. A hidden file is never a member: a delivered folder holding `.env` puts it nowhere in the library, search, a preview or a hand-off. Beyond these structural skips, no file type or folder name decides membership: `dist` or `build` may hold what was asked for.
- **A repository inside.** A Git repository inside the folder (a folder holding `.git`, as a submodule or a vendored checkout does, or a bare repository, holding `HEAD`, `objects` and `refs`) is another project. The listing doesn't enter it and lists everything else; none of its files is a member, and the folder's detail says it was listed without it, naming where it is in the folder.
- **A package** is a member as a delivered folder is a delivery: listed and not versioned, its capture a folder's, never read, `at_delivery` when listed within 10 minutes of T and last written by T plus 2 seconds, `first_seen_after_delivery` otherwise. None of its own files is a member.
- **Not unpacked.** The folder stays one work, and why is kept, shown in its detail and in Sources under its agent (not a problem), when it is: named by a reply without a time; a link, since no link is followed; a folder a workspace walk skips (§5.3); a folder that holds a person's things rather than one deliverable, as the home, a volume (one whose device differs from its parent's) and a cloud drive (each folder directly in `~/Library/CloudStorage` or `~/Library/Mobile Documents`, iCloud Drive among them) do, or a folder directly in one of them, since Desktop, Documents, Downloads, Projects or a drive's top folders hold many things (decided by depth, not names); a cache, by the names and mark above, or a folder inside a cache, a hidden folder or a package, however deep, up to the home (or the root): a hidden folder that is itself a repository (`~/.config` kept in git) or holds one (a clone in `~/.local/share`) counts, and only a hidden folder that a repository other than the home keeps above a checkout inside it is passed, so an agent's worktree (`.claude/worktrees/<name>`) is unpacked as its repository's folders are, as §5.3 walks it; a package (§5.3), which Finder shows as one file; a Git repository's own folder (a checkout's, holding `.git`, or a bare repository, holding `HEAD`, `objects` and `refs`); or the folder its conversation worked in or its checkout, inside git or not, or a folder holding either, since handing over the project points at the project and §5.3 already observes what changed there.
- **Membership by time.** With T the folder delivery's `delivered_at`, and 2 seconds for the granularity of the log's clock and the disk's: a file created by T whose inode last changed by T was handed over, as it is listed. Any other isn't counted: one created after T was added later, and one whose inode changed after T isn't shown to have been there, since a file moved, linked or copied in after the reply keeping its dates (`mv`, `ln`, `cp -p`, `rsync -a`, Finder) carries a creation date from before it. As in §5.3, the cost is a miss, never a false claim: a file edited after the reply is missed too. On a volume without creation dates, the inode change date alone decides. Read as the agent replies, the files are as handed over; read long afterwards, a file unchanged since is still counted.
- **Deliveries.** Each member is a delivery of its own file, numbered with that file's other deliveries by time (§5.2). It carries the folder delivery's reply, session, request, time and evidence, and names the folder delivery it came through ("Handed over in out/"). It is shown where its folder is: its folder's project, repository and checkout. A file the reply also named itself is delivered once by that reply, as named, and a file a reply of the folder's log, or any naming a path in the folder, named in another spelling (another case, or through a linked folder) is listed under that name, matched by device and inode; one in two folders the reply named, once, through the innermost. A delivered folder's files aren't among the other files its reply named: each is reached through its folder.
- **Listed, then read.** A member's capture holds its size and dates, as `listed`, with no hash. It is completed once, the first time Gleaner reads the file while it is still as listed (at the same path, the same inode, creation and modification dates, and size; not the device number, which a volume mounted again may change): when the person selects, opens, looks at, compares, drags or hands it on, or when a later reply names the file and its bytes are captured, in the same run as the folder's listing or a later one. Its provenance follows §5.1: `at_delivery` only when the read comes within 10 minutes of T, the file's modification date is no later than T plus 2 seconds, and so is its inode change date; `first_seen_after_delivery` otherwise. A file not as listed is not completed, since it isn't shown to be the file handed over, and is said to be not as listed, not changed. Before a hash, two deliveries are said only to match in size and dates, and only when both record the file as it was at their own delivery: listed with a folder, or read at delivery. Size, modification date and creation date are compared as far as both recorded them; a file a reply named records no creation date, so "dates" is said only when both recorded it, and "size and modification date" otherwise. "Same as N" stays a hash statement.
- **Delivered again.** Each delivery of the folder lists its members at its own T, so a file gets one delivery per folder delivery it was in (§5.2). One row per folder delivery and member, written as listed and never rewritten but for its completion.
- **Existing libraries.** A folder delivery not listed yet waits for its listing, which the next run makes whether or not its log changed; a listing that couldn't be recorded is made again, and so is one of a folder gone, no longer a folder, or that can't be read, which each run names in Sources until a run can list it: one that can't be read as a problem, and the folders gone folded into one row with their count, since a removed worktree may leave many and a volume may come back. Membership by time makes that safe: whenever it is listed, nothing is claimed that the dates don't show. No log is read again for it.
- **Observations.** A member is a work, so what §5.3 observed of it is shown beside its delivery, and a candidate that turns out to be a member is no longer a candidate. The person's corrections (§5.1a) apply to a member's work as to any work.
- **Shown** where works are: in a project's outline under their folders, ordered and folded as §5.3 says, with the files a reply named never folded; in search by name, folder and project (§10); in the detail, with "Handed over in" the folder and the folder's reply, and their versions. Selecting one, which Quick Look and Open act on, or dragging its row reads the file while it is as listed, completing its capture; what is handed over is bytes verified by hash, as for any delivery (§6).

### 5.5 Review

What only the person can add (`docs/design/review.md`): which works go together, which observed files belong in the library, and a judgement of exact bytes. Each is the person's, kept apart from what Gleaner found.

- **Work units.** A unit (a collection in the window) belongs to one project and has the name the person gives it. It may sit inside one other unit, one level deep. It holds works, each in at most one, by its files' paths. A unit is never a same-work join: its works keep their own revisions and verdicts. Making one adds it, and undoing that removes it with every decision naming it. Renaming, deleting, adding a work and taking one out are corrections (§5.1a), appended, so undoing one returns to the one before it. Deleting a unit deletes the units inside it and returns their works to the project; undone, they are back as they were. A work is in the unit the latest decision about any of its files put it in, while that unit is in the work's project: adding a work shown in another project moves it there in the same decision, and moving it on takes it out of the unit until that move is undone. Units go by name in natural order ("2" before "10"), a unit's works in list order (§5.3). A project holding a unit is listed with it. Undo All Corrections removes them. *New Collection from These* makes a unit holding exactly a group the window shows (a folder of a project's outline, a session's observed files, a folded row, files shown together on a review page, the files a reply delivered together, what a search found), its observed files kept, as one decision undone at once; it is offered only for a group within one project, and infers nothing. A work in another unit leaves that one, since a work is in one at most, and the command says so before it is made.
- **Keeping an observed file.** Keep is a correction: the file becomes a work whose one revision is its latest observation, kept by the person, observed during that session. The revision is dated by the write the observation recorded and carries its size and dates as `listed` (§5.1), with the session and none of a reply's words: it is found by its name, folder and project. Its bytes are read when the person acts on it, as a delivered folder's file is (§5.4), and the first read while the file is still as observed completes it once: `at_delivery` only within 10 minutes of that write, the file last written and its inode last changed by it plus 2 seconds; `first_seen_after_delivery` otherwise. The completion is kept with the observation, which is never rewritten, so undoing the keep makes it a candidate again and keeping it again finds the read. A package is kept as a folder, never read. Adding an observed file to a unit keeps it. A reply that later names the file adds a revision.
- **Verdicts and published marks.** A verdict (approved, changes requested or rejected, with an optional note) or a published mark (with an optional place, words or a link) is made on a work's current file, on the bytes there then. Making one is the person's action: it reads the file, saves a small file's bytes as a first read does (§6), and a larger one's when the person asks (Save a Copy), completes what a first read completes, and records the bytes' SHA-256 with the file's size, creation and modification dates and inode, and the time. One whose bytes Gleaner holds no saved copy of says so, with the file's size, why (over the limit, or a save that failed, said with its reason when the person had asked for it), and what Git says of the file (ignored, uncommitted or committed), only while the file may still hold those bytes: of a file rewritten since, Git speaks of other bytes. Save a Copy keeps them while the file still holds them, checked by hash before the copy is stored, so other bytes are never kept in their place. Kept, they are compared and handed over as a version's bytes are. A verdict binds to the bytes hashed when it was made, never to the path or to what was shown before. Nothing is made on a file that isn't as the person was shown it, or that changed while it was read, nor where there is no regular file Gleaner can read, each said as itself: gone, a folder, not a regular file, unreadable. A later one is added beside the others; none is rewritten or removed by another, each can be undone, and Undo All Corrections leaves them.
- **What they say now.** For a work's current file: the newest verdict whose hash matches its bytes once they are read (on select, or by a verdict); not read since, the newest made while the file had the same size, dates and inode. Bytes that match a verdict's hash keep it, at any revision of the work, whichever of its files had them; identical bytes at a path the person hasn't joined share no verdict (§5.2). Otherwise the newest verdict "may have changed since review" until the file is read, then "changed since review". With no readable file there, the newest stands as made, unless a delivery of the file came after it: then the bytes that delivery recorded decide as if read, and with none recorded it may have changed (A16). Within a session, what Gleaner last saw at the path, after the newest delivery it recorded, decides the same way: bytes read by their hash, and a size and dates by the bytes recorded with them (a verdict or mark made on the file so, by its size, dates and inode, or a revision that recorded that size and modification date, as §5.4 matches a listed file), else it may have changed; so a file seen changed and then deleted stays changed. A relaunch remembers none of it. Published marks are read the same way, on their own.
- **Four states, kept apart.** Generated (named in a reply, handed over in a folder, or kept, observed during a session), On this Mac (the locator, §5), Reviewed and Published, each shown for a work's current file. None completes another: not a delivery, a version, a saved copy, a push, a file played to its end, nor an agent's claim (§6.2). A published file need not be reviewed, a reviewed one need not be on this Mac, and a delivered one need not be reviewed.
- **To Review.** The works in units with no verdict on their current bytes, and the works anywhere whose newest verdict was made on other bytes or may have been, grouped by unit in the order the sidebar lists them, then by project. A work nobody put in a unit and nobody reviewed is never in it, nor a folder, which has no bytes to judge.
- **Reading.** Units, To Review and each work's states come from sizes and dates, taken when the library is organized, when a file is selected and when a review page draws it, and from bytes read this session while the file is still as read; a file stat finds but Gleaner may not read is unreadable. Bytes are hashed only when a verdict or mark is made, and when a file is selected, as before (§7). Showing a review page, or a collection's poster, plays and renders from the file on disk, only what scrolls into view: that hashes nothing and completes no capture.
- **Shown** (`docs/design/review.md`, The window): To Review with its count, and each project's units under it, in the sidebar; a project's outline lists its units first, after its head, and each work's row names its unit. A search matches the names of a work's unit and of the unit holding that one, beside its project's (§10). A unit lists the units inside it, then its works; its review page shows each of its works in place, played and rendered from the file on disk, with the four states, and a verdict made there binds only to a file still as it was drawn. Review All acts only on the images and documents the page drew whole: each video and audio file needs a verdict of its own (A07), and the menu says how many of the page's wait, drawn yet or not. An image nothing can draw says so. A project's outline lists the files that appeared or changed while sessions worked, and that no reply handed over, under Observed, by session, to keep, add to a unit or detach. A work's detail has its verdicts and marks, newest first, each to undo; it makes one only while it shows the file's current bytes. A kept revision is named as kept, never as a delivery.

## 6. Snapshots and storage

- Location: `~/Library/Application Support/Gleaner/` — `registry.sqlite` and `objects/<sha256-prefix>/<sha256>`.
- Nothing is written to project folders.
- Policy by size, not type: every regular file up to 64 MB gets a saved copy when Gleaner first reads it. A larger file is tracked by hash, and "Save a copy" keeps it while the file on disk still matches the delivery. Thumbnails for large video, directory snapshots and HTML dependency handling are deferred.
- Folders are listed but not versioned: preview, Open and drag use the folder as it is now, only while the path is still a folder, and the UI says so. The files in a delivered folder are versioned one by one (§5.4).
- A delivered symlink is captured by the file it points to; the link itself is never copied, and the target's permissions are never changed.
- **Hand-off copies** (`~/Library/Caches/Gleaner/handoff`, read-only files) and the **version store** are separate. Hand-off copies are disposable; clearing them keeps the one on the clipboard, which a paste still reads, and a saved copy that backs a version is never removed by cleaning caches.
- A drag hands over an immutable, verified copy, never the live source path. Gleaner copies the chosen version's bytes (from the saved copy when there is one, else from the source while it still matches) to a staging file, hashes the staged file, and hands it over only if the hash equals the version's. The detail's tile prepares its copy when the delivery is selected, so the preview shows the same bytes, and the text preview shows the text read once that copy was verified; a list row prepares its copy at drop. A copy already there is hashed again before it is reused. Gleaner keeps the identity a prepared copy had when it was hashed (its inode, size, and modification and change times), and the tile, ⌘C, Open and Quick Look use the copy only while it is still that file: a write, a replacement or a removal changes it, and the copy is then made and hashed again. Once a file is handed to another app, what that app reads from it later is beyond Gleaner's check. Handing over the source path itself would only guarantee the content at the moment of the check; an agent or editor may change it before the receiver reads it.
- Which bytes back the chosen version:

| Situation | Drag behavior |
|---|---|
| Source matches the chosen version | Stage a copy (an APFS clone of the saved copy, else of the source), verify its hash, drag that |
| Source differs or is missing, and a snapshot of the chosen version exists | Drag the snapshot |
| Something else is at the path (a changed file, a folder, a file Gleaner can't read, a pipe), and the chosen version has no snapshot | Say the version isn't available, and why Gleaner has none of its bytes: never seen, never read (unreadable or not a regular file at first look), a folder, too large to have been saved, or a save that failed. Say "no longer" only for bytes Gleaner had, and "now" while the path can't be read. If the current file matches another delivery k, offer delivery k by name; otherwise, when Gleaner can read the file there, offer it only under an explicit "not among the deliveries Gleaner found" label |
| Source missing, no snapshot, but git history has the path | Offer a restore command for the user to run, naming a commit checked to hold the path: the checkout's HEAD when it does, else the newest commit on any ref that does. For a removed worktree, the command adds the worktree back at that commit. Gleaner never restores it itself (Invariant 2), and says it cannot confirm that the git version is the delivered one |
| Source missing, no snapshot, not in git | Lost: keep the record, offer no drag |

- A list row hands over what the detail would for the delivery the row shows: the chosen one for the selected row, the matched one for any other. A row with nothing to hand over is marked unavailable, with why, and starts no drag.
- A saved copy inherits its capture's provenance. A snapshot taken during backfill keeps its delivery number with the qualifier "first seen later" in storage labels, previews and drag captions (rulings §9).
- **UI vocabulary.** "Snapshot" and "pin" are internal terms. The user sees "saved copy" for a snapshot and "Save a copy" for pinning. Plain "copy" is never used for Gleaner's storage, because every drag copies.

### 6.1 Comparing versions

Any two versions Gleaner holds bytes for (two deliveries, or a delivery and the file on disk) can be compared, read-only. Both ends are named with their hash and must still hash to it. Text gets a line diff in one accent: grey for what was there, the accent for new lines, a solid block only on the new words of a one-for-one replaced line, both line numbers and the ± mark always shown. Two versions whose bytes differ never read as "No changes": when no line differs, Compare says that only line endings or the final newline differ. Images show side by side; other kinds compare size and hash. Text over 64 KB or 2000 lines is reported as limited, never shown partially; a file of a text kind that isn't text (a PDF) compares by size and hash at any size. See `docs/design/diff-and-references.md`.

### 6.2 Claims in replies

A reply's claims about an artifact ("signed", "notarized", "tests pass", "final") are evidence, not facts. The UI quotes them as unchecked text attributed to the reply and never turns them into a status or a solid mark. Only Gleaner's own checks (existence, hash, git state) become statuses. This applies to every delivery in v0.1, not only to the release groups in §15.

## 7. Watching

- Watch only the agents' log directories (FSEvents). New sessions are ingested near real time, so `observed_at` stays close to `delivered_at`. While a log directory does not exist yet, the nearest existing folder above it is watched only to notice it appear.
- Do not watch the paths of indexed artifacts. Re-verify a file's hash when it is selected, again when its hand-off copy is staged, and when the person makes a verdict or a mark on it (§5.5); there is no background pass in v0.1.
- A session's workspace is walked, not watched, after its log is read and its span has moved (§5.3). Live capture while a log is being written is a later layer.
- Observation is read-only: only regular files are opened (a FIFO, socket, or device is reported as `special`; a file that can't be opened or read, or a path behind a folder that can't be searched, as `unreadable`), and git runs with `--no-optional-locks` so `git status` never rewrites the index, and runs nothing the repository configures: `core.fsmonitor` off, so it starts no hook or daemon; `log.showSignature` off, so `git log` starts no signature program; and lazy fetching off, so a partial clone fetches nothing it lacks. A commit is checked to hold a path through its trees, never by reading the file's contents. A clean filter (Git LFS, for one) may still run while git compares a file with the index; that is a known limit.

## 8. Adapters

- Each provider is an isolated module that turns its log format into `Session`, turns, user requests, and final replies. The extractor downstream is provider-agnostic.
- Log formats are undocumented and change. Each adapter ships fixture tests built from real record shapes (sanitized). An unknown record type, or an unknown key in a known one, is counted and reported, never silently dropped into "no deliveries". An adapter change merges only with passing fixture tests and the owner's review (`AGENTS.md`).
- Each read of a log counts its records, the records of a known type, the closed turns the assistant answered in, the final replies of closed turns, and the candidates the final replies name. A turn is closed once the log holds the next one. The last turn is open and isn't counted: the session may still be running, the text it ends on may yet be followed by a tool call, or it ended on one. A turn the person interrupted was not answered. The source status reports a log whose closed turns have assistant records but no final reply, and a log whose closed turns hold fewer final replies on a complete reread.
- Sub-agent and side-chain transcripts are excluded: they are not replies to the user.
- A log that disappears (agents prune old transcripts) leaves its deliveries as last derived: they are not re-derived on an extractor change, and their captures and saved copies stay.

### 8.1 Claude Code (`~/.claude/projects/<project>/<session>.jsonl`)

- Records are one content block per line; `type` is `user`, `assistant`, `system`, `attachment`, `ai-title`, `custom-title`, and others.
- A turn begins at a `user` record that is not a tool result, not `isMeta`, and not `isCompactSummary`. Records with `origin.kind == "human"` are the user's request, and their `timestamp` its time (§5.3); `task-notification` and similar also start a turn (the agent's answer to them is still user-facing) but do not replace the request context or its time.
- The final reply is the assistant `text` blocks that come after the turn's last `tool_use`.
- When the person stops a turn, Claude Code writes a `user` record with the text `[Request interrupted by user]`, or `[Request interrupted by user for tool use]` when they stopped a tool call. It ends the turn, which was not answered, and does not replace the request context.
- Relative paths resolve against the `cwd` of the reply record, not the request: the agent may have entered a worktree mid-turn.
- Title: latest `custom-title`, else latest `ai-title`.
- Exclude `subagents/` directories and `isSidechain` records.

### 8.2 Codex (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`)

- `session_meta.payload` gives id, cwd, `thread_source`; skip `thread_source == "subagent"`.
- Forked threads replay parent messages marked `metadata.inherited_user_message`; skip them.
- The user request is a `response_item` `message` with role `user` whose `content_item_kinds` include `user.text`, and the record's `timestamp` its time (§5.3). A user message without `content_item_kinds` (older rollouts) is not taken as a request. Codex's attachment header ("# Files mentioned by the user … ## My request:") is dropped: the request is the words after it, or the attachment names when nothing was typed.
- The final reply is an assistant `message` with `phase == "final_answer"`.
- A turn starts at a `turn_context`. An `event_msg` of type `turn_aborted` means the person interrupted the turn: it was not answered.
- Title from `~/.codex/session_index.jsonl` (`thread_name` by id).

## 9. Extraction

Candidates come from the final reply only:

- Markdown links and images whose target is a local path (absolute, `~`, relative, or `file://`).
- Inline code spans and bare absolute paths that look like files.
- Relative targets resolve against the cwd of the record that names them. Line anchors (`:42`, `#L42`) are stripped and recorded. The fragment is split off before percent-decoding, so an encoded `%23` stays part of the file name. Balanced parentheses in link targets belong to the path. `file://localhost/` is a local path; `file://<other host>/` is not.
- Each mention keeps the record it came from (line, time, cwd). A reply spanning several records never attributes a mention to a later record.

Features recorded per candidate, for later ranking: syntax (link / image / code / bare), line anchor present, target kind (file / directory), extension, exists now.

A line-anchored code reference (`src/foo.swift:42`) is usually a pointer, not a delivery.

Admission for v0.1 is a synthetic rule derived from what a delivery is: a file the agent hands to the person. Each clause is a test case (`AdmissionTests`):

- A link or image is a hand-off: the agent made the file clickable.
- A line anchor (`:42`, `#L42`) points into code instead of handing a file over, so a mention with one never admits a file, even as a link. A heading anchor (`#usage`) points at a section of a document that may itself be the delivery, so it does not block admission.
- Inline code or a bare path admits a file only when it names a place (a directory component) and has no anchor. A bare file name (`App.tsx`) names a topic, not a place.
- Anything inside a fenced code block, or a link written inside inline code, is an example or an instruction, not a hand-off. Fences are read as CommonMark reads them: only a fence of the same character (backtick or tilde) at least as long closes one, and an unclosed fence runs to the end of the reply.
- A path with a placeholder (`build/<name>.zip`, `out/{id}.md`) names a pattern, not a file.

When a log is reread completely, deliveries it no longer admits are removed from the index. Their captures and saved copies stay, so a delivery the log admits again gets its own capture back. A capture belongs to its reply, not to a line: it records the log, the file and the times of the reply's records, and a reread finds a reply's capture by a time no other reply naming the file has, so a log rewritten with its replies moved keeps each reply's bytes, and so does a reply that grew. A reply whose times other replies share, or that has none, is found by its place in the log, as before, but never takes a capture that records a time it doesn't have; when its place is held, it is captured anew under an id of its own that later reads find again. A log with malformed lines removes nothing: what it still names is updated, it is reported as partial, and it is read again on the next run. Neither does a log found shorter than when Gleaner read it, even after an extractor change: it lost records for good, so it removes nothing from then on, however it grows again, and it is reported as found shorter on every run.

Answers to an agent's question prompt (Codex sends them as JSON, sometimes wrapped in a tag) are not requests; the previous request stays as context.

Derived fields (request, evidence) are versioned: when extraction changes, logs are reread and those fields refreshed. Captures record what Gleaner saw at a moment and are never rewritten.

## 10. Search

A result matches when every search term is found in one delivery's own words (request, session, reply), together with the file name, project and collections (§5.5); terms from different deliveries do not combine. The result opens on the newest delivery whose own words matched, falling back to the newest delivery when only the file name, project or collections matched, and shows that delivery's date. Changing the query resets a manually chosen delivery to the matched one.

The index covers, per delivery: the reply excerpt, the user request that started the turn, the session title, the project, the work's collection and the one holding it (§5.5), and the file name with its folder (not the whole path, whose home and `Projects` components would match everything). The delivery sentence alone usually lacks the topic words the user remembers.

A file handed over in a folder (§5.4) is found by its name, its folder and its project. The reply's own words find the folder they named, not each file in it, so a topic word doesn't list a folder's hundreds of files.

## 11. Privacy

- Store excerpts, not whole logs: the reply passage around a mention (up to about 400 characters, cut only at whitespace), the request (up to 2000 characters), titles, paths.
- Redact secret-shaped strings (API keys and access tokens, bearer tokens, `key=value` secrets, credentials in URLs, and runs of 40 or more base64-like characters mixing upper case, lower case and digits; lowercase hex such as hashes and IDs is kept) before storing any excerpt, request, title or link anchor, and before truncating, so a secret at an edge is still recognized. Saved copies are the delivered bytes and are not redacted.
- All data stays local.

## 12. Gates

**Gate 1 — Discovery reliability (Spike A).** On real local sessions, label candidates and a random sample of final replies. Report:

- delivery precision (candidates that are real deliveries),
- recall (deliveries in sampled replies that were extracted),
- locator resolution rate (real deliveries whose file was found),
- duplicate rate (same file mentioned repeatedly).

Library work was meant to start only once these numbers are acceptable. At the user's direction the native library was built before labeling (2026-10-17). Labeling one person's logs would overfit the rule to one working style, so v0.1 ships the synthetic rule in §9, and Gate 1 is measured on broader feedback after release.

**Gate 2 — Artifact usability (Spike B).** With fixed MP4, PDF, Markdown, and HTML-bundle samples: find, preview, detect source change, restore from snapshot, and drag into Finder, Claude Desktop, Codex, and a browser upload field. Show correctly which versions remain available after a worktree is removed.

After both gates: visual polish, incremental indexing performance, cache cleanup, packaging.

## 13. Spike A tool

`swift run gleaner-spike` (see `README.md`) runs the adapters and extractor read-only over the local logs and writes, under `out/`:

- `candidates.tsv` — one row per candidate with request, evidence, resolution, whether the §9 rule admits it (`admitted`, yes or no), and empty `label` / `note` columns.
- `recall-sample.md` — a random sample of final replies with the candidates found in each, for marking misses.
- `summary.txt` — counts per provider, unknown record types, resolution stats.
- `locators.internal.tsv` — full local paths for the owner's checks; never shared.

The sheet lists every candidate, admitted or not, so the §9 rule can be measured against the labels after release.

`out/` contains log excerpts and is never committed.

## 14. Beyond v0.1: connections and reasoning (direction, not scheduled)

Ratified direction. None of this blocks the v0.1 release.

**Three layers.** The core is narrow, the connections are thin, and distribution is broad.

1. **Gleaner Core** — evidence, registry, snapshots, library, native drag. It runs on its own.
2. **Stable local API / CLI** — the only surface extensions use.
3. **Extensions** — one per ecosystem, built on whatever entry point it actually exposes (plugin, skill, MCP, CLI, deep link). Do not assume every ecosystem has a plugin system.

**Source adapter ≠ extension.** An adapter reads a runtime's history into Gleaner. An extension lets that runtime's users call Gleaner. They evolve separately.

**Bidirectional semantics.**

| Direction | Capability |
|---|---|
| Runtime → Gleaner | session logs, delivery statements, artifact references, revision hints |
| Gleaner → Runtime | find, locate, read, resolve an exact version, hand off the file |
| Runtime ↔ Gleaner | optional long-tail reasoning, evidence completion, review feedback |

Adapters are capability-based. A runtime may offer only a read-only log, or also hooks, MCP, or reasoning.

**Extensions stay thin.** They offer three actions: *Find in Gleaner*, *Open in Gleaner*, and *Handoff from Gleaner*, which returns the chosen version's file reference, or an explicitly authorized snapshot transfer for a remote runtime. An extension keeps no artifact database, does not re-parse sessions, copies no snapshots, and manages no versions. Uninstalling it leaves Gleaner fully working.

**Optional reasoning (e.g. DeepSeek through a DSH extension).** A model proposes, and Gleaner verifies.

- Use cases: ambiguous delivery statements, semantic recall ("the Agent Memory demo"), the same logical work at different paths, revisions that disagree with delivery history.
- A model may suggest that a message refers to a file. It may never record "verified", "same version", or "available". Those facts come only from the file system, hashes, and git. Model suggestions wait for local verification or human confirmation.
- Send only minimal, redacted evidence excerpts and candidate metadata, never whole sessions or file contents. Network reasoning is opt-in.
- Bring it in only if labeled data from Gate 1 shows that the deterministic extractor leaves a long tail large enough to matter. Measure its gain against the same labels.

**Distribution.** Ecosystems are channels, not dependencies: GitHub Release / Homebrew, then in-app updates (Sparkle) → agent plugin directories (Claude Code, Codex) → MCP Registry → related communities. The demo is the P0 scenario: a video delivered into a worktree that has since been deleted, found again, its version identified, and dragged into another agent.

## 15. Beyond v0.1: build and release artifacts (direction, not scheduled)

In v0.1, a delivered `SomeApp.dmg` is an ordinary artifact: detected, hashed, located, opened, dragged, and checked for change on the next delivery.

Later, a **Release Group** organizes RCs, final builds, and per-architecture packages, with lightweight metadata: product, version, build number, channel, git commit/tag, source session, sha256, size, architecture, and signing/notarization/stapling checks with their verification time. These are separate steps that can change the bytes, so each keeps its own hash.

- An agent's claim that a build is signed or notarized is evidence, not a fact (§6.2). Release groups add verification of the actual file.
- Artifact version ≠ software release. GitHub Releases is a remote artifact source. Sparkle keeps owning updates. Gleaner indexes, identifies, and hands off; it never builds, publishes, signs, or updates.
- Large installers are not snapshotted by default. Prefer the source file or a published remote asset, and pin only what must be kept.
