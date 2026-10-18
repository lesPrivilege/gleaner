# Evaluation E0: results

Seeds 1–3; 15 tasks; policies R, G. Run 2026-10-18T01:34:59+00:00 on macOS 27.0.1 (arm64) at commit ba428b1, with ripgrep 15.1.0, jq-1.7.1-apple, git version 2.50.1 (Apple Git-155) and Python 3.14.2.

These are development seeds, where the raw recipe is tuned and locked. The tree was clean.

How it was made: [docs/design/evaluation-e0.md](../../../../docs/design/evaluation-e0.md) and [eval/README.md](../../../README.md). Every episode, with its commands and answer, is in `results.json`.

## What this can and cannot show

Two scripted, deterministic policies answer the same questions over the same worlds. This shows whether each answer is correct against mechanical gold, whether it stays within its evidence, how many bytes and commands each policy needed, and what the catalog cost to prepare. Nothing here calls a model. So it cannot show model efficacy, token savings, or benefit to real users. Bytes read by a script are not tokens a model would spend. The worlds are synthetic and few, and none of this is a production rate.

Limits of this design:

- **One template per task.** The scored seeds run the same 15 world builders as the development seeds. Only the values, ids, order, timestamps and distractors are new. Both policies were written against these templates, and `asks` alone names the task for 10 of the 15 (every `asks` but `value` and `delivery`). So correctness here shows the policies hold up on new draws of templates they were built for. It does not show they generalize to new kinds of question. The protocol (08) asks for a split by generator template; this split is by seed.
- **One raw variant.** R projects each candidate log whole, which is close to the protocol's R-session. R-search and R-section (01) were not run. The synthetic sessions are one or two turns long, so a section read would differ little from a whole-log read here.
- **Equal tools.** Both policies may use `jq`, and G projects each `gleaner` answer to the fields it reads, with the home folder written `~`, as R projects its logs. Commands count requests; processes count the tools a pipeline starts.
- **One query per world.** Each world is prepared once and asked one question, so preparation is charged in full to that one G episode. The break-even line below says how many queries a world would need.
- **T25.** The drift lands after the first output that holds the delivered hash. Gleaner hands off from its saved copy, as the protocol's retained capture allows, so its check of a copy made from the changed original is never reached.

## How the policies ran

