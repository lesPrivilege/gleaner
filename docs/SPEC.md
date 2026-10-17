# Gleaner — v0.1 Specification

Gleaner finds what your agents delivered, wherever they left it.

It is a local macOS library of the artifacts that local coding agents (Claude Code, Codex) explicitly handed to the user: videos, HTML pages, documents, images, reports. It lets a person search, preview, tell versions apart, and drag a delivered file into another app, without reopening the original conversation and without calling a model.

This document records the decisions ratified for v0.1. Implementation details not covered here are the implementer's call, provided they keep the three invariants in §1.

## 1. Invariants

1. **Delivery messages are the evidence.** An item enters the library only because an assistant reply to the user named it. Every item can be traced back to that reply.
2. **The source stays where it is.** Gleaner never moves, rewrites, or deletes files in project folders. It keeps its own index and its own snapshots.
3. **Humans operate it directly.** Finding, previewing, and handing off an artifact need no model call, no session ID, no branch name, and no remembered path.

### 1.1 Product boundary

Gleaner's domain is **agent deliverable discovery, preservation, and handoff**: what an agent handed to a human, found again, identified by version, and passed on. It is not session memory, observability, or harness management.

- **Independent.** Own repository, data model, desktop app, and release. No runtime dependency on another session indexer, and Gleaner is not built as a plugin of another product.
- **Runtime-agnostic.** No runtime (Claude Code, Codex, DSH, Pi, …) owns an artifact's identity, versions, or review state. Switching runtimes never forks them.
- **Connection is never an admission gate.** A runtime with no extension is still indexed passively from its logs.
- **Sessions are evidence, not the product.** Adapters parse only what delivery discovery needs.
- **Prior art is a reference corpus, not a dependency graph.** Projects such as Obelisk and agentsview are studied per engineering question (adapter normalization, incremental cursors, SQLite concurrency, fixture strategy). Each study yields: a method to adopt, a hypothesis to verify, or a design that does not apply. Another project having a feature does not add it to Gleaner's scope.

## 2. Product contract

> Find a delivery from an old session → preview it → confirm its source and version → drag it into another app.

P0 acceptance scenario: three weeks ago a Claude Code session compiled a demo video. The session is closed, and another agent has since modified the same file. The user remembers only the project and roughly the topic. They open Gleaner, type a keyword, find the delivery, read the delivery message, see that the current file differs from what was delivered, choose an available version, and drag it into another agent's composer. No model call, no project file modified.

## 3. Scope

In v0.1:

- Read-only adapters for Claude Code (`~/.claude/projects`) and Codex (`~/.codex/sessions`).
- Delivery extraction from user-facing final replies.
- Registry of sessions, deliveries (mentions) and captures in SQLite. Locator state (git, availability) is recomputed when a file is checked, not stored.
- Content-addressed snapshots under a size policy.
- Library window: search, preview (Quick Look, text, Markdown), compare versions, reveal in Finder, copy path, drag out.

Deferred: review states and approvals, comments, Work Units, MCP or `artifact://` resolvers, agent-initiated submission, remote-agent handoff, cross-device sync, cloud deliveries (ChatGPT, claude.ai), automatic HTML dependency bundling, Claude Code hooks as a capture path, runtime extensions and model reasoning (§14), release groups (§15).

The core is a library (`GleanerCore`), not logic inside the UI, so that the Spike A CLI today and extensions later (§14) use the same API as the app.

## 4. Platform

- **SwiftUI + AppKit + SQLite**, macOS only.
- SwiftUI for the library, search, and cards; AppKit for system drag (`NSFilePromiseProvider` or file URL pasteboard items); Quick Look for preview of video, PDF, images. Text and Markdown have their own views (rulings §7). An HTML page is previewed by Quick Look as the single staged file, without the files it references; an interactive HTML preview is deferred.
- Drag-out always uses **copy** semantics. A drag must never let Finder move the source file.
- Distribution decides sandboxing. If the app is sandboxed, project folders are reached through security-scoped bookmarks granted by the user.

