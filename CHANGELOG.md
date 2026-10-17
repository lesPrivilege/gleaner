# Changelog

## Unreleased (after 0.1.0)

Not part of 0.1.0: these changes come after it is tagged.

### The gleaner command

- Adds `gleaner`, for a coding agent on your Mac to find the file you mean, select its exact version, read only what it needs, and hand those bytes on: `find`, `show`, `read`, `resolve`, `handoff` and `verify`. It is built from source (`swift build -c release --product gleaner`); the release zip holds only the app.
- Writes one JSON object to stdout for every answer and every failure, `{"error": {"kind", "message"}}` for a failure, with the message on stderr too. Exits 0 on success; 1 when not found, when there are no bytes for that version, or on another failure; 2 on wrong usage; 3 when there is no library, or one of another version.
- Never indexes: it opens the app's library read-only, and refuses one that is missing, of another version, or can't be opened to read, saying to open Gleaner. Every answer, and every failure once the library is open, carries the index it is evidence of (the library, its runs, when the last finished, how each agent's logs read), so an empty answer from a stale or partial index isn't taken for absence. `--home` reads the library kept for another home folder.
- `read` gives the text of a version's exact bytes, at most 16 KB unless asked, by `--lines` or `--bytes`: from the saved copy whenever there is one, from the original only while it still holds them, in one pass however large the file. `handoff` stages a read-only copy checked by hash, in Gleaner's caches. `verify` checks a delivery, or a reference kept as `resolve` wrote it, by the delivery it names.
- `find --project` takes a project's name or its folder, `/private` or not.

### In the app

- Copy Reference (⇧⌘C, in the Edit menu and in a row's or a delivery's context menu) copies a delivery's reference as `gleaner resolve` gives it.
- Show in Log selects the delivering session's log in Finder; the detail pane gives the reply's line.
- A `gleaner://delivery/<id>` link opens Gleaner on that delivery, and says so when it names none in this library.

### The agents' logs

- Counts each log's records, known records, answered turns, final replies and candidates, and reports in the source status: unknown fields in known record types, logs with assistant records but no final reply, and logs with fewer final replies than when read before. A last turn still under way, or one that ended on a tool call, doesn't count as lacking a final reply.
- Knows Claude Code's `pr-link` record, which holds no reply, instead of reporting it as an unknown record type.
- Keeps a delivered path, and the folder its agent worked in, in one form under `/private`: a project in `/private/tmp` is no longer named "tmp", and a path keeps its form once its file is gone.
- CI runs `swift test` on every push and pull request. An adapter change merges only with passing fixture tests and the owner's review.

## 0.1.0 (Unreleased)

The first release: a macOS 15 app that lists the files Claude Code and Codex named in their final replies to you.

### Find a delivery

- Reads Claude Code logs (`~/.claude/projects`) and Codex logs (`~/.codex`), skipping sub-agent replies, and watches them for new deliveries while the app is open, including a log folder created after launch. ⌘R checks at once.
- Admits a file named in a final reply by a link, an image, or a path with a folder; skips line-anchored code references, fenced examples (a fence left open runs to the end of the reply) and placeholder paths.
- Searches requests, replies, session titles, file names and projects; every word must appear in one delivery. A result opens on the newest delivery whose own words matched, and returns to it when the search changes.
- Filters by project (the git repository's folder, with worktrees folded in, those of a bare repository too; two projects with one name show their parent folder, and a file outside git says so) and by ten kinds. A file in a deleted worktree keeps its project and its worktree after a restart, even when a later reply delivers it again or a reread drops and restores it, and a worktree kept outside its repository is named as one.
- Tells apart a first index still running, missing log folders, an empty library and no matches. Says per source when logs can't be read or were read with problems, offers Try Again when reading again can help, and keeps showing what it already found.
- Removes a delivery only when a log read whole no longer names it. A log with malformed lines removes nothing and is reported; a log found shorter than when Gleaner read it lost records, so it removes nothing from then on, however it grows again, and is reported. A delivery named again gets back what Gleaner first saw of it.

### Identify the version

- Numbers each delivery of the same path and marks repeated bytes as "same as N".
- States what Gleaner checked: seen at delivery, first seen later, never seen, or never read; same as, changed since, or rolled back to a delivery; not on disk, or lost; a folder, not a regular file, or can't be read. A file Gleaner can't read is never called missing, changed or seen. A delivery whose bytes Gleaner never read is completed, as first seen later, the first time it reads the file.
- Keeps "first seen later" on every label that names a delivery number.
- Marks a list row only when it needs a look: not available and why, not on disk, changed (once checked this session), or first seen later. The type badge keeps the exact extension.
- Quotes claims in replies as the agent's words, never as a status.
- Saves a copy of every file up to 64 MB when first read; Save a Copy keeps a larger one while it still matches.

### Preview and compare

- Previews with Quick Look (Space or ⌘Y), a text view, and a built-in Markdown renderer that fetches nothing. Quick Look shows only the selected delivery's verified copy, and closes when another version is picked.
- Compares two deliveries, or a delivery and the file on disk: a line diff for text, side by side for images, size and hash otherwise, a PDF of any size included. Each end is read once, from a regular file only, and checked by hash; a result shows only for the pair asked for; an end first seen later says so. Versions that differ only in line endings or the final newline say so, never "No changes".
- Lists the other files delivered in the same reply, in the reply's order however many records it took, and opens each on its delivery from that reply.

### Hand off

- Drags the tile or a list row as a copy whose hash was checked after copying; ⌘C copies it as a file and ⌘O opens it. A row hands over the version the detail would, a delivered folder's row drags the folder as a copy, and a row with nothing to hand over starts no drag. Copies of one version prepared at the same time never remove each other.
- Hands over a delivered file by its bytes even when a folder now stands at its path, and a delivered folder only while it is still one.
- Falls back to the saved copy when the file on disk has changed, and labels the current file "Not among the deliveries Gleaner found" when no delivered version is left.
- Says why a version can't be handed over: never seen, never read, a folder, too large to have been saved, a save that failed, or a saved copy no longer in Gleaner's store. Offers only actions that exist, and Check Again wherever it advises checking again.
- Offers a git restore command for a missing file, naming a commit checked to hold it, instead of restoring it. A file committed in a worktree that has since been removed is found in the repository's history, and the command adds the worktree back at that commit, also when its folder was deleted without git.
- Open and Save a Copy say why when they fail, beside the button.
- Show in Finder (⇧⌘R) and Copy Path (⌥⌘C) act on the original location; Show Folder says when the folder is gone too.

### Keep data local

- Keeps redacted excerpts, not whole logs, and never writes to project folders. Redacts before cutting an excerpt to length, so a secret at its edge is still caught. Makes no model calls or network requests of its own.
- Runs only read-only git commands, and runs nothing the repository configures while checking a file: no fsmonitor hook or daemon, no signature program for `git log`, and no fetch in a partial clone.
- Settings shows how each log folder read, the size of saved copies, and clears hand-off copies, except the one on the clipboard; the selected file's copy is prepared again.

### Known limits

- Folders are not versioned, and HTML dependencies are not saved with a page.
- A file over 64 MB that you didn't save is gone with its worktree, unless git history has it.
- A git clean filter (Git LFS, for one) may still run when git compares a file.
- The admission rule is provisional.
- No app icon; the release zip is ad-hoc signed, not notarized.
