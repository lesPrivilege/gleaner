# Changelog

## 0.1.0 (Unreleased)

The first release: a macOS 15 app that lists the files Claude Code and Codex named in their final replies to you.

### Find a delivery

- Reads Claude Code logs (`~/.claude/projects`) and Codex logs (`~/.codex`), skipping sub-agent replies, and watches them for new deliveries while the app is open. ⌘R checks at once.
- Admits a file named in a final reply by a link, an image, or a path with a folder; skips line-anchored code references, fenced examples and placeholder paths.
- Searches requests, replies, session titles, file names and projects; every word must appear in one delivery.
- Filters by project (git repository, with worktrees folded in) and by ten kinds.
- Tells apart a first index still running, missing log folders, an empty library and no matches.

### Identify the version

- Numbers each delivery of the same path and marks repeated bytes as "same as N".
- States what Gleaner checked: seen at delivery, first seen later, or never seen; same as, changed since, or rolled back to a delivery; not on disk, or lost.
- Quotes claims in replies as the agent's words, never as a status.
- Saves a copy of every file up to 64 MB when first read; Save a Copy keeps a larger one while it still matches.

### Preview and compare

- Previews with Quick Look (Space or ⌘Y), a text view, and a built-in Markdown renderer that fetches nothing.
- Compares two deliveries, or a delivery and the file on disk: a line diff for text, side by side for images, size and hash otherwise.
- Lists the other files delivered in the same reply.

### Hand off

- Drags the tile or a list row as a copy whose hash was checked after copying; ⌘C copies it as a file and ⌘O opens it.
- Falls back to the saved copy when the file on disk has changed, and labels the current file "Not among the deliveries Gleaner found" when no delivered version is left.
- Offers a git restore command for a missing file instead of restoring it.
- Show in Finder (⇧⌘R) and Copy Path (⌥⌘C) act on the original location.

### Keep data local

- Keeps redacted excerpts, not whole logs, and never writes to project folders. Makes no model calls or network requests of its own.
- Settings shows the log folders read, the size of saved copies, and clears hand-off copies.

### Known limits

- Folders are not versioned, and HTML dependencies are not saved with a page.
- The admission rule is provisional.
- No app icon; the release zip is ad-hoc signed, not notarized.