## 5. Data model

Four core objects. Project is a derived label (from cwd and git repository), not a stored entity with its own lifecycle.

| Object | Holds |
|---|---|
| **Session** | provider, provider session ID, title, cwd, log file location |
| **Delivery Mention** | the reply excerpt that names the artifact, the raw target as written, the user request that started the turn, position in the log (its own log file and line), its place in the reply (the line where the reply starts, which every file the reply named shares, and the order the reply names them in), `delivered_at` |
| **Locator** | resolved path, worktree / repository root, git state (`committed`, `modified`, `untracked`, `ignored`, `not_in_repo`; when missing: `recoverable_from_head`, `recoverable_from_history`, `lost`), availability (`file`, `directory`, `special`, `unreadable`, `missing`), last verified time |
| **Capture** | `observed_at`, sha256, size, optional snapshot reference (`captured_at`), the capture's provenance, and what was at the path (a file, a folder, or, without a hash, nothing, an unreadable file, or not a regular file) |

Artifact identity in v0.1 is the path. A renamed or moved file appears as a separate artifact; re-linking is deferred, and Gleaner never guesses identity across paths. A project is the git repository holding the file (every worktree folds into its repository), else the one its cwd belongs to, else the folder name (rulings §2). Projects are told apart by the repository's main folder (for a bare repository, its own folder, named without `.git`) and shown by its name. Each delivery records, with its capture, the repository it resolved to and the checkout it was in (the main folder or a worktree's own folder), only while the file's folder is there to show them. The record outlives a reread that drops the delivery, and the earliest one wins over any later resolution: a deleted worktree keeps its project and its name, and a file committed on its branch is still looked up in the repository's history at its path within that checkout. A delivery never resolved stays explicitly outside any repository.

### 5.1 Time semantics

Three fields, never conflated:

- `delivered_at` — when the assistant reply that names the file was written.
- `observed_at` — when Gleaner read the file and computed its hash.
- `captured_at` — when Gleaner stored a snapshot of those bytes.

When history is backfilled, these can be months apart. A capture records its provenance:

- `at_delivery` — observed within 10 minutes of `delivered_at`, and the file's mtime is no later than `delivered_at` plus 2 seconds of clock granularity.
- `first_seen_after_delivery` — observed during backfill or after the file's mtime moved past the delivery. The UI must say plainly that this may not be the delivered version.
- `never_observed` — Gleaner never read the file's bytes: when it first looked, the path was missing, unreadable, or not a regular file. The capture has no hash and records which. It is completed once, the first time Gleaner reads the file (checking it, or capturing a later delivery of it), as `first_seen_after_delivery`.

A capture with a hash is never rewritten. A file that is there but cannot be opened or read is `unreadable`, with its own wording: it is never described as missing, gone, changed, or seen.

Gleaner never labels a file "latest" unconditionally. It shows the time of the last verification.

When the latest delivery's capture is `first_seen_after_delivery`, the on-disk status reads "unchanged since first seen", never "same as delivery N". A match with a capture made after delivery is not a match with the delivery.

### 5.2 Versions

Versions follow **delivery events**, not file saves. Twenty-five rebuilds between two deliveries produce two version nodes, not twenty-five.

| Event | Behavior |
|---|---|
| Same path delivered again, same bytes | Append a delivery; its capture repeats the hash, no new saved bytes, and the UI marks it "same as N" |
| Same path delivered again, new bytes | New capture → new version node |
| Source changed silently since last capture | Mark "changed since delivery"; no version node until the next delivery or an explicit pin |
| Source matches an older delivery, not the latest | Mark "rolled back to delivery k". It is a delivered version, never labeled "not delivered". When delivery k's bytes were first seen later, say "back to what Gleaner first saw for delivery k" |
| Identical bytes at two paths | One content hash, two locators; review context stays per locator |
| Source missing, snapshot exists | Offer the snapshot, label the source unavailable |
| Source missing, no snapshot | Keep the entry and its history; say it cannot be recovered |

