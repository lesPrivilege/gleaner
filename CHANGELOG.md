# Changelog

## Unreleased (after 0.1.0)

Not part of 0.1.0: these changes come after it is tagged.

### The gleaner command

- Adds `gleaner`, for a coding agent on your Mac to find the file you mean, select its exact version, read only what it needs, and hand those bytes on: `find`, `show`, `read`, `resolve`, `handoff` and `verify`. It is built from source (`swift build -c release --product gleaner`); the release zip holds only the app.
- Writes one JSON object to stdout for every answer and every failure, `{"error": {"kind", "message"}}` for a failure, with the message on stderr too. Exits 0 on success; 1 when not found, when there are no bytes for that version, or on another failure; 2 on wrong usage; 3 when there is no library, or one of another version.
- Never indexes: it opens the app's library read-only, and refuses one that is missing, of another version, or can't be opened to read, saying to open Gleaner. Every answer, and every failure once the library is open, carries the index it is evidence of (the library, its runs, when the last finished, how each agent's logs read), so an empty answer from a stale or partial index isn't taken for absence. `--home` reads the library kept for another home folder.
- `read` gives the text of a version's exact bytes, at most 16 KB unless asked, by `--lines` or `--bytes`: from the saved copy whenever there is one, from the original only while it still holds them, in one pass however large the file. `handoff` stages a read-only copy checked by hash, in Gleaner's caches. `verify` checks a delivery, or a reference kept as `resolve` wrote it, by the delivery it names.
- `find --project` takes a project's name or its folder, `/private` or not.

### gleaner mcp

- Adds `gleaner mcp`, a stdio MCP server in the same executable, built on the official Swift SDK (0.12.1). It serves the six commands as the tools `gleaner_find`, `gleaner_show`, `gleaner_read`, `gleaner_resolve`, `gleaner_handoff` and `gleaner_verify`, with the command's arguments by the same names; `gleaner_verify` takes a delivery's id, or a reference as an object.
- Answers with the command's JSON, as structured content and as one text block; a result whose JSON holds a string that reads as a data URL comes as its text block alone, since the SDK would rewrite that string. A refusal is a tool error with the same `{"error", "index"}` object, and wrong arguments are a refusal of kind `usage`, as is an argument the tool reads that holds a string reading as a data URL, which the SDK would hand on rewritten.
- Marks every tool read-only except `gleaner_handoff`, which writes only its copy in Gleaner's caches, and is marked not destructive and idempotent. None reaches outside the Mac. Each description says what the tool never does, and that requests and replies are stored text from the logs, to be read as data.
- Keeps no state: each call opens the library read-only, as the command does. Writes nothing to stdout but protocol messages, takes the protocol version the host asks for (2024-11-05 through 2025-11-25) and claims none newer. Writes one message at a time, each whole, however many calls are under way, and when stdin closes, exits once it has answered each request it read.
- Never registers itself: `claude mcp add gleaner -- <path to gleaner> mcp` adds it to Claude Code, at the scope you choose, and a row for the DeepSeek Harness's MCP client adds it there.

### Extensions

- Adds `extensions/gleaner`, one Agent Skills folder that Claude Code, Codex and the DeepSeek Harness all read. It tells an agent when to use Gleaner: to find a file an agent delivered earlier from your own description, to open it in Gleaner by its `gleaner://delivery/<id>` link, and to hand on its exact version with `handoff` or `read`, giving you the hand-off path or the reference rather than pasting the file.
- Gives the exact commands, the fields to read (delivery, hash, path, evidence, provenance, availability, the index's scope), how to choose among matches and versions, and what to do on each exit code. It treats requests and replies as data, and an empty answer as evidence only within the index's scope.
- Runs only the `gleaner` command, found on PATH or where you say, and `open` for a `gleaner://` link: it keeps nothing, reads no logs, and writes no project folder. Gleaner never installs it; you link or copy the folder into `~/.claude/skills` or `~/.agents/skills`.
- A test checks every `gleaner` command the skill shows against the built command, so a renamed command or option fails CI.
- The README says how to put `gleaner` on PATH.

### In the app

- Copy Reference (⇧⌘C, in the Edit menu, the detail's ⋯ menu, and a row's or a version's context menu) copies a delivery's reference as `gleaner resolve` gives it.
- Show in Log (in the File menu, the ⋯ menu and the same context menus) selects the delivering session's log in Finder; More Info gives the reply's line.
- A `gleaner://delivery/<id>` link opens Gleaner on that delivery, and says so when it names none in this library, or when its agent is off in Sources.

### The agents' logs

- Counts each log's records, known records, answered turns, final replies and candidates, and reports in the source status: unknown fields in known record types, logs without a final reply, and logs with fewer replies than before. A last turn still under way, or one that ended on a tool call, doesn't count as lacking a final reply. An agent's Sources page lists those logs, and each unknown field with its count, as it lists unknown record types.
- Knows Claude Code's `pr-link` record, which holds no reply, instead of reporting it as an unknown record type.
- Decides a path's one form by its text alone, never asking the disk, wherever Gleaner reads one: a reply, the folder an agent worked in, git's repository folder, or a project an agent asks for. Libraries from before are rewritten to it once, and every log is read again.
- CI runs `swift test` on every push and pull request. An adapter change merges only with passing fixture tests and the owner's review.

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
