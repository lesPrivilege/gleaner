# Changelog

## 0.1.0 (Unreleased)

The first release: a macOS 15 app that lists the files Claude Code and Codex named in their final replies to you.

### Find a delivery

- Reads Claude Code logs (`~/.claude/projects`) and Codex logs (`~/.codex`), skipping sub-agent replies, and watches them for new deliveries while the app is open, including a log folder created after launch. ⌘R checks at once.
- Admits a file named in a final reply by a link, an image, or a path with a folder; skips line-anchored code references, fenced examples (a fence left open runs to the end of the reply) and placeholder paths.
- Searches requests, replies, session titles, file names and projects; every word must appear in one delivery. A result opens on the newest delivery whose own words matched, and returns to it when the search changes.
- Groups by project (the git repository's folder, with worktrees folded in, those of a bare repository too; two projects with one name show their parent folder, and a file outside git says so) and filters by ten kinds. A file in a deleted worktree keeps its project and its worktree after a restart, even when a later reply delivers it again or a reread drops and restores it, and a worktree kept outside its repository is named as one.
- Tells apart a first index still running, missing log folders, an empty library and no matches. Says per source when logs can't be read or were read with problems, offers Try Again when reading again can help, and keeps showing what it already found.
- Removes a delivery only when a log read whole no longer names it. A log with malformed lines removes nothing and is reported; a log found shorter than when Gleaner read it lost records, so it removes nothing from then on, however it grows again, and is reported. A path keeps one spelling whether or not it exists, so a file under `/private/var` or `/private/tmp` that is gone at a reread keeps its history, and a folder there is one project with its files. A delivery named again gets back what Gleaner first saw of it, and a log rewritten with its replies on other lines keeps each reply's bytes, found by the times of the reply's records (by its place, as before, when another reply naming the file shares those times or the records carry none).

### Organize work

- A sidebar lists every project, with All Deliveries and Sources. A project opens on an outline: what it is and why, the works delivered last, the joins Gleaner suggests, then every work by the folder it is in; search inside a project searches that project.
- A work is a file, or several files you said are versions of one work, with every delivery of each. Gleaner suggests a join only with its reason (the later file arrived with the bytes the earlier one last had, and that one is no longer at its path; or their names in one folder differ only by a version mark such as `v2` or `final`), and never joins files itself; Keep Apart ends suggestions for that file. Edit › Undo takes back a join, a keep-apart or a move.
- Move to Project… puts a work, and its files' later deliveries, in another project or a new one of your own; a derived project can be shown inside another. Each work says why it is in its project.
- Every correction is kept apart from what Gleaner observed, survives reading the logs again and relaunching, and can be undone one by one or all at once in Sources → Corrections.
- Delivered With reaches every file the reply named. Copy Resume Command gives `claude --resume` or `codex resume` for the conversation, run from the folder it started in, while its log and that folder are there, and says why not otherwise.
- Each agent has a switch, in Sources and in the toolbar's Sources popover: off, its logs are neither read nor watched and its deliveries are hidden, never removed. Each agent's page draws its line to the provider and the models behind its replies, and each delivery names its model, with the vendors' marks from lobe-icons.
- Sources (⌘,) shows each agent's log folder, how and when it was last read, its deliveries and conversations, the logs behind each read problem (unknown record types are counted per type), and what Gleaner reads and skips; Corrections; and Storage, laid out as System Settings lays out a pane.

### Identify the version

- Numbers each delivery of the same path and marks repeated bytes as "same as N".
- States what Gleaner checked: seen at delivery, first seen later, never seen, or never read; same as, changed since, or rolled back to a delivery; not on disk, or lost; a folder, not a regular file, or can't be read. A file Gleaner can't read is never called missing, changed or seen. A delivery whose bytes Gleaner never read is completed, as first seen later, the first time it reads the file.
- Keeps "first seen later" on every label that names a delivery number.
- Marks a list row only when it needs a look: unavailable and why, not on disk, changed (once checked this session), or first seen later. Each file shows its own icon, as Finder draws it, and each delivery its agent's mark (Claude Code, Codex; drawings from lobe-icons, MIT).
- Says a state in as few words as it needs: a mark alone when all is as it should be, a word or two when something needs a look, and the full sentence behind ⓘ, in the help tag and to VoiceOver.
- "Lost" has its own mark, a cross between brackets, so it never differs from "not on disk" by color alone.
- Under Increase Contrast, status colors, the edges of tinted panels and suggestions, and link underlines draw stronger, in light and in dark; under Reduce Transparency, a label floating over a preview turns opaque.
- Quotes claims in replies as the agent's words, never as a status.
- Saves a copy of every file up to 64 MB when first read; Save a Copy keeps a larger one while it still matches.

### Preview and compare

- Previews with Quick Look (Space or ⌘Y), a text view, and a built-in Markdown renderer that fetches nothing. Quick Look shows only the selected delivery's verified copy, and closes when another version is picked.
- Compares two deliveries, or a delivery and the file on disk: a line diff for text, side by side for images, size and hash otherwise, a PDF of any size included. Each end is read once, from a regular file only, and checked by hash; a result shows only for the pair asked for; an end first seen later says so. Versions that differ only in line endings or the final newline say so, never "No changes".
- Lists the other files delivered in the same reply, in the reply's order however many records it took, and opens each on its delivery from that reply.

### Hand off

- Drags the file at the top of the detail, or a list row, as a copy whose hash was checked after copying; ⌘C copies it as a file and ⌘O opens it. A row hands over the version the detail would, a delivered folder's row drags the folder as a copy, and a row with nothing to hand over offers another app nothing (it still drops on a collection). Copies of one version prepared at the same time never remove each other. The tile, ⌘C, Open and Quick Look use a prepared copy only while it is the very file Gleaner hashed, and make it again when another app wrote to, replaced or removed it; the text preview shows the text that was verified.
- Hands over a delivered file by its bytes even when a folder now stands at its path, and a delivered folder only while it is still one.
- Falls back to the saved copy when the file on disk has changed, and labels the current file "not a found delivery" when no delivered version is left.
- Says why a version can't be handed over: never seen, never read, a folder, too large to have been saved, a save that failed, or a saved copy no longer in Gleaner's store. Offers only actions that exist, and Check Again wherever it advises checking again.
- Offers a git restore command for a missing file, naming a commit checked to hold it, instead of restoring it. A file committed in a worktree that has since been removed is found in the repository's history, and the command adds the worktree back at that commit, also when its folder was deleted without git.
- Open and Save a Copy say why when they fail, beside the button.
- Show in Finder (⇧⌘R) and Copy Path (⌥⌘C) act on the original location; Show Folder says when the folder is gone too.

### Observe each conversation's workspace

- Each conversation read now gets a span, when it was working: from each request to the last reply answering it, so the days between a reply and a conversation resumed later aren't in it. The adapters now give each reply's request time, from the request's record. A conversation also gets a workspace: the git checkout of each folder it worked in, else the folder. A workspace is walked when its conversation's span moves, by names, sizes, dates and file identities only, never contents. The home folder and its Library (but for iCloud Drive and cloud storage), system folders, hidden folders, the agents' logs, Gleaner's own library, dependency caches and folders marked as caches with `CACHEDIR.TAG` are skipped, a skipped or gone folder is named in Sources with why, links and other volumes aren't followed, and a walk stops after 100,000 entries, which Sources reports until the conversation is walked again. A walk cut off by a quit, or whose findings couldn't be written, is made again next run.
- A file whose creation or modification date falls in a span is recorded as having appeared or changed during that conversation, the first time Gleaner sees it, and never rewritten; another conversation's observation of it is added beside it. A file whose dates were set after its stretch ended, a copy that kept them, say, isn't counted. It shows when the file appeared or changed, not who made it, and no file type or output folder is left out.
- Observed files are candidates kept beside the deliveries, never deliveries: a delivered file keeps its delivery, and its observation sits next to it, under the name the reply gave it even when the disk spells it in another case. Two corrections join the others, with Undo: a file is not from a conversation, and a file goes with a work, without becoming one of its versions.
- The model can order a project's files (handed over before observed, what a person opens before what a program reads, newest first), fold a folder crowded with one kind into one row with its count, and show files that share a stem together, claiming nothing. A project's outline lists its works so, and what was observed under Observed (see Review).
- The extractor version moves to 15: every log is read once more, and each conversation's workspace observed as the disk is now.

### Hand over a folder's files

- A reply that names a folder hands over what is in it. Each regular file under the folder becomes a delivery of its own, carrying the reply, request, conversation, time and evidence, and saying which folder it was handed over in; a file the reply also named itself, in any spelling, is delivered once, as named. Files are listed as a workspace is walked, by names, sizes, dates and identities only, never contents, with the same skips and bound; hidden files never are.
- A Git repository inside the folder (a submodule, a vendored checkout, a bare repository) is another project: the listing leaves it out, lists everything else, and the folder's detail names it. A package (an app, an Xcode project, an RTFD document, any folder the system declares a package) is one file, as Finder shows it: handed over in a folder as one delivery, a folder, never entered; observed during a conversation as one entry, by its own dates.
- A file counts by the reply's time: created by then and unchanged since, it was handed over; created later, or changed since (edited, or moved, linked or copied in keeping older dates), it isn't, missed rather than claimed. A folder delivered again lists its files again, at its own time, so each file gets one version per delivery of its folder.
- A file's bytes are read when you select it, open or look at it, compare it or drag its row, or when a reply names it: that first read records its hash and saves a copy, as at delivery only when it comes within ten minutes of the reply and the file hasn't changed since. A file not as listed isn't taken for the one handed over; a volume mounted again still matches. Before a hash, two versions say only that their size and dates match, and only when both record the file at their own delivery: "dates" when the creation and modification dates both match, "size and modification date" against a file a reply named, which records no creation date.
- Not unpacked, with why in the folder's detail and Sources: the home, a volume or a cloud drive, or a folder directly in one; a link; a cache, or a folder inside a cache, a hidden folder or a package, a hidden folder kept as a repository (`~/.config`) or holding one (`~/.local/share/<clone>`) included; a package; a project's own folder (a git checkout's or a bare repository's, or the one a conversation worked in or its checkout) or a folder holding the one a conversation worked in; and what the walk skips. A listing cut short is reported in Sources; a folder gone or unreadable is listed once it can be, and named on each run until then, the folders gone folded into one row with their count.
- A project's outline lists a folder's files under their folders, a crowded folder's files of one kind folded into one row; files a reply named never fold. Search finds a folder's file by its name and folder; the reply's words find the folder. A file observed during a conversation and handed over in a folder keeps its observation beside it, and corrections apply to it as to any work.
- Folders already in a library are listed on the next read; no log is read again. The library loads off the main thread at launch, and a file's first read updates that file alone, in the list and outline already shown: with 20,000 files, a first selection no longer stalls the window for over a second.

### Review

- Collections (work units): made in a project, one inside another one level deep, each work in at most one. Renaming, deleting, adding a work and taking one out are corrections, kept through rereads and relaunches, listed in Sources → Corrections and undone one by one, each back to the decision before it. Deleting a collection deletes those inside it and returns their works to the project; undone, they are back. A work added from another project moves with it. Moves are appended too, so undoing one returns the work to the project before it, and to its collection there.
- Keep: a file observed during a conversation becomes a work whose one revision is kept by you, observed during it, listed by its size and dates and read when you act on it. Adding an observed file to a collection keeps it. Undone, it is a candidate again.
- Verdicts (approved, changes requested, rejected, with a note) and published marks (with where) are made on the bytes there then: making one reads the file and records its hash with its size, dates and inode. A file touched, rewritten or replaced since may have changed until it is read, and then has changed, or hasn't; bytes that match a verdict's hash keep it, at any revision; a file gone keeps its verdict as made, unless a later delivery recorded other bytes. A file that can't be read is said as unreadable, never as on this Mac. A file changed since you were shown it isn't judged. Every verdict stays in the history, each can be undone, and Undo All Corrections leaves them. No state completes another.
- To Review holds the works in collections with no verdict on their bytes and the works anywhere whose verdict is on other bytes, by collection. It and each work's states come from sizes and dates, never by reading bytes.
- The sidebar has To Review, with its count, and each project's collections under it. A new collection is named in place; New Collection is in a project's and a collection's menus and the File menu (⇧⌘N), with Add to Collection, Remove from Collection, Rename and Delete. Rows dropped on a collection go in it, and rows can be chosen several at once.
- A collection lists the collections inside it, each with its first image as a poster and what waits, then its works. Its review page shows each work in place: a video plays (AVKit), audio plays in a row, images stand side by side at their own aspects, documents render as the preview pane renders them, and what a program reads is under Other Files, closed; a file stands beside another whose name differs only by its extension. Images are read as their row scrolls into view. Each carries its four states as marks, Review (Approve, Request Changes…, Reject…, with a note), Mark Published… and More; Review All acts on what the page drew whole: never on a file only named, cut off at 64 KB, drawn by Quick Look, too thin to see, or that AVKit or ImageIO couldn't draw. What was recorded and what was refused are both said, where they were asked for. A verdict is bound to the bytes hashed when it is made, and is made only while the file is still as it was drawn; otherwise the page says to look again.
- To Review lists what waits by collection. A work's detail has a Review section: its collection, its verdict and published mark, and its history with Undo. A project's outline lists what sessions were observed doing and no reply handed over under Observed, by session, with Keep, Add to Collection and Not From This Session. A kept file is named as kept, never as a delivery.
- Every decision is on Edit › Undo and announced to VoiceOver in the words Sources → Corrections lists it by. Two marks are new: a collection's, and published.

### Keep data local

- Keeps redacted excerpts, not whole logs, and never writes to project folders. Redacts before cutting an excerpt to length, so a secret at its edge is still caught. Makes no model calls or network requests of its own.
- Runs only read-only git commands, and runs nothing the repository configures while checking a file: no fsmonitor hook or daemon, no signature program for `git log`, and no fetch in a partial clone.
- Sources shows how each log folder read; Storage shows the size of saved copies, and clears hand-off copies, except the one on the clipboard; the selected file's copy is prepared again.

### Known limits

- A delivered folder is not versioned as a whole (its files are, one by one), and HTML dependencies are not saved with a page.
- A file over 64 MB that you didn't save is gone with its worktree, unless git history has it.
- A git clean filter (Git LFS, for one) may still run when git compares a file.
- The admission rule is provisional.
- Files observed during a conversation are listed only in a project where a reply handed something over. A stretch ends at its last reply, so work after a final reply, an interrupted turn, and a background job still running after the last reply to its request fall outside it. A file renamed, or given new permissions, after its stretch is left out with the copies.
- No app icon; the release zip is ad-hoc signed, not notarized.
