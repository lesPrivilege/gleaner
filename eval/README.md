# Evaluation E0

Scripted retrieval without a model, as [docs/design/evaluation-e0.md](../docs/design/evaluation-e0.md) specifies it. This folder holds the worlds, the two policies that answer over them, the runner and the scorer. Everything here is Python 3's standard library, deterministic from a seed, and makes no model or network call.

You need macOS, the Swift toolchain (to build the app and the `gleaner` command), git and Python 3.

## Run it

```sh
python3 eval/run.py 1-3 build/e0          # the development seeds, into eval/results/<date>/dev/
python3 eval/run.py 101-110 build/e0      # the scored seeds, into eval/results/<date>/, once locked
python3 eval/score.py                     # score the newest results again
```

`run.py` builds the app and `gleaner` (skip with `--no-build`), writes and prepares each seed's worlds under `<out>/seed-<n>` and their gold under `<out>/gold/seed-<n>`, and runs both policies on every world. A world already prepared there is used as it is. A world whose writing or preparation fails is set aside and written once more; every failed attempt is recorded and counted against G. After both policies answer a world, it is checked against its gold (`check_worlds.check`).

Each episode is appended to `episodes.jsonl` as it finishes, so a run that stops keeps what it ran. At the end `results.json` holds every episode and replaces it, and `score.py` adds the scored rows and tables and writes `report.md` beside it. A results folder is written once: a run refuses a folder that already holds results. `--tasks` and `--policies` narrow a run; `--results` names another folder.

### Locking the raw recipe

The scored seeds run only on a recipe locked on the development seeds:

1. Run the development seeds from a clean tree, and commit their results.
2. Write `eval/lock.json`: the commit of that run, the seeds, the results folder, and the sha256 of every `eval/*.py`. Commit it.
3. Run the scored seeds. `run.py` refuses unless the tree is clean and every `eval/*.py` has the hash the lock records.

The scored worlds are written, prepared and checked only in that run. Their gold check keeps pass or fail, not what failed.

The steps below are what `run.py` does, one at a time.

## Write worlds

```sh
python3 eval/worlds.py <seed> <out>
```

This writes one folder per task (T01, T02, T03, T04, T07, T09, T10, T12, T16, T19, T20, T21, T22, T23, T25) under `<out>/seed-<seed>`:

- `world/` is the home folder both policies see. It has `.claude/projects` (Claude Code logs, sub-agent transcripts under `<session>/subagents/`), `.codex/sessions` and `.codex/session_index.jsonl` (Codex rollouts), and `work/north`, `work/south` and `work/harbor`, which are git repositories.
- `task.json` holds the question, the `words` a person would type for it, and `asks`, the kind of answer it wants (below).

What the evaluator keeps from the policies goes to `<out>/gold/seed-<seed>/<task>`, which is neither inside nor beside any world:

- `gold.json` holds the answer.
- `history.json` holds the epochs that `prepare.py` applies (below), including the edits made after a delivery.
- T25 also has `drift.json` and `drift/`: the change the runner makes while a policy works.
- `prepared.json`, once the world is prepared.

Besides each task's own distractors, every world has decoy sessions about other things, drawn without regard to the question except that none holds every word of it, and one or two near misses. A near miss is a session that holds exactly one of the question's words and nothing else of it.

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

`prepared.json`, in the gold folder, records:
- when each epoch was applied;
- each index run's time;
- the library's id and generation;
- its size on disk and the number of saved copies.

These are the preparation costs charged to the gleaner policy. Prepare a world once. A second run is refused, even after one that stopped partway; write that world again. Timestamps from the later epochs depend on when the world was prepared. Nothing in `gold.json` does.

## Check the worlds

```sh
python3 eval/check_worlds.py                    # the development seeds 1 2 3, every task
python3 eval/check_worlds.py --seeds 1 --tasks T16 T23 --out build/worlds --keep
```

