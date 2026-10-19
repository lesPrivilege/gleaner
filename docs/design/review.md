# Reviewing

Opus, 2026-10-19. This is layer 3 of [capture.md](capture.md): work units, the window that reviews them, the four states, and review verdicts.

## The owner's case, in general terms

A long task delivers many files. The person wants to review them together, in the shape they have in mind: a series, then its episodes. For each unit, they want to see the things themselves (the video playing, the narration, both covers, the script) and record a judgement about exactly what they saw. They also need to know what is left to review, without opening the conversation or Finder.

Layers 1 and 2 put the files in the library: what replies named, what was in folders they handed over, and what appeared during a session. This chapter adds what only the person can add.

## What a review needs

1. **A unit of review.** The person makes it, because evidence can't. That `00-overview`, `ep00` and `ov` are one episode is the person's knowledge. Files stay where they are on disk.
2. **The thing itself, in place.** Play, hear and show each item without opening another app.
3. **A judgement bound to bytes.** A verdict holds for the exact bytes it was made on. When the bytes change, the verdict stays in the history, the item says so, and the verdict is never carried to the new bytes.
4. **What is left.** A queue drawn from the person's own acts, not from everything ever delivered.
5. **States kept apart.** No state implies another.

## Collections

A work unit is called a **collection** in the window and `WorkUnit` in code, after the original model's name. The same structure serves any kind of work, so the code uses no domain words.

**The structure**
- A collection belongs to one project and has a name the person gives it.
- It may sit inside one other collection, one level deep: a series holds its episodes, and a collection inside another holds no collections of its own.
- It holds works. A work is in at most one collection. A file shared by every episode, such as a logo, stays in the series itself or outside it.

**Making and filling one**
- **New Collection**: in a project's or a collection's context menu, and in the File menu. Its name is edited in place.
- **Rename** and **Delete**. Deleting returns the collection's works to the project. Nothing on disk changes, ever.
- **Add to Collection ▸**: in a row's context menu, for a multiple selection too, or by dragging rows onto a collection in the sidebar.
- **Remove from Collection**.
- **Adding an observed file keeps it** (see below).

**Kept and shown**
- Each change is the person's decision. It is appended like a correction, undone with Edit › Undo, listed under Sources › Corrections, and kept through rereads and relaunches. Files that are gone stay in their collection, said as gone.
- **Order.** Collections go by name in natural order ("2" before "10"). Works go in Listing order: what a person opens first, then newest.

## Keeping an observed file

A candidate (layer 1) stays under its session until the person keeps it. In a project's outline, the files observed and not handed over sit in their own section, **Observed**. They are grouped by session, newest first, folded as Listing folds them, and each says "Appeared during …" or "Changed during …".

Each candidate has three actions:
- **Keep** admits it. It becomes a work whose one revision is "Kept by you, observed during …". The revision carries the size and dates Gleaner listed (the listed capture of §5.4), and its bytes are read on the person's action, as a member's are. Undo returns it to a candidate.
- **Add to Collection** keeps it and puts it in the collection.
- **Not From This Session** detaches it, as in layer 1.

Invariant 1 gains a second door, said as plainly as the first: an item enters the library because a reply named it, or because the person kept a file observed during a session. Either way it can be traced to that reply, or to that decision and the session.

## The four states

Each state is shown for a work's current file, and each is drawn on its own.

| State | What it says | Where it comes from |
|---|---|---|
| **Generated** | How the file came: named in a reply, handed over in a folder, or kept, observed during a session | The deliveries and decisions, as recorded |
| **On this Mac** | There and readable, changed, gone or unreadable, each said as itself (A20) | The locator, as now |
| **Reviewed** | The latest verdict on these bytes: **Approved**, **Changes Requested** or **Rejected**, with an optional note and the time | The person's verdict |
| **Published** | The person's mark on these bytes, with the time and, optionally, where (words or a link) | The person's mark |

**Binding.** A verdict and a published mark each record the file's SHA-256, size and dates at the moment they are made.
- Making one reads the file's bytes then. That is the person's action.
- If the file's size or dates no longer match, the item says "May have changed since review". Once the file is read again (on select, as now), it says either "Changed since review" or nothing.
- Bytes that match a verdict's hash keep that verdict, at any revision (A16, A18).

**Independence (A22).** A published file need not be reviewed. A reviewed file need not be on this Mac. A delivered file need not be reviewed. Nothing completes one state for another: not a version, not a push, not playing a video to the end.

