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

- **Storage.** A unit is a row of `units`: its key, project, parent, name as made, and when. Everything after that is a correction: adding a work, taking it out, renaming, deleting, and keeping. They are appended, so undoing one returns to the decision before it (A19). A work's unit is the latest of these for any of its files. Keeping is keyed by the file and the session's log. Corrections are indexed by subject, since every read of a file asks whether it was kept.
- **Moves are appended too.** A move to another project replaced the last one, so undoing a second move sent the work to where Gleaner found it, out of a unit in the project it had been moved to. Each move is now kept on top of the last: undoing one returns the work to the project before it, and to its unit there. Put Back still takes back every move, and Sources › Corrections lists each.
- **Making a unit isn't listed.** Undoing New Collection removes the unit with every decision naming it, as if never made. Rename, Delete, Add and Remove are each listed under Sources › Corrections. Decisions made together, like keeping an observed file and adding it to a unit, are one line and one Undo.
- **A unit inside a deleted one** is deleted with it, as Finder and Mail delete what a folder holds; its works go back to the project, and Undo brings both back.
- **A work in a unit of another project.** A unit belongs to one project, so adding a work shown elsewhere also moves it there, as one decision, and the work says it was moved. A move to another project takes it out of the unit, and undoing the move puts it back. A work's unit applies only in the work's project, so a work is never listed in one project and in a unit of another.
- **A kept revision** is dated by the write the observation recorded, so it sits among the file's other revisions in time. Its first read completes it as a listed member's does, measured against that write: within ten minutes, unchanged since, `at_delivery`; otherwise first seen later. The read is stored with the observation, so undoing a keep loses nothing and keeping again finds it. An observed package is kept as a folder and never read. Undoing a keep takes back, with it, the collection and project decisions made about the file since, while no reply handed the file over: they would stay listed with nothing to act on, and come back with the next keep.
- **Binding records the inode too,** beside the hash, the size and both dates, as a listed file is matched (§5.4). A copy that keeps the size and the dates but replaces the file is then said to have possibly changed, rather than taken for the bytes judged. Dates are compared as stored, in seconds since 1970.
- **Not as shown (A17).** A verdict or mark can carry the file as the person was shown it, by size, dates and inode. If the file isn't so when the verdict is made, nothing is recorded and the window says to look again. A file that changes while it is read is refused the same way. Size, dates and inode are compared, not the inode's change time, which opening a file in many apps moves: a rewrite in place that keeps the size and sets the modification date back (`cp -p` over the file) passes as shown. Hashing at the verdict still binds it to the bytes read then.
- **To Review includes "may have changed".** Without reading, Gleaner can't say the bytes differ, only that the file isn't as it was when judged; that waits on the person until a selection reads it. A file gone that was never judged stays queued in its unit, said as gone. One gone after a verdict isn't queued: its verdict stands as made (A22), unless a delivery after the verdict recorded other bytes, which nobody judged: then it has changed, and waits (A16), or, with no bytes recorded, it may have. A folder has no bytes and is never queued.
- **Undo All Corrections** removes units and kept files with the other corrections, and leaves verdicts and published marks, which judge bytes, not how the library is organized.
- **A work of several files** keeps a verdict made on bytes any of its files had. Files the person hasn't joined share no verdict, even with the same bytes (§5.2).
- **Reading.** The model takes the size, dates and inode of each work in a unit or with a verdict when it organizes the library, when the file is selected, and when a review page draws it, so a file rewritten outside any session is said as the page drew it. It remembers the bytes read this session, on select or by a verdict, while the file is still as read. To Review and each work's states draw from these and read nothing. A regular file Gleaner may not read is unreadable, never on this Mac: `stat` needs no permission to read, so that is asked on its own (A20). Selecting a file no review state is shown for leaves the queue as it was.
- **The window** came next: [The window, as built](#the-window-as-built).

Checked: `swift test`.
- `WorkUnitTests`: nesting one level, natural order, membership by the latest decision and undo back to the one before, a work of several files, a work from another project moved with it and out again, a move undone back to the person's project and its unit there, rename, delete and undo, taking back a made unit, Undo All, a removed project, a unit following its project shown inside another, another connection to the library.
- `KeepTests`: a kept file's one revision as observed and undone back to a candidate; its first read while as observed, at delivery and first seen later, and not when changed since; adding an observed file to a unit; a reply naming it later; a reread and a relaunch; no bytes read by keeping.
- `ReviewTests`: a verdict on the bytes read; a rewrite, a rollback to approved bytes, a change of dates alone, a copy keeping size and dates (A16, A18); not as shown, gone, a folder and unreadable (A17, A20); a file gone after a later delivery, with other bytes, the same bytes or none recorded (A16); history and undo; a work of several files; the four states as a matrix (A22); To Review's contents and grouping; no bytes read but for a verdict; another connection, a reread and Undo All.
- `ReviewingTests`: the model's decisions and their words in Sources › Corrections, verdicts and To Review through a relaunch and a selection, a file changed since shown, and every decision through a reread and a relaunch; a recut gone from disk (A16, A24); a file the page drew rewritten by hand; a file that can't be read (A20); a work added twice, taken out of two collections at once, and a keep undone with what followed it.
- `RegistryTests`: a file's decisions found through the index.

## The window, as built

Built on `feat/review`, 2026-10-19, over the core. [SPEC §5.5](../SPEC.md) gains how it is shown. Where the window settles what this chapter left open, or departs from it:

**Sidebar**
- **To Review** sits under All Deliveries, counted as Mail counts unread mail.
- **A project with collections** opens on them by disclosure, and each collection on those inside it. A collection's badge counts its works and those inside it.
- **New Collection** is named in place, in the sidebar, as Finder names a new folder: Return or leaving the field keeps the name, Escape and an empty name make nothing. It is in a project's menu, in a collection's (inside it; beside it for one already inside another, since collections nest one level deep), and in the File menu (⇧⌘N). Made for rows the person chose, it takes them; made for nothing, it opens. Naming, new or a rename from any menu, opens the project and the collection the row is in, and shows the sidebar if it was hidden.
- **Dropping rows.** A row carries its work, for a collection, as a type only Gleaner reads (`app.gleaner.work`, declared by the app bundle), beside what it hands another app. A row with nothing to hand over now starts a drag too: another app is offered nothing, so no drop there fails. Dragging one of several chosen rows brings all of them, as Finder does.

**Choosing several.** Lists take ⌘- and ⇧-clicks. The detail then says how many, with Add to Collection and Remove from Collection; Open, Quick Look and ⌘C act on the one shown. Removing works from several collections is one decision, one line and one Undo. Adding a work to the collection it is in decides nothing.

**A collection's content column**
- **Its head** is a row of its own, naming it, its counts, what waits, and where it is (the collection it is inside, its project). The head's row shows the review page; so does a row of a collection inside it, while the window stays where it is. A work's row shows the work's detail.
- **Keys.** Return opens a collection chosen inside, and Delete takes the chosen works out.
- **Empty**, it offers Add Works…, the project's works in no collection, as many as the person chooses, added as one decision; with none left, the sheet says every work there is in a collection.

**The review page**
- **What it shows.** The collection's own works, drawn as they scroll into view, so a collection of hundreds plays and reads only what is shown, and images are read no larger than their tiles. Images stand in a grid whose rows are made as they scroll in: laid out in one wrapping row, every image of a page was read, and counted as drawn, when the page opened. The collections inside it are rows at the top, each showing its own page, so Review All acts only on what the page drew.
- **Review All** gives a verdict to each image and document the page drew whole, on the bytes there now: an image ImageIO or AppKit drew large enough to see, and words drawn whole. Videos and audio each need a verdict of their own (A07): a file played isn't a file watched or heard, so its menu says how many wait one by one ("1 video and 1 audio file to review one by one"). Each of its verdicts is offered only while some image or document drawn hasn't that verdict on these bytes. A file only named, beside another or under Other Files, drawn only as its icon, that couldn't be drawn, a document cut off at 64 KB (it says "First 64 KB"), or one Quick Look draws, since Gleaner can't tell what Quick Look drew, is judged on its own Review menu: a source next to its render isn't passed with it (A10).
- **The forms**, all the platform's:
  - video: AVKit's player, its floating controls, at its own aspect up to 420 points tall;
  - audio: the same player with its inline controls, as a row;
  - images: ImageIO, in tiles 220 points tall and at least 360 wide, each fitted at its own aspect, side by side; AppKit reads what ImageIO doesn't (SVG). A picture whose shorter side would be drawn under 44 points in the narrowest tile, a long scroll or a thin banner, is a sliver there and isn't counted as drawn;
  - Markdown and text: as the preview pane draws them, from the file; anything else a person opens, Quick Look;
  - models, builds and folders: the file's own icon;
  - a file gone or unreadable, or a video or audio AVFoundation can't play: the file's icon and why, compact, never a player.
- **Same name, not same stem.** The design put same-stem files together. Grouped by the name before the first dot, `ep01.mp4`, `ep01.vertical.mp4`, both covers and the script stood under one lead, and only the lead was drawn. A file now stands beside another of its folder only when their names differ by the extension alone (`ov-4x3.svg` beside `ov-4x3.png`); every other file is drawn in its own form. Of those, the file drawn is the first a person looks at: a video before an image, an image before a document, a document before audio, else the first in list order. The others are named beside it, each with its own states and actions, and audio beside it plays in its own row. A file a program reads goes under Other Files (`ep01.inputs.json`): the page is for looking, and Other Files is where the design puts what a program reads.
- **Marks.** Generated is the agent's mark for a reply or a folder, the observed mark for a kept file. On this Mac shows nothing while the file is there. Reviewed is the check, the open arrow or the crossed circle alone; "To review" in the accent, and "May have changed since review" or "Changed since review" in amber. A file in a collection with no verdict and nothing there to judge says "Can’t be reviewed" in amber instead, and Remove from Collection takes the place of Review and Mark Published. Published is the tray alone, with words only when its bytes may have changed or did. Each has its sentence in the help tag, and all four are read to VoiceOver with the name.
- **As shown (A17).** Each item takes its file's size, dates and inode as it is drawn, and a verdict is made only while the file is still so; the marks, To Review and Review All take what the page drew. It is bound to the bytes hashed when it is made, which the Review menu's help, the note sheet ("Request Changes to “script.md”") and each verdict's sentence say. A refusal is said under the item asked about, with Look Again, which draws every item again from disk; Review All's is also said at the top, with how many were recorded ("Approved 49 works, 1 not recorded"), and VoiceOver hears both. A refusal is said only where it was asked for, until the person goes elsewhere. A file replaced between that and AVKit's own read of it isn't caught: the player's race is untested.

**A work's detail** has its Review section after Information:
- its collection, with Remove, or Add to Collection;
- Reviewed, once it is in a collection or has a verdict, and Published, once it has a mark: a state as it should be says nothing;
- every verdict and mark on any of its files, newest first, each with its file, time, hash, note or place, and Undo.

Review and Mark Published act only while the detail shows the file's current bytes: the newest delivery, still on disk, or the current file chosen to hand over. A verdict binds to the bytes shown.

**To Review** lists what waits by collection, named with the one it is inside and its project, then by project; each name leads there. A work reviewed there stays shown until the person moves on, as Mail keeps a message read in Unread.

**Observed** sits after a project's folders, in a project something was handed over in: one whose sessions were only observed isn't listed yet, as the core lists projects. Hidden files are never there: no walk lists them. Each file is under the session it was last observed during (a file two sessions observed, under the newer), folded as Listing folds them; a session opens where works open, so it is closed in a repository. A row says Appeared or Changed and its folder: the session is said once, by its group, and each session's full sentence is in the help tag. It has Keep, and a menu with Add to Collection and Not From This Session; a folded row has Keep All and a menu with Add All to Collection, on the row as a file's are.

**A kept file** is named as kept wherever a delivery would be named: "Kept file", "Kept by you, observed during …", "Seen as observed", "Kept, not read". No label calls it a delivery, or listed with a folder.

**Corrections** lists an observed file kept to go in a collection as one line: "Kept and added cover.png to Episode 3, observed during Series covers". Collection decisions carry the collection's mark there.

**Undo and VoiceOver.** Every decision goes on Edit › Undo under its name, as its command names it (Rename Collection, Delete Collection), and is announced in the words Corrections lists it by. A collection made for chosen rows, or from a group the window shows, is one step on Edit › Undo: the making and the adding together.

**Deleting a project of the person's own** deletes the collections made in it, with every decision about them, and can't be undone; its confirmation says how many collections go.

**Checked**
- **`swift test`:** 363 tests pass; the gallery and the three tours run only with a folder for their pictures.
  - `WordingTests` says each new state as itself and never as another: the Reviewed states in a collection and out of one, with nothing there to judge too, the Published states, what waits, On this Mac with unreadable never gone (A20), how a file came, a kept revision never a delivery, collections' counts and names, a note sheet's title, and a refused verdict's reasons, with how many were recorded.
  - `ReviewingTests` adds: a collection as a place with its page, its works and those inside it, deleted while shown; naming in place, with what was chosen; several rows chosen, added and dragged together; Observed by session, detached and kept; what waits and where each work is, To Review keeping the work shown, and a file gone after its verdict (A22); refusals said where they were asked for; a page's layout by name, and pictures too thin to see; a page of 60 images in an 880 by 860 window reading only the rows on screen (with the wrapping row it read all 60); what deleting a project takes with it.
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
  - After the review's repairs, episode 1's page draws its two covers side by side in the grid, the 4:3 one fitted in its tile, its SVG named beside it.
- **A page of edge cases**, drawn once off screen and not kept as a test: a video gone, one unreadable and one AVKit can't play each stand as their icon and why; the gone and the unreadable say "Can’t be reviewed" with Remove from Collection; an image ImageIO can't read is its icon (now with "Can’t show this image", below); a 54 by 1000 picture is a sliver in its tile; a script over 64 KB says "First 64 KB".
- **Not checked:**
  - Review All's own menu on the edge page, which a picture doesn't open: that it passes over what wasn't drawn whole is reasoned from the code, not seen;
  - a video's frames, and the players' glass: drawn off screen, a video is black and AVKit's glass capsule is white;
  - a file replaced while AVKit reads it, after the page took its size and dates (A17);
  - a real drag onto the sidebar, and its highlight;
  - naming in place from the keyboard, and the sidebar shown for it when it was hidden;
  - VoiceOver listening, and full keyboard access through a page;
  - Increase Contrast and large text.

  These need a person at the window.

## Before landing, as built

Built on `feat/review`, 2026-10-19, after a review that traced the layer back to the owner's requirements. Each item, and what checks it:

1. **Keeping what was judged.**
   - A verdict or mark keeps its bytes as saved copies are kept, by hash. Its own read saves a file up to 64 MB, as a first read does. A larger file, or one whose save failed, isn't saved: its row in the work's history, and its item on a review page, say "Not kept · 708 MB · ignored by Git" (or "uncommitted", or "committed"). The sentence behind ⓘ says why there is no copy, what Git holds of the file (in a worktree, that it may not reopen once the worktree's folder is gone), and that once the file is rewritten Gleaner can't show the bytes or hand them on. Git is said of only while the file may still hold the bytes judged: once it holds others, what Git says is about those, so the label leaves it out. Git is asked off the main thread when the label is shown and when the file is selected, and its answer is kept with the file's size, dates and inode as they were then: it is repeated only while the file is still so, and asked again once it isn't.
   - **Save a Copy** sits beside the label while the file may still hold those bytes (read since as them, or still with the size, dates and inode judged). It saves them as a delivery's Save a Copy does, checked by hash before the copy goes into the store, so a file that has changed leaves nothing there (the delivery's Save a Copy now checks the same way), and says so.
   - **The note sheet** says the same before the verdict, for each file over 64 MB whose bytes Gleaner doesn't hold as far as it knows without reading: one read this session as bytes it saved, or still with the size and modification date a revision recorded (or the size, dates and inode of a verdict) whose bytes it saved, is said nothing of. It then offers **Save a Copy** (Save Copies, for several): on for Request Changes, since the changes will be made over the file; off for Reject and Mark Published. Approve has no sheet: its row says it once made. The copy is saved once the verdict is made; one that can't be saved, the store's disk full say, is said with the result, and the verdict's label says why ("You asked Gleaner to keep the bytes judged, and it couldn't save them: …") rather than that it saves them only when asked.
   - **Kept bytes are a version.** The revision that recorded them hands them over from the saved copy. A verdict's row compares the bytes it was made on with the file on disk, whenever Gleaner keeps them and the file holds others, whether or not a revision also recorded them: "what changed since I judged it" is one action, wherever the bytes came from. A verdict whose bytes are kept is the file to drag (components.md): its row's words wash under the pointer and take the grab pointer, and drag its bytes out, staged and hashed. A row whose bytes aren't kept offers no drag.
   - Checked: `ReviewingTests` judges a 65 MiB file a Git repository ignores: the label; Save a Copy from the row; the file rewritten and judged with the sheet's Save a Copy on; and, once the agent writes over it again, both verdicts' bytes compared and staged. It also judges a committed one, said as committed until it is rewritten and selected, then with nothing of Git; a copy asked for into a store that can't be written, said with why; Save a Copy of bytes the file no longer holds, which leaves nothing in the store; and the note sheet after a relaunch, silent about bytes a delivery's Save a Copy kept. `LibraryFlowTests` checks a delivery's Save a Copy leaves nothing either. `WordingTests` says each label and sentence.
2. **Collections in the outline.** A project's outline lists its collections first, after its head: each with its poster, its works (with those inside it) and what waits, and those inside one under it. Choosing one shows its review page and keeps the outline; Return opens it. The sidebar keeps them. A work's row names its collection, with the one it is inside, in its help tag and for VoiceOver. The chapter's design had left collections out of the outline; capture.md had put them first, as the owner's case does. Checked: `ReviewingTests`, and the tour's outline.
3. **Search by collection.** `Work.match` takes the names of the collection holding a work and of the one it is inside, as fields beside the project's name. Words still combine within one work only. A result names its collection on its row. Checked: `ReviewingTests`, a rename included, and the tour.
4. **New Collection from These.** It is in the context menu of a folder's header in the outline, an Observed session, a folded row (works or observed files), files shown together on a review page, and the Delivered With list. While searching, it is on the results' first row, with how many works were found, and in how many projects when more than one ("6 works found in 2 projects"), and in the list's own menu. It names a collection in place holding exactly that group, observed files kept, as one decision: one line in Corrections, and one step on Edit › Undo, as New Collection from These (one made for chosen rows is New Collection), which takes back the making and the adding together; it is announced in Corrections' words. A work already in a collection leaves it, since a work is in one at most: the command's help tag says so before ("Takes 2 of them out of Episode 2"), and the announcement after. On a review page, it makes one inside that collection, or beside it when that one is inside another. For a group spanning projects it is shown disabled, with why in its help tag: a collection holds one project's works, and adding the others would move them. Nothing is inferred. Checked: `ReviewingTests`, `WordingTests`, and the tour, from a search.
5. **Review All** acts on images and documents only (above). A PDF or a page Quick Look draws, and a file drawn as its icon, stay on their own menus, as before. Its menu counts every video and audio file of the page that waits, from what the library knows of each, as To Review does, whether or not it has scrolled into view. Checked: `ReviewingTests` (`ReviewAll` over every form, one video not drawn yet), and the tour's stand-in for its menu.
6. **Hidden files** are never observed: a workspace walk lists no file whose name starts with a dot, as a delivered folder's listing never did (SPEC §5.3, §5.4). The two share the walk, so the listing's own filter went. A library that observed a hidden file before keeps that record: nothing is released, so there is no migration. Checked: `BundleTests` and `ReviewingTests`, with `.env` and `.DS_Store`.
7. **Docs.** capture.md names `docs/MAINTAINING.md` as planned, and its warning on approval is the Not kept label built here; SPEC's title covers the release after 0.1.0; the committed `.DS_Store` is gone and ignored; the READMEs' limits and the changelog's are one list.
8. **Deleting a project of your own** says what it does: each work goes back to the project it was in before. Moves are appended, so taking back the moves into the project leaves each work where the move before put it. Checked: `ReviewingTests`.
9. **A file seen changed, then gone (A16).** The model remembers what it last saw of each reviewed file this session, and when: bytes read, on select or by a verdict, or the size, dates and inode a page drew or the library took. When the file is gone, that decides as a newer delivery's recorded bytes would, unless Gleaner recorded a delivery since: bytes by their hash, a size and dates by the bytes a verdict, or a revision, recorded with them, else "may have changed". So a file seen changed, then deleted, stays changed and in To Review, and a recut delivered while Gleaner runs, then deleted, is changed as it is after a relaunch: the size and dates the library took of it are its delivery's. After a relaunch none of this is remembered, and the verdict stands as made, as for any file gone, unless a delivery recorded other bytes. Checked: `ReviewingTests`: selected, drawn, drawn as judged, a recut delivered in the session, and a relaunch.
10. **An image nothing can draw** says "Can’t show this image" in its tile, with why behind ⓘ, in the help tag and for VoiceOver. Before, it kept the icon a tile shows while it reads. Checked: `ReviewingTests`, `WordingTests`, and the tour.
11. **The README** says that PDFs and web pages, drawn by Quick Look, are left out of Review All, with videos and audio.
12. **No domain words** in Sources' comments: their example names are generic.

**The tour** draws more pictures: the outline with its Collections; a search by a collection's name; New Collection from These named in place, and what it made (then taken back); Review All's menu, as a stand-in drawn from the `ReviewAll` the menu reads, since a menu doesn't open off screen; the note sheet with Not kept and Save a Copy, for a 65 MiB master a Git repository ignores (`scripts/acceptance-home.py review` now writes one); the master's detail after Approve; and an image that can't be drawn.

**What the pictures showed, and what changed:**
- The search's New Collection from These, at first in the bar above the list, cut off itself and the project's name. On a line of its own under the bar, it then sat across the edge of the band the filters sit in, faded, and so would a header pinned to the list's top. It is now the list's first row, below the band, with how many works were found.
- In the note sheet, a checked Save a Copy before "Not kept" read as a contradiction. The label now comes first, then the box that keeps the bytes.
- A verdict's row offered Compare beneath it on every line, even for bytes a revision had recorded, which Versions already compares. It is now an inline Compare beside Undo. It was first offered only for bytes no revision recorded; a review of the current document (2026-10-19) found that made one question, "what changed since my verdict", take two paths, so it is offered for any kept bytes the file no longer holds.
- The tour's detail window, closed with a Quick Look preview in it, still took the next file, and Quick Look stopped the process. The tour now empties a window before closing it; the app's own window is never closed that way.

**Checked:** `swift test`, 382 tests, twice; the tour, `GLEANER_TOUR=<folder> swift test --filter TourTests/walkTheReviewOfASeries`, whose search picture shows the found line below the band.

**Not checked:** the context menus themselves, which only the system draws; VoiceOver reading "Not kept"; a real drag of a verdict's row.

## The current document first

A review of the window on 2026-10-19 took one task as its test: several agents edit an instruction file, and the person wants to read what it says now, see what they last asked of it, and decide; history and differences only when asked. Three changes follow, none adding a state or a table.

- **The file on disk is always shown when it can be read.** A delivery whose bytes are gone (never seen, never read, or no longer held) used to leave the preview empty behind a button, Hand Off the Current File. The detail now shows the file on disk at once, captioned "Current file · not a found delivery", or "Current file · same as delivery N" when another delivery recorded those bytes, and it can be judged as shown. Only that delivery's bytes are unavailable, and the panel says so.
- **Compare with what was judged.** Each verdict's row compares its bytes with the file on disk whenever Gleaner keeps them and the file holds others.
- **What was asked comes next to the file.** The Review section follows the preview, before Information, and the newest verdict's note is read whole; older notes keep two lines. Each line still names the bytes it was made on.

