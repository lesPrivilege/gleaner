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

Type what you remember: words from your request, the reply, the file name, or the project. A result matches only when every word appears in one delivery, so words from two different conversations never combine into a match. The result opens on the newest delivery that matched and shows that delivery's date.

Two menus above the list narrow the results: one by project, one by kind. A project is the git repository that holds the file, with every worktree folded into it; outside git it is the folder the agent worked in. The ten kinds are Documents, Images, Video & Audio, Web Pages, Code, Data, 3D & CAD, Builds & Archives, Folders, and Other.

The detail pane shows the preview, a caption naming exactly which bytes are on screen, the hand-off tile, and the request and reply that delivered the file. Markdown is rendered in place; most other formats use Quick Look. Under **Deliveries**, each time an agent delivered the same path is one line; picking a line switches the preview and the hand-off together. **Compare** shows what changed between two deliveries, or between a delivery and the file on disk now: a line diff for text, side by side for images, size and hash for anything else.

## Status words

Gleaner says only what its own checks show (whether the file exists, its hash, its git state). A claim inside a reply, such as "tests pass" or "final", is quoted as the agent's words and never becomes a status.

| Status | Meaning |
|---|---|
| Seen at delivery | Gleaner read the file within ten minutes of the reply, and it had not been modified since |
| First seen later | Gleaner first read the file after the delivery, for example while reading older logs; it may differ from what was delivered |
| Never seen | The file was gone before Gleaner first looked; only the reply is on record |
| Same as delivery N | The file on disk has the hash of delivery N |
| Changed since delivery N | The file on disk was edited after the last delivery and matches none of them |
| Rolled back to delivery N | The file on disk matches an earlier delivery, not the latest |
| Not on disk | The file is gone; Gleaner offers its saved copy, or notes that git history still has the path |
| Lost | The file is gone, with no saved copy and nothing in git at that path; the delivery record stays |

## Hand-off

Drag the tile in the detail pane, or drag a row from the list, into Finder, a chat, or an upload field. The receiver gets a copy that Gleaner hashed after copying and that matched the chosen version; the original file is never moved, and edits made after the check cannot slip in. When the file on disk no longer matches, Gleaner hands over its saved copy. When neither is available, it says so, and offers the current file only under the label "Not among the deliveries Gleaner found".

| Action | Shortcut |
|---|---|
| Copy the verified file (in the list) | ⌘C |
| Open the verified file | ⌘O |
| Quick Look | Space or ⌘Y |
| Show the original in Finder | ⇧⌘R |
| Copy the original's path | ⌥⌘C |
| Check for new deliveries | ⌘R |
| Close a comparison | Esc |

Show in Finder and Copy Path act on the original location, which may have changed since delivery. Copy, Open, Quick Look and drag use the verified copy.

## What counts as a delivery

Gleaner reads only the final reply of each turn and admits a file when the reply hands it over:

- A Markdown link or image to a local file admits it.
- Inline code or a bare path admits a file only when it includes a folder, such as `out/report.html`. A bare name like `App.tsx` does not.
- A line anchor (`main.swift:42`, `#L42`) marks a code reference and never admits a file. A heading anchor (`guide.md#usage`) does not block admission.
- Paths inside fenced code blocks, links written inside inline code, and paths with placeholders (`build/<name>.zip`) are examples, not deliveries.

Replies from sub-agents are skipped, since they are not addressed to you. This rule was written from the definition of a delivery, not measured on a broad set of real logs. Reports of files it wrongly lists or misses help tune it.

## What Gleaner reads and keeps

- **Reads** Claude Code logs in `~/.claude/projects`, Codex logs in `~/.codex`, and the files those replies name. It watches the log folders while it is open and runs read-only git commands (`--no-optional-locks`) in the repositories it finds.
- **Keeps** excerpts of each reply and request, with secret-shaped strings (API keys, bearer tokens, long hex or base64 runs) redacted, never whole logs. Its index and saved copies live in `~/Library/Application Support/Gleaner`. Every file up to 64 MB is saved when Gleaner first reads it; a larger file is tracked by hash, and **Save a Copy** keeps it while the file on disk still matches the delivery. Saved copies are the delivered bytes and are not redacted.
- **Hand-off copies** live in `~/Library/Caches/Gleaner`. Settings shows their size and clears them; clearing never removes a saved copy.
- **Never writes** to project folders. Gleaner itself makes no network requests. A Quick Look preview of a web page may load what that page references, and links open only when you click them.

## Limits in v0.1

- Folders are listed but not versioned: preview, Open and drag use the folder as it is now.
- An HTML page's images, scripts and stylesheets are not saved with it.
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

The decisions behind v0.1 are in [docs/SPEC.md](docs/SPEC.md); the design exploration and its rulings are in [docs/design/](docs/design/README.md).

### Spike A

```bash
swift build -c release && .build/release/gleaner-spike
```

Reads `~/.claude/projects` and `~/.codex` (read-only; it runs `git status`, `git cat-file`, and `git log` in the repositories it finds) and writes `out/candidates.tsv`, `out/recall-sample.md`, and `out/summary.txt`. `out/` holds log excerpts and is git-ignored.

Options: `--claude-root DIR`, `--codex-home DIR`, `--out DIR`, `--sample N`, `--seed N`.
