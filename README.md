# Gleaner

[简体中文](README.zh-CN.md)

Gleaner is a macOS app that lists the files your coding agents (Claude Code and Codex) named in their final replies to you. Search by what you asked for, see which version of a file you are looking at, preview it, compare it with other versions, and drag the exact bytes that were delivered into another app. Gleaner makes no model calls, and nothing it reads leaves your Mac.

Gleaner 0.1.0 runs on macOS 15 or later. It is an early release: which files count as deliveries is decided by a provisional rule (see [What counts as a delivery](#what-counts-as-a-delivery)).

## Installation

**From the release zip.** Unzip `Gleaner-<version>.zip` and move Gleaner to Applications. The app is ad-hoc signed, not notarized, so macOS refuses to open it the first time. After that first attempt, open System Settings → Privacy & Security, click Open Anyway beside the message about Gleaner, and confirm. Later launches open normally.

**From source.** Building needs a Swift 6 toolchain; it is developed with Xcode 26.

```bash
./scripts/bundle-app.sh && open build/Gleaner.app
```

## Search and preview

Type what you remember: words from your request, the reply, the file name, or the project. A result matches only when every word appears in one delivery, so words from two different conversations never combine into a match. The result opens on the newest delivery whose own words (your request, the reply, the session title) matched, or on the newest delivery when only the file name or project did, and shows that delivery's date. When you change the search, a result you had switched to another delivery goes back to the one that matched.

Two menus above the list narrow the results: one by project, one by kind. A project is the git repository that holds the file, with every worktree folded into it wherever the worktree is kept; outside git it is the folder the agent worked in, and the row says "outside git". Two projects with the same name also show their parent folder, and a file in a worktree names that worktree. The ten kinds are Documents, Images, Video & Audio, Web Pages, Code, Data, 3D & CAD, Builds & Archives, Folders, and Other.

The detail pane shows the preview, a caption naming exactly which bytes are on screen, the hand-off tile, and the request and reply that delivered the file. Markdown is rendered in place; most other formats use Quick Look. Under **Deliveries**, each time an agent delivered the same path is one line; picking a line switches the preview and the hand-off together. **Compare** shows what changed between two deliveries, or between a delivery and the file on disk now: a line diff for text, side by side for images, size and hash for anything else. When two versions differ only in line endings or the final newline, Compare says so.

## Status words

Gleaner says only what its own checks show (whether the file exists, whether it can be read, its hash, its git state). A claim inside a reply, such as "tests pass" or "final", is quoted as the agent's words and never becomes a status. A file that is there but can't be read is never called missing, changed or seen.

**How Gleaner first read each delivery**, in the Deliveries list and under Details:

| Status | Meaning |
|---|---|
| Seen at delivery | Gleaner read the file within ten minutes of the reply, and it had not been modified since |
| First seen later | Gleaner first read the file after the delivery, for example while reading older logs; it may differ from what was delivered. Every label that names the delivery's number keeps "first seen later" |
| Never seen | Nothing was at the path when Gleaner first looked |
| Never read | Something was at the path when Gleaner first looked, but it couldn't read it: a file it couldn't open (for want of permission, say), or not a regular file (a pipe, socket or device) |

A delivery Gleaner never saw or never read becomes *first seen later*, once, the first time Gleaner reads the file. Bytes Gleaner has read are never rewritten.

**On disk now**, in the hand-off panel, from a check of the file when you select it:

| Status | Meaning |
|---|---|
| Same as delivery N | The file on disk has the hash of delivery N |
| Unchanged since Gleaner first saw it | The file matches the latest delivery, whose bytes Gleaner first saw after it was delivered |
| Changed since delivery N | What is at the path now (a file, or a folder where a file was delivered) matches none of the deliveries |
| Rolled back to delivery N | The file on disk matches an earlier delivery, not the latest |
| Back to what Gleaner first saw for delivery N | The file on disk matches an earlier delivery whose bytes Gleaner first saw after it was delivered |
| Not among the deliveries Gleaner found | A file is at the path, but Gleaner never read the latest delivery, so it can't tell whether this is it |
| Folder on disk | The delivered folder, shown as it is now; folders aren't versioned |
| Not a regular file | A pipe, socket or device; Gleaner doesn't open it |
| Can't be read | Something is at the path, but Gleaner can't open or read it, so it can't tell which version it is |
| Not on disk | The file is gone; Gleaner offers its saved copy, or notes that git history still has a file at the path |
| Lost | The file is gone, with no saved copy and nothing in git at that path; the delivery record stays |

**In the list**, a row carries at most one mark, and only when something needs a look: *Not available* with why (never seen, never read, not on disk, can't be read, not a regular file, a folder is there now, changed), *Not on disk*, *Changed*, or *First seen later*. Drawing the list never reads the disk, so *Changed* appears only for a file Gleaner has checked since it opened. A file delivered more than once shows "Delivery N of M".

**The agents' logs**, in Settings and, when one needs a look, in a line under the list: *Read*; *Read with problems* (unknown record types, logs with malformed lines or shorter than when last read, logs or folders that couldn't be read); *Can't be read*; *Not on this Mac*. Try Again appears when reading again can help, and what Gleaner already found stays shown.

## Hand-off

Drag the tile in the detail pane, or drag a row from the list, into Finder, a chat, or an upload field. A row hands over the version the detail pane would: the delivery you picked for the selected file, the matched delivery for any other. The receiver gets a copy that Gleaner hashed after copying and that matched the chosen version; the original file is never moved, and edits made after the check cannot slip in. When the file on disk no longer matches, Gleaner hands over its saved copy. A delivered folder is handed over as it is now, as a copy, and only while it is still a folder.

When neither the file nor a saved copy holds the version, Gleaner says why it has none of its bytes: it never saw or never read them, the delivery was a folder, the file was too large to have been saved, or saving it failed. If the file on disk is another delivery, it offers that one; otherwise, when it can read the file there, it offers that file only under the label "Not among the deliveries Gleaner found". A row with nothing to hand over starts no drag. When a file is gone but git still has it, Gleaner shows a command for you to run, naming a commit it checked holds the file: `git restore` from that commit, or `git worktree add` at that commit for a worktree that has been removed. Gleaner never runs it. Wherever Gleaner advises checking again, **Check Again** checks the file now and prepares its copy again.

| Action | Shortcut |
|---|---|
| Copy the verified file (in the list) | ⌘C |
| Open the verified file | ⌘O |
| Quick Look | Space or ⌘Y |
| Show the original in Finder | ⇧⌘R |
| Copy the original's path | ⌥⌘C |
| Check for new deliveries | ⌘R |
| Close a comparison | Esc |

Show in Finder and Copy Path act on the original location, which may have changed since delivery. When the file is gone, Show Folder opens the folder it was in, or says that folder is gone too. Copy, Open, Quick Look and drag use the verified copy.

## What counts as a delivery

Gleaner reads only the final reply of each turn and admits a file when the reply hands it over:

- A Markdown link or image to a local file admits it. A heading anchor (`[guide](docs/guide.md#usage)`) does not block that.
- Inline code or a bare path admits a file only when it includes a folder, such as `out/report.html`, and carries no anchor of any kind. A bare name like `App.tsx` does not.
- A line anchor (`main.swift:42`, `#L42`) marks a code reference and never admits a file, even in a link.
- Paths inside fenced code blocks (a fence left open runs to the end of the reply), links written inside inline code, and paths with placeholders (`build/<name>.zip`) are examples, not deliveries.

Replies from sub-agents are skipped, since they are not addressed to you. This rule was written from the definition of a delivery, not measured on a broad set of real logs. Reports of files it wrongly lists or misses help tune it.

## What Gleaner reads and keeps

- **Reads** Claude Code logs in `~/.claude/projects`, Codex logs in `~/.codex`, and the files those replies name. It watches the log folders while it is open, including one that appears after launch. It finds a file's repository by reading `.git` entries, and runs only read-only git commands in it: `git status --porcelain --ignored` for a file on disk, and for a file that is gone `git rev-parse`, `git log --all` and `git cat-file -e`, to find a commit that holds it. Each runs with `--no-optional-locks`, so git never rewrites the index, and with `core.fsmonitor` off, so it starts no hook or daemon the repository configures. A clean filter such as Git LFS may still run while git compares a file.
- **Keeps** excerpts of each reply and request, never whole logs. Secret-shaped strings are redacted before an excerpt is cut to length: API keys and access tokens, bearer tokens, `key=value` secrets, credentials in URLs, and runs of 40 or more letters and digits that mix upper case, lower case and digits. Lowercase hex, such as hashes and IDs, is kept. The index and saved copies live in `~/Library/Application Support/Gleaner`. Every file up to 64 MB is saved when Gleaner first reads it; a larger file is tracked by hash, and **Save a Copy** keeps it while the file on disk still matches the delivery. Saved copies are the delivered bytes and are not redacted.
- **Hand-off copies** live in `~/Library/Caches/Gleaner`. Settings shows their size and clears them; clearing keeps the copy on the clipboard, which a paste still reads, and never removes a saved copy.
- **Never writes** to project folders. Gleaner itself makes no network requests. A Quick Look preview of a web page may load what that page references, and links open only when you click them.

## Limits in v0.1

- Folders are listed but not versioned: preview, Open and drag use the folder as it is now.
- An HTML page's images, scripts and stylesheets are not saved with it, and Quick Look previews the page without them.
- A file over 64 MB is saved only when you choose **Save a Copy** while the file still matches its delivery. If the worktree holding an unsaved one is deleted, Gleaner can offer it only through git, as a command you run, and only if the file was committed; otherwise it is lost. Save a large file you may need before removing its worktree.
- The admission rule is provisional, pending feedback from more users' logs.
- The app has no icon yet.
- The release build is not notarized.

## Development

```bash
swift test                      # fixture tests
./scripts/bundle-app.sh         # build/Gleaner.app, ad-hoc signed
./scripts/release.sh            # tests, then build/Gleaner-<version>.zip and its sha256
```

`release.sh` refuses to run with uncommitted changes. A commit tagged `v0.1.0` builds as version 0.1.0; any other commit builds as `0.1.0-dev+<commit>`.

- `Sources/GleanerCore`: provider adapters (Claude Code, Codex), mention extraction, locator, redaction, the registry (SQLite), the content store (saved copies, verified hand-off copies), the indexer, the log watcher, and the status logic (`Library.swift`).
- `Sources/Gleaner`: the macOS app (SwiftUI and AppKit, Quick Look).
- `Sources/gleaner-spike`: Spike A, read-only extraction over local logs that writes a labeling sheet.
- `Tests/GleanerCoreTests`: fixture tests built from sanitized record shapes, and the library flow (concurrent edits, deleted worktrees, rollback, backfill, verified staging).
- `Tests/GleanerTests`: the app's decisions on a synthetic library (which delivery a click lands on, which bytes Quick Look, Compare and a drag use) and its wording.

The decisions behind v0.1 are in [docs/SPEC.md](docs/SPEC.md); the design exploration and its rulings are in [docs/design/](docs/design/README.md).

### Spike A

```bash
swift build -c release && .build/release/gleaner-spike
```

Reads `~/.claude/projects` and `~/.codex` read-only, checks each named file with the same read-only git commands as the app (`git status`, `git rev-parse`, `git log`, `git cat-file`), and writes under `out/`:

- `candidates.tsv`: one row per candidate, admitted or not, with the request, the evidence, what was found at the path, whether the delivery rule admits it (`admitted`, yes or no), and empty `label` and `note` columns to fill in. A rerun keeps the labels already entered. Paths start with `~`, and text is redacted.
- `recall-sample.md`: a random sample of final replies with the candidates found in each, for marking misses.
- `summary.txt`: counts per agent, unknown record types, and what was found at the named paths.
- `locators.internal.tsv`: each candidate's full log path, log lines and file path, for your own checks; never share it.

`out/` holds log excerpts and is git-ignored.

Options: `--claude-root DIR`, `--codex-home DIR`, `--out DIR`, `--sample N`, `--seed N`.
