# Work order: CedarSearch as a frozen home

Fable, 2026-10-22, from [questions.md](../design/questions.md) (Acceptance → Corpora and Open rulings §3). For one Opus worker. Base: main at `023fa06` or later.

## Goal

Turn the human-labeled four-week project in [project-knowledge-explorations.md](../design/project-knowledge-explorations.md#a-four-week-synthetic-project) into a frozen home that `scripts`/Gleaner can index, with gold for questions Q3 (thread), Q4 (project stream) and Q5 (a section of one version). It is the only corpus long enough to measure a thread or a stream. Nothing else in E0 is long enough: its sessions are one or two turns.

Done when a command writes the home deterministically from a seed, the bundled app indexes it, and a check asserts the library holds every handover the gold names, in order, with `gleaner find`, `show` and `outline` answering as the gold says.

## Shape

Build on `eval/worlds.py` and `eval/history.py` by **importing them, never editing them**. `eval/lock.json` hashes every `eval/*.py`, and `run.py`'s `require_lock` compares the union of the locked and present files, so a new or changed file at `eval/*.py` breaks the scored-seed lock. Read how `run.py` collects `now['files']` before choosing where the module lives: `eval/corpora/cedarsearch.py` if the glob is not recursive, else a top-level `corpora/`. Say in the report which it was.

**The project.** One repository `work/cedarsearch` on `main`, with a worktree `work/cedarsearch-ranking` (branch `ranking`) and a worktree `work/cedarsearch-release` (branch `release`). All three fold into one project (rulings §2). `World.repo` only knows north/south/harbor, so write this repository with `w.write` and `w.git` directly. Call `w.projects()` too, so `w.decoys` has its usual projects to put decoys in.

**Time.** Everything is epoch 0, at fixed offsets from a project start S about 35 days before the base date, so the newest handover is still about ten days before the base. Days from S, in the sample's order:

| Day | Conversation | Where | Reply names | Notes |
|---|---|---|---|---|
| 0 | A, Claude Code | main | `baseline.md`, `latency.svg`, `benchmark.csv` | `baseline.md` has ATX headings `# Baseline`, `## Method`, `## Results`, `## Limitations`; Results states 180 ms p95 on a 10,000-document corpus |
| 3 | B, Claude Code | ranking worktree | `option-a.md`, `ranker-a.swift` | Both named as outputs |
| 5 | B | ranking | `option-b.md`, `ranker-b.swift` | A sibling alternative, not A's next version |
| 9 | B | ranking | `comparison.html`, `quality-v-latency.svg` | `comparison.html` embeds `error-breakdown.svg`, written to disk and never named in any reply |
| 12 | B | ranking | `adr-004-ranking.md` | States A is accepted for the first release, multilingual deferred |
| 16 | B | ranking | `comparison.html` again | New bytes add a multilingual limitation |
| 19 | C, Codex | release worktree | `release-notes.md`, `CedarSearch-0.4.0-rc1.dmg` | The dmg is sparse, over `SAVE_LIMIT`, committed on `release`; the reply calls it signed and ready |
| 22 | — | — | — | `git worktree remove --force` the release worktree |
| 25 | B | ranking | `follow-up.md`, `multilingual.svg` | Questions A's suitability; does not supersede the ADR |

Conversation B is one Claude Code log resumed over 22 days: six requests, six final replies, each `user` → work → `reply` as `t03` does. Use `Claude.title` once. C is one Codex rollout (`World.codex`), as `background` writes one.

**What epoch 0 cannot give, and the gold must say so.** Every capture is `first_seen_after_delivery`, since the app first reads the files at preparation. `comparison.html`'s day-9 bytes are gone: both deliveries' captures hold the day-16 bytes. The sample's "an older saved copy preserves the earlier version" is therefore **not** reproduced here; it is covered by `scripts/acceptance-home.py` (second phase). Record the dmg as Gleaner actually records it (never observed; hand-off plan `restore_from_git` or `lost`), by running it, not by guessing.

**Decoys.** `w.decoys(words, old, new)` as the E0 tasks use it, with the task's words, so every word reaches more logs than the answer's.

## Tasks and gold

Three tasks over the same world, built by one shared function and three builders, registered in the module's own `BUILDERS`, written by `worlds.generate(seed, out, tasks=...)` if it accepts foreign builders, else by the module's own `generate` that mirrors it. Task ids `Q03`, `Q04`, `Q05`; family `Q`. Gold follows `worlds.gold` (`answer`, `library`, `sessions`, `hard_failures`); `library` follows what `check_worlds.py` asserts: `deliveries` (with `reply_line`, `sha256`, `provenance`), `not_delivered`, `disk`, `find`.

| Task | `asks` | Question (person's words) | `words` | `answer` |
|---|---|---|---|---|
| Q03 | `thread` | "Where did the ranking conversation leave off?" | `ranking` | B's log; its handovers in order (reply line, request, files in reply order, day); `last` = day 25's |
| Q04 | `stream` | "What are the latest handovers in CedarSearch?" | `cedarsearch` | All eight handovers across A, B and C newest first, each with its log, agent, reply line, request and files; `latest_four` = days 25, 19, 16, 12, which span two agents and two worktrees |
| Q05 | `section` | "The Limitations section of the baseline report" | `baseline`, `limitations` | The `baseline.md` delivery; heading `Limitations`, level 2; the section's exact text from the heading to the end; that `outline` with the term `Limitations` yields exactly one heading |

`library.not_delivered` holds `error-breakdown.svg`. `library.find` for each task's words lists the paths `gleaner find` must return. Hard failures: `Q03` a handover from A or C given as part of B; `Q04` the embedded SVG or a decoy listed as a handover, or order lost; `Q05` a range from any other bytes than the delivery's `sha256`.

## Checks (all run, results in the report)

1. Writing the same seed twice into two folders gives identical bytes and mtimes outside `.git` (`check_worlds.py` shows how).
2. `prepare.py` on the bundled app indexes the home; the library's `generation` is 1; sources both `read`, no partial logs.
3. The `library` block asserted against the registry, with `check_worlds.py`'s functions imported.
4. `gleaner find ranking` and `gleaner find cedarsearch` return the gold's paths and nothing from decoys; `show` on B's day-25 delivery has `delivered_with` of exactly the other file; `outline <baseline> Limitations` returns one heading whose `range` read back with `read --bytes` equals the gold text byte for byte.
5. `swift test` untouched and passing (nothing in `Sources/` or `Tests/` changes).

Run on a folder with no symbolic link in its path, outside `/tmp` and `/private` (`history.place` refuses the rest).

## Out of scope

- `policies.py`, `score.py`, `run.py`, `lock.json`: no change. The policies don't answer `thread`, `stream` or `section` yet; that is the browse-level work, which waits on the owner's ruling (questions.md, Open rulings §2).
- Any adapter, `Sources/`, `Tests/`, `SPEC.md`.
- Real logs. Everything is invented, as the sample is.
- The saved-copy property of the day-16 rewrite (above).

## Report back

Base revision; files changed; where the module lives and why; decisions taken where this order was silent; each check with its result; what could not be checked and why. Commit on the session's branch with a message in the repository's voice (what and why, no file list); don't merge or push main.
