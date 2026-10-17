# Changelog

## 0.1.0 (Unreleased)

The first release: a macOS 15 app that lists the files Claude Code and Codex named in their final replies to you.

### Find a delivery

- Reads Claude Code logs (`~/.claude/projects`) and Codex logs (`~/.codex`), skipping sub-agent replies, and watches them for new deliveries while the app is open, including a log folder created after launch. ⌘R checks at once.
- Admits a file named in a final reply by a link, an image, or a path with a folder; skips line-anchored code references, fenced examples (a fence left open runs to the end of the reply) and placeholder paths.
- Searches requests, replies, session titles, file names and projects; every word must appear in one delivery. A result opens on the newest delivery whose own words matched, and returns to it when the search changes.
- Filters by project (the git repository's folder, with worktrees folded in, those of a bare repository too; two projects with one name show their parent folder, and a file outside git says so) and by ten kinds. A file in a deleted worktree keeps its project after a restart, and a worktree kept outside its repository is named as one.
- Tells apart a first index still running, missing log folders, an empty library and no matches. Says per source when logs can't be read or were read with problems, offers Try Again when reading again can help, and keeps showing what it already found.
- Removes a delivery only when a log read whole no longer names it. A log with malformed lines, or shorter than when Gleaner last read it, removes nothing and is reported. A delivery named again gets back what Gleaner first saw of it.

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
- Says why a version can't be handed over: never seen, never read, a folder, too large to have been saved, or a save that failed. Offers only actions that exist, and Check Again wherever it advises checking again.
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
