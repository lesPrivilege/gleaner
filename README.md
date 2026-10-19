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

Type what you remember: words from your request, the reply, the file name, or the project. A result matches only when every word appears in one delivery, so words from two different conversations never combine into a match. The result opens on the newest delivery whose own words (your request, the reply, the session title) matched, or on the newest delivery when only the file name or project did, and shows that delivery's date. When you change the search, a result you had switched to another delivery goes back to the one that matched. A file handed over in a folder is found by its name, its folder and its project; the reply's words find the folder.

The sidebar lists All Deliveries, every project, and Sources. A project is the git repository that holds the file, with every worktree folded into it wherever the worktree is kept; outside git it is the folder the agent worked in, marked with a folder instead of a repository's branches. Two projects with the same name also show their parent folder, and a file in a worktree names that worktree. Searching inside a project searches that project. A menu above the results narrows them by kind: Documents, Images, Video & Audio, Web Pages, Code, Data, 3D & CAD, Builds & Archives, Folders, and Other.

The detail pane is laid out as Finder's preview pane: the file itself, with its own icon, to drag and open, a line saying exactly which bytes it carries and whether Gleaner verified them, then the preview, then **Information**: your request, the reply that delivered the file, the agent (by its own mark) and conversation, when, what is on disk now, and where. Markdown is rendered in place; most other formats use Quick Look. Under **Versions**, each time an agent delivered the same path is one line; picking a line switches the file, its preview and the hand-off together. A state that is as it should be shows only its mark; one that needs a look says so in a word or two, with the full sentence behind ⓘ. **More Info** keeps the path, hashes and session log. **Compare** shows what changed between two deliveries, or between a delivery and the file on disk now: a line diff for text, side by side for images, size and hash for anything else. When two versions differ only in line endings or the final newline, Compare says so.

## Projects and works

A project opens on its outline: what it is and why, the works delivered last, the joins Gleaner suggests, then every work under the folder it is in, what you open before what a program reads, newest first. When a reply names a folder, each file in it is a work handed over in that folder, listed under its own folder; a folder crowded with such files of one kind folds them into one row with their count, while files a reply named never fold. The file's detail names the folder it came in and the reply; the folder's detail counts its files, or says why it isn't unpacked (your home, a volume or a cloud drive, a folder directly in one, a hidden folder or a cache, a project's own folder). A work delivered more than once opens on its deliveries, each with your request; outside git and in projects of your own they start open, in a git repository closed. Use ← and → to close and open one. A work is a file, or several files you said are versions of one work, such as a report renamed from draft to final; its detail lists every delivery of each file. Gleaner never joins files by itself. It suggests a join only with a reason you can check: the later file arrived with the exact bytes the earlier one last had, and that one is no longer at its path; or the two names in one folder differ only by a version mark (`v2`, `rev 3`, `draft`, `final`, `(1)`; a date or a bare number names another document). Choose **Join** or **Keep Apart**; after Keep Apart, Gleaner suggests nothing more for that file. Edit › Undo takes back a join, a keep-apart or a move.

**Project**, in a work's detail, says why the work is in its project (the repository it is in, the repository its agent worked in, or the folder outside git), and offers **Move to Project…**, to another project or a new one of your own, and **Join With Another File…**. A derived project can be shown inside another from its menu in the sidebar. These decisions change only how Gleaner shows the library, never a file, a delivery or a status; reading the logs again keeps them. **Sources → Corrections** lists each one with Undo, and Undo All.

**Copy Resume Command**, beside the conversation, copies `claude --resume <id>` or `codex resume <id>`, with a `cd` to the folder the conversation started in, to continue it in Terminal. It is offered while the conversation's log and that folder are there; otherwise it says why it can't be resumed. **Delivered With** reaches every file the reply named.

## Status words

Gleaner says only what its own checks show (whether the file exists, whether it can be read, its hash, its git state). A claim inside a reply, such as "tests pass" or "final", is quoted as the agent's words and never becomes a status. A file that is there but can't be read is never called missing, changed or seen.

**How Gleaner first read each delivery**, in Versions (by its mark, with words for the exceptions) and under More Info:

