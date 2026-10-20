# The outline

Opus, 2026-10-18, on the window of [projects-and-works.md](projects-and-works.md), [window-polish.md](window-polish.md) and [sources-plane.md](sources-plane.md). The owner set the app's fundamentals before the CLI, MCP and dsh-gleaner, which come later as thin adapters. The first-level objects stay the logical ones: project, then work, then revision, file and evidence. They should read as a navigable outline that gives directory guidance for any task: a little weaker for codebases, where agents revise quickly, and stronger for other work. The owner asked for:
- conventions at every level;
- an interface that teaches its own use;
- graded object distinction;
- an outline view.

The yardstick is airy, clean and clear, after first-party Mac apps and Magpie.

This is the library's outline: projects, works and revisions. A file's own headings are a different outline, the one [structure.md](structure.md) calls Outline. Where the two meet, that one is called Contents.

## Levels

The window reads left to right, as a Finder column view does:
- the sidebar holds places;
- the content column holds a project's works and their revisions;
- the detail holds one revision's file and evidence.

| Level | Object | Where | Type | Mark | Room |
|---|---|---|---|---|---|
| 1 | Project | A sidebar row; the head of its outline | Sidebar text; the head in Title 3 semibold | Its origin: repository, folder outside git, or yours | The head stands alone above the outline |
| 2 | Folder | A section of the outline | The system's section header | None: a group, not an object | A section's space above it |
| 3 | Work | A row in every list | Name in semibold, request in secondary | The file's own icon, at 32 points | 4 points above and below |
| 4 | Revision | A row under its work; a row of Versions | Callout, regular; its request under it in secondary | The endpoint: filled when Gleaner saw the bytes at delivery, hollow when it first saw them later | 2 points above and below, with no rule between revisions |
| 5 | Evidence | The detail | The detail's own sections | The agent's mark, the model vendor's mark | 24 points between sections |

Each level is set apart by more than one of type, mark and room, so the grade holds in grey.

The sidebar keeps places, not items, as Mail's and Finder's do. A tree of works in the sidebar would repeat the list and crowd the places, so a project opens in the content column.

A revision's row keeps the order of its work's row:
- first its number, its file when the work has several, and the agent and date at the end;
- then what you asked for, on a line or two of its own;
- then, only when it has nothing to hand over, why.

Its text starts under its work's name, as a table of contents sets a subsection under its section's title, and its endpoint sits in the gutter to its left.

A work and its revisions read as one group. There is no rule under an open work's row or between its revisions. One rule follows the last revision, starting where every work's rule starts.

## Conventions at every level

**Naming.** Each level is named one way, wherever it appears.
- **A project:** its folder's name, or the name you gave it. Two folders with one name carry their parent's (`client-a/app`). It is drawn by its name alone. What it is made of (a git repository, a folder outside git, a project you made) is metadata: it stays in the help tag, for VoiceOver and in Sources, never as a mark beside the name. A collection is likewise its name alone, under its project, as the indent shows; where a row names both, they read as a path (`Praxis › Covers`).
- **A folder:** its path inside the project (`charts`, `atlas-feature › docs`). The project's own folder is "Top level". A folder outside the project is named as one ("Outside the repository: ~/…").
- **A work:** its newest file's name.
- **A revision:** "Delivery N", with "(first seen later)" when that applies. N is numbered per file (SPEC §5.2), so a renamed work starts again at 1 under its new name. When the work has several files, the revision's row names its file.

**Order, said once.**
- **Objects:** newest first at every level. Projects go by their latest delivery, works by their newest revision, revisions newest first. The sidebar, every list and Versions follow this rule. In the outline, each folder's works follow the order and grouping of [SPEC §5.3](../SPEC.md) (capture.md, "Order and grouping"): what a person opens before what a program reads, then newest first, with a crowded folder's files that no reply named itself folded and files sharing a stem side by side.
- **Folders:** they keep the project's own layout, Top level first and then by name, as Finder lays out a folder.

Because the rule is the same everywhere, no list states it, and no row repeats its place in it.

**Counts.**
- A count says how many of the level below there are. It sits at the trailing end in secondary digits, and is said once.
- **The sidebar's badge:** only what waits on the person, as Mail counts only what is unread: To Review. A project's and a collection's works are counted in their help tags and on their own pages, never as a badge, which would read as something waiting.
- **A folder's header:** the works listed in it.
- **A work's row:** its revisions, when there is more than one, as Mail counts a conversation's messages.
- **The project's head:** the totals (works, deliveries, latest).
- A row says which delivery it shows ("Delivery 1 of 3") only when that is not the file's newest. Before, every row repeated "Delivery 3 of 3".

**Said once.** These repeated words were removed:
- the project's name in the bar above its own outline, where its head already names it;
- "· outside git", and then the mark that replaced it: the name is the project's identity;
- the request, the agent's mark and the date on an open work's row, since its revisions each carry their own;
- "showing report.md" and the delivery's number on an open work's row, since the selected revision's row says both.

## Opening a work on its revisions

