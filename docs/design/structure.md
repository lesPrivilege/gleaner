# Recovering the structure of agent work

Opus, 2026-10-17. Gleaner can now find scattered outputs. It cannot yet show how they relate: which request produced what, how one conversation built on the last, how a project moved over weeks. This round asks what structure the evidence supports, and which views would show it.

## Was it planned?

Not as views. The planning conversation used "timeline" for the sequence of delivery events behind a file's versions (SPEC §5.2), which is what the Deliveries list shows. The design exploration offered a work brief and topic dossiers ([editorial](project-knowledge-explorations.md)); rulings §1 declined both because they make Gleaner an authoring tool. No outline, activity ordering or conversation view was ever specified.

## What the evidence already holds

Every relation below is derived from what agents wrote and Gleaner observed. None needs the person to author anything.

| Level | Unit | Evidence | Stored today |
|---|---|---|---|
| Version | A file's deliveries in order | Same path, each delivery's capture hash | Yes |
| Handover | One reply and every file it named, with the request it answered | Same log, same reply time | Yes (shown as "Delivered with") |
| Thread | One conversation's handovers in order | Same log file | Yes (`deliveries.log_path`, `delivered_at`) |
| Project stream | All handovers in one repository, across conversations and agents | Git-derived project | Yes |
| Document outline | Headings inside one file | The file's own Markdown structure | Derivable (`MarkdownBlock`) |
| Cross-path lineage | `report-v2.md` continues `report.md` | Only a reply that names both, or the person | No, and not inferred |

The handover, not the file, is the unit a person remembers: "the time I asked for the retry policy, it gave me a report, a diagram and a patch". The library is file-first; the structure the person lost is handover-first.

## Three views over the same records

**Thread** answers "what did this conversation produce, in what order?" It lists one log's handovers oldest first: each request, the files that reply named, and the agent's own words. It opens from a delivery's session line. A thread is a page, not a mode: it ends where the conversation ended.

**Project timeline** answers "what has happened in this project?" It lists the project's handovers newest first, across every conversation and agent, grouped by day. Rows keep the order of events but not their spacing, so nothing implies that a gap in the list is a gap in time (Praxis placement rule). Selecting a file goes to it in the library; selecting a request opens its thread.

**Outline** answers "what is inside this document?" For Markdown, the detail view lists the headings the file actually has, and choosing one scrolls the preview. It shows the delivered version's own structure, never a summary.

Ordering choices, all derived:

| Order | Meaning |
|---|---|
| Latest delivery (default) | What arrived most recently |
| Activity | Deliveries in the last 14 days; shows where work is happening now |
| Name | Scanning for a known file |

## What stays out

- **Inferred lineage.** Two files with similar names, or a later file in the same folder, are not versions of each other without a reply that names both or a person who says so. A wrong lineage is worse than none.
- **Authored structure.** Briefs, dossiers, tags and manual groups stay declined (rulings §1) until real use shows retrieval failing without them.
- **Summaries.** A thread shows the requests and replies as written; nothing is generated.
- **Graphs.** The relations are mostly sequences and groups; a list shows them without a canvas to learn.

## Precedents

| Reference | Lesson | Limit |
|---|---|---|
| agentsview "Recent Edits" | A file links to the message that changed it | It is session analytics; Gleaner shows deliveries only |
| `git log` and GitHub's PR timeline | Order of events as a list, each with its author and message | No branch topology to draw here |
| Obsidian outline | Headings that are actually in the document | No editing or reordering |
| Zotero collections | Membership without moving items | Only if authored grouping is ever adopted |

## Ruling

v0.1 ships with the library, versions and Compare; the release work comes first. The next round builds, in order:

1. **Thread**, from the session line in the detail view. Cheapest and closest to how people remember work.
2. **Outline** for Markdown in the detail view.
3. **Project timeline** with the activity order, as the project menu's second mode.

Cross-path lineage waits for evidence-backed links (a reply that names both files) or a person's explicit link, and is designed then.

## Built on the current window

Opus, 2026-10-20: PR #4 built all three on the window before projects and works; they were ported onto main rather than rebased (retrieval rulings §3, step 4). This settles review rulings C12.

**What supersedes what.**
- This chapter supersedes rulings §1 for the timeline and the thread: they are views of handovers over the same records, not a second navigation system, so §1's "Handover groups (B) as a mode" no longer stands.
- Orders: rulings §6 ("newest delivery first") stands, with [outline.md](outline.md) ("Order, said once"). The Activity and Name orders above are not built. The timeline shows where work is happening now, and a name order waits for a case where scanning by name fails (outline.md).
- Placement: the List menu C12 named is gone, and with it the project menu. Every delivery and a project show their works or their timeline, chosen beside the kind filter (Works | Timeline) and under View (as Works, as Timeline), as Finder offers its views. To Review and a collection keep their own lists.

**Handover.** One log and one reply line, however many records the reply took (review rulings §2, A8), the key "Delivered With" uses. Its files are in the order the reply named them, and it is dated by its earliest record. A delivery read before Gleaner recorded reply lines is a handover of its own. A delivered folder's files come with their folder, and a file the person kept was handed over by no reply, so neither is a handover.

**Thread.** The conversation's name, on a delivery's Agent line or a timeline row, opens it in place of the detail: its replies in the order the log holds them, each with its request, its files and the agent's words, laid out as Information. The reply it was opened from is scrolled to and its file set in semibold. Choosing a file shows that delivery; Back and Esc return to the file.

**Timeline.** The listed works' handovers, newest first and grouped by day, with undated ones last under Unknown Date. It follows the place, the kind and the search, and keeps only the listed files in each handover. Its first row is the project's head, or the count of replies across every project, so the first day's header starts below the filter band.

**Contents.** A Markdown preview that scrolls and has more than one heading offers Contents at its top right, listing the headings it has, indented by level. Choosing one scrolls the page to it. It is a menu, not a column beside the text: the preview is a page inside the detail, and a column would crowd it.

Grouping lives in `Sources/GleanerCore/Handovers.swift` and `MarkdownBlock.headings`. `HandoverTests` covers one reply across records, two replies at one time, folders' and kept files, thread order, and timelines of one undated delivery, only undated deliveries and none. `LibraryModelTests` covers opening and leaving a thread and where the timeline is offered; the tour draws the thread and both timelines. Not checked: clicking, the View menu, Esc, and Contents scrolling, which need a person at the window.