| Status | Meaning |
|---|---|
| Seen at delivery (filled dot) | Gleaner read the file within ten minutes of the reply, and it had not been modified since |
| First seen later (hollow dot) | Gleaner first read the file after the delivery, for example while reading older logs; it may differ from what was delivered. Every label that names the delivery's number keeps "first seen later" |
| Never seen | Nothing was at the path when Gleaner first looked |
| Never read | Something was at the path when Gleaner first looked, but it couldn't read it: a file it couldn't open (for want of permission, say), or not a regular file (a pipe, socket or device) |
| Listed, not read | A file handed over in a folder the reply named, listed by its size and dates; Gleaner reads it when you select, open, compare or drag it |

A delivery Gleaner never saw or never read becomes *first seen later*, once, the first time Gleaner reads the file. A file listed with its folder is read then too, while it is still as listed: *seen at delivery* within ten minutes of the reply if it hasn't changed since, *first seen later* otherwise. Bytes Gleaner has read are never rewritten.

**On Disk**, under Information, from a check of the file when you select it:

| Status | Meaning |
|---|---|
| Same as delivery N | The file on disk has the hash of delivery N |
| As first seen | The file matches the latest delivery, whose bytes Gleaner first saw after it was delivered |
| Changed | What is at the path now (a file, or a folder where a file was delivered) matches none of the deliveries |
| Back to delivery N | The file on disk matches an earlier delivery, not the latest |
| Back to delivery N as first seen | The file on disk matches an earlier delivery whose bytes Gleaner first saw after it was delivered |
| Can't verify | A file is at the path, but Gleaner never read the latest delivery, so it can't tell whether this is it |
| Folder | The delivered folder, shown as it is now; folders aren't versioned |
| Not a file | A pipe, socket or device; Gleaner doesn't open it |
| Can't read | Something is at the path, but Gleaner can't open or read it, so it can't tell which version it is |
| Not on disk | The file is gone; Gleaner offers its saved copy, or notes that git history still has a file at the path |
| Lost | The file is gone, with no saved copy and nothing in git at that path; the delivery record stays |

**Hand-off**, under the file's name, for the delivery you picked:

| Status | Meaning |
|---|---|
| Verified · file on disk | The file on disk has the delivery's hash; a drag hands over a copy Gleaner checked after copying |
| Verified · saved copy | The file on disk no longer holds the delivery; a drag hands over Gleaner's saved copy, checked by hash |
| First seen later | Gleaner first saw these bytes after the delivery, so they may differ from what was delivered |
| Delivery N is no longer available | Neither the file on disk nor a saved copy holds the delivery's bytes now, or the delivered folder is no longer a folder. Gleaner says why it has no copy, and offers another delivery the file matches, or the current file as "not a found delivery" |
| Delivery N isn't available | Gleaner never saw or never read the delivery's bytes |
| Delivery N isn't available now | Something is at the path, but Gleaner can't read it |
| Restore from git first | The file is gone, and git history has a file at the path; Gleaner shows a command for you to run |
| Delivery N is lost | The file is gone, with no saved copy and nothing in git at that path; the delivery record stays |
| Folder | A delivered folder, handed over as it is now |

**Copy**, under More Info, where the delivery's bytes are kept:

| Status | Meaning |
|---|---|
| Saved copy | Gleaner keeps the delivery's bytes |
| Saved copy of what Gleaner first saw | Gleaner keeps the bytes it first saw, after the delivery |
| Not saved: too large | Over 64 MB, and not kept with Save a Copy |
| Not saved: saving failed | Gleaner read the file but couldn't save a copy |
| Saved copy gone from Gleaner's store | Gleaner saved a copy, but its store no longer holds it |
| Not saved: never read | Gleaner never saw or never read the delivery's bytes |
| Folder: not versioned | A delivered folder; Gleaner keeps no copy |

The three without a saved copy go on with what the latest check found: the file on disk still holds it (checked by hash), not on disk, the file on disk can't be read, or the file on disk no longer holds it.