A work with more than one revision opens with a disclosure triangle, and its revisions are listed under it. This is how a project expands into works and versions.

| Where | Works start |
|---|---|
| A project outside git, or one of yours | **Open.** Each revision is a step the person may return to: the draft, the revision, the final. |
| A git repository's outline | **Closed.** Agents revise code quickly, the newest revision is the one picked up, and the repository's folders already guide. |
| All Deliveries, and search results | **Closed.** These lists are for recognizing what arrived. |
| A work with one revision | Nothing to open. |

What the person opens or closes stays that way for the session, wherever the work is listed, as Finder keeps a window's open folders.

## Selection, keys, drag and menus

- **Choosing a work's row** shows what the row shows: the revision the search matched, or the newest.
- **A work's row stands for what it names.**
  - Closed, it stands for its revisions: it shows the one chosen in the detail, and drags and opens its menu on it.
  - Open, it stands for the work alone: it drags and opens its menu on the matched or newest revision, whichever revision the detail shows, and each revision's row stands for itself.
- **Choosing a revision's row** shows that revision, as choosing it under Versions does.
- **Choosing under Versions** selects that revision's row when its work is open. When the work is closed, the work's row stays selected, and the detail keeps the revision chosen. Choosing the row that is already selected changes nothing.
- **Keys:** the list's own. ↑ and ↓ move through works and revisions, → opens a work and ← closes it. Space is Quick Look, ⌘O opens and ⌘C copies.
- **Following a link:** when the selection is made outside the list (Recent, Delivered With, a suggestion's file), the list scrolls only as far as it needs to show the row.
- **Dragging:** every row hands over what it names, decided when the drag starts. A revision's row hands over that revision's bytes. Each is a verified copy, as before, never the original. A row with nothing to hand over starts no drag.
- **Right-clicking:** Show in Finder and Copy Path act on the file the row names.

**What needs a look sits on the row it is about.**
- **A revision's row:** says only that it has nothing to hand over. It shows the attention mark and "Unavailable" with why in a few words. The sentence is in its help tag and for VoiceOver. Its endpoint already says whether it was first seen later.
- **An open work's row:** says only what is true of its file now, Not on disk or Changed.
- **A closed work's row:** says what it always said, for the revision it shows.

## Search and the kind filter

- **The kind filter** filters the outline in place, and each folder's count follows it.
- **A search inside a project** lists flat results, newest first, with works closed, as Finder and Mail do. Clearing the search brings the outline back as it was.

## An interface that teaches its own use

Each empty place shows three things, in every list alike, and no how-to sentence:
- its mark;
- a title that names what isn't there;
- the next step, as a control.

A line under the title appears only for a fact the person needs, such as the folders Gleaner watches.

| State | Next step |
|---|---|
| Reading the logs for the first time | The running mark; the count in the subtitle |
| Nothing delivered yet | The folders Gleaner watches, and **Sources** |
| No agent logs found | The folders Gleaner looked in, and **Sources** |
| A project of yours with no work | **Move Work Here…**, which lists works from other projects to bring in |
| Nothing of the kind chosen, in any list | **Show All Kinds** |
| No search results | **Clear Search**, and **Search All Deliveries** inside a project |
| Nothing selected | The newest work in this place, as a button |

The outline teaches itself the same way:
- the triangle and the count show that a work has revisions;
- the endpoint repeats the words "first seen later";
- a suggestion waits in the one accent until it is joined or kept apart.

## Not in this chapter

- **Contents** and **the project timeline**, since built ([structure.md](structure.md#built-on-the-current-window)).
- **Choosing another order.** Newest first is the rule, within a folder of the outline after what a person opens comes first (SPEC §5.3). A name order waits for a case where scanning by name fails.
- **Keeping what is open across launches.** Selection isn't kept either.
- **Moving several works at once.**

## Checked

- **The suite.** `swift test`: 226 tests pass. `OutlineTests` covers five things:
  - which works open, in a folder outside git, in a git repository, in every list and in search;
  - that an open work's row names the work's own revision while another is chosen, and that a revision with nothing to hand over says so on its row alone, with its reason;
  - what choosing a work's row, a revision's row or a delivery under Versions shows, and that the outline follows;
  - that a revision's row drops its own bytes;
  - the arrow keys, sent to the list's own `NSOutlineView` in a window: ↓ moves into a work's revisions, ← closes the work and → opens it again.

  `LibraryModelTests` checks that a row showing its file's newest delivery no longer repeats the number.
- **The tour.** `GLEANER_TOUR=<folder> swift test --filter TourTests` now also draws:
  - the board outline with its works open;
  - the detail with nothing selected, offering the newest work;
  - the chart's first revision chosen in the outline, then the chart closed with its row standing for it;
  - the joined report's three revisions across two files;
  - a project of yours left empty, and its Move Work Here… sheet.
- **Not checked:**
  - clicking a triangle with the mouse;
  - VoiceOver reading a revision's row in place;
  - a drag from a revision's row into Finder (the drop is checked through the model);
  - Increase Contrast;
  - large text.

  These need a person at the window.