It checks development seeds only. A scored world is checked by `run.py`, after the lock.

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

The summary goes to `eval/results/<date>/dev/check_worlds.json`. The worlds go to a new folder under `build/`, removed afterwards unless `--out` or `--keep` is given. The command exits 1 if any world fails.

## task.json

| Field | Meaning |
|---|---|
| `task`, `family` | The task and its benchmark class: `E` shared information, `S` recorded state, `B` fallback |
| `question` | The question as a person asks it |
| `words` | What they would type to search for it |
| `asks` | The kind of answer, so a generic policy knows which commands it needs |
| `project`, `projects` | A project the question names |
| `field` | For `value`: the `name:` line to read from the delivered bytes, as the question names it |
| `at` | For `provenance`: the delivery time the question names |
| `name` | For `referenced`: the file name asked about |
| `pointer` | For `verify` (T23): the catalog pointer the question supplies |

Values of `asks`; for 10 of the 15 tasks it names the task:
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

It is in the world's gold folder. Paths are relative to `world/`. A delivery is named by its file, the session that delivered it, that session's log and the reply record's line.

- `answer`: the expected answer for the task's `asks`, with what must be excluded and why.
- `hard_failures`: the failure classes the task tests, such as `false_global_absence`, `current_as_delivered`, `hash_merge` and `tool_only_as_delivery`.
- `sessions`: every log in the world, sub-agent transcripts marked, and decoys and near misses marked with their `role`. This is the scope a bounded negative answer refers to.
- `library`: what the prepared library must hold, as `check_worlds.py` asserts it.
- `seed`.

## T25's hook

`drift.json` says when the runner rewrites the delivered file during an episode. After the first command whose standard output holds the delivered bytes' sha256, and before the policy's next command, the runner copies `drift/kpis.csv` over `world/work/south/out/kpis.csv`, once. So each policy has seen the file verified before it changes: G after `gleaner find`, R after its `stat` and `shasum`. The same hook runs for both policies. The delivered bytes are still Gleaner's saved copy, the protocol's retained capture, so Gleaner's hand-off reads that copy and never the changed file. The new bytes must never be passed off as the delivery.

## The policies

`policies.py` holds both. Each is a generic function of `task.json`: its `words`, its `asks`, and the fields `asks` uses. No task id, path, gold or answer word is in the policy code.

- **R**, the locked raw recipe:
  1. One `rg` pipeline over `.claude/projects` and `.codex/sessions` that keeps the logs holding every word, sub-agent transcripts left out (`rg -l0 … | xargs -0 rg -l0 …`). Codex titles come from `.codex/session_index.jsonl` when it is there; a Codex log whose title holds some words need hold only the rest. One `rg -l` per word is used only to weigh partial matches: for `decision`, and to say where the words are when no log holds them all.
  2. A `jq` projection of each log that holds every word: one short line per request, assistant text, tool call, tool result and title, with the home folder written `~`. Turns are split from it. The turn chosen is the one whose request, title, final reply and project hold every word, ranked by the words in its request, then the newest. For `decision`, the one that holds the most words.
  3. The paths its final reply names, resolved against each record's cwd. A link names a delivery; inline code names one only with a folder in it, a line anchor makes it a reference into code, and a bare file name is a mention, placed through the one file of that name the turn's tools touched.
  4. `stat` and `shasum -a 256` of the file, and of the turn's last logged write of it (a Write call's content, or a here-document). The logged write stands for the delivered bytes while the file still has them, or changed after the reply, or is gone. A file that differs from it with a modification time before the reply was changed by something the log does not show, so neither is the delivery. Without such a write, `git -C … log` finds a commit made during the turn. A modification time alone never establishes the bytes.