**In the list**, a row carries at most one mark, and only when something needs a look: *Unavailable* with why (never seen, never read, not on disk, can't read, not a file, a folder now, changed), *Not on disk*, *Changed*, or *First seen later*. Drawing the list never reads the disk, so *Changed* appears only for a file Gleaner has checked since it opened. A work delivered more than once counts its deliveries at the end of its first line, and a row says "Delivery N of M" only when it shows an older one. Under an open work, a delivery's row says *Unavailable* with why when it has nothing to hand over.

**Each agent** has a switch, in Sources (⌘,) and in the toolbar's Sources popover. Off, Gleaner neither reads nor watches its logs and hides its deliveries; nothing is removed, and on again shows everything. An agent's page draws its line to the provider and the models behind its replies, each with its vendor's mark, and a delivery's Information names its model.

**The agents' logs**, in Sources (⌘,), as a triangle at the end of the Sources row, and in a line under the list when one needs a look: *Read*; *Read with problems* (unknown record types, logs with malformed lines or shorter than before, logs or folders that couldn't be read, workspaces Gleaner couldn't walk whole); *Can't read*; *Not on this Mac*. Try Again appears when reading again can help, and what Gleaner already found stays shown.

## Hand-off

Drag the file at the top of the detail pane, or drag a row from the list, into Finder, a chat, or an upload field. A row hands over the version the detail pane would: the delivery you picked for the selected file, the matched delivery for any other. The receiver gets a copy that Gleaner hashed after copying and that matched the chosen version; the original file is never moved, and edits made after the check cannot slip in. When the file on disk no longer matches, Gleaner hands over its saved copy. A delivered folder is handed over as it is now, as a copy, and only while it is still a folder.

When neither the file nor a saved copy holds the version, Gleaner says why it has none of its bytes: it never saw or never read them, the delivery was a folder, the file was too large to have been saved, saving it failed, or the copy it saved is no longer in its store. If the file on disk is another delivery, it offers that one; otherwise, when it can read the file there, it offers that file only under the label "not a found delivery". A row with nothing to hand over starts no drag. When a file is gone but git still has it, Gleaner shows a command for you to run, naming a commit it checked holds the file: `git restore` from that commit, or `git worktree add` at that commit for a worktree that has been removed. Gleaner never runs it. Wherever Gleaner advises checking again, **Check Again** checks the file now and prepares its copy again.

| Action | Shortcut |
|---|---|
| Copy the verified file (in the list) | ⌘C |
| Open the verified file | ⌘O |
| Quick Look | Space or ⌘Y |
| Show the original in Finder | ⇧⌘R |
| Copy the original's path | ⌥⌘C |
| Check for new deliveries | ⌘R |
| Undo a join, keep-apart or move | ⌘Z |
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

- **Reads** Claude Code logs in `~/.claude/projects`, Codex logs in `~/.codex`, and the files those replies name. It watches the log folders while it is open, including one that appears after launch. It finds a file's repository by reading `.git` entries, and runs only read-only git commands in it: `git status --porcelain --ignored` for a file on disk, and for a file that is gone `git rev-parse` and `git log --all`, to find a commit that holds it. Each runs with `--no-optional-locks`, so git never rewrites the index, and so that it runs nothing the repository configures: `core.fsmonitor` off, so it starts no hook or daemon; signature checks off, so `git log` starts no signature program; and in a partial clone, no fetch of what the clone lacks. A clean filter such as Git LFS may still run while git compares a file.
- **Observes** the folder each conversation worked in (its git checkout, else the folder itself), after its log is read and the conversation's span has moved: the names, sizes, dates and file identities of the files whose creation or modification date falls while the conversation was working, from each request to the last reply answering it, never their contents. A file whose dates were set after that, such as a copy that kept older dates, isn't counted. Such a file *appeared* or *changed during* that conversation, which doesn't say who made it, and it is kept beside the deliveries, never as one. A package (an app, an Xcode project) is one entry, by its own dates. Your home folder and its Library (but for iCloud Drive and cloud storage), system folders, hidden folders, the agents' logs, Gleaner's own library, dependency caches (`node_modules`, `__pycache__`, `DerivedData`) and folders a tool marked with `CACHEDIR.TAG` are skipped, and Sources names each workspace not walked, with why; links and other volumes aren't followed, and a walk stops after 100,000 entries, which Sources reports. See [docs/design/capture.md](docs/design/capture.md).
- **Lists** the files of a folder a reply handed over, as handed over with it: by names, sizes, dates and file identities, never contents, and never hidden files, with the skips and bound of a workspace walk. A file counts when its creation date and its last inode change both come by the reply, so a file changed, moved or copied in since is missed rather than claimed; each file's bytes are read when you select, open, compare or drag it. A Git repository inside the folder is another project, left out and named in the folder's detail, and a package (an app, an Xcode project, an RTFD document) is one file, as Finder shows it. Your home folder, a volume or a cloud drive, a folder directly in one, a link, a folder inside a hidden folder or a cache, a package, and a project's own folder or one holding it aren't unpacked, and the folder's detail and Sources say why. See [SPEC §5.4](docs/SPEC.md).
- **Keeps** excerpts of each reply and request, never whole logs. Secret-shaped strings are redacted before an excerpt is cut to length: API keys and access tokens, bearer tokens, `key=value` secrets, credentials in URLs, and runs of 40 or more letters and digits that mix upper case, lower case and digits. Lowercase hex, such as hashes and IDs, is kept. The index and saved copies live in `~/Library/Application Support/Gleaner`. Every file up to 64 MB is saved when Gleaner first reads it; a larger file is tracked by hash, and **Save a Copy** keeps it while the file on disk still matches the delivery. Saved copies are the delivered bytes and are not redacted.
- **Hand-off copies** live in `~/Library/Caches/Gleaner`. Sources → Storage shows their size and clears them; clearing keeps the copy on the clipboard, which a paste still reads, and never removes a saved copy.
- **Never writes** to project folders. Gleaner itself makes no network requests. A Quick Look preview of a web page may load what that page references, and links open only when you click them.

## Limits in v0.1

- Folders are listed but not versioned: preview, Open and drag use the folder as it is now. The files in a delivered folder are versioned one by one.
- An HTML page's images, scripts and stylesheets are not saved with it, and Quick Look previews the page without them.
- A file over 64 MB is saved only when you choose **Save a Copy** while the file still matches its delivery. If the worktree holding an unsaved one is deleted, Gleaner can offer it only through git, as a command you run, and only if the file was committed; otherwise it is lost. Save a large file you may need before removing its worktree.
- The admission rule is provisional, pending feedback from more users' logs.
- Files observed during a conversation are recorded, but the window doesn't list them yet.
- The app has no icon yet.
- The release build is not notarized.

## Development

```bash
swift test                      # fixture tests
./scripts/bundle-app.sh         # build/Gleaner.app, ad-hoc signed
./scripts/release.sh            # tests, then build/Gleaner-<version>.zip and its sha256
```

`release.sh` refuses to run with uncommitted changes. A commit tagged `v0.1.0` builds as version 0.1.0; any other commit builds as `0.1.0-dev+<commit>`.

- `Sources/GleanerCore`: provider adapters (Claude Code, Codex), mention extraction, locator, redaction, the registry (SQLite), the content store (saved copies, verified hand-off copies), the indexer, observations of each session's workspace (`Observations.swift`), the files of delivered folders (`Bundles.swift`), how a list of them is ordered (`Listing.swift`), the log watcher, and the status logic (`Library.swift`).
- `Sources/GleanerUI`: the component library the window draws with: marks, status, surfaces, controls and motion, after [docs/design/components.md](docs/design/components.md). SwiftUI and AppKit only.
- `Sources/Gleaner`: the macOS app (SwiftUI and AppKit, Quick Look).
- `Sources/gleaner-spike`: Spike A, read-only extraction over local logs that writes a labeling sheet.
- `Tests/GleanerCoreTests`: fixture tests built from sanitized record shapes, the library flow (concurrent edits, deleted worktrees, rollback, backfill, verified staging), and observations and delivered folders in several kinds of work.
- `Tests/GleanerUITests`: the marks, the tokens, and the gallery of every component (`GLEANER_GALLERY=<folder> swift test --filter GalleryTests`).
- `Tests/GleanerTests`: the app's decisions on a synthetic library (which delivery a click lands on, which bytes Quick Look, Compare and a drag use) and its wording.

The decisions behind v0.1 are in [docs/SPEC.md](docs/SPEC.md); the design exploration and its rulings are in [docs/design/](docs/design/README.md).

### Spike A

```bash
swift build -c release && .build/release/gleaner-spike
```

Reads `~/.claude/projects` and `~/.codex` read-only, checks each named file with the same read-only git commands as the app (`git status`, `git rev-parse`, `git log`), and writes under `out/`:

- `candidates.tsv`: one row per candidate, admitted or not, with the request, the evidence, what was found at the path, whether the delivery rule admits it (`admitted`, yes or no), and empty `label` and `note` columns to fill in. A rerun keeps the labels already entered. Paths start with `~`, and text is redacted.
- `recall-sample.md`: a random sample of final replies with the candidates found in each, for marking misses.
- `summary.txt`: counts per agent, unknown record types, and what was found at the named paths.
- `locators.internal.tsv`: each candidate's full log path, log lines and file path, for your own checks; never share it.

`out/` holds log excerpts and is git-ignored.

Options: `--claude-root DIR`, `--codex-home DIR`, `--out DIR`, `--sample N`, `--seed N`.
