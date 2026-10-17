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
| T01 | The retry-policy file delivered for North's timeout request, and the retry count in that version | The North delivery and the bytes captured for it (`retries: 3`). Neither the same-named South file (7) nor North's live file (5) counts. |
| T02 | The version that answered the original accessibility request | The older delivery whose own request matched, and its content |
| T03 | The files handed over in the reply to the latency review | Exactly the reply's three files. Neither the neighbouring reply's file nor a tool-only file counts. |
| T04 | A delivery whose request mentions both "retry policy" and "board presentation" | None within the indexed scope, stated with that scope. The terms are split across two sessions. |
| T07 | Are North's and South's templates one item because their bytes match? | Two artifacts with equal hashes, kept apart |
| T09 | Does the current file match the latest delivery? | It matches delivery 1, not the later delivery 2 |
| T10 | Can the saved copy establish the bytes delivered at 10:00? | No. The bytes were first seen later, at a stated time. |
| T12 | The file the final reply delivered for the Unicode heading request | The document. Neither the sub-agent decoy nor the line-reference example counts. |
| T16 | Recover the artifact from a deleted worktree | The saved copy, or the git restore command for the hash-only file, with what survives |
| T19 | The file the reply called the accessibility checklist, named by bare file name | The catalog doesn't hold it, and says so with its scope. The raw fallback finds the mention, which is not called a delivery. |
| T20 | Was the generated plot handed over? | No: it appears in tool output only. |
| T21 | A later decision in a partially read session | Unknown past the partial point, because the index reports that log as partial |
| T22 | Was `spec.pdf` referenced in North's sessions? | No, within the enumerated scope only |
| T23 | Resolve a delivered plan whose path now holds other content | `verify` reports the mismatch. The saved copy is the delivered version. |
| T25 | The bytes of a delivery whose file changes during hand-off | The verified capture, or an honest failure. The new bytes are never passed off as the delivery. |

Left out, because they need what Gleaner deliberately does not have:
- T05, T06, T08: logical identity, derivatives and bundle membership;
- T11: tool-record corroboration;
- T13–T15, T17, T18: approvals and authored state;
- T24: candidate leads;
- T26: bundle members and redaction tiers.

## Worlds

`eval/worlds.py <seed> <out>` writes one frozen world per task:
- `world/`: a home folder with `.claude/projects`, `.codex/sessions` and `work/`. These are the logs, files and git repositories both policies see.
- `task.json`: the question and the words a person would type for it. It carries no paths or IDs from the answer.
- `gold.json`, kept outside `world/`: the mechanically checkable answer.

Every world has balanced distractors:
- similar names in another project;
- older and newer deliveries;
- decoy sessions;
- repeated phrases.

IDs, file order and timestamps are randomized from the seed. Seeds 1–3 are for development, where the raw recipe is locked. Seeds 101–110 are scored.

## Preparing the catalog

For each world, the bundled app runs with `-GleanerHome <world>` until the library's `generation` reaches 1. Then that instance is stopped. The indexing time and the library's size are recorded and charged to G. The live file system is never touched outside `world/`.

## Policies

Both policies are generic functions of `task.json`, never written per task. They are run as subprocesses, and every byte they read from stdout or from files is counted.
- **R (locked raw recipe):**
  1. `rg` over the log folders for the typed words.
  2. `jq` to take the matching turn's request and final reply.
  3. Resolve each named path against the record's `cwd`.
  4. Read the file, hashing it with `shasum -a 256`, and use `git -C … log` for missing files.

  It may keep simple scratch lists. Development seeds tune it and test seeds never do.
- **G:**
  1. `gleaner find`, then `show` for the matched delivery.
  2. `read` / `verify` / `handoff` as the question needs.
  3. Fall back to R when the response's index scope reports incomplete sources, or when `find` returns nothing.

  G never states absence beyond the scope `find` reports.

## Scoring

Per episode:
- task, seed and policy;
- answer status, and correct or not;
- the evidence each answer cites;
- the scope it claims;
- bytes read, commands run, wall time and preparation cost.

Hard failures:
- a false global absence;
- current bytes passed off as a delivered version;
- two artifacts merged on a hash;
- a tool-only file called a delivery.

The report keeps every episode, gives per-task and per-family tables, and gives the bytes ratio G/R overall and per family. It states the limits above.

## Layout

- `eval/` in this repository, Python 3 standard library only, outside `swift test`.
- `eval/README.md` says how to run it.
- Results go to `eval/results/<date>/`, containing `results.json` and `report.md`.