- **G**: `gleaner find` with the words (and `--project`), then only what the question needs: `read` for a value, `show` for the other versions or a hand-off plan, `handoff` and `shasum` for bytes, `verify` for a pointer, and `git show … | shasum` to check the commit a restore command names. Each `gleaner` answer goes through `jq` (`G_PROJECTION`), which keeps the fields G reads and writes the home folder `~`, as R's projection does for logs. It falls back to R, run in full, when find's index reports a source not read cleanly, or when find returns nothing. For what the catalog does not record, the delivering turn's tool output and later turns, it reads the one log the delivery's evidence names with R's projection. Its negative answers carry the index's scope, and R's when it fell back.

Two points go beyond evaluation-e0.md, which has G always call `show` and names only the two fallback conditions: G calls `show` only when the answer needs it, and it reads the delivering log for what is outside the catalog.

### How an episode runs

The runner starts the policy as a subprocess and is its only way to the world. The policy writes each command as one JSON line, `{"argv": [...]}` or `{"sh": "..."}` for a pipeline. The runner runs it in the world's home folder, with that folder as `HOME`, no git configuration and git kept from looking above the world, and answers with its status, standard output and standard error. The policy's last line is its answer.

Before running a command, the runner splits it into the commands sh would run (the one `xargs` starts included) and refuses:
- a tool outside `rg`, `jq`, `shasum`, `git`, `stat`, `sed`, `awk`, `cat`, `head`, `xargs`, `tr` and `dirname`, and the shell's `[`, `test`, `set`, `true` and `false`;
- `gleaner`, unless the policy is G and the command ends `--home <world>`; it may be in a pipeline;
- a path outside the world and the policy's scratch folder;
- a command substitution inside quotes, which it can't check.

The policy process and every command run under `sandbox-exec`. They can read and write nothing under the run's folder but this world and the scratch folder, can write only to the scratch folder (and G to the world's `Library`, where `gleaner` stages hand-off copies), and can't read the person's `~/.claude`, `~/.codex` or Gleaner library. The raw policy can't read `world/Library` at all.

The runner counts each command, the tool processes it starts, and every byte of its standard output and standard error. A pipeline counts what it prints. It also counts the same bytes with the world's home folder written `~`, so where a world was written weighs nothing. A refused command, one that timed out, or a policy that breaks is recorded with the episode, never dropped. After the episode, the runner hashes any file the answer offers as bytes, and runs `git show` itself for any git restore command it offers. Then it puts the world back: T25's file, and Gleaner's hand-off copies. Which policy goes first alternates by world.

### Scoring

`score.py` scores each answer against its world's `gold.json` by what the question asks: the delivery cited (file, log and reply line), the value, hash or files, and for a negative, a scope that is complete and covers the sessions it should. It records the hard failures an answer commits: the four the evaluation names (`false_global_absence`, `current_as_delivered`, `hash_merge`, `tool_only_as_delivery`) and the task-specific ones each gold lists. A `not_found` for an item the gold holds is a false global absence unless its scope is bounded and says it is incomplete. An answer with a hard failure is not correct.

The report keeps every episode. It gives per-family and per-task tables, the ratio of bytes read, G to R, overall and per family, and G's wall time with its world's preparation charged to it. It also counts refusals, timeouts and truncations, the hard failures, and failed preparations. A break-even line gives the queries a world would need before G's preparation repays itself. It lists every run under `eval/results/`.

### The worlds, for the policies

- Both policies see `world/`. The gleaner policy runs `gleaner … --home <world>`. `world/Library` is the catalog and is charged to it; the raw policy never reads it.
- T10 follows the benchmark: the file's modification time is five minutes before the reply, as if restored, and its bytes differ from the logged write. Gleaner first read it when the world was prepared, long after the reply, so its capture is `first_seen_after_delivery`. An answer must state when the bytes were first observed: G gives the capture's time, R the time of its own read.
- T21's log ends mid-record, the way a log copied while it was being written does. The index counts one partial Claude Code log (`partial_logs: 1`) without naming it, so G falls back to R, whose read of the log stops at the cut record. Nothing after that point can be read.