- **R**: one `rg` pipeline over the two log folders keeps the logs that hold every word, sub-agent transcripts left out, with Codex titles from its session index. A per-word listing is used only for a decision, which weighs partial matches, and to explain a negative. Then a `jq` projection of each candidate log; the turn whose request, title, final reply and project hold every word; each path the final reply names, resolved against its record's cwd; then `stat` and `shasum -a 256` of the file and of the turn's logged write of it, and `git log` for a file that is gone. The logged write stands for the delivered bytes only while the file still has them, or changed after the reply.
- **G**: `gleaner find` with the words, then only what the question needs: `read` for a value, `show` for the other versions or a hand-off plan, `handoff` for bytes, `verify` for a pointer. Each answer is projected with `jq`. G falls back to R, counted in full, when the index reports a source read with problems or find returns nothing. For what the catalog does not record (the delivering turn's tool output, later turns), it reads the log the delivery's evidence names, with R's projection.
- Two points go beyond evaluation-e0.md, which has G always call `show` and names only the two fallback conditions. G skips `show` when the answer does not need it, and it reads the delivering log for what is outside the catalog.
- The runner is each policy's only way to the world. The policy, and every command, run under `sandbox-exec`. They can read and write nothing of the run's but that world and the policy's scratch folder; R cannot read the world's catalog either. Gold lives outside every world.

## Summary

| Policy | Correct | Hard failures | Fallbacks | Bytes read | Bytes, home as ~ | Commands | Processes | Refused | Timed out | Wall time (s) | With preparation (s) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| R | 45 of 45 | 0 | 0 | 113,147 | 94,717 | 250 | 465 | 0 | 0 | 8.858 | 8.858 |
| G | 45 of 45 | 0 | 12 | 99,098 | 81,832 | 128 | 232 | 0 | 0 | 14.717 | 35.001 |

Bytes read, G over R: **0.876** overall; B (fallback) 1.07; E (shared information) 0.73; S (recorded state) 1.19.

With the home folder's path counted as ~, G over R: **0.864** overall; B (fallback) 1.08; E (shared information) 0.717; S (recorded state) 1.183.

R reported 9 projected fields clipped at 240 characters; G 1 in its raw reads, and 0 gleaner answers marked truncated. Episodes that could not run: R 0, G 0.

## Preparation

Charged to G: 45 of 45 worlds prepared, 51 index runs, 20.284 s of indexing, 20,023,247 library bytes on disk (444,961 per world), 366 saved copies. Failed preparation attempts: 0. R prepares nothing.

Per world, G's preparation took 0.451 s on average. Its episodes took 0.327 s against R's 0.1968 s, so G is 0.1302 s a query slower and **preparation never repays itself in wall time**. G read 312.2 fewer bytes a query than R. Bytes have no preparation counterpart: the index reads every log, but no policy reads what it read.

| Queries a world | R seconds | G seconds, preparation included |
|---|---|---|
| 1 | 0.197 | 0.778 |
| 10 | 1.968 | 3.721 |
| 100 | 19.684 | 33.155 |
| 1000 | 196.844 | 327.495 |

These counts are a sensitivity range, not observed workloads.

## By family

| Family | Policy | Correct | Hard failures | Fallbacks | Bytes read | Bytes, home as ~ | Commands | Processes | Wall time (s) | With preparation (s) |
|---|---|---|---|---|---|---|---|---|---|---|
| B (fallback) | R | 18 of 18 | 0 | 0 | 34,576 | 26,622 | 74 | 116 | 2.722 | 2.722 |
| B (fallback) | G | 18 of 18 | 0 | 9 | 36,992 | 28,747 | 66 | 99 | 4.227 | 11.105 |
| E (shared information) | R | 24 of 24 | 0 | 0 | 68,275 | 58,963 | 149 | 298 | 4.502 | 4.502 |
| E (shared information) | G | 24 of 24 | 0 | 3 | 49,851 | 42,285 | 47 | 106 | 6.972 | 19.198 |
| S (recorded state) | R | 3 of 3 | 0 | 0 | 10,296 | 9,132 | 27 | 51 | 1.634 | 1.634 |
| S (recorded state) | G | 3 of 3 | 0 | 0 | 12,255 | 10,800 | 15 | 27 | 3.518 | 4.698 |

## By task

| Task | Asks | R correct | R bytes | R commands | G correct | G bytes | G commands | G/R bytes |
|---|---|---|---|---|---|---|---|---|
| T01 | value | 3 of 3 | 1,921 | 5.0 | 3 of 3 | 1,841 | 2.0 | 0.958 |
| T02 | value | 3 of 3 | 4,092 | 7.0 | 3 of 3 | 1,943 | 2.0 | 0.475 |
| T03 | files | 3 of 3 | 2,769 | 3.0 | 3 of 3 | 2,984 | 1.0 | 1.078 |
| T04 | delivery | 3 of 3 | 3,125 | 4.7 | 3 of 3 | 3,380 | 5.7 | 1.082 |
| T07 | same_item | 3 of 3 | 3,079 | 9.0 | 3 of 3 | 2,274 | 1.0 | 0.739 |
| T09 | current_match | 3 of 3 | 3,982 | 9.0 | 3 of 3 | 2,345 | 2.0 | 0.589 |
| T10 | provenance | 3 of 3 | 1,409 | 7.3 | 3 of 3 | 917 | 1.0 | 0.651 |
| T12 | delivery | 3 of 3 | 2,381 | 4.7 | 3 of 3 | 933 | 1.0 | 0.392 |
| T16 | recover | 3 of 3 | 3,432 | 9.0 | 3 of 3 | 4,085 | 5.0 | 1.19 |
| T19 | delivery | 3 of 3 | 1,199 | 4.0 | 3 of 3 | 1,454 | 5.0 | 1.213 |
| T20 | handed_over | 3 of 3 | 2,136 | 4.0 | 3 of 3 | 2,775 | 3.0 | 1.299 |
| T21 | decision | 3 of 3 | 2,529 | 5.0 | 3 of 3 | 2,798 | 6.0 | 1.106 |
| T22 | referenced | 3 of 3 | 2,261 | 3.0 | 3 of 3 | 2,516 | 4.0 | 1.113 |
| T23 | verify | 3 of 3 | 1,813 | 3.0 | 3 of 3 | 770 | 1.0 | 0.425 |
| T25 | bytes | 3 of 3 | 1,586 | 5.7 | 3 of 3 | 2,017 | 3.0 | 1.271 |

Bytes and commands per task are means per episode.

## Hard failures

None in 90 episodes. Each was checked for the four general classes (`false_global_absence`, `current_as_delivered`, `hash_merge`, `tool_only_as_delivery`) and for the task-specific ones its gold lists. Zero observed failures in this many synthetic episodes does not establish a failure rate.

## Worlds

A world has 8.1 session logs on average, sub-agent transcripts left out: 3.5 decoys about other things and 1.3 near misses that each hold exactly one query word. A query word is in 2.8 logs on average; every word is in 1.2. The per-world counts are in `results.json` (`worlds[].distractors`).

After its episodes, each world was checked against its gold (check_worlds.check): 45 of 45 hold what their gold presumes.

## Every episode

| Task | Seed | Policy | Status | Correct | Hard failures | Bytes | Commands | Seconds | Notes |
|---|---|---|---|---|---|---|---|---|---|
| T01 | 1 | G | found | yes | – | 1,841 | 2 | 0.361 | – |
| T01 | 1 | R | found | yes | – | 1,921 | 5 | 0.159 | – |
| T01 | 2 | G | found | yes | – | 1,841 | 2 | 0.322 | – |
| T01 | 2 | R | found | yes | – | 1,921 | 5 | 0.19 | – |
| T01 | 3 | G | found | yes | – | 1,841 | 2 | 0.352 | – |
| T01 | 3 | R | found | yes | – | 1,921 | 5 | 0.167 | – |
| T02 | 1 | G | found | yes | – | 1,943 | 2 | 0.328 | – |
| T02 | 1 | R | found | yes | – | 4,092 | 7 | 0.167 | – |
| T02 | 2 | G | found | yes | – | 1,943 | 2 | 0.349 | – |
| T02 | 2 | R | found | yes | – | 4,092 | 7 | 0.196 | – |
| T02 | 3 | G | found | yes | – | 1,943 | 2 | 0.334 | – |
| T02 | 3 | R | found | yes | – | 4,092 | 7 | 0.182 | – |
| T03 | 1 | G | found | yes | – | 2,984 | 1 | 0.332 | – |
| T03 | 1 | R | found | yes | – | 2,769 | 3 | 0.108 | – |
| T03 | 2 | G | found | yes | – | 2,984 | 1 | 0.33 | – |
| T03 | 2 | R | found | yes | – | 2,769 | 3 | 0.113 | – |
| T03 | 3 | G | found | yes | – | 2,984 | 1 | 0.324 | – |
| T03 | 3 | R | found | yes | – | 2,769 | 3 | 0.115 | – |
| T04 | 1 | G | not_found | yes | – | 3,236 | 5 | 0.148 | fallback: find returned nothing |
| T04 | 1 | R | not_found | yes | – | 2,981 | 4 | 0.125 | – |
| T04 | 2 | G | not_found | yes | – | 3,492 | 6 | 0.182 | fallback: find returned nothing |
| T04 | 2 | R | not_found | yes | – | 3,237 | 5 | 0.155 | – |
| T04 | 3 | G | not_found | yes | – | 3,412 | 6 | 0.179 | fallback: find returned nothing |
| T04 | 3 | R | not_found | yes | – | 3,157 | 5 | 0.154 | – |
| T07 | 1 | G | found | yes | – | 2,274 | 1 | 0.389 | – |
| T07 | 1 | R | found | yes | – | 3,079 | 9 | 0.239 | – |
| T07 | 2 | G | found | yes | – | 2,274 | 1 | 0.383 | – |
| T07 | 2 | R | found | yes | – | 3,079 | 9 | 0.244 | – |
| T07 | 3 | G | found | yes | – | 2,274 | 1 | 0.386 | – |
| T07 | 3 | R | found | yes | – | 3,079 | 9 | 0.25 | – |
| T09 | 1 | G | found | yes | – | 2,345 | 2 | 0.316 | – |
| T09 | 1 | R | found | yes | – | 3,982 | 9 | 0.244 | – |
| T09 | 2 | G | found | yes | – | 2,345 | 2 | 0.358 | – |
| T09 | 2 | R | found | yes | – | 3,982 | 9 | 0.241 | – |
| T09 | 3 | G | found | yes | – | 2,345 | 2 | 0.341 | – |
| T09 | 3 | R | found | yes | – | 3,982 | 9 | 0.282 | – |
| T10 | 1 | G | found | yes | – | 917 | 1 | 0.215 | – |
| T10 | 1 | R | found | yes | – | 1,369 | 7 | 0.197 | – |
| T10 | 2 | G | found | yes | – | 917 | 1 | 0.165 | – |
| T10 | 2 | R | found | yes | – | 1,369 | 7 | 0.257 | – |
| T10 | 3 | G | found | yes | – | 917 | 1 | 0.22 | – |
| T10 | 3 | R | found | yes | – | 1,489 | 8 | 0.25 | – |
| T12 | 1 | G | found | yes | – | 933 | 1 | 0.21 | – |
| T12 | 1 | R | found | yes | – | 2,421 | 5 | 0.146 | – |
| T12 | 2 | G | found | yes | – | 933 | 1 | 0.215 | – |
| T12 | 2 | R | found | yes | – | 2,421 | 5 | 0.162 | – |
| T12 | 3 | G | found | yes | – | 933 | 1 | 0.233 | – |
| T12 | 3 | R | found | yes | – | 2,302 | 4 | 0.159 | – |
| T16 | 1 | G | found | yes | – | 4,091 | 5 | 1.194 | – |
| T16 | 1 | R | found | yes | – | 3,459 | 9 | 0.492 | – |
| T16 | 2 | G | found | yes | – | 4,082 | 5 | 1.15 | – |
| T16 | 2 | R | found | yes | – | 3,390 | 9 | 0.544 | – |
| T16 | 3 | G | found | yes | – | 4,082 | 5 | 1.174 | – |
| T16 | 3 | R | found | yes | – | 3,447 | 9 | 0.598 | – |
| T19 | 1 | G | found | yes | – | 1,454 | 5 | 0.162 | fallback: find returned nothing |
| T19 | 1 | R | found | yes | – | 1,199 | 4 | 0.136 | – |
| T19 | 2 | G | found | yes | – | 1,454 | 5 | 0.173 | fallback: find returned nothing |
| T19 | 2 | R | found | yes | – | 1,199 | 4 | 0.138 | – |
| T19 | 3 | G | found | yes | – | 1,454 | 5 | 0.204 | fallback: find returned nothing |
| T19 | 3 | R | found | yes | – | 1,199 | 4 | 0.191 | – |
| T20 | 1 | G | found | yes | – | 2,748 | 3 | 0.265 | – |
| T20 | 1 | R | found | yes | – | 2,109 | 4 | 0.135 | – |
| T20 | 2 | G | found | yes | – | 2,826 | 3 | 0.318 | – |
| T20 | 2 | R | found | yes | – | 2,187 | 4 | 0.157 | – |
| T20 | 3 | G | found | yes | – | 2,753 | 3 | 0.321 | – |
| T20 | 3 | R | found | yes | – | 2,114 | 4 | 0.162 | – |
| T21 | 1 | G | unknown | yes | – | 2,854 | 6 | 0.153 | fallback: the index reports incomplete sources |
| T21 | 1 | R | unknown | yes | – | 2,585 | 5 | 0.132 | – |
| T21 | 2 | G | unknown | yes | – | 2,855 | 6 | 0.195 | fallback: the index reports incomplete sources |
| T21 | 2 | R | unknown | yes | – | 2,586 | 5 | 0.155 | – |
| T21 | 3 | G | unknown | yes | – | 2,685 | 6 | 0.192 | fallback: the index reports incomplete sources |
| T21 | 3 | R | unknown | yes | – | 2,416 | 5 | 0.187 | – |
| T22 | 1 | G | not_found | yes | – | 2,083 | 4 | 0.13 | fallback: find returned nothing |
| T22 | 1 | R | not_found | yes | – | 1,828 | 3 | 0.105 | – |
| T22 | 2 | G | not_found | yes | – | 2,587 | 4 | 0.127 | fallback: find returned nothing |
| T22 | 2 | R | not_found | yes | – | 2,332 | 3 | 0.106 | – |
| T22 | 3 | G | not_found | yes | – | 2,878 | 4 | 0.173 | fallback: find returned nothing |
| T22 | 3 | R | not_found | yes | – | 2,623 | 3 | 0.134 | – |
| T23 | 1 | G | found | yes | – | 770 | 1 | 0.21 | – |
| T23 | 1 | R | found | yes | – | 1,813 | 3 | 0.118 | – |
| T23 | 2 | G | found | yes | – | 770 | 1 | 0.214 | – |
| T23 | 2 | R | found | yes | – | 1,813 | 3 | 0.124 | – |
| T23 | 3 | G | found | yes | – | 770 | 1 | 0.25 | – |
| T23 | 3 | R | found | yes | – | 1,813 | 3 | 0.161 | – |
| T25 | 1 | G | found | yes | – | 2,017 | 3 | 0.363 | drift after command 1 |
| T25 | 1 | R | found | yes | – | 1,627 | 6 | 0.186 | drift after command 5 |
| T25 | 2 | G | found | yes | – | 2,017 | 3 | 0.351 | drift after command 1 |
| T25 | 2 | R | found | yes | – | 1,627 | 6 | 0.183 | drift after command 5 |
| T25 | 3 | G | found | yes | – | 2,017 | 3 | 0.426 | drift after command 1 |
| T25 | 3 | R | found | yes | – | 1,506 | 5 | 0.212 | drift after command 4 |

## Measurement

- Bytes read are every byte of standard output and standard error of every command a policy ran. The question itself is not counted. A pipeline counts what it prints, not what its stages pass between them. `rg`, `git` and `gleaner` read more than they print, so what they scan is not counted.
- The worlds live deep in the repository, so every absolute path carries a long prefix. The second count writes the home folder's path, and its spelling in Claude Code's log folder names, as `~`, so where a world was written weighs nothing. Both projections already write the home folder as `~`. The log folder names in `rg` listings and in `gleaner` evidence keep the long spelling.
- Commands are the requests a policy made; processes are the tools those requests started, so a pipeline counts each tool in it. Refused and timed-out commands count as commands, with what they printed.
- G falls back to R, counted in full, when find reports incomplete sources or returns nothing.
- Wall time includes starting each command under `sandbox-exec`, about 7 ms a command on this machine, and the policy itself. G's time with preparation adds its world's indexing time.
- The earlier synthetic comparison (4,885 catalog bytes against 5,967 for targeted section reads) is motivation only; its definitions were not supplied, so its numbers are not comparable with these.

## Runs

The results kept under `eval/results/`, newest first:

| Results | Created | Seeds | Commit | Episodes |
|---|---|---|---|---|
| `eval/results/2026-10-18/dev/results.json` | 2026-10-18T01:34:59+00:00 | Seeds 1–3 | ba428b1 | 90 |
| `eval/results/2026-10-18/dev-d8e43d4/results.json` | 2026-10-18T00:40:25+00:00 | Seeds 1–3 | d8e43d4 | 90 |
