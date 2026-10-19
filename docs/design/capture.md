# Capture from the session

Opus, 2026-10-19. This chapter replaces two drafts from the same day that fit one case:
- reading folder-and-range shorthand in replies;
- finding episodes by numbered names.

The owner set the bar. Capture should take what an agent's session gives, naturally, and catch the key artifacts without the person doing anything. It must not be fitted to one kind of work, since different work has different key artifacts, and keeping the topology general is the key problem. Adapters stay thin, and a coding agent can maintain them plainly.

## The owner's case, checked

The owner's series (`Praxis/palantir/reading-list-series`) was made in one Claude Code session with 94 subagent logs, over 36 hours. With the owner's permission, Gleaner's author read that session's record shapes, tool names, paths and timestamps. No message text was read. The author also read the series folder's names, sizes and dates.

- **Names don't carry the topology.** One episode is named three ways:
  - the folder `episodes/00-overview/`;
  - the video `out/ep00.mp4`, beside `ep00.narration.wav`, `ep00.mix.wav` and `ep00.inputs.json`;
  - the covers `ov-4x3.svg` and `ov-4x3.png`.

  Any naming rule would be written for this series.
- **The log's own records miss the media.** Claude Code records the files its Write and Edit tools touch, and after each Bash call a diff of text files (`bashEditDiff`). Together these name 168 of the folder's 461 files, all of them text. They name none of the 119 WAV, 15 PNG, 13 JPEG or 7 MP4 files, which are what the person reviews.
- **The disk catches nearly all of it.** 459 of the 461 files were created or last changed while the session, its subagents or its background tasks were running.
- **Single tool calls can't be told apart.** Subagents ran in parallel, so most files fall inside several tool calls' windows. Attributing a file to one call by time alone would be a guess.

So capture rests on the session, not on the tool call, and finds files on the disk, not only in what the log says it touched. What the disk finds is an observation, not proof of who made the file.

## What every session gives

Every agent session, whatever the provider and whatever the work, gives three things:

| | What | From |
|---|---|---|
| **Intent** | The requests, and the files a final reply hands over | The adapter, as now |
| **Span** | The workspace (Git root, or the working folder) and the session's time span | The adapter: the records' folders, and the times of each request and its replies |
| **Observations** | The files that appeared or changed in the workspace during the span | Gleaner, from the disk's metadata, with no provider code |

The span runs from each request to the last reply answering it. The time between a reply and the next request is left out: a conversation resumed days later wasn't working in between, and the person's own edits then aren't its. The workspace is where the records say the agent worked. The first layer's one adapter change is the request's time, a key the request's record already carries.

## Two kinds of evidence, kept apart

A file whose dates fall inside a session's span shows only that it **appeared or changed during** that session, in that workspace. It does not prove that the session made it. Parallel sessions, copied files and background jobs all fall inside spans too. The owner's case shows discovery coverage (459 of 461 files were found), not how accurate the attribution is.

A file's dates can also be set. A copy that keeps them (`cp -p`, `rsync -a`, Finder, an archive) carries older dates into the workspace, and they would fall inside an old session's span. The inode's change time can't be set back, so a file whose inode last changed after the stretch its date falls in isn't placed there. The cost is a miss, never a false claim: anything that rewrites the inode later also moves that time, including a new permission, a rename, or an extended attribute such as the last-used date some apps write when a file is opened. A session read soon after it works, as the log watcher reads it, is unaffected. One first read long afterwards misses the files changed that way since. In the owner's series none were: no file's change time moved after the session.

So Gleaner keeps two kinds of evidence and never turns one into the other:
- **Handed over.** A final reply named the file, or a folder holding it (layer 2). This is a delivery, as today, with its capture.
- **Observed.** The file appeared during the span (its creation date falls inside it) or changed during it (its modification date does). This is a candidate:
  - Gleaner records it the first time it sees it and never rewrites it;
  - a later session's observation is added beside it;
  - the person's corrections ("not from this session", "goes with this work") are appended, never applied as edits.

Both kinds show in one window, where the person can relate them. A candidate is never labeled "made by" the session or treated as handed over.

**Admission.** No file enters the library on its own; only a reply that hands it over, or the person, admits it. A candidate stays where it was observed, under its session in its project. It isn't searched, counted or queued for review. Keeping one is the person's admission, appended like any correction and undone the same way.

