# Projects, works and sources

Opus, 2026-10-18, after an independent completion review of main `3a89888`. The review found two byte-correctness defects (A1, A2, fixed first: SPEC §6, §9) and a gap against what the person asked for: they return to work by **project → logical work → revision, file and evidence**, also for non-code work that is renamed between revisions, and they need to see and correct the sources and associations Gleaner relies on before a release. A flat list of paths with a project menu did not do that job.

This chapter is the contract the app now keeps. It supersedes rulings §2's deferral of reassigning projects and its C4 ("the project label is not editable"), and it is the "person's explicit link" that `structure.md` left cross-path lineage waiting for.

## The objects the person sees

| Object | What it is | Who decides |
|---|---|---|
| **Project** | Where work belongs. Gleaner derives one per git repository (worktrees folded in) or per folder an agent worked in outside git (SPEC §5). The person can make their own, move work into it, and show a derived project inside another. | Gleaner, then the person |
| **Work** | One piece of work: a file, or several files the person said are versions of one work (a report renamed from draft to final, a chart saved as `-v2`). | The person only |
| **Revision** | A delivery of one of the work's files: its bytes, its evidence, its provenance. Delivery numbers stay per file (SPEC §5.2). | The logs |

Same bytes, names, folders, sessions or times never make two files one work. Gleaner **suggests** a join only with a reason the person can check, and never applies it:

- **Moved:** a file first arrived with the exact bytes another file last had, after that file was gone from its path.
- **Version mark:** two files in one folder, of one kind, whose names differ only by a version mark (`v2`, `rev 3`, `draft`, `final`, a date, `(1)`). A bare number is not a version mark: `chapter1` and `chapter2` are two parts.

Each file gets at most one suggestion, for the file it most likely continues, and only within one project. A suggestion the person declined is not made again.

## Corrections

A correction is the person's decision, kept apart from what Gleaner observed (review-rulings §3, foundation 2): its own tables (`corrections`, `projects`) in the library. No correction changes a delivery, a capture, a hash or a status. Reading the logs again, a new extractor version and a relaunch all keep them.

| Decision | Scope | Undo |
|---|---|---|
| Move a work to a project, or to a new one | Every file of the work, and later deliveries of those files | Put Back |
| Show a derived project inside another | Every work Gleaner finds in it, now and later | Show Apart |
| Same work | Two files, and through them their works | Undo, beside the join |
| Not the same | Two files: the suggestion stops | Undo, in the list |
| A project of your own | Its name; deleting it returns its work | Delete Project |

Sources → Your Corrections lists every decision with its date and an Undo, and Undo All Corrections resets the organization to what Gleaner found. These are distinct from Read Again (reread logs; derived data only), clearing hand-off copies (cache), and deleting saved copies (never offered).

## The window

- **Sidebar:** All Deliveries, then every project with its count, then Sources. ⌘, opens Sources.
- **A project** opens on its outline: what it is and why (the repository or the folder, the latest three works to pick up from), the joins Gleaner suggests with Same Work and Not the Same, then every work by the folder it is in, as the project's own folders lay it out. A file outside the project's folder is listed under that folder by name, never hidden. Searching inside a project searches that project.
- **A work's detail** keeps the order of the delivery detail (rulings §5): the bytes, the hand-off, the reply. What the work may be (a suggestion) sits under its name, before its bytes. Its deliveries list every file's deliveries, named by file once there is more than one. **Where This Belongs** says why the work is in its project, offers Move to Project…, Put Back or Show Apart, lists the files joined and each join's Undo, and Join With Another File….
- **Delivered with** reaches every file the reply named: six, then Show All.

## Opening

Each action names what it opens.

| Action | Opens |
|---|---|
| Open (⌘O), the tile, ⌘C | The selected revision's verified copy |
| Show in Finder (⇧⌘R), Copy Path | The original's location |
| Show in Finder on a project | The project's folder |
| Copy Resume Command | A command that continues the conversation in its agent: `claude --resume <id>` (in Claude Code 2.1.302's own help) or `codex resume <id>` (OpenAI's Codex CLI reference), run from the folder the conversation started in. Offered only while its log and that folder are there; otherwise the row says why it can't be resumed. |

Gleaner opens no conversation itself and invents no URL scheme for one. A log file is not the conversation, so revealing one is never offered as opening it.

## Sources

Sources → each agent shows its log folder, how the last read went and when, how many deliveries and conversations it gave, each kind of read problem with the logs or folders behind it (Show), and Read Again. It also says what Gleaner reads and what it leaves out: sub-agent transcripts and side chains (Claude Code), sub-agent threads and messages a fork copied from its parent (Codex), examples, line references and placeholders. Admission does not change: a sub-agent's file appears once the main conversation hands it to the person. Gleaner draws no agent topology.

## Paths keep one spelling

Dogfooding the window on a synthetic home under `/var/folders` showed one folder as two projects. `standardizingPath` drops `/private` from `/private/var`, `/private/tmp` and `/private/etc` only while the path exists, so a delivered file that was gone at a reread became another path, a new artifact without its history, and the agent's working folder never matched the files in it. Paths are now spelled one way (`standardPath`), and the working folder is compared in that spelling. The extractor version moved to 13, so logs are read again once.

## Not in this contract

- Folder rules that file future deliveries under a subfolder into another project (a monorepo holding two projects). Moving a work covers its files and their later deliveries; a rule per folder waits for a case where that is not enough.
- Suggestions from a model, or from similarity of content.
- Adding, changing or pausing a source folder.
- An agent topology browser, fork or delegation views.
- PR #4's Thread and project Timeline, which stay for after the tag.

## Verification

- `swift test`: the organization model, corrections and their persistence (`OrganizationTests`); joining, moving, declining, Undo All and a relaunch after rereading every log on a real index (`OrganizingTests`); the conversation route; one spelling for `/private` paths (`ProjectTests`).
- **Walk on the synthetic home.** `scripts/acceptance-home.py` phases `board`, `board-revise` and `board-final` add a non-code project: a report revised and then renamed, a chart revised and then saved as `-v2`, a deck, a PDF brief deleted after delivery, and an appendix delivered from a client-a session. `GLEANER_TOUR=<folder> swift test --filter TourTests` hosts the app's own window off screen on that home and takes a picture at each step: enter the board project, see both suggestions with their reasons, join the renamed report, take its first draft from the saved copy under its own name, reach every file of a nine-file reply, find the brief from its saved copy, find the appendix filed under client-a/app with the reason, move it, read every log again and relaunch with both decisions kept, Sources and Your Corrections, and dark appearance.
- **What the walk is not.** Its steps act through the model, as the buttons do; no click, key, drag or VoiceOver ran. The pictures leave out the toolbar, draw the sidebar's selected row as a black bar and Quick Look's previews blank; the window itself draws them. Drops into Finder and other apps, keyboard traversal, VoiceOver, Increase Contrast and the owner's own judgment stay with the native acceptance in review-rulings §4.