Same bytes do not imply the same logical artifact.

## 6. Snapshots and storage

- Location: `~/Library/Application Support/Gleaner/` — `registry.sqlite` and `objects/<sha256-prefix>/<sha256>`.
- Nothing is written to project folders.
- Policy by size, not type: every regular file up to 64 MB gets a saved copy when Gleaner first reads it. A larger file is tracked by hash, and "Save a copy" keeps it while the file on disk still matches the delivery. Thumbnails for large video, directory snapshots and HTML dependency handling are deferred.
- Folders are listed but not versioned: preview, Open and drag use the folder as it is now, only while the path is still a folder, and the UI says so.
- A delivered symlink is captured by the file it points to; the link itself is never copied, and the target's permissions are never changed.
- **Hand-off copies** (`~/Library/Caches/Gleaner/handoff`, read-only files) and the **version store** are separate. Hand-off copies are disposable; clearing them keeps the one on the clipboard, which a paste still reads, and a saved copy that backs a version is never removed by cleaning caches.
- A drag hands over an immutable, verified copy, never the live source path. Gleaner copies the chosen version's bytes (from the saved copy when there is one, else from the source while it still matches) to a staging file, hashes the staged file, and hands it over only if the hash equals the version's. The detail's tile prepares its copy when the delivery is selected, so the preview shows the same bytes; a list row prepares its copy at drop. A copy prepared earlier is hashed again before it is reused. Handing over the source path itself would only guarantee the content at the moment of the check; an agent or editor may change it before the receiver reads it.
- Which bytes back the chosen version:

| Situation | Drag behavior |
|---|---|
| Source matches the chosen version | Stage a copy (an APFS clone of the saved copy, else of the source), verify its hash, drag that |
| Source differs or is missing, and a snapshot of the chosen version exists | Drag the snapshot |
| Something else is at the path (a changed file, a folder, a file Gleaner can't read, a pipe), and the chosen version has no snapshot | Say the version isn't available, and why Gleaner has none of its bytes: never seen, never read (unreadable or not a regular file at first look), a folder, too large to have been saved, or a save that failed. Say "no longer" only for bytes Gleaner had, and "now" while the path can't be read. If the current file matches another delivery k, offer delivery k by name; otherwise, when Gleaner can read the file there, offer it only under an explicit "not among the deliveries Gleaner found" label |
| Source missing, no snapshot, but git history has the path | Offer a restore command for the user to run, naming a commit checked to hold the path: the checkout's HEAD when it does, else the newest commit on any ref that does. For a removed worktree, the command adds the worktree back at that commit. Gleaner never restores it itself (Invariant 2), and says it cannot confirm that the git version is the delivered one |
| Source missing, no snapshot, not in git | Lost: keep the record, offer no drag |

- A list row hands over what the detail would for the delivery the row shows: the chosen one for the selected row, the matched one for any other. A row with nothing to hand over is marked unavailable, with why, and starts no drag.
- A saved copy inherits its capture's provenance. A snapshot taken during backfill keeps its delivery number with the qualifier "first seen later" in storage labels, previews and drag captions (rulings §9).
- **UI vocabulary.** "Snapshot" and "pin" are internal terms. The user sees "saved copy" for a snapshot and "Save a copy" for pinning. Plain "copy" is never used for Gleaner's storage, because every drag copies.

### 6.1 Comparing versions

Any two versions Gleaner holds bytes for (two deliveries, or a delivery and the file on disk) can be compared, read-only. Both ends are named with their hash and must still hash to it. Text gets a line diff in one accent: grey for what was there, the accent for new lines, a solid block only on the new words of a one-for-one replaced line, both line numbers and the ± mark always shown. Two versions whose bytes differ never read as "No changes": when no line differs, Compare says that only line endings or the final newline differ. Images show side by side; other kinds compare size and hash. Text over 64 KB or 2000 lines is reported as limited, never shown partially; a file of a text kind that isn't text (a PDF) compares by size and hash at any size. See `docs/design/diff-and-references.md`.

### 6.2 Claims in replies

A reply's claims about an artifact ("signed", "notarized", "tests pass", "final") are evidence, not facts. The UI quotes them as unchecked text attributed to the reply and never turns them into a status or a solid mark. Only Gleaner's own checks (existence, hash, git state) become statuses. This applies to every delivery in v0.1, not only to the release groups in §15.

## 7. Watching

- Watch only the agents' log directories (FSEvents). New sessions are ingested near real time, so `observed_at` stays close to `delivered_at`. While a log directory does not exist yet, the nearest existing folder above it is watched only to notice it appear.
- Do not watch the paths of indexed artifacts. Re-verify a file's hash when it is selected and again when its hand-off copy is staged; there is no background pass in v0.1.
- Observation is read-only: only regular files are opened (a FIFO, socket, or device is reported as `special`; a file that can't be opened or read, or a path behind a folder that can't be searched, as `unreadable`), and git runs with `--no-optional-locks` so `git status` never rewrites the index, and runs nothing the repository configures: `core.fsmonitor` off, so it starts no hook or daemon; `log.showSignature` off, so `git log` starts no signature program; and lazy fetching off, so a partial clone fetches nothing it lacks. A commit is checked to hold a path through its trees, never by reading the file's contents. A clean filter (Git LFS, for one) may still run while git compares a file with the index; that is a known limit.

## 8. Adapters

- Each provider is an isolated module that turns its log format into `Session`, turns, user requests, and final replies. The extractor downstream is provider-agnostic.
- Log formats are undocumented and change. Each adapter ships fixture tests built from real record shapes (sanitized). An unknown record type is counted and reported, never silently dropped into "no deliveries".
- Sub-agent and side-chain transcripts are excluded: they are not replies to the user.
- A log that disappears (agents prune old transcripts) leaves its deliveries as last derived: they are not re-derived on an extractor change, and their captures and saved copies stay.

### 8.1 Claude Code (`~/.claude/projects/<project>/<session>.jsonl`)

- Records are one content block per line; `type` is `user`, `assistant`, `system`, `attachment`, `ai-title`, `custom-title`, and others.
- A turn begins at a `user` record that is not a tool result, not `isMeta`, and not `isCompactSummary`. Records with `origin.kind == "human"` are the user's request; `task-notification` and similar also start a turn (the agent's answer to them is still user-facing) but do not replace the request context.
- The final reply is the assistant `text` blocks that come after the turn's last `tool_use`.
- Relative paths resolve against the `cwd` of the reply record, not the request: the agent may have entered a worktree mid-turn.
- Title: latest `custom-title`, else latest `ai-title`.
- Exclude `subagents/` directories and `isSidechain` records.

### 8.2 Codex (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`)

- `session_meta.payload` gives id, cwd, `thread_source`; skip `thread_source == "subagent"`.
- Forked threads replay parent messages marked `metadata.inherited_user_message`; skip them.
- The user request is a `response_item` `message` with role `user` whose `content_item_kinds` include `user.text`. A user message without `content_item_kinds` (older rollouts) is not taken as a request. Codex's attachment header ("# Files mentioned by the user … ## My request:") is dropped: the request is the words after it, or the attachment names when nothing was typed.
- The final reply is an assistant `message` with `phase == "final_answer"`.
- Title from `~/.codex/session_index.jsonl` (`thread_name` by id).

## 9. Extraction

Candidates come from the final reply only:

- Markdown links and images whose target is a local path (absolute, `~`, relative, or `file://`).
- Inline code spans and bare absolute paths that look like files.
- Relative targets resolve against the cwd of the record that names them. Line anchors (`:42`, `#L42`) are stripped and recorded. The fragment is split off before percent-decoding, so an encoded `%23` stays part of the file name. Balanced parentheses in link targets belong to the path. `file://localhost/` is a local path; `file://<other host>/` is not.
- Each mention keeps the record it came from (line, time, cwd). A reply spanning several records never attributes a mention to a later record.