**Reading.** Discovery reads metadata only: names, sizes, dates and file identity. Bytes are read when the person acts on a file: when they mark it, hand it on, compare it or open a version. A 742 MB video is listed without being read.

**Skipped:**
- sessions whose workspace is the home folder or a system folder, a hidden folder, or the agents' logs or Gleaner's own library, so Gleaner never observes transcripts or itself;
- `.git` and hidden folders;
- the dependency caches tools leave (`node_modules`, `__pycache__`, `DerivedData`; `.build` and `.venv` are hidden), and folders their tool marked as a cache with a `CACHEDIR.TAG` file (Cargo's `target`).

These skips are structural. No file type is excluded: a script may itself be the deliverable. No output folder is excluded by its name either: `dist` or `build` may hold what was asked for.

## Order and grouping, without fitting

Type, stem and folder help order and group a list. They never decide whether a file enters, or which files are one work. An SVG may be a cover or a source asset, and a script may be the deliverable.

- **Order.** Handed over before observed. Within each, files a person opens (documents, images, audio, video) before files a program reads (data, code). Newest first.
- **Session and request.** What a session handed over and what was observed during it are one list. A request's own span narrows the list when requests are far apart.
- **Folders.** The outline keeps the workspace's own layout. A folder with many files of one kind that no reply named itself, observed or handed over in a folder, folds into one row with its count ("out/voice · 211 files"), which opens on demand. A file a reply named never folds.
- **Stems.** Files in one folder whose names share a stem before their extensions or role suffixes are shown together: `ep00.mp4` beside `ep00.mix.wav`, `ep00.narration.wav` and `ep00.inputs.json`; `ov-4x3.svg` beside `ov-4x3.png`. Showing them together claims nothing: not that one was made from the other, nor that they are one work.

What evidence can't group, the person groups once, into **work units**: a series, an episode, a chapter, a demo. A work unit sits between a project and its works and may span folders, repositories and sessions. It nests once, so a series holds episodes. That `00-overview`, `ep00` and `ov` are one episode is the owner's knowledge, not the log's. It puts three different works into one work unit. It is not a same-work join: a video, its narration and its cover are not versions of one another, and none takes another's revisions or review. The grouping is kept and can be undone. A model may later propose groupings, citing evidence, for the person to accept. That waits for the evaluation the owner gates.

## The four states

Kept apart, as the owner set them:

- **Generated:** handed over in a session, or observed appearing or changing during one (which, when, which agent). These are two evidences, said as such.
- **On this Mac:** the file is there and readable now.
- **Reviewed:** the person's verdict on these bytes: approved, changes requested or rejected, with their hash, the time and an optional note. Approving a file that is uncommitted in a worktree says that it may not reopen once its folder is gone.
- **Published:** the person's mark on these bytes (the hash, the time, an optional place or link).

A mark stays when the file changes, and the item says "Changed since review". None of the four implies another.

## Maintenance

Provider code is one map per provider, from record shapes to requests, replies, folders and times. It is what the adapters already are. Everything else is shared: the span, observations, order, groups, marks and the window. A new agent is one adapter and its fixtures. When a provider adds a structured record of what a tool wrote (as Claude Code's Write tool and Codex's `apply_patch` do), the adapter may report it as extra evidence ("written by the agent"). Capture never depends on it.

Each shape an adapter knows keeps a sanitized fixture line from a real log and the record's known keys, and drift shows as unknown-field counts, as today. `docs/MAINTAINING.md` gives a coding agent the loop: take the new log line, sanitize it, add the fixture, update the map, and run the fixture tests.

## Layers

1. **Observations.**
   - For each session, its workspace and span, and the files that appeared or changed during it, kept as candidates beside deliveries.
   - Metadata only; bytes are read on the person's action.
   - Tests on synthetic sessions in several kinds of work: a video series, a report, a slide deck, a data analysis, and a code change.
2. **Bundles.** A reply that hands over a folder hands over what is in it. Its files are listed with "Handed over in" evidence, stronger than "Appeared during", by metadata: each is a delivery of its own file, versioned with that file's other deliveries, whose bytes are read when the person acts on it.
3. **Work units and the window.** Designed and built in [review.md](review.md), which settles what follows: collections sit in the sidebar, under their project, rather than first in its outline, and candidates under Observed, after its folders.
   - **In a project:** work units first (a series, then its episodes), then what each session handed over and what was observed during it, by folder, with crowded folders folded and stems shown together. Candidates stay under their session until kept.
   - **In a work unit's detail:** its works played, heard and shown in place, each with "Handed over in", "Appeared during" or "Changed during", its versions, and the four states.
   - **Review:** the Reviewed verdict and the Published mark. They, hand-on and comparison read the bytes then. The review queue is a saved view of the library (delivered or new revisions awaiting review), not a second library.
4. **Live capture.** FSEvents on a session's workspace while its log is being written.
5. **Written-by evidence.** Structured write records from the adapters, with sanitized fixtures from the owner's session.
6. **Acceptance.** The owner's series, reviewed episode by episode without the conversation or Finder.

## Layer 1, as built

Built on `feat/capture`, 2026-10-19, and revised after its review the same day. [SPEC §5.3](../SPEC.md) is the contract. Where it differs from the chapter above, or settles what the chapter left open:

- **The span** is a list of stretches, one per request: from the request's record to the last reply answering it, a minute either side, joined where they meet. A reply to a task notification answers the request before it, so a background job between the two is inside; one still running after the last reply to its request is not. A session without a reply time has no span: an interrupted turn and a title appended later give none. The first build ran one span from the log file's creation date to the last reply, and a conversation resumed days later covered the days between. The owner's case was counted against the whole session (459 of 461 files); stretches may place fewer of its files.
- **The adapters changed** for this, and only for this: each turn carries `requestAt`, the `timestamp` of the human request's record (Claude Code) or of the typed user message (Codex), kept with the request by a reply to a task notification. Both keys sit on records the adapters already read, and the fixtures already carried them. Under `AGENTS.md`, this merges only with the owner's review.
- **The inode change time** (`st_ctime`) is read with the other dates, and a file is placed in a stretch only when its inode last changed before that stretch ended. A copy keeping older dates is left out, whether the session is read for the first time (the extractor bump, a fresh library) or again. So is a file renamed or given new permissions after its stretch: Gleaner misses it rather than claims it. Hence "That says when it appeared" stands in the window's words.
- **When a workspace is walked.** A session's span, workspaces and the folders not walked are recorded with its log's reading. It waits to be walked when its span or workspaces moved, or when its last walk came before its span ended. It is marked walked only once its observations are recorded, so a quit or a failed write leaves it waiting, and the next run walks it whether or not its log changed. A log read again for a title, or reread every run for a malformed line, walks nothing once its session is walked. The window reloads the observations only when a run recorded one, and groups them by file then, off the main thread, so a correction doesn't regroup them.
- **Not walked, and why.** The workspace's own name is checked too, so a session in `~/.claude` or `~/.codex` walks nothing. So is a workspace that is, holds or is inside the agents' log folders, Gleaner's saved copies or its hand-off copies, or that holds its registry. Inside the home's Library only `Mobile Documents` (iCloud Drive) and `CloudStorage` are walked. Each check compares the folder as the disk has it, links followed and case as on disk (`realpath`), so `/Volumes/Macintosh HD` is `/`. A walk doesn't enter a folder on another volume. Each folder a session worked in and that isn't walked is kept with its reason (gone, or which skip), and Sources lists them apart from the problems.
- **Output folders.** `dist` and `target` were in the chapter's list of caches. A folder's name is no better evidence than a file's type: `dist` is where a build puts what it made. Only `node_modules`, `__pycache__` and `DerivedData` are skipped by name. A folder holding `CACHEDIR.TAG`, which Cargo writes into `target`, is skipped by that mark, read by name only. The owner may rule otherwise.
- **Another spelling of a delivered file.** When a workspace is walked, the paths delivered by the sessions in it, and any delivered path under it in any case, are looked up by device and inode. A walked file that is one of them is observed under the delivered name, beside its delivery, not as a second file.
- **Storage.** Observations are keyed by path, then log, in a table without row ids. The session's id is kept once, with its span. Each session's observations are written as its matches are found.
- **Who opens a kind.** A person opens documents, images, audio and video, pages, models, installers and folders. A program reads code, data and formats Gleaner can't place. Each extension's kind is looked up once.
- **Crowded** is twelve or more observed files of one kind in one folder. What was handed over never folds.
- **A stem** is the name before its first dot, compared without case, so dotted roles (`ep00.mix.wav`) share it. A hyphen isn't read as a role: `ov-4x3` and `ov-3x4` stay apart.
- **Hidden files** are observed. Only hidden folders are skipped, as the skips above say.
- **A package is one entry.** Finder shows a package (an app, an Xcode project, an RTFD document, a bundle: any folder whose extension the system declares conforming to `UTType.package`) as one file, and a person opens it as one. So the walk never enters one: it is observed as one entry, by its own creation, modification and inode change dates, under the same rule as a file (`Workspace.place`). A build that makes an app is observed making the app, not each of its resources. An app rebuilt in place whose own folder's dates don't move (Xcode touches it; not every tool does) isn't observed changing. Whether an extension is a package is the system's declaration, looked up once per extension, not a list Gleaner keeps: it is structure, as a hidden folder is, not a type deciding admission. `.framework` and `.xcassets`, which the system doesn't declare packages, are walked as folders.
- **A project with candidates and no delivery** isn't added to the sidebar's projects yet. `Organization.candidates(in:)` lists any project's candidates, and the window decides in layer 2.
- **The observed mark** is the kit's unverified one, a line to an open circle, in secondary ink.
- **The extractor version** moved to 15, since spans are derived from the logs. Every log is read once more, and each session's workspace observed as the disk is now.

Checked: `swift test`.
- `AdapterTests` checks each turn's request time against both fixtures.
- `ObservationTests` reads synthetic sessions in five kinds of work: a video series whose reply names only a folder, with three hundred segments; a report with Markdown, a PDF and charts; a slide deck; a data analysis; a code change in a Git repository. It also checks:
  - a reread, a later session editing a file, two overlapping sessions;
  - stretches, and a conversation resumed days later;
  - a copy keeping its dates, on a first and a later reading;
  - a session walked again only when its span moves;
  - observations that couldn't be recorded, recorded next run;
  - the home folder, its Library, hidden folders, the agents' logs and Gleaner's library, and the home through a link or in another case;
  - `CACHEDIR.TAG` and `dist`;
  - a delivered file named in another case;
  - the walk's bound, and that discovery reads no bytes (access times stay where they were set);
  - a delivered file with its observation beside it;
  - an app built during a session, observed as one entry by its own dates, nothing inside it;
  - corrections appended and undone;
  - `scripts/acceptance-home.py <home> capture`.
- `ListingTests` checks the order, the fold and stems.
- `ObservingTests` checks the model, and `WordingTests` the words.

## Layer 2, as built

Built on `feat/bundles`, 2026-10-19. [SPEC §5.4](../SPEC.md) is the contract, and Invariant 1 now says that naming a folder names what is in it. Where it differs from the chapter above, or settles what the chapter left open:

- **A folder's files are deliveries, not observations.** Each is a revision of its own file's work, carrying the reply, session, request, time and evidence of the folder's delivery, and which folder delivery it came through. Works stay per path (SPEC §5.1a), so a file a reply also named itself numbers those deliveries together with its folder's, by time. Nothing joins files: the folder and its files are separate works.
- **Listed by the workspace walk.** `Workspace.walk` lists the folder as it lists a workspace: metadata only, no links, no other volume, the same structural skips and the same bound, a listing cut short reported in Sources. Hidden files, which layer 1 observes, are never a folder's files.
- **A repository inside is another project.** The walk never enters a folder below the delivered one that is a Git repository's own (one holding `.git`, as a submodule or a vendored checkout does, or a bare repository, holding `HEAD`, `objects` and `refs`), and lists everything else. None of that repository's files is a member, and the folder's detail says it was listed without it, naming where it is. The first build stopped at the first such folder and left the whole folder unpacked ("a folder holding a Git repository"): a site with its theme as a submodule handed over nothing, and what the walk had found before stopping depended on name order. The repository inside is someone's project, often not this conversation's work, so its files aren't claimed; the rest of the folder is what the reply named. What stays not unpacked is a folder that is, or holds, the folder the conversation worked in or its checkout: that is the project itself.
- **A package is one file.** As in layer 1, a package in the folder is one member, never entered. It is a folder-kind delivery, listed and not versioned as a delivered folder is, never read, seen at delivery when listed within the live window of a reply after its last write, and its own files are never members: an app handed over in `build/` is one work, not its `Contents`. A package a reply names itself isn't unpacked, for the same reason ("a package, which Finder shows as one file").
- **Not unpacked**, with why, in words that complete "it is": named by a reply without a time; a link; what a workspace walk skips; the home, a volume or a cloud drive, or a folder directly in one, by depth; a cache, or a folder inside a cache or a hidden folder; a package; a repository's own folder; the folder a conversation worked in or its checkout, inside git as outside it, or a folder holding either. Handing over a project points at the project, which only those last reasons say; layer 1 observes what changed there. The folder and why are named in its detail and, apart from problems, in Sources. The review found the first build checking only the folder's own name and parent: a folder named inside `~/.config` or `.build`, inside Cargo's `target` or `node_modules`, a volume, a cloud drive, a link, a bare repository, and a working folder inside git were all unpacked.
- **Where hidden, cache and package folders are counted from.** Every folder up to the home, or the root. The second build counted from the checkout itself, below its name: with `~/.config` kept as a repository, a reply naming `~/.config/gh` unpacked it, and `hosts.yml`, with its token, became a delivery and searchable. The third counted from the folder holding the checkout, which still unpacked a clone kept in `~/.local/share` or `~/.config/nvim`, and a folder inside an app a reply named. A hidden folder above the checkout is passed only when a repository other than the home holds it, as a repository keeps its agents' worktrees (`.claude/worktrees/<name>`), which are unpacked as layer 1 walks them. Members are admitted, searched and handed on, unlike layer 1's candidates, so this check is stricter than `Workspace.skipped`, which walks `~/.config/nvim` as a workspace.
- **Membership by the reply's time.** With 2 seconds of grace, the clock tolerance §5.1 already uses: created by the reply and its inode unchanged since, handed over as it is; anything else, not. The ruling first gave a middle case, created by the reply and changed since, handed over and said to have possibly changed. The review showed it wrong on APFS: a file moved (`mv`), linked (`ln`) or copied keeping its dates (`cp -p`, `ditto`, `rsync -a`) into the folder after the reply carries a creation date from before it, so the middle case claimed files added later, months later on a backfill. Its correction is layer 1's rule (`Workspace.place`): a file whose inode changed after the reply is missed, never claimed. A listing near the reply, as the log watcher makes it, loses only what changed in the seconds between; a backfill misses the files written since, which is as much as the dates show.
- **Listed, then read.** A file's capture holds its size and dates as `listed` until Gleaner first reads it: when the person selects it (which Quick Look, Open, Compare and the tile act on), drags its row, or a reply names it, in the run that lists the folder or a later one. That read completes every listing the file still matches (path, inode, creation and modification dates, and size; not the device number, which changes when a volume is mounted again), at delivery only under §5.1's rules and with the inode unchanged since the reply, else first seen after. One that no longer matches stays listed and is said to be not as listed: the bytes read now aren't shown to be the ones handed over. A file the folder's reply, or another naming a path in it, named in another spelling is listed under that name, as layer 1 records an observation. The chapter's "versioned when the person acts on it" is that: versions follow deliveries; acting on one reads its bytes.
- **Storage.** `members`, keyed by path then folder delivery, without row ids, one row per folder delivery and file, written as listed, with whether it is a file or a package; each carries only its own fields, and is read as a copy of its folder's delivery, so a reply's request and evidence are read once per folder, not once per file. `listings`, one row per folder delivery, records when it was listed, how many files, why it wasn't unpacked, what the listing couldn't see and the repositories it left out; a folder delivery without one is what the next run lists, so a library read before this layer has its folders listed then, with no log read again and no extractor version bump. A folder gone or unreadable gets no listing yet, and each run names it until one can list it, since a volume may come back. Sources folds the folders gone into one row with their count under each agent: a removed worktree's `dist/` would otherwise be a line on every run.
- **Search** finds a folder's file by its name, its folder and its project, which is its folder's. Its delivery carries the reply's words but isn't found by them: they find the folder, so a topic word doesn't return hundreds of files.
- **The window.** A project's outline lays out each folder's works as `Listing.rows` orders them: what a person opens first, newest first, stems side by side, and files of one kind that no reply named itself folded from twelve, those handed over in a folder apart from those observed. Layer 1 folded only observed files; what a reply named still never folds. The outline is made again only when what the window lists changes. The detail names the folder a file came in, with a link to it; a folder's detail counts its files or says why they aren't listed; Versions says "same size and dates" before a hash, only between deliveries that record the file as it was at each, comparing size, modification and creation dates; a file a reply named records no creation date, so against it the words are "same size and modification date". A row drag reads a listed file at the drop. A first read puts that one file's deliveries in place rather than reading the library again, and the app reads the library off the main thread at launch. A first read or a saved copy changes captures only, never what lists, orders, folds or finds a work, so the list and the outline already made keep their rows with the work as it is now, and the files its reply named with it list its deliveries as they are now; anything more (other deliveries, another place) makes them again. Measured in release with 20,000 files handed over in 200 folders, each first selection of an unread file cost the main actor about 1.44 s, listing and outlining the project again; it now costs a few milliseconds. The project's Recent names what replies named. All Deliveries and search results list a folder's files unfolded.
- **Not in this layer.** Candidates still aren't listed in the window: where they show, and a project with candidates and no delivery, wait for layer 3.

Checked: `swift test`.
- `BundleTests` reads synthetic sessions whose replies name folders, in five kinds of work: a media pipeline with three hundred nested segments, a hidden `.env` and `.DS_Store`, a hidden folder and a cache; a report; a static site whose page the reply also named; a data analysis's output; a code change naming a folder inside its repository. It also checks:
  - a repository's folder, the home, a folder directly in it, the folder a conversation worked in and one holding it, none unpacked, each with its reason;
  - a site holding its theme as a submodule and a vendored bare repository, listed without them and naming them, and the same site handed over by a conversation working in the theme, not unpacked;
  - a folder holding an app, an RTFD document and a framework: the app and the document one member each, folders, nothing in them listed or read; the app named itself, not unpacked;
  - a folder inside `.config` or `.build`, inside a cache's `target` or `node_modules`, none unpacked, `.config` kept as a repository included, and an agent's worktree in a hidden folder, unpacked, as layer 1 decides for both;
  - a cloud drive, a folder directly in one, and a link, none unpacked, and a folder deeper in a drive, unpacked;
  - a working folder inside a repository and one holding it, a bare repository and a folder holding one, none unpacked;
  - a folder gone, one whose parent can't be searched and one that can't be listed, each listed once it can be, and named on every run until then, the gone one apart, for Sources to fold;
  - membership by time on a live read (added after; edited, moved, linked or copied in after) and on a backfill;
  - a folder delivered twice, and a file in a folder also named itself, whose listing a later capture completes, in a later run or the same one;
  - a file named in another case, delivered once as named;
  - a listed file read as listed after its device number changed;
  - one artifact read alone, the same as read with the rest;
  - a candidate in a folder a later reply names;
  - a library read before this layer, listed on the next run;
  - a reread and a relaunch, and a file changed since it was listed;
  - corrections on a folder's file, and undo;
  - that listing reads no bytes (access times, a file Gleaner can't read, a FIFO, a large sparse file), and the first read's provenance;
  - the listing's bound;
  - `scripts/acceptance-home.py <home> bundle`.
- A volume, a folder directly on it and a link to it were checked by hand on a disk image: none unpacked; a folder deeper on the volume, unpacked.
- `ObservationTests` now finds a folder's files handed over beside their observations.
- `ListingTests` checks that a folder's files fold apart from observed ones, and named files never.
- `BundlingTests` checks the outline's folding and order, search by name, reading on selection and at a row's drop, a first read put in place in the list and the outline already made (statuses, "same as N" and the files a reply named with it as read), versions (size and dates said to match only when both record the file at their delivery, "dates" only when both recorded its creation date), corrections and undo, and the words. `TourTests` walks the bundle phase in pictures (`GLEANER_TOUR=<folder>`).
