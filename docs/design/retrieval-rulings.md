# Rulings on the retrieval exploration

Inputs:
- The retrieval exploration on branch [`cloud/gleaner-retrieval-core-20261019`](https://github.com/lesPrivilege/gleaner/tree/56889c3b8306b87146ad661334e2aae385e9a533) (head `56889c3`, three cycles on main `2648094`). Its [convergence ledger](https://github.com/lesPrivilege/gleaner/blob/56889c3b8306b87146ad661334e2aae385e9a533/docs/retrieval-core/cycle3/CONVERGENCE-LEDGER.md) leaves four product questions to Opus, and its [engineering gates](https://github.com/lesPrivilege/gleaner/blob/56889c3b8306b87146ad661334e2aae385e9a533/docs/retrieval-core/cycle3/ENGINEERING-GATES.md) set obligations for any slice adopted from it.
- A code review of main `2648094`, that branch and PR #4 (2026-10-20): six P2 findings, no P0 or P1.
- Reference reading (2026-10-20): DSH session-query tracing, Hy-Memory and MemHub, EverOS, LayerFS.

The exploration ends here. Its evidence selects no new first layer, and no further ranking cycle is scheduled. The branch stays on origin, pinned at `56889c3`, as the record of its measurements; nothing from it merges as it is.

## 1. The ledger's four questions

| Question | Ruling |
|---|---|
| Default interaction | Show the matching works at once, best first, with the total and whether the list was cut (`find` today). No clarification gate: forcing scope asked for it on 4 of 8 tasks, one of them already unique. No diversity ordering: it equalled the baseline on all 8. No context overview. |
| Discovery scope | What the app shows: deliveries, and observed files the person kept. An unkept observation stays out of search until kept (capture §3, the original spec's first decision). A current file no reply delivered is not a result; it is reached through the work or folder that holds it. Every answer keeps carrying its index, so an empty result says what was read. |
| Version and representation | A verdict belongs to the exact bytes it was made on (review §3). "Approved" means a delivery whose captured hash carries an approving verdict. Searching a work's other renditions for approved bytes waits until a task needs it. Until then `show` lists each version's verdicts, so the caller chooses. |
| Public interface | No selection policy is exposed. `find`, `show`, `read`, `resolve`, `handoff` and `verify` keep their shape; `show` grows by disclosing what the library already records (§3). |

## 2. What is adopted from the branch

| Piece | Ruling |
|---|---|
| Exact IDs inside one report (`outline`) | Adopted as a later slice, rewritten on main. It parses once per request, caps bytes and headings, binds its ranges to the report's hash, tells `R1` from `R10`, and keeps repeated headings ambiguous. The fence test reuses `MentionExtractor`'s, so a line starting with inline code (```` ```x``` ````) opens no fence. |
| Current original on request | Deferred. It needs a root-alias policy proven by native tests (`/var` and `/private/var`). `read` and `verify` already serve the exact historical bytes. |
| Extraction and range syntax | Declined. Capture from the session superseded the prose shorthand grammar; the branch never bumped `extractorVersion`. |
| Generation and offset pagination | Declined until there is a continuation contract: bound to library, query and ordering, with a stale outcome instead of silent skips. `find` keeps `limit`, `total` and `truncated`. |
| Linux portability, `GleanerRetrievalExperiments`, eval data | Not merged. Linux is test infrastructure, not a platform. |

The engineering gates bind every adopted slice: declared discovery scope with honest denominators, state-qualified results naming the exact bytes and verdict, bytes returned from the same checked read that hashed them, real response bounds, and migration proven apart from rereading.

## 3. The loop from here

Each change answers three things: what the developer is doing, which step blocks them, and what the change removes, with the test that proves it. The task the loop serves first is **continuing earlier work in a new session**: find the earlier result, its exact version, what came with it and what a person already judged, and hand it on.

1. **Correct answers before more answers** (the review's main findings):
   - a new delivery is recorded under the repository its checkout holds now, not one a folder had earlier;
   - `read` falls back to an original that still hashes to the version when the saved copy is damaged, as `handoff` does;
   - one answer reads the library once, so its scope and its results agree;
   - a delivery time after the file was seen is not `at_delivery` beyond a small clock tolerance.
2. **`show` discloses what is already recorded:** the files delivered with this one in the same reply, and the verdicts on each version's bytes. A caller who found a review report gets its scripts without a second search, and a caller about to build on a version sees whether a person approved it.
3. **`outline`**, as §2.
4. **PR #4**, ported onto main with the turn key (review rulings §2, A8) and a timeline that holds only undated deliveries.

## 4. Reference reading, registered not scheduled

- **Typed relations, never one graph.** DSH session tracing keeps replacement, source and derived links apart and refuses recursive expansion. Gleaner's relations (delivered with, joined, kept, judged) stay typed, each with its evidence.
- **Why this result.** A retrieval trace (scope read, candidates, what excluded the rest) would make a wrong or empty answer diagnosable. It waits for a failure that needs it.
- **Real history over summaries.** Hy-Memory chains versions from real diffs, not model summaries; Gleaner's versions already come from captured hashes and Git.
- **A checkpoint is not a revision.** LayerFS can prove a file existed in a state; whether it was delivered, judged or superseded is still Gleaner's evidence. A LayerFS or DSH source would be a thin read-only adapter.