Features recorded per candidate, for later ranking: syntax (link / image / code / bare), line anchor present, target kind (file / directory), extension, exists now.

A line-anchored code reference (`src/foo.swift:42`) is usually a pointer, not a delivery.

Admission for v0.1 is a synthetic rule derived from what a delivery is: a file the agent hands to the person. Each clause is a test case (`AdmissionTests`):

- A link or image is a hand-off: the agent made the file clickable.
- A line anchor (`:42`, `#L42`) points into code instead of handing a file over, so a mention with one never admits a file, even as a link. A heading anchor (`#usage`) points at a section of a document that may itself be the delivery, so it does not block admission.
- Inline code or a bare path admits a file only when it names a place (a directory component) and has no anchor. A bare file name (`App.tsx`) names a topic, not a place.
- Anything inside a fenced code block, or a link written inside inline code, is an example or an instruction, not a hand-off. Fences are read as CommonMark reads them: only a fence of the same character (backtick or tilde) at least as long closes one, and an unclosed fence runs to the end of the reply.
- A path with a placeholder (`build/<name>.zip`, `out/{id}.md`) names a pattern, not a file.

When a log is reread completely, deliveries it no longer admits are removed from the index. Their captures and saved copies stay, so a delivery the log admits again gets its own capture back. A log with malformed lines removes nothing: what it still names is updated, it is reported as partial, and it is read again on the next run. Neither does a log shorter than when it was last read, even after an extractor change: it lost records, so it is reported as shorter and read again on the next run.

Answers to an agent's question prompt (Codex sends them as JSON, sometimes wrapped in a tag) are not requests; the previous request stays as context.

Derived fields (request, evidence) are versioned: when extraction changes, logs are reread and those fields refreshed. Captures record what Gleaner saw at a moment and are never rewritten.

## 10. Search

A result matches when every search term is found in one delivery's own words (request, session, reply), together with the file name and project; terms from different deliveries do not combine. The result opens on the newest delivery whose own words matched, falling back to the newest delivery when only the file name or project matched, and shows that delivery's date. Changing the query resets a manually chosen delivery to the matched one.

The index covers, per delivery: the reply excerpt, the user request that started the turn, the session title, the project, and the file name with its folder (not the whole path, whose home and `Projects` components would match everything). The delivery sentence alone usually lacks the topic words the user remembers.

## 11. Privacy

- Store excerpts, not whole logs: the reply passage around a mention (up to about 400 characters, cut only at whitespace), the request (up to 2000 characters), titles, paths.
- Redact secret-shaped strings (API keys and access tokens, bearer tokens, `key=value` secrets, credentials in URLs, and runs of 40 or more base64-like characters mixing upper case, lower case and digits; lowercase hex such as hashes and IDs is kept) before storing any excerpt, request, title or link anchor, and before truncating, so a secret at an edge is still recognized. Saved copies are the delivered bytes and are not redacted.
- All data stays local.

## 12. Gates

**Gate 1 — Discovery reliability (Spike A).** On real local sessions, label candidates and a random sample of final replies. Report:

- delivery precision (candidates that are real deliveries),
- recall (deliveries in sampled replies that were extracted),
- locator resolution rate (real deliveries whose file was found),
- duplicate rate (same file mentioned repeatedly).

Library work was meant to start only once these numbers are acceptable. At the user's direction the native library was built before labeling (2026-10-17). Labeling one person's logs would overfit the rule to one working style, so v0.1 ships the synthetic rule in §9, and Gate 1 is measured on broader feedback after release.

**Gate 2 — Artifact usability (Spike B).** With fixed MP4, PDF, Markdown, and HTML-bundle samples: find, preview, detect source change, restore from snapshot, and drag into Finder, Claude Desktop, Codex, and a browser upload field. Show correctly which versions remain available after a worktree is removed.

After both gates: visual polish, incremental indexing performance, cache cleanup, packaging.

## 13. Spike A tool

`swift run gleaner-spike` (see `README.md`) runs the adapters and extractor read-only over the local logs and writes, under `out/`:

- `candidates.tsv` — one row per candidate with request, evidence, resolution, whether the §9 rule admits it (`admitted`, yes or no), and empty `label` / `note` columns.
- `recall-sample.md` — a random sample of final replies with the candidates found in each, for marking misses.
- `summary.txt` — counts per provider, unknown record types, resolution stats.
- `locators.internal.tsv` — full local paths for the owner's checks; never shared.

The sheet lists every candidate, admitted or not, so the §9 rule can be measured against the labels after release.

`out/` contains log excerpts and is never committed.

## 14. Beyond v0.1: connections and reasoning (direction, not scheduled)

Ratified direction. None of this blocks the v0.1 release.

**Three layers.** The core is narrow, the connections are thin, and distribution is broad.

1. **Gleaner Core** — evidence, registry, snapshots, library, native drag. It runs on its own.
2. **Stable local API / CLI** — the only surface extensions use.
3. **Extensions** — one per ecosystem, built on whatever entry point it actually exposes (plugin, skill, MCP, CLI, deep link). Do not assume every ecosystem has a plugin system.

**Source adapter ≠ extension.** An adapter reads a runtime's history into Gleaner. An extension lets that runtime's users call Gleaner. They evolve separately.

**Bidirectional semantics.**

| Direction | Capability |
|---|---|
| Runtime → Gleaner | session logs, delivery statements, artifact references, revision hints |
| Gleaner → Runtime | find, locate, read, resolve an exact version, hand off the file |
| Runtime ↔ Gleaner | optional long-tail reasoning, evidence completion, review feedback |

Adapters are capability-based. A runtime may offer only a read-only log, or also hooks, MCP, or reasoning.

**Extensions stay thin.** They offer three actions: *Find in Gleaner*, *Open in Gleaner*, and *Handoff from Gleaner*, which returns the chosen version's file reference, or an explicitly authorized snapshot transfer for a remote runtime. An extension keeps no artifact database, does not re-parse sessions, copies no snapshots, and manages no versions. Uninstalling it leaves Gleaner fully working.

**Optional reasoning (e.g. DeepSeek through a DSH extension).** A model proposes, and Gleaner verifies.

- Use cases: ambiguous delivery statements, semantic recall ("the Agent Memory demo"), the same logical work at different paths, revisions that disagree with delivery history.
- A model may suggest that a message refers to a file. It may never record "verified", "same version", or "available". Those facts come only from the file system, hashes, and git. Model suggestions wait for local verification or human confirmation.
- Send only minimal, redacted evidence excerpts and candidate metadata, never whole sessions or file contents. Network reasoning is opt-in.
- Bring it in only if labeled data from Gate 1 shows that the deterministic extractor leaves a long tail large enough to matter. Measure its gain against the same labels.

**Distribution.** Ecosystems are channels, not dependencies: GitHub Release / Homebrew, then in-app updates (Sparkle) → agent plugin directories (Claude Code, Codex) → MCP Registry → related communities. The demo is the P0 scenario: a video delivered into a worktree that has since been deleted, found again, its version identified, and dragged into another agent.

## 15. Beyond v0.1: build and release artifacts (direction, not scheduled)

In v0.1, a delivered `SomeApp.dmg` is an ordinary artifact: detected, hashed, located, opened, dragged, and checked for change on the next delivery.

Later, a **Release Group** organizes RCs, final builds, and per-architecture packages, with lightweight metadata: product, version, build number, channel, git commit/tag, source session, sha256, size, architecture, and signing/notarization/stapling checks with their verification time. These are separate steps that can change the bytes, so each keeps its own hash.

- An agent's claim that a build is signed or notarized is evidence, not a fact (§6.2). Release groups add verification of the actual file.
- Artifact version ≠ software release. GitHub Releases is a remote artifact source. Sparkle keeps owning updates. Gleaner indexes, identifies, and hands off; it never builds, publishes, signs, or updates.
- Large installers are not snapshotted by default. Prefer the source file or a published remote asset, and pin only what must be kept.