**History.** A work's verdicts and marks are listed newest first, each with its hash. Each can be undone, and none is deleted by a later one.

## The window

**Sidebar**
- **To Review**, at the top, with its count.
- Under each project, its collections, with their own collections under them by disclosure.

**A collection's content column**
- Its collections come first, as rows. Each row has the first image among its works as a poster, the name, the number of works, and only what waits on the person ("3 to review").
- Then its own works, in Listing order.

**A collection's detail: the review page**
- **The header**: the name, then **Review All ▸** (Approve All, and so on, for each work's current bytes).
- **Each work in place**, what a person opens first:
  - a video plays in place (AVKit), at its own aspect;
  - audio plays in a player row;
  - images are shown at their own aspects, side by side when there are several;
  - a document is rendered as the preview pane renders it (Markdown, text, PDF);
  - files a program reads are rows under **Other Files**, closed.
- **Same-stem files** in one folder are shown together, a render with the file beside it ("Beside it: `ov-4x3.svg`"). This claims nothing about derivation.
- **Each item carries**:
  - its name;
  - the four states as marks, with labels only where something needs a look;
  - **Review ▸** (Approve; Request Changes…; Reject…, with an optional note);
  - **Mark Published…**;
  - **More**, which opens the work's own detail.

**A work's detail** gains a **Review** section: the current verdict and the history, the published mark, and their actions.

**To Review** lists, grouped by collection:
- works in any collection whose current bytes have no verdict;
- works anywhere whose verdict was made on other bytes.

A file nobody put in a collection and nobody reviewed is never queued. Otherwise the queue would be the whole library.

**Reading**
- Showing a page plays and renders from disk. That is the person opening it.
- Hashing happens only when a verdict or mark is made, and on select, as now.
- A large video is played where it is and never copied.

**Words** follow window-polish.md's three tiers. The accent marks only what waits on the person: "To review" and an unreviewed item on a review page.

## Not in this chapter

- A model proposing collections. That waits for the evaluation the owner gates.
- "Made from" claims beyond stems shown together.
- Timecoded notes and pronunciation checklists (A08, A09).
- Publishing to platforms, and fetching stats.
- Live capture (layer 4) and written-by evidence (layer 5).

## Layers inside this layer

1. **Core.**
   - `WorkUnit` and its decisions; keeping a candidate; verdicts and published marks bound to bytes; the queue.
   - Persistence with undo, and Organization's derivations, all tested on synthetic libraries.
2. **Window.**
   - The sidebar, a collection's list and review page, the Observed section, a work's Review section, and To Review.
   - Wording tests, and a tour that renders a synthetic series.

## The core, as built

Built on `feat/review`, 2026-10-19. [SPEC §5.5](../SPEC.md) is the contract. Where it settles what this chapter left open, or departs from it:

- **Storage.** A unit is a row of `units`: its key, project, parent, name as made, and when. Everything after that is a correction: adding a work, taking it out, renaming, deleting, and keeping. They are appended, so undoing one returns to the decision before it (A19). A work's unit is the latest of these for any of its files. Keeping is keyed by the file and the session's log.
- **Making a unit isn't listed.** Undoing New Collection removes the unit with every decision naming it, as if never made. Rename, Delete, Add and Remove are each listed under Sources › Corrections. Decisions made together, like keeping an observed file and adding it to a unit, are one line and one Undo.
- **A unit inside a deleted one** is deleted with it, as Finder and Mail delete what a folder holds; its works go back to the project, and Undo brings both back.
- **A work in a unit of another project.** A unit belongs to one project, so adding a work shown elsewhere also moves it there, as one decision, and the work says it was moved. A move to another project takes it out of the unit, and undoing the move puts it back. A work's unit applies only in the work's project, so a work is never listed in one project and in a unit of another.
- **A kept revision** is dated by the write the observation recorded, so it sits among the file's other revisions in time. Its first read completes it as a listed member's does, measured against that write: within ten minutes, unchanged since, `at_delivery`; otherwise first seen later. The read is stored with the observation, so undoing a keep loses nothing and keeping again finds it. An observed package is kept as a folder and never read.
- **Binding records the inode too,** beside the hash, the size and both dates, as a listed file is matched (§5.4). A copy that keeps the size and the dates but replaces the file is then said to have possibly changed, rather than taken for the bytes judged. Dates are compared as stored, in seconds since 1970.
- **Not as shown (A17).** A verdict or mark can carry the file as the person was shown it, by size, dates and inode. If the file isn't so when the verdict is made, nothing is recorded and the window says to look again. A file that changes while it is read is refused the same way.
- **To Review includes "may have changed".** Without reading, Gleaner can't say the bytes differ, only that the file isn't as it was when judged; that waits on the person until a selection reads it. A file gone that was never judged stays queued in its unit, said as gone. One gone after a verdict isn't queued: its verdict stands as made (A22). A folder has no bytes and is never queued.
- **Undo All Corrections** removes units and kept files with the other corrections, and leaves verdicts and published marks, which judge bytes, not how the library is organized.
- **A work of several files** keeps a verdict made on bytes any of its files had. Files the person hasn't joined share no verdict, even with the same bytes (§5.2).
- **Reading.** The model takes the size, dates and inode of each work in a unit or with a verdict when it organizes the library, and remembers the bytes read this session, on select or by a verdict, while the file is still as read. To Review and each work's states draw from these and read nothing.
- **The window** came next: [The window, as built](#the-window-as-built).

Checked: `swift test`.
- `WorkUnitTests`: nesting one level, natural order, membership by the latest decision and undo back to the one before, a work of several files, a work from another project moved with it and out again, rename, delete and undo, taking back a made unit, Undo All, a removed project, a unit following its project shown inside another, another connection to the library.
- `KeepTests`: a kept file's one revision as observed and undone back to a candidate; its first read while as observed, at delivery and first seen later, and not when changed since; adding an observed file to a unit; a reply naming it later; a reread and a relaunch; no bytes read by keeping.
- `ReviewTests`: a verdict on the bytes read; a rewrite, a rollback to approved bytes, a change of dates alone, a copy keeping size and dates (A16, A18); not as shown, gone, a folder and unreadable (A17, A20); history and undo; a work of several files; the four states as a matrix (A22); To Review's contents and grouping; no bytes read but for a verdict; another connection, a reread and Undo All.
- `ReviewingTests`: the model's decisions and their words in Sources › Corrections, verdicts and To Review through a relaunch and a selection, a file changed since shown, and every decision through a reread and a relaunch.

## The window, as built

Built on `feat/review`, 2026-10-19, over the core. [SPEC §5.5](../SPEC.md) gains how it is shown. Where the window settles what this chapter left open, or departs from it:

**Sidebar**
- **To Review** sits under All Deliveries, counted as Mail counts unread mail.
- **A project with collections** opens on them by disclosure, and each collection on those inside it. A collection's badge counts its works and those inside it.
- **New Collection** is named in place, in the sidebar, as Finder names a new folder: Return or leaving the field keeps the name, Escape and an empty name make nothing. It is in a project's menu, in a collection's (inside it; beside it for one already inside another, since collections nest one level deep), and in the File menu (⇧⌘N). Made for rows the person chose, it takes them; made for nothing, it opens.
- **Dropping rows.** A row carries its work, for a collection, as a type only Gleaner reads (`app.gleaner.work`, declared by the app bundle), beside what it hands another app. A row with nothing to hand over now starts a drag too: another app is offered nothing, so no drop there fails. Dragging one of several chosen rows brings all of them, as Finder does.

**Choosing several.** Lists take ⌘- and ⇧-clicks. The detail then says how many, with Add to Collection and Remove from Collection; Open, Quick Look and ⌘C act on the one shown.

**A collection's content column**
- **Its head** is a row of its own, naming it, its counts, what waits, and where it is (the collection it is inside, its project). The head's row shows the review page; so does a row of a collection inside it, while the window stays where it is. A work's row shows the work's detail.
- **Keys.** Return opens a collection chosen inside, and Delete takes the chosen works out.
- **Empty**, it offers Add Works…, the project's works in no collection.

**The review page**
- **What it shows.** The collection's own works. The collections inside it are rows at the top, each showing its own page, so Review All acts only on what the page drew.
- **Review All** gives each work drawn a verdict on the bytes there now: those already given that verdict on these bytes are skipped, as are folders and files gone. Other Files count once opened.
- **The forms**, all the platform's:
  - video: AVKit's player, its floating controls, at its own aspect up to 420 points tall;
  - audio: the same player with its inline controls, as a row;
  - images: ImageIO, at their own aspects, 220 points tall, side by side and wrapping; AppKit reads what ImageIO doesn't (SVG);
  - Markdown and text: as the preview pane draws them, from the file; anything else a person opens, Quick Look;
  - models, builds and folders: the file's own icon.
- **Same stem.** The file drawn is the first a person looks at: a video before an image, an image before a document, a document before audio, else the first in list order. The others are named beside it, each with its own states and actions, and audio beside it plays in its own row. A file a program reads goes under Other Files even when it shares the stem (`ep01.inputs.json`): the page is for looking, and Other Files is where the design puts what a program reads.
- **Marks.** Generated is the agent's mark for a reply or a folder, the observed mark for a kept file. On this Mac shows nothing while the file is there. Reviewed is the check, the open arrow or the crossed circle alone; "To review" in the accent, and "May have changed since review" or "Changed since review" in amber. Published is the tray alone, with words only when its bytes may have changed or did. Each has its sentence in the help tag, and all four are read to VoiceOver with the name.
- **As shown (A17).** Each item takes its file's size, dates and inode as it is drawn, and a verdict binds only to the file still so. A refusal is said at the top of the page, with Look Again, which draws every item again from disk.

**A work's detail** has its Review section after Information:
- its collection, with Remove, or Add to Collection;
- Reviewed, once it is in a collection or has a verdict, and Published, once it has a mark: a state as it should be says nothing;
- every verdict and mark on any of its files, newest first, each with its file, time, hash, note or place, and Undo.

Review and Mark Published act only while the detail shows the file's current bytes: the newest delivery, still on disk, or the current file chosen to hand over. A verdict binds to the bytes shown.

**To Review** lists what waits by collection, named with the one it is inside and its project, then by project; each name leads there. A work reviewed there stays shown until the person moves on, as Mail keeps a message read in Unread.

**Observed** sits after a project's folders, in a project something was handed over in: one whose sessions were only observed isn't listed yet, as the core lists projects. Each file is under the session it was last observed during (a file two sessions observed, under the newer), folded as Listing folds them; a session opens where works open, so it is closed in a repository. A row says Appeared or Changed and its folder: the session is said once, by its group, and each session's full sentence is in the help tag. It has Keep, and a menu with Add to Collection and Not From This Session; a folded row keeps or adds all of its files.

**A kept file** is named as kept wherever a delivery would be named: "Kept file", "Kept by you, observed during …", "Seen as observed", "Kept, not read". No label calls it a delivery, or listed with a folder.

**Corrections** lists an observed file kept to go in a collection as one line: "Kept and added cover.png to Episode 3, observed during Series covers". Collection decisions carry the collection's mark there.

**Undo and VoiceOver.** Every decision goes on Edit › Undo under its name, and is announced in the words Corrections lists it by. A collection made for chosen rows is two steps on Edit › Undo: the adding, then the making.

**Checked**
- **`swift test`:** 343 tests pass; the gallery and the three tours run only with a folder for their pictures.
  - `WordingTests` says each new state as itself and never as another: the Reviewed states in a collection and out of one, the Published states, what waits, On this Mac with unreadable never gone (A20), how a file came, a kept revision never a delivery, collections' counts and names, and a refused verdict's reasons.
  - `ReviewingTests` adds: a collection as a place with its page, its works and those inside it, deleted while shown; naming in place, with what was chosen; several rows chosen, added and dragged together; Observed by session, detached and kept; what waits and where each work is, To Review keeping the work shown, and a file gone after its verdict (A22).
- **The tour.** `GLEANER_TOUR=<folder> swift test --filter TourTests/walkTheReviewOfASeries` writes real videos, builds a synthetic series of three episodes and a compilation (`scripts/acceptance-home.py <home> review`, then `review-revise`), and draws fifteen pictures:
  - the outline, whole, with Observed;
  - the series' list and page, naming a collection in place, two works chosen;
  - episode 1's page in the window and whole, before and after its verdicts;
  - To Review after the recut, and with the recut chosen;
  - the recut's detail and the script's, with their Review sections and history;
  - the note sheet, Corrections, and episode 2's page in dark.

  **What the pictures showed, and what changed:**
  - Corrections said a keep and an add made together twice, file by file; they are now one line.
  - Every work's detail said None, Not reviewed and Not published; nothing is said now until something is decided.
  - An observed file's row ran its other sessions together until they were cut off; they moved to its help tag.
  - A collection chosen in a list wasn't selected in it: the list's selection now names the collection whose page is shown.
- **Not checked:**
  - a video's frames, and the players' glass: drawn off screen, a video is black and AVKit's glass capsule is white;
  - a real drag onto the sidebar, and its highlight;
  - naming in place from the keyboard;
  - VoiceOver listening, and full keyboard access through a page;
  - Increase Contrast and large text.

  These need a person at the window.
