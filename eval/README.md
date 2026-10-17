# Evaluation E0

Scripted retrieval without a model, as [docs/design/evaluation-e0.md](../docs/design/evaluation-e0.md) specifies it. This folder holds the worlds the policies answer over. Everything here is Python 3's standard library, deterministic from a seed, and makes no model or network call.

You need macOS, the Swift toolchain (to build the app and the `gleaner` command), git and Python 3.

## Write worlds

```sh
python3 eval/worlds.py <seed> <out>
```

This writes one folder per task (T01, T02, T03, T04, T07, T09, T10, T12, T16, T19, T20, T21, T22, T23, T25) under `<out>`:

- `world/` is the home folder both policies see. It has `.claude/projects` (Claude Code logs, sub-agent transcripts under `<session>/subagents/`), `.codex/sessions` and `.codex/session_index.jsonl` (Codex rollouts), and `work/north`, `work/south` and `work/harbor`, which are git repositories.
- `task.json` holds the question, the `words` a person would type for it, and `asks`, the kind of answer it wants (below).
- `gold.json` holds the answer, kept outside `world/`.
- `history.json` holds the epochs that `prepare.py` applies (below).
- T25 also has `drift.json` and `drift/`: the change the runner makes while a policy works.

Choose a folder with no symbolic link in its path, outside `/tmp` and `/private`, such as one under `build/` or your home folder. Gleaner lists logs with their links resolved (`/tmp` becomes `/private/tmp`), but it standardizes the paths a reply names, which drops `/private`. So in such a folder, one world would be recorded under two spellings. `worlds.py` refuses such a folder.

The logs record absolute paths, so a world stays where it was written. Writing the same seed into the same folder gives the same bytes and modification times. The exceptions are inside `.git`, and anything prepared later.

Seeds 1–3 are for development, where the raw recipe is locked. Seeds 101–110 are scored.

## Prepare a world and its catalog

```sh
./scripts/bundle-app.sh
python3 eval/prepare.py <out>/T01 <out>/T02 …
```

Gleaner calls a capture "at delivery" only when it reads the file within ten minutes of the reply that named it (SPEC §5.1). It also captures a delivery's bytes once, when it first reads the reply. So a world cannot be written whole in advance and indexed once. Its history is in epochs:

- **Epoch 0** is the past: older sessions, repositories and files, at the seed's base date. `worlds.py` writes it.
- **Later epochs** are written by `prepare.py`, each anchored to the moment it applies them. After each indexed epoch, it starts the app with `open -n build/Gleaner.app --args -GleanerHome <world>`. It waits until the library's `meta.generation` counts that run, reading it with SQLite in read-only mode, then stops that instance.
  - Most worlds have one indexed epoch.
  - T02 and T09 have two: each delivers the same path again with new bytes, so the library ends at generation 2.
  - T01, T09, T16 and T23 then change files after the last index, the way a person would after a delivery: a live edit, a restored file, a removed worktree, a moved and reused path.

The app runs only on the world's own folders. Its library is `world/Library/Application Support/Gleaner`. The person's own library, `~/.claude` and `~/.codex` are never read or written.

`prepared.json` records:
- when each epoch was applied;
- each index run's time;
- the library's id and generation;
- its size on disk and the number of saved copies.

These are the preparation costs charged to the gleaner policy. Prepare a world once. A second run is refused, even after one that stopped partway; write that world again. Timestamps from the later epochs depend on when the world was prepared. Nothing in `gold.json` does.

## Check the worlds

```sh
python3 eval/check_worlds.py                    # seeds 1 2 3 101 102, every task
python3 eval/check_worlds.py --seeds 1 --tasks T16 T23 --out build/worlds --keep
```

It works in four steps:
1. Builds the app and `gleaner` (skip with `--no-build`).
2. Writes each seed's worlds twice into the same folder and compares them byte for byte.
3. Prepares every world.
4. Asserts `gold.json`'s `library` against what Gleaner recorded.

The `library` checks cover:
- each delivery's hash, provenance and saved copy;
- its number among its file's deliveries, its reply line and anchor;
- what must not be a delivery;
- exactly which files `gleaner find` returns for the task's words;
- the files on disk now;
- how the index read each agent's logs;
- the raw log facts a negative answer rests on.

Through `gleaner show`, `verify` and `handoff` it also checks availability, the hand-off plan and T16's restore command. For the command, it confirms the commit it names holds the delivered bytes. It also applies T25's drift and undoes it, checking that a hand-off still gives the delivered bytes.

The summary goes to `eval/results/<date>/check_worlds.json`. The worlds go to a new folder under `build/`, removed afterwards unless `--out` or `--keep` is given. The command exits 1 if any world fails.

## task.json

| Field | Meaning |
|---|---|
| `task`, `family` | The task and its benchmark class: `E` shared information, `S` recorded state, `B` fallback |
| `question` | The question as a person asks it |
| `words` | What they would type to search for it |
| `asks` | The kind of answer, so a generic policy knows which commands it needs |
| `project`, `projects` | A project the question names |
| `field` | For `value`: the `name:` line to read from the delivered bytes |
| `at` | For `provenance`: the delivery time the question names |
| `name` | For `referenced`: the file name asked about |
| `pointer` | For `verify` (T23): the catalog pointer the question supplies |

Values of `asks`:
- `value`: T01, T02
- `files`: T03
- `delivery`: T04, T12, T19
- `same_item`: T07
- `current_match`: T09
- `provenance`: T10
- `recover`: T16
- `handed_over`: T20
- `decision`: T21
- `referenced`: T22
- `verify`: T23
- `bytes`: T25

T23's pointer carries no `library`, because a library's id is made when it is first prepared. `gleaner verify <delivery>` takes the id alone.

## gold.json

Paths are relative to `world/`. A delivery is named by its file, the session that delivered it, that session's log and the reply record's line.

- `answer`: the expected answer for the task's `asks`, with what must be excluded and why.
- `hard_failures`: the failure classes the task tests, such as `false_global_absence`, `current_as_delivered`, `hash_merge` and `tool_only_as_delivery`.
- `sessions`: every log in the world, sub-agent transcripts marked. This is the scope a bounded negative answer refers to.
- `library`: what the prepared library must hold, as `check_worlds.py` asserts it.
- `seed`.

## T25's hook

`drift.json` says when the runner rewrites the delivered file during an episode. After the first command whose standard output contains the file's name, and before the policy's next command, the runner copies `drift/kpis.csv` over `world/work/south/out/kpis.csv`, once. The same hook runs for both policies. The delivered bytes are still Gleaner's saved copy; the new bytes must never be passed off as the delivery.

## For the policies

- Both policies see `world/`. The gleaner policy runs `gleaner … --home <world>`. `world/Library` is the catalog and is charged to it; the raw policy never reads it.
- T10 follows the benchmark: the file's modification time is five minutes before the reply, as if restored, and its bytes differ from the logged write. Gleaner first read it when the world was prepared, long after the reply, so its capture is `first_seen_after_delivery`.
- T21's log ends mid-record, the way a log copied while it was being written does. The index reports it as partial (`partial_logs: 1`), and nothing after that point can be read.
