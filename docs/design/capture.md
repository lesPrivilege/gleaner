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
| **Span** | The workspace (Git root, or the working folder) and the session's time span | The adapter, as now: the records' folders and times |
| **Observations** | The files that appeared or changed in the workspace during the span | Gleaner, from the disk's metadata, with no provider code |

The first layer needs no change to any adapter. The span runs from the first record's time to the last's. The workspace is where the records say the agent worked.

## Two kinds of evidence, kept apart

A file whose dates fall inside a session's span shows only that it **appeared or changed during** that session, in that workspace. It does not prove that the session made it. Parallel sessions, copied files and background jobs all fall inside spans too. The owner's case shows discovery coverage (459 of 461 files were found), not how accurate the attribution is.

So Gleaner keeps two kinds of evidence and never turns one into the other:
- **Handed over.** A final reply named the file. This is a delivery, as today, with its capture.
- **Observed.** The file appeared during the span (its creation date falls inside it) or changed during it (its modification date does). This is a candidate:
  - Gleaner records it the first time it sees it and never rewrites it;
  - a later session's observation is added beside it;
  - the person's corrections ("not from this session", "same work as…") are appended, never applied as edits.

Both kinds show in one window, where the person can relate them. A candidate is never labeled "made by" the session or treated as handed over.

**Reading.** Discovery reads metadata only: names, sizes, dates and file identity. Bytes are read when the person acts on a file: when they mark it, hand it on, compare it or open a version. A 742 MB video is listed without being read.

**Skipped:**
- sessions whose workspace is the home folder or a system folder;
- `.git` and hidden folders;
- the dependency and build caches tools leave (`node_modules`, `.build`, `__pycache__`, `.venv`, `DerivedData`, `target`, `dist`).

These skips are structural. No file type is excluded: a script may itself be the deliverable.

## Order and grouping, without fitting

Type, stem and folder help order and group a list. They never decide whether a file enters, or which files are one work. An SVG may be a cover or a source asset, and a script may be the deliverable.

- **Order.** Handed over before observed. Within each, files a person opens (documents, images, audio, video) before files a program reads (data, code). Newest first.
- **Session and request.** What a session handed over and what was observed during it are one list. A request's own span narrows the list when requests are far apart.
- **Folders.** The outline keeps the workspace's own layout. A folder with many observed files of one kind folds into one row with its count ("out/voice · 211 files"), which opens on demand.
- **Stems.** Files in one folder whose names share a stem before their extensions or role suffixes are shown together: `ep00.mp4` beside `ep00.mix.wav`, `ep00.narration.wav` and `ep00.inputs.json`; `ov-4x3.svg` beside `ov-4x3.png`. Showing them together claims nothing: not that one was made from the other, nor that they are one work.

What evidence can't join, the person joins once. That `00-overview`, `ep00` and `ov` are one episode is the owner's knowledge, not the log's. The correction is kept and can be undone. A model may later propose such joins, citing evidence, for the person to accept. That waits for the evaluation the owner gates.

## The four states

Kept apart, as the owner set them:

- **Generated:** handed over in a session, or observed appearing or changing during one (which, when, which agent). These are two evidences, said as such.
- **On this Mac:** the file is there and readable now.
- **Reviewed:** the person's mark on these bytes (their hash, the time, an optional note).
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
2. **The window.**
   - **In a project:** what each session handed over and what was observed during it, by folder, with crowded folders folded and stems shown together.
   - **In the detail:** "Handed over in" and "Appeared during" or "Changed during", and the four states with the Reviewed and Published marks.
   - **Reading:** the Reviewed and Published marks, hand-on and comparison read the bytes then.
3. **Live capture.** FSEvents on a session's workspace while its log is being written.
4. **Written-by evidence.** Structured write records from the adapters, with sanitized fixtures from the owner's session.
5. **Acceptance.** The owner's series, reviewed episode by episode without the conversation or Finder.

## Layer 1, as built

Built on `feat/capture`, 2026-10-19. [SPEC §5.3](../SPEC.md) is the contract. Where it differs from the chapter above, or settles what the chapter left open:

- **The span's ends.** The adapters give times for reply records only, so "the first record's time" is the log file's creation date, which that record's write set, bounded by the first reply for a log copied later. The span ends at the last reply, not at the log's last write: an agent may append to an old log, a title set days later for one, which would stretch the span over days. A session without a reply ends at the log's last write. No adapter changed; work after a final reply, and an interrupted turn, may fall outside the span.
- **Who opens a kind.** A person opens documents, images, audio and video, pages, models, installers and folders; a program reads code, data and formats Gleaner can't place.
- **Crowded** is twelve or more observed files of one kind in one folder. What was handed over never folds.
- **A stem** is the name before its first dot, compared without case, so dotted roles (`ep00.mix.wav`) share it. A hyphen isn't read as a role: `ov-4x3` and `ov-3x4` stay apart.
- **Hidden files** are observed; only hidden folders are skipped, as the skips above say.
- **A project with candidates and no delivery** isn't added to the sidebar's projects yet; `Organization.candidates(in:)` lists any project's candidates, and the window decides in layer 2.
- **The observed mark** is the kit's unverified one, a line to an open circle, in secondary ink.
- **The extractor version** moved to 15, since spans are derived from the logs: every log is read once more, and each session's workspace observed.

Checked: `swift test`. `ObservationTests` reads synthetic sessions in five kinds of work (a video series whose reply names only a folder, with three hundred segments; a report with Markdown, a PDF and charts; a slide deck; a data analysis; a code change in a Git repository), and checks a reread, a later session editing a file, two overlapping sessions, the home folder, the walk's bound, that discovery reads no bytes (access times stay where they were set), a delivered file with its observation beside it, corrections appended and undone, and `scripts/acceptance-home.py <home> capture`. `ListingTests` checks the order, the fold and stems; `ObservingTests` the model; `WordingTests` the words.
