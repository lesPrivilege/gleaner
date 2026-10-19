# Evaluation E0: scripted retrieval without a model

The first evaluation named in [review-rulings §3](review-rulings.md#3-after-v010-what-to-build-next) item 7. It is built on `feat/query-core`.

## What it can and cannot show

Two deterministic, scripted policies answer the same questions over identical inputs:
- **R**: a strong raw-search recipe over the logs and files.
- **G**: the `gleaner` command, with the same raw recipe as fallback.

It measures:
- whether each answer is correct against mechanical gold;
- whether each answer stays within the evidence it saw;
- how many bytes each policy read;
- how many commands each policy ran;
- what the catalog costs to prepare.

It re-measures, on Gleaner itself, the earlier synthetic comparison (4,885 catalog bytes against 5,967 for targeted section reads).

It cannot show model efficacy, token savings or benefit to real users. Model trials (E1) need the owner's authorization of model, budget, repetitions and corpus. Nothing here calls a model.

## Tasks

Fifteen of the benchmark's 26 specifications fall within what Gleaner does. Their gold is restated in Gleaner's terms.

| Task | Question | Gold |
|---|---|---|
| T01 | The retry-policy file delivered for North's timeout request, and its `retries` value in that version | The North delivery and the bytes captured for it (`retries: 3`). Neither the same-named South file (7) nor North's live file (5) counts. |
| T02 | The version that answered the original accessibility request | The older delivery whose own request matched, and its content |
| T03 | The files handed over in the reply to the latency review | Exactly the reply's three files. Neither the neighbouring reply's file nor a tool-only file counts. |
| T04 | A delivery whose request mentions both "retry policy" and "board presentation" | None within the indexed scope, stated with that scope. The terms are split across two sessions. |
| T07 | Are North's and South's templates one item because their bytes match? | Two artifacts with equal hashes, kept apart |
| T09 | Does the current file match the latest delivery? | It matches delivery 1, not the later delivery 2 |
| T10 | Can the saved copy establish the bytes delivered at 10:00? | No. The bytes were first seen later, at a stated time more than ten minutes after the reply. |
| T12 | The file the final reply delivered for the Unicode heading request | The document. Neither the sub-agent decoy nor the line-reference example counts. |
| T16 | Recover the artifact from a deleted worktree | The saved copy, or the git restore command for the hash-only file, with what survives |
| T19 | The file the reply called the accessibility checklist, named by bare file name | The catalog doesn't hold it, and says so with its scope. The raw fallback finds the mention, which is not called a delivery. |
| T20 | Was the generated plot handed over? | No: it appears in tool output only. |
| T21 | A later decision in a partially read session | Unknown past the partial point. The index reports one partial Claude Code log (`partial_logs: 1`, a count, not which log), so G falls back; the raw read finds that this session's log ends mid-record at line N. |
| T22 | Was `spec.pdf` referenced in North's sessions? | No, within the enumerated scope only |
| T23 | Resolve a delivered plan whose path now holds other content | `verify` reports the mismatch. The saved copy is the delivered version. |
| T25 | The bytes of a delivery whose file changes during hand-off | The verified capture, or an honest failure. The new bytes are never passed off as the delivery. The file changes after the policy first sees the delivered hash. |

In T25 the protocol keeps a retained capture of the delivered bytes, so Gleaner hands off from its saved copy. Its check of a copy made from a changed original is not exercised.

Left out, because they need what Gleaner deliberately does not have:
- T05, T06, T08: logical identity, derivatives and bundle membership;
- T11: tool-record corroboration;
- T13–T15, T17, T18: approvals and authored state;
- T24: candidate leads;
- T26: bundle members and redaction tiers.

## Worlds

`eval/worlds.py <seed> <out>` writes one frozen world per task under `<out>/seed-<n>/<task>/`:
- `world/`: a home folder with `.claude/projects`, `.codex/sessions` and `work/`. These are the logs, files and git repositories both policies see.
- `task.json`: the question and the words a person would type for it. It carries no paths or IDs from the answer.

What the evaluator keeps goes to `<out>/gold/seed-<n>/<task>/`, which is neither inside nor beside any world:
- `gold.json`: the mechanically checkable answer;
- `history.json`: the epochs applied when the catalog is prepared, including the edits made after a delivery;
- T25's drift;
- the preparation record.

Every world has balanced distractors:
- similar names in another project;
- older and newer deliveries;
- decoy sessions about other things, drawn without regard to the question, except that none holds every word of it;
- near misses: one or two sessions that each hold exactly one of the question's words and nothing else of it;
- repeated phrases.

The run records, for each world, how many logs hold each word and every word.

IDs, file order and timestamps are randomized from the seed. Seeds 1–3 are for development, where the raw recipe is locked. Seeds 101–110 are scored.

Each task has one generator template. The scored seeds draw new values, IDs, order, timestamps and distractors from the same 15 templates; they don't add new kinds of question. The protocol (08) asks for a split by template. This split is by seed, so a scored result shows how the policies hold up on new draws of the templates they were written for, not how they generalize.

## Preparing the catalog

For each world, the bundled app runs with `-GleanerHome <world>` until the library's `generation` reaches 1. Then that instance is stopped. The indexing time and the library's size are recorded and charged to G. The live file system is never touched outside `world/`.

## Policies

Both policies are generic functions of `task.json`: no task ID, path or answer is in their code. But `task.json`'s `asks`, the kind of answer wanted, names the task for 10 of the 15, so each of those has a handler written against one template. They are run as subprocesses, and every byte they read from stdout or from files is counted.
- **R (locked raw recipe):**
  1. `rg` over the log folders for the typed words: one pipeline that keeps only the logs holding every word. One listing per word is used only to weigh partial matches, for a decision or to explain a negative.
  2. `jq` to take the matching turn's request and final reply.
  3. Resolve each named path against the record's `cwd`.
  4. Read the file, hashing it with `shasum -a 256`, and use `git -C … log` for missing files.

  It may keep simple scratch lists. Development seeds tune it and test seeds never do.
- **G:**
  1. `gleaner find`, then `show` for the matched delivery.
  2. `read` / `verify` / `handoff` as the question needs.
  3. Fall back to R when the response's index scope reports incomplete sources, or when `find` returns nothing.

  G never states absence beyond the scope `find` reports.

Both have the same tools (01, "Exact R0 tools plus catalog"). G may pipe `gleaner` through `jq` as R pipes its logs, and it projects each answer to the fields it reads, with the home folder written `~`, as R's projection does. Commands count the requests a policy makes. Processes count the tools those requests start, so a pipeline doesn't favour either arm.

Only one raw recipe is run. It projects every candidate log whole, close to the protocol's R-session. R-search and R-section (01) are not run. The synthetic sessions are one or two turns long, so a section read would differ little from a whole-log read.

### Isolation

The runner is each policy's only way to the world. The policy process, and every command it asks for, run under `sandbox-exec`. Nothing of the run can be read or written except that world and the policy's scratch folder. The raw policy can't read the world's catalog, and nothing can read the person's own agent logs or library. The runner also refuses, before running it, any tool outside the policies' list, `gleaner` without `--home <world>`, and any path outside the world and scratch.

### Locking

The development run that locks R records its commit and the sha256 of every `eval/*.py` in `eval/lock.json`, committed before any scored run. A run on seeds from 101 refuses to start unless the tree is clean and those files still have those hashes. Scored worlds are written, prepared and checked against their gold only in that run, after the lock. Their check is kept as pass or fail, without detail.

## Scoring

Per episode:
- task, seed and policy;
- answer status, and correct or not;
- the evidence each answer cites;
- the scope it claims;
- bytes read, commands and processes run, commands refused or timed out, what the policy saw clipped or truncated, wall time and preparation cost.

Hard failures:
- a false global absence: a negative beyond its scope, including a `not_found` for an item the gold holds when the answer states no scope or a complete one;
- current bytes passed off as a delivered version;
- two artifacts merged on a hash;
- a tool-only file called a delivery.

The runner hashes every file an answer offers as bytes, and what every git restore command it offers would give, rather than taking either from the answer.

The report keeps every episode, gives per-task and per-family tables, and gives the bytes ratio G/R overall and per family. G's wall time is also given with its world's preparation charged to it. A break-even line gives the number of queries a world would need before G's per-query saving repays its preparation, if it saves at all. Failed or retried preparations are counted against G. The report states the limits above.

## Layout

- `eval/` in this repository, Python 3 standard library only, outside `swift test`.
- `eval/README.md` says how to run it.
- Results go to `eval/results/<date>/`, containing `results.json` and `report.md`. Development runs go to `eval/results/<date>/dev/`. A results folder is written once, and every run keeps its own.
