# Rulings on the v0.1 review, the research streams and the requirements ledger

Inputs:
- The independent release review and four research streams on branch [`cloud/gleaner-review-research-20261017`](https://github.com/lesPrivilege/gleaner/tree/cloud/gleaner-review-research-20261017/docs/research/2026-10-17) (commit `6a95aad`), audited against main `22dd07d`. Finding IDs D1–D8 and N1–N4 are the review's.
- A requirements ledger (2026-10-18) that traced every normative item in SPEC, the design docs, `release.md`, the backlog, both READMEs, the CHANGELOG, the research reports and the original planning notes (private, not in this repository) against the code. Ledger IDs A1–A19 and C1–C12 are used below.

The research is treated as verified input. These rulings decide what Gleaner does with it.

## 1. Before tagging v0.1.0: the review's defects

The review's central recommendation is accepted. Its preservation and exact-selection defects violate SPEC §1 and §6 and are fixed before the tag. Each fix lands with a test that fails on `22dd07d`.

All rows landed on `fix/release-review`, together with the fixes from an independent review of that branch: 113 tests, including a new app-target suite.

| ID | Ruling | Fix, at its smallest |
|---|---|---|
| D1 | Blocks | Resolve hand-off and preview from the **selected delivery's capture**, not from today's path kind. A delivery captured as a regular file resolves by its hash: the original if it still matches, else the saved copy, even when the path is now a folder. Live-folder actions apply only to a delivery captured as a folder whose path is still a directory. A folder delivery whose path is now missing or a file is unavailable. |
| D2 | Blocks | Adapters report whether a log was read completely (malformed records, read errors). Prune deliveries a log no longer admits **only after a complete reread**. On an incomplete reread, upsert what was found, keep everything else, and report the log as partial. A database error on one log is recorded as that log's failure, and the run continues. |
| D3 | Blocks | Compare holds the bytes it names. Image ends are loaded once from verified data, never re-read from a live URL. A comparison result is published only for the pair it was requested for. Compare ends keep "first seen later". Binary or document files over the text limit (PDF etc.) fall through to the size/hash comparison SPEC §6.1 promises, instead of being refused. |
| N1 | Blocks | Quick Look shows exactly the selected delivery's prepared bytes. When the selected delivery changes (version buttons, query), the panel follows it or closes. |
| D5 | Blocks | The offered restore command names a commit that actually contains the path. The commit is found and checked, not taken as "parent of the latest touching commit". Every path gets POSIX-safe quoting. Recovery stays user-run, and the existing warning stays. |
| D7 | Blocks | An unclosed fence masks to the end of the reply (CommonMark). Fence scanning tracks the delimiter character and length. Bump `extractorVersion`. |
| H1 | Blocks | `Locator.sha256` returns nil on a read error, never the digest of a prefix. |
| N3 | Blocks | SPEC §8 already requires this. Per source, distinguish *not present*, *unreadable* and *read with problems* (unknown record types, malformed lines, partial logs). Carry that into one compact status line in the library and in Settings, and keep showing cached results. No onboarding flow. |
| D4 | Blocks | Filter by a repository key (the repository's main folder path) and display its short name; disambiguate equal names with the parent folder. Record the repository each delivery resolved to while it could be resolved, so a deleted external worktree keeps its project after a cold restart. Unresolvable history stays explicitly unresolved. |
| N2 | Fix now | Clearing hand-off copies restages the current selection (explicit generation), and never deletes a copy a preparation is writing. |
| D6 | Fix now | "Delivered with" carries the sibling's delivery, not just its artifact, and lands on that occurrence. |
| H3 | Fix now | Staging writes to a unique temporary file and publishes it atomically, so overlapping stages of the same version cannot remove each other's file. |
| H2 | Fix now | Comparison loads only regular files (the same check as staging). |
| N4 | Fix now, minimally | Open and Save a Copy report failure where the button was pressed. A failed small-file save is not described as the large-file policy. |
| — | Fix now | Log folders absent at launch are picked up when they appear (the watcher is recreated on reread). |
| — | Spec wording | SPEC §10: a result opens on the newest delivery whose own words matched, falling back to the newest delivery when only the name or project matched. That is the current behavior, and the better one. |
| D8 | Deferred | Provider-scoped session keys come before a third adapter or any import. Claude and Codex session IDs are UUIDs, so no collision is plausible within v0.1. |

## 2. Before tagging v0.1.0: gaps from the requirements ledger

These defects were not in the review. Each one breaks a promise SPEC, the rulings or the README already make. Each lands with a test, or with a precise source trace where only the app layer is involved.

| ID | Ruling | Fix, at its smallest |
|---|---|---|
| A1 | Blocks | A delivery already keeps its id when a reread finds its first mention in another record of the same turn (landed with §1). Remaining: **captures are never deleted.** A reread that no longer admits a delivery removes its index row but keeps its capture row, so the same id re-admitted later (after an admission change, Gate 1 retuning or a repaired log) gets its original capture back. Test: un-admit, then re-admit, keeps `at_delivery`. |
| A2 | Blocks | A file that exists but cannot be read is **unreadable**: a locator kind with its own wording, never "missing", "gone", "changed" or "seen". A capture without a hash (the file was missing, unreadable or not a regular file at first look) is completed once, the first time Gleaner reads the file, as *first seen later*. A capture with a hash is never rewritten. Test with a `chmod 000` file and with a path that appears later. Amend SPEC §5.1 to match. |
| A3 | Blocks | Status and hand-off wording say only what Gleaner checked, with a reason: never seen, not a regular file, folder, unreadable, too large to have been saved, save failed. Never offer an action that does not exist. "Show Folder" on a missing folder says so. A row whose chosen version has no bytes is shown as unavailable instead of starting a drag that fails at drop. |
| A4 | Blocks | A list-row drag hands over the same version the detail pane would: for the selected row, the chosen delivery; for any other row, the delivery the row shows. A folder row drags the live folder, with copy semantics (Finder check in acceptance). |
| A5 | Blocks | When two ends hash differently but no line differs, Compare says that only line endings or the final newline differ, never "No changes". |
| A6 | Blocks | Redact reply excerpts **before** cutting them to length (SPEC §11). Bump `extractorVersion` so that rereading refreshes the stored excerpts. A1 keeps their captures. |
| A7 | Fix now | Wherever the app advises checking again, a Check Again action re-observes the selected file and restages it, reusing N2's restage. |
| A8 | Fix now | "Delivered with" groups by reply (the turn), not by the timestamp of each path's first record, and lists siblings in reply order. A multi-record Claude reply stays one group. `Handovers` uses the same key (`Delivery.replyKey`). |
| A9, A10 | Fix now | Every label that names a delivery number keeps "first seen later" (rulings §9), including the hand-off header, the tile's accessibility label and the deliveries list. List rows mark *not on disk* and *first seen later* from stored data, and mark *changed* only for files already checked this session (C7), with no disk access while drawing rows. |
| A11 | Fix now | Worktrees of a bare repository fold into that repository (SPEC §5). |
| A12–A15 | Fix now | The release-notes command in `release.md` §4 publishes the whole 0.1.0 section. `release.md` gains a step to reconcile the signing text, marks the tag as an owner step and cites SPEC §14 for Sparkle. CHANGELOG lists the fixes in §1 and §2. README.md and README.zh-CN.md say the same thing and match the code: SPEC §10 wording, every status the app shows, the heading-anchor rule, and Spike A's outputs. |
| A16 | Fix now | Clearing hand-off copies keeps the copy currently on the pasteboard. |
| A17 | Fix now | The type badge keeps the exact extension (rulings §7a). |
| A18 | Fix now | The row's place ("worktree x" / "main folder") comes from repository resolution, not path markers, so an external worktree is named as one. |
| A19 | Fix now | A log that is shorter than when it was last read counts as an incomplete reread: nothing is pruned. |
| — | Fix now | **A deleted worktree's committed files stay recoverable.** Record each delivery's checkout root (the worktree's own folder) at ingest, next to its repository. For a missing file, look for git history with the path relative to that checkout root, in the repository's common git directory, so a file committed on the worktree's branch is not reported lost. This is the SPEC §14 demo, and Gate 2's "versions left after a worktree is removed". |
| — | Fix now | git runs with `core.fsmonitor` disabled. Observation never runs repository-configured commands (SPEC §7). Clean filters stay a known limit. |
| — | Fix now | Tests for three cases from the original test matrix that nothing covers: identical bytes re-delivered from a second session add a delivery without a new version; identical bytes in two projects stay two artifacts with their own requests; a deleted log leaves its deliveries and evidence. |
| — | Fix now | `gleaner-spike`'s `candidates.tsv` gains the `admitted` column that SPEC §13 says Gate 1 needs. |

**Decisions on the ledger's contradictions.** C1–C10 are settled by amending the docs to match the code, as the ledger recommends:
- C1: lowercase hex is kept, and only mixed-case base64-like runs are masked.
- C2: Quick Look of the staged file; interactive HTML preview is deferred.
- C3: the tile prepares its copy on selection, a row at drop, and both are re-hashed before reuse.
- C4: the project label is not editable.
- C5: rulings §2 cites D4's column.
- C6: the folder is shown relative to the agent's working directory.
- C7: see A10.
- C8: delete the unused `matchedIn`.
- C9: never_observed is a capture without a hash.
- C10: Reindex is the only reset of derived data.

C11 is fixed with the CLI work: `diff-and-references.md` declines session-analytics helpers, not the ruled CLI. C12 is settled in [structure.md](structure.md#built-on-the-current-window) (2026-10-20): it supersedes rulings §1 for the timeline and the thread; §6's newest-first order stands, with outline.md, so Activity and Name aren't built; and with the List menu gone, the timeline is chosen beside the kind filter and under View.

**Owner decisions before the tag:**
- The binary's architecture. Recommended: universal (arm64 and x86_64), built by `bundle-app.sh` and checked with `lipo`.
- A license. There is none, and a public release, Homebrew and plugin directories are planned.
- An icon.
- Signing and notarization.
- Whether the 64 MB save limit stands, given that the P0 demo's video may exceed it. Ruled for now: the limit stands, the README states it, and the demo uses a file under it or Save a Copy.

## 3. After v0.1.0: what to build next

The order below covers both the CLI direction from the [handoff outline](https://github.com/lesPrivilege/gleaner/blob/cloud/gleaner-review-research-20261017/docs/research/2026-10-17/decisions/opus-handoff.md) and requirements the original planning set that SPEC §14 ratified but nothing yet schedules.

**Three foundations, kept from now on because they are cheap now and expensive later:**
1. **Identity is not the path.** Every external result carries the delivery ID, the capture's sha256, the locator (path) and the evidence location (log path and line) as separate fields, under a library namespace. Path identity remains SPEC §5's v0.1 rule inside the app. Nothing outside may rely on it.
2. **Derived records never overwrite observations.** Anything later produced by a model or a person (titles, aliases, tags, relations, summaries, corrections) lives in its own table keyed by delivery ID, input sha256, producer and version. It never writes `deliveries` or `captures`, and the app derives no status from it.
3. **The query surface does not depend on the app window.** The CLI, MCP and extensions all read through one GleanerCore query layer that opens the registry read-only and reports the index's freshness. None of them reads SQLite directly.

**Order of work:**
1. **Adapter maintenance.** Undocumented log formats change silently. Record per log the counts of records, known records, turns, final replies and candidates. Fingerprint the key set of each record type against the fixtures, and say so in the source status when a log's count drops or an unknown field appears. Run `swift test` in CI on every push. An adapter change, including one an agent writes, merges only with passing fixtures and owner review. This comes before any third adapter, together with D8.
2. **Shared query core and the `gleaner` CLI**, for a local shell agent whose job is to find the intended delivery, select its exact version and hand those bytes on:
   - **Commands:** `find`, `show`, `read` (bounded and pinned to a hash), `resolve` (exact delivery, capture and original location) and `handoff` (a verified copy and its digest). `verify` re-checks a reference against the file system. `outline` comes later, with hash-pinned sections.
   - **Prerequisites:** a read-only registry initializer and a stored last-scan time and generation.
   - **Not claimed:** progressive retrieval and retrospective provenance are established practice. The open question is version-correct selection under incomplete evidence.
3. **The same reference inside the app.** "Copy Reference" copies the JSON reference that `resolve` returns, for composers that accept only text. "Show in Log" reveals the delivering log at its line, which is how the original "jump to conversation" is met. A provider resume command is added only where a provider documents one.
4. **Open in Gleaner.** A `gleaner://` URL scheme selects a delivery by ID. Extensions and other tools link into the library through it.
5. **MCP.** A thin stdio adapter over the same calls. The first host tested is Claude Code, on this Mac; then the DeepSeek Harness, whose MCP client speaks stdio. Harness-native context assembly (pushing Gleaner content into an agent's context unasked) is declined for now, because it leans toward session memory (SPEC §1.1).
6. **Thin extensions** (SPEC §14): Find, Open and Handoff for Claude Code (plugin or skill), Codex (skill) and the DeepSeek Harness (plugin). They keep no database, parse no sessions and copy no snapshots.
7. **Evaluation.**
   - **First, without a model:** the benchmark's retrieval and fallback families become deterministic contract tests against the real CLI, with the locked raw-search recipe as baseline, and bytes are re-measured on Gleaner itself.
   - **Model trials:** raw logs plus file search against the registry. These need the owner's authorization of model, budget, repetitions and corpus, and none run before it.
8. **PR #4** (Thread, Outline, Timeline) is rebased after the tag, with C12 and A8's turn key.
9. **Gate 1.** Label admitted and rejected candidates on a corpus broader than one person's logs. Ranking or model help (SPEC §14) is considered only if the labels show a long tail.
10. **Distribution:** a Homebrew cask, then Sparkle; plugin directories and the MCP Registry once there is something to list.
11. **Storage.** Saved copies grow without bound. A budget needs a policy decision, because a saved copy that backs a version is never removed by cleaning caches.

**Registered as research, not scheduled:**
- **Continuous artifact and knowledge governance.** A model-optional enrichment layer using the user's own key, kept in the Keychain. A low-cost, high-throughput model works over a cached stable prefix with a replaceable task tail, batched per project, and its context size is set by experiment. It annotates, distills and consolidates into derived records only (foundation 2). It may propose display titles, aliases, tags and relations. It never renames files, merges objects or approves anything. Each pass is bound to the exact revisions and inputs it read. Before any trial, the owner must amend SPEC §14's rule that only minimal redacted excerpts leave the Mac.
- **Its evaluation.**
  - **Arms:** raw logs plus search; the deterministic registry; plus annotation; plus distillation; plus continuous governance.
  - **Reporting:** knowledge quality is reported separately from knowledge utility for the next agent, with structure fidelity, disclosure efficiency, reconstruction cost, continuity and governance reliability as measures.
  - **Control:** flat and structure-preserving data are compared under the same retrieval method, so that preserving source structure is measured on its own, not credited to a different retriever.
- **Also research:** logical-object overlays, reconstruction adapters, review states, Work Units, release groups (SPEC §15), remote and cloud sources (including exported conversations as a second kind of source), enterprise permissions.

## 4. Native acceptance

Once §1 and §2 land, these run on this Mac:
- **Build and tests:** `swift test`, `bundle-app.sh`, and the ad-hoc `release.sh`.
- **Fixtures:** the review's synthetic fixtures run in an isolated home.
- **Gate 2:** samples for MP4, PDF, Markdown and an HTML bundle.
- **Behavior:**
  - search, exact bytes after source changes, and Compare;
  - Quick Look and keyboard;
  - the preparation and cache lifecycle, and Finder drops with sha256 checks;
  - failure recovery, and window and source lifecycle;
  - appearance screenshots in light, dark and Increase Contrast, and scan and staging timings.

Results are recorded per check with the commit and the fixture phase.

**Run on 2026-10-18 at `edefa99`** (Apple silicon, macOS 27, `scripts/acceptance-home.py` with `-GleanerHome`):
- `swift test`: 168 tests in 22 suites pass. `bundle-app.sh` builds an ad-hoc signed arm64 app.
- The bundled app indexed the synthetic home with no clicks:
  - every regular file captured `at_delivery`, with copies saved up to 64 MB and the two 65 MiB files tracked by hash only;
  - the FIFO recorded as not a regular file, the chmod-000 file as unreadable, and the folder as a folder;
  - the external worktree's delivery recorded with its repository and its own checkout.
- A second delivery, appended while the app ran, was indexed through the log watcher as new versions with saved copies.
- None of these removed a delivery or a capture (15 of each throughout):
  - editing files without a delivery;
  - replacing a delivered file with a folder;
  - removing the worktree;
  - a malformed line appended to the log;
  - the log rewritten shorter, then restored.
- Not run: every check that needs the window (selection, Quick Look, Compare, drags, Check Again, Settings, appearance, keyboard). Computer use was not granted in this session, so these move to the owner's list below. The app-target tests cover their logic.

These stay with the owner:
- drops into Claude Desktop, Codex and a browser upload field;
- VoiceOver listening and visual judgment;
- the icon and the architecture decision;
- the tag, Developer ID signing and notarization;
- a clean-Mac install;
- publishing, and the P0 end-to-end demo.
