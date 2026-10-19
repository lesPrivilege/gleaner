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
- **Handed over.** A final reply named the file. This is a delivery, as today, with its capture.
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
- **Folders.** The outline keeps the workspace's own layout. A folder with many observed files of one kind folds into one row with its count ("out/voice · 211 files"), which opens on demand.
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
2. **Bundles.** A reply that hands over a folder hands over what is in it. Its files are listed with "Handed over in" evidence, stronger than "Appeared during", by metadata, and each is versioned when the person acts on it.
3. **Work units and the window.**
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
  - corrections appended and undone;
  - `scripts/acceptance-home.py <home> capture`.
- `ListingTests` checks the order, the fold and stems.
- `ObservingTests` checks the model, and `WordingTests` the words.
