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
- Quotes claims in replies as the agent's words, never as a status.
- Saves a copy of every file up to 64 MB when first read; Save a Copy keeps a larger one while it still matches.

### Preview and compare

- Previews with Quick Look (Space or ⌘Y), a text view, and a built-in Markdown renderer that fetches nothing. Quick Look shows only the selected delivery's verified copy, and closes when another version is picked.
- Compares two deliveries, or a delivery and the file on disk: a line diff for text, side by side for images, size and hash otherwise, a PDF of any size included. Each end is read once, from a regular file only, and checked by hash; a result shows only for the pair asked for; an end first seen later says so. Versions that differ only in line endings or the final newline say so, never "No changes".
- Lists the other files delivered in the same reply, in the reply's order however many records it took, and opens each on its delivery from that reply.

### Hand off

- Drags the file at the top of the detail, or a list row, as a copy whose hash was checked after copying; ⌘C copies it as a file and ⌘O opens it. A row hands over the version the detail would, a delivered folder's row drags the folder as a copy, and a row with nothing to hand over starts no drag. Copies of one version prepared at the same time never remove each other. The tile, ⌘C, Open and Quick Look use a prepared copy only while it is the very file Gleaner hashed, and make it again when another app wrote to, replaced or removed it; the text preview shows the text that was verified.
- Hands over a delivered file by its bytes even when a folder now stands at its path, and a delivered folder only while it is still one.
- Falls back to the saved copy when the file on disk has changed, and labels the current file "not a found delivery" when no delivered version is left.
- Says why a version can't be handed over: never seen, never read, a folder, too large to have been saved, a save that failed, or a saved copy no longer in Gleaner's store. Offers only actions that exist, and Check Again wherever it advises checking again.
- Offers a git restore command for a missing file, naming a commit checked to hold it, instead of restoring it. A file committed in a worktree that has since been removed is found in the repository's history, and the command adds the worktree back at that commit, also when its folder was deleted without git.
- Open and Save a Copy say why when they fail, beside the button.
- Show in Finder (⇧⌘R) and Copy Path (⌥⌘C) act on the original location; Show Folder says when the folder is gone too.

### Keep data local

- Keeps redacted excerpts, not whole logs, and never writes to project folders. Redacts before cutting an excerpt to length, so a secret at its edge is still caught. Makes no model calls or network requests of its own.
- Runs only read-only git commands, and runs nothing the repository configures while checking a file: no fsmonitor hook or daemon, no signature program for `git log`, and no fetch in a partial clone.
- Sources shows how each log folder read; Storage shows the size of saved copies, and clears hand-off copies, except the one on the clipboard; the selected file's copy is prepared again.

### Known limits

- Folders are not versioned, and HTML dependencies are not saved with a page.
- A file over 64 MB that you didn't save is gone with its worktree, unless git history has it.
- A git clean filter (Git LFS, for one) may still run when git compares a file.
- The admission rule is provisional.
- No app icon; the release zip is ad-hoc signed, not notarized.
