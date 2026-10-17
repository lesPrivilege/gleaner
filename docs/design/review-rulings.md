# Rulings on the v0.1 review and the 2026-10-17 research

Inputs: the independent release review and four research streams on branch [`cloud/gleaner-review-research-20261017`](https://github.com/lesPrivilege/gleaner/tree/cloud/gleaner-review-research-20261017/docs/research/2026-10-17) (commit `6a95aad`), audited against main `22dd07d`. Finding IDs (D1–D8, N1–N4) are the review's. The research is treated as verified input; these rulings decide what Gleaner does with it.

## 1. Before tagging v0.1.0

The review's central recommendation is accepted: the preservation and exact-selection defects violate SPEC §1 and §6 and are fixed before the tag. Each fix lands with a test that fails on `22dd07d`.

| ID | Ruling | Fix, at its smallest |
|---|---|---|
| D1 | Blocks | Resolve hand-off and preview from the **selected delivery's capture**, not today's path kind. A delivery captured as a regular file resolves by its hash (original if it still matches, else the saved copy) even when the path is now a folder. Live-folder actions only for a delivery captured as a folder whose path is a directory now; a folder delivery whose path is missing or now a file is unavailable. |
| D2 | Blocks | Adapters report whether a log was read completely (malformed records, read errors). Prune deliveries a log no longer admits **only after a complete reread**; on an incomplete one, upsert what was found, keep everything else, and report the log as partial. A database error on one log is recorded as that log's failure and the run continues. |
| D3 | Blocks | Compare holds the bytes it names: image ends are loaded once from verified data, never re-read from a live URL. A comparison result is published only for the pair it was requested for. Compare ends keep "first seen later". Binary or document files over the text limit (PDF etc.) fall through to the size/hash comparison SPEC §6.1 promises, instead of being refused. |
| N1 | Blocks | Quick Look shows exactly the selected delivery's prepared bytes; when the selected delivery changes (version buttons, query), the panel follows it or closes. |
| D5 | Blocks | The offered restore command names a commit that actually contains the path (found and checked, not "parent of the latest touching commit"), with POSIX-safe quoting for any path. Recovery stays user-run; the existing warning stays. |
| D7 | Blocks | An unclosed fence masks to the end of the reply (CommonMark). Fence scanning tracks delimiter character and length. Bump `extractorVersion`. |
| H1 | Blocks | `Locator.sha256` returns nil on a read error, never the digest of a prefix. |
| N3 | Blocks | SPEC §8 already requires it: per source, distinguish *not present*, *unreadable* and *read with problems* (unknown record types, malformed lines, partial logs), carry it into one compact status line in the library and Settings, and keep showing cached results. No onboarding flow. |
| D4 | Blocks | Filter by a repository key (the repository's main folder path), display its short name, disambiguate equal names with the parent folder. Record the repository a delivery was resolved to while it could be resolved, so a deleted external worktree keeps its project after a cold restart. Unresolvable history stays explicitly unresolved. |
| N2 | Fix now | Clearing hand-off copies restages the current selection (explicit generation), and never deletes a copy a preparation is writing. |
| D6 | Fix now | "Delivered with" carries the sibling's delivery, not just its artifact, and lands on that occurrence. |
| H3 | Fix now | Staging writes to a unique temporary file and publishes it atomically, so overlapping stages of the same version cannot remove each other's file. |
| H2 | Fix now | Comparison loads only regular files (same check as staging). |
| N4 | Fix now, minimally | Open and Save a Copy report failure where the button was pressed. A failed small-file save is not described as the large-file policy. |
| — | Fix now | Log folders absent at launch are picked up when they appear (watch recreated on reread). |
| — | Spec wording | SPEC §10: a result opens on the newest delivery whose own words matched, falling back to the newest delivery when only the name or project matched. That is the current behavior and the better one. |
| D8 | Deferred | Provider-scoped session keys before a third adapter or any import. Claude and Codex session IDs are UUIDs; no collision is plausible within v0.1. |

Release documents: README, README.zh-CN and CHANGELOG describe the signing state the owner actually ships; settled at tagging (docs/release.md), not before.

## 2. After v0.1.0: what to build next

Decisions on the [handoff outline](https://github.com/lesPrivilege/gleaner/blob/cloud/gleaner-review-research-20261017/docs/research/2026-10-17/decisions/opus-handoff.md):

1. **First consumer and job.** A local shell agent (Claude Code or Codex on the same Mac). The job: find the intended delivery, select its exact version, hand those bytes on. This is the product contract (SPEC §2) and the one claim the prior-art review leaves open: version-correct selection under incomplete evidence. Progressive retrieval and retrospective provenance are established practice and are not claimed.
2. **Architecture.** A shared query/read boundary in GleanerCore, exposed first as a `gleaner` command-line tool with JSON output (`find`, `show`, `read`, `handoff`). It is the second layer of SPEC §14. The CLI opens the registry read-only (today's initializer creates tables and resets cursors, so it cannot be reused as is), never indexes, and reports index freshness. MCP comes later as a thin adapter over the same calls, only once a concrete host is chosen to test it against.
3. **What an identifier promises.** A delivery ID is stable within one library while its log path is unchanged; a capture's sha256 is the exact selector. No logical-object identity, cross-path linking, or merge on hash.
4. **Admission boundary.** Unchanged: the user-facing final reply (SPEC §9). Measuring what the gate excludes is Gate 1, after release.
5. **Evaluation.** First without a model: turn the benchmark's retrieval and fallback families into deterministic contract tests against the real CLI, with the locked raw-search recipe as baseline, and re-measure bytes on Gleaner itself. Model trials (arms, model, repetitions, budget, corpus) need the owner's authorization and are not run before it.
6. **Not scheduled.** Logical-object overlays, reconstruction adapters, authored governance, enterprise permissions, generated summaries. They stay research until a real task needs them.

## 3. Native acceptance

After §1 lands: `swift test`, a bundled build, and the review's synthetic fixtures in an isolated home, driven on this Mac where an agent can see the result. VoiceOver listening, Developer ID signing and notarization, a clean-Mac install and third-party receivers stay with the owner.
