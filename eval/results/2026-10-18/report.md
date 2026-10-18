# Evaluation E0: results

Seeds 101–110; 15 tasks; policies R, G. Run 2026-10-18T01:56:56+00:00 on macOS 27.0.1 (arm64) at commit 7611cf5, with ripgrep 15.1.0, jq-1.7.1-apple, git version 2.50.1 (Apple Git-155) and Python 3.14.2.

These are the scored seeds. The raw recipe was locked on development seeds 1, 2, 3 at commit ba428b1 (2026-10-18T01:41:42+00:00), recorded in `eval/lock.json` with the sha256 of every `eval/*.py`. The run checked that those files still had those hashes and that the tree was clean. The development run that locked it is `eval/results/2026-10-18/dev/results.json`.

How it was made: [docs/design/evaluation-e0.md](../../../docs/design/evaluation-e0.md) and [eval/README.md](../../README.md). Every episode, with its commands and answer, is in `results.json`.

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
| R | 150 of 150 | 0 | 0 | 368,477 | 307,394 | 827 | 1531 | 0 | 0 | 31.204 | 31.204 |
| G | 150 of 150 | 0 | 40 | 328,426 | 270,709 | 423 | 747 | 0 | 0 | 48.951 | 115.354 |

Bytes read, G over R: **0.891** overall; B (fallback) 1.072; E (shared information) 0.751; S (recorded state) 1.181.

With the home folder's path counted as ~, G over R: **0.881** overall; B (fallback) 1.082; E (shared information) 0.739; S (recorded state) 1.172.

R reported 25 projected fields clipped at 240 characters; G 0 in its raw reads, and 0 gleaner answers marked truncated. Episodes that could not run: R 0, G 0.

## Preparation

Charged to G: 150 of 150 worlds prepared, 170 index runs, 66.403 s of indexing, 66,570,424 library bytes on disk (443,802 per world), 1211 saved copies. Failed preparation attempts: 0. R prepares nothing.

Per world, G's preparation took 0.443 s on average. Its episodes took 0.3263 s against R's 0.208 s, so G is 0.1183 s a query slower and **preparation never repays itself in wall time**. G read 267.0 fewer bytes a query than R. Bytes have no preparation counterpart: the index reads every log, but no policy reads what it read.

| Queries a world | R seconds | G seconds, preparation included |
|---|---|---|
| 1 | 0.208 | 0.769 |
| 10 | 2.08 | 3.706 |
| 100 | 20.803 | 33.077 |
| 1000 | 208.027 | 326.783 |

These counts are a sensitivity range, not observed workloads.

## By family

| Family | Policy | Correct | Hard failures | Fallbacks | Bytes read | Bytes, home as ~ | Commands | Processes | Wall time (s) | With preparation (s) |
|---|---|---|---|---|---|---|---|---|---|---|
| B (fallback) | R | 60 of 60 | 0 | 0 | 114,127 | 88,189 | 247 | 387 | 9.062 | 9.062 |
| B (fallback) | G | 60 of 60 | 0 | 30 | 122,392 | 95,464 | 222 | 332 | 13.695 | 35.328 |
| E (shared information) | R | 80 of 80 | 0 | 0 | 219,675 | 188,490 | 488 | 972 | 16.601 | 16.601 |
| E (shared information) | G | 80 of 80 | 0 | 10 | 165,078 | 139,239 | 151 | 325 | 23.726 | 64.835 |
| S (recorded state) | R | 10 of 10 | 0 | 0 | 34,675 | 30,715 | 92 | 172 | 5.541 | 5.541 |
| S (recorded state) | G | 10 of 10 | 0 | 0 | 40,956 | 36,006 | 50 | 90 | 11.53 | 15.191 |

## By task

| Task | Asks | R correct | R bytes | R commands | G correct | G bytes | G commands | G/R bytes |
|---|---|---|---|---|---|---|---|---|
| T01 | value | 10 of 10 | 1,936 | 5.1 | 10 of 10 | 1,845 | 2.0 | 0.953 |
| T02 | value | 10 of 10 | 3,421 | 6.8 | 10 of 10 | 1,947 | 2.0 | 0.569 |
| T03 | files | 10 of 10 | 2,782 | 3.1 | 10 of 10 | 2,992 | 1.0 | 1.075 |
| T04 | delivery | 10 of 10 | 2,983 | 4.1 | 10 of 10 | 3,238 | 5.1 | 1.085 |
| T07 | same_item | 10 of 10 | 3,124 | 9.3 | 10 of 10 | 2,280 | 1.0 | 0.73 |
| T09 | current_match | 10 of 10 | 4,025 | 9.3 | 10 of 10 | 2,351 | 2.0 | 0.584 |
| T10 | provenance | 10 of 10 | 1,375 | 7.0 | 10 of 10 | 919 | 1.0 | 0.668 |
| T12 | delivery | 10 of 10 | 2,317 | 4.1 | 10 of 10 | 935 | 1.0 | 0.403 |
| T16 | recover | 10 of 10 | 3,467 | 9.2 | 10 of 10 | 4,095 | 5.0 | 1.181 |
| T19 | delivery | 10 of 10 | 1,227 | 4.2 | 10 of 10 | 1,482 | 5.2 | 1.208 |
| T20 | handed_over | 10 of 10 | 2,168 | 4.2 | 10 of 10 | 2,784 | 3.0 | 1.284 |
| T21 | decision | 10 of 10 | 2,496 | 5.0 | 10 of 10 | 2,765 | 6.0 | 1.108 |
| T22 | referenced | 10 of 10 | 2,157 | 3.0 | 10 of 10 | 2,412 | 4.0 | 1.118 |
| T23 | verify | 10 of 10 | 1,815 | 3.0 | 10 of 10 | 772 | 1.0 | 0.425 |
| T25 | bytes | 10 of 10 | 1,547 | 5.3 | 10 of 10 | 2,023 | 3.0 | 1.307 |

Bytes and commands per task are means per episode.

## Hard failures

None in 300 episodes. Each was checked for the four general classes (`false_global_absence`, `current_as_delivered`, `hash_merge`, `tool_only_as_delivery`) and for the task-specific ones its gold lists. Zero observed failures in this many synthetic episodes does not establish a failure rate.

## Worlds

A world has 8.0 session logs on average, sub-agent transcripts left out: 3.4 decoys about other things and 1.4 near misses that each hold exactly one query word. A query word is in 2.8 logs on average; every word is in 1.2. The per-world counts are in `results.json` (`worlds[].distractors`).

After its episodes, each world was checked against its gold (check_worlds.check): 150 of 150 hold what their gold presumes. For scored worlds only pass or fail is kept.

## Every episode

| Task | Seed | Policy | Status | Correct | Hard failures | Bytes | Commands | Seconds | Notes |
|---|---|---|---|---|---|---|---|---|---|
| T01 | 101 | G | found | yes | – | 1,845 | 2 | 0.486 | – |
| T01 | 101 | R | found | yes | – | 1,925 | 5 | 0.201 | – |
| T01 | 102 | G | found | yes | – | 1,845 | 2 | 0.331 | – |
| T01 | 102 | R | found | yes | – | 1,925 | 5 | 0.199 | – |
| T01 | 103 | G | found | yes | – | 1,845 | 2 | 0.351 | – |
| T01 | 103 | R | found | yes | – | 1,925 | 5 | 0.171 | – |
| T01 | 104 | G | found | yes | – | 1,845 | 2 | 0.325 | – |
| T01 | 104 | R | found | yes | – | 2,042 | 6 | 0.219 | – |
| T01 | 105 | G | found | yes | – | 1,845 | 2 | 0.341 | – |
| T01 | 105 | R | found | yes | – | 1,925 | 5 | 0.176 | – |
| T01 | 106 | G | found | yes | – | 1,845 | 2 | 0.331 | – |
| T01 | 106 | R | found | yes | – | 1,925 | 5 | 0.199 | – |
| T01 | 107 | G | found | yes | – | 1,845 | 2 | 0.359 | – |
| T01 | 107 | R | found | yes | – | 1,925 | 5 | 0.173 | – |
| T01 | 108 | G | found | yes | – | 1,845 | 2 | 0.334 | – |
| T01 | 108 | R | found | yes | – | 1,925 | 5 | 0.199 | – |
| T01 | 109 | G | found | yes | – | 1,845 | 2 | 0.373 | – |
| T01 | 109 | R | found | yes | – | 1,925 | 5 | 0.223 | – |
| T01 | 110 | G | found | yes | – | 1,845 | 2 | 0.332 | – |
| T01 | 110 | R | found | yes | – | 1,925 | 5 | 0.2 | – |
| T02 | 101 | G | found | yes | – | 1,947 | 2 | 0.336 | – |
| T02 | 101 | R | found | yes | – | 4,100 | 7 | 0.216 | – |
| T02 | 102 | G | found | yes | – | 1,947 | 2 | 0.371 | – |
| T02 | 102 | R | found | yes | – | 4,100 | 7 | 0.21 | – |
| T02 | 103 | G | found | yes | – | 1,947 | 2 | 0.333 | – |
| T02 | 103 | R | found | yes | – | 2,888 | 6 | 0.208 | – |
| T02 | 104 | G | found | yes | – | 1,947 | 2 | 0.359 | – |
| T02 | 104 | R | found | yes | – | 2,888 | 6 | 0.195 | – |
| T02 | 105 | G | found | yes | – | 1,947 | 2 | 0.34 | – |
| T02 | 105 | R | found | yes | – | 3,013 | 7 | 0.227 | – |
| T02 | 106 | G | found | yes | – | 1,947 | 2 | 0.351 | – |
| T02 | 106 | R | found | yes | – | 4,100 | 7 | 0.204 | – |
| T02 | 107 | G | found | yes | – | 1,947 | 2 | 0.347 | – |
| T02 | 107 | R | found | yes | – | 4,218 | 8 | 0.241 | – |
| T02 | 108 | G | found | yes | – | 1,947 | 2 | 0.356 | – |
| T02 | 108 | R | found | yes | – | 3,006 | 7 | 0.209 | – |
| T02 | 109 | G | found | yes | – | 1,947 | 2 | 0.373 | – |
| T02 | 109 | R | found | yes | – | 2,888 | 6 | 0.218 | – |
| T02 | 110 | G | found | yes | – | 1,947 | 2 | 0.347 | – |
| T02 | 110 | R | found | yes | – | 3,013 | 7 | 0.208 | – |
| T03 | 101 | G | found | yes | – | 2,992 | 1 | 0.334 | – |
| T03 | 101 | R | found | yes | – | 2,771 | 3 | 0.111 | – |
| T03 | 102 | G | found | yes | – | 2,992 | 1 | 0.335 | – |
| T03 | 102 | R | found | yes | – | 2,771 | 3 | 0.135 | – |
| T03 | 103 | G | found | yes | – | 2,992 | 1 | 0.326 | – |
| T03 | 103 | R | found | yes | – | 2,771 | 3 | 0.122 | – |
| T03 | 104 | G | found | yes | – | 2,992 | 1 | 0.327 | – |
| T03 | 104 | R | found | yes | – | 2,771 | 3 | 0.117 | – |
| T03 | 105 | G | found | yes | – | 2,992 | 1 | 0.325 | – |
| T03 | 105 | R | found | yes | – | 2,771 | 3 | 0.119 | – |
| T03 | 106 | G | found | yes | – | 2,992 | 1 | 0.341 | – |
| T03 | 106 | R | found | yes | – | 2,771 | 3 | 0.123 | – |
| T03 | 107 | G | found | yes | – | 2,992 | 1 | 0.349 | – |
| T03 | 107 | R | found | yes | – | 2,771 | 3 | 0.122 | – |
| T03 | 108 | G | found | yes | – | 2,992 | 1 | 0.338 | – |
| T03 | 108 | R | found | yes | – | 2,771 | 3 | 0.122 | – |
| T03 | 109 | G | found | yes | – | 2,992 | 1 | 0.33 | – |
| T03 | 109 | R | found | yes | – | 2,889 | 4 | 0.15 | – |
| T03 | 110 | G | found | yes | – | 2,992 | 1 | 0.33 | – |
| T03 | 110 | R | found | yes | – | 2,771 | 3 | 0.123 | – |
| T04 | 101 | G | not_found | yes | – | 3,063 | 6 | 0.19 | fallback: find returned nothing |
| T04 | 101 | R | not_found | yes | – | 2,808 | 5 | 0.173 | – |
| T04 | 102 | G | not_found | yes | – | 3,122 | 5 | 0.189 | fallback: find returned nothing |
| T04 | 102 | R | not_found | yes | – | 2,867 | 4 | 0.143 | – |
| T04 | 103 | G | not_found | yes | – | 3,292 | 5 | 0.172 | fallback: find returned nothing |
| T04 | 103 | R | not_found | yes | – | 3,037 | 4 | 0.148 | – |
| T04 | 104 | G | not_found | yes | – | 3,363 | 5 | 0.174 | fallback: find returned nothing |
| T04 | 104 | R | not_found | yes | – | 3,108 | 4 | 0.144 | – |
| T04 | 105 | G | not_found | yes | – | 3,263 | 5 | 0.167 | fallback: find returned nothing |
| T04 | 105 | R | not_found | yes | – | 3,008 | 4 | 0.149 | – |
| T04 | 106 | G | not_found | yes | – | 3,254 | 5 | 0.177 | fallback: find returned nothing |
| T04 | 106 | R | not_found | yes | – | 2,999 | 4 | 0.146 | – |
| T04 | 107 | G | not_found | yes | – | 3,114 | 5 | 0.172 | fallback: find returned nothing |
| T04 | 107 | R | not_found | yes | – | 2,859 | 4 | 0.149 | – |
| T04 | 108 | G | not_found | yes | – | 3,529 | 5 | 0.185 | fallback: find returned nothing |
| T04 | 108 | R | not_found | yes | – | 3,274 | 4 | 0.14 | – |
| T04 | 109 | G | not_found | yes | – | 3,269 | 5 | 0.172 | fallback: find returned nothing |
| T04 | 109 | R | not_found | yes | – | 3,014 | 4 | 0.149 | – |
| T04 | 110 | G | not_found | yes | – | 3,119 | 5 | 0.172 | fallback: find returned nothing |
| T04 | 110 | R | not_found | yes | – | 2,864 | 4 | 0.148 | – |
| T07 | 101 | G | found | yes | – | 2,280 | 1 | 0.396 | – |
| T07 | 101 | R | found | yes | – | 3,089 | 9 | 0.251 | – |
| T07 | 102 | G | found | yes | – | 2,280 | 1 | 0.378 | – |
| T07 | 102 | R | found | yes | – | 3,089 | 9 | 0.283 | – |
| T07 | 103 | G | found | yes | – | 2,280 | 1 | 0.386 | – |
| T07 | 103 | R | found | yes | – | 3,209 | 10 | 0.295 | – |
| T07 | 104 | G | found | yes | – | 2,280 | 1 | 0.382 | – |
| T07 | 104 | R | found | yes | – | 3,089 | 9 | 0.27 | – |
| T07 | 105 | G | found | yes | – | 2,280 | 1 | 0.383 | – |
| T07 | 105 | R | found | yes | – | 3,089 | 9 | 0.271 | – |
| T07 | 106 | G | found | yes | – | 2,280 | 1 | 0.412 | – |
| T07 | 106 | R | found | yes | – | 3,089 | 9 | 0.427 | – |
| T07 | 107 | G | found | yes | – | 2,280 | 1 | 0.401 | – |
| T07 | 107 | R | found | yes | – | 3,207 | 10 | 0.298 | – |
| T07 | 108 | G | found | yes | – | 2,280 | 1 | 0.386 | – |
| T07 | 108 | R | found | yes | – | 3,207 | 10 | 0.293 | – |
| T07 | 109 | G | found | yes | – | 2,280 | 1 | 0.384 | – |
| T07 | 109 | R | found | yes | – | 3,089 | 9 | 0.276 | – |
| T07 | 110 | G | found | yes | – | 2,280 | 1 | 0.383 | – |
| T07 | 110 | R | found | yes | – | 3,089 | 9 | 0.258 | – |
| T09 | 101 | G | found | yes | – | 2,351 | 2 | 0.317 | – |
| T09 | 101 | R | found | yes | – | 3,988 | 9 | 0.27 | – |
| T09 | 102 | G | found | yes | – | 2,351 | 2 | 0.345 | – |
| T09 | 102 | R | found | yes | – | 3,992 | 9 | 0.256 | – |
| T09 | 103 | G | found | yes | – | 2,351 | 2 | 0.328 | – |
| T09 | 103 | R | found | yes | – | 4,105 | 10 | 0.301 | – |
| T09 | 104 | G | found | yes | – | 2,351 | 2 | 0.36 | – |
| T09 | 104 | R | found | yes | – | 3,992 | 9 | 0.255 | – |
| T09 | 105 | G | found | yes | – | 2,351 | 2 | 0.338 | – |
| T09 | 105 | R | found | yes | – | 3,988 | 9 | 0.299 | – |
| T09 | 106 | G | found | yes | – | 2,351 | 2 | 0.363 | – |
| T09 | 106 | R | found | yes | – | 3,992 | 9 | 0.259 | – |
| T09 | 107 | G | found | yes | – | 2,351 | 2 | 0.342 | – |
| T09 | 107 | R | found | yes | – | 4,112 | 10 | 0.316 | – |
| T09 | 108 | G | found | yes | – | 2,351 | 2 | 0.358 | – |
| T09 | 108 | R | found | yes | – | 3,988 | 9 | 0.246 | – |
| T09 | 109 | G | found | yes | – | 2,351 | 2 | 0.338 | – |
| T09 | 109 | R | found | yes | – | 4,108 | 10 | 0.306 | – |
| T09 | 110 | G | found | yes | – | 2,351 | 2 | 0.362 | – |
| T09 | 110 | R | found | yes | – | 3,988 | 9 | 0.259 | – |
| T10 | 101 | G | found | yes | – | 919 | 1 | 0.234 | – |
| T10 | 101 | R | found | yes | – | 1,375 | 7 | 0.211 | – |
| T10 | 102 | G | found | yes | – | 919 | 1 | 0.167 | – |
| T10 | 102 | R | found | yes | – | 1,375 | 7 | 0.334 | – |
| T10 | 103 | G | found | yes | – | 919 | 1 | 0.219 | – |
| T10 | 103 | R | found | yes | – | 1,375 | 7 | 0.215 | – |
| T10 | 104 | G | found | yes | – | 919 | 1 | 0.161 | – |
| T10 | 104 | R | found | yes | – | 1,375 | 7 | 0.284 | – |
| T10 | 105 | G | found | yes | – | 919 | 1 | 0.221 | – |
| T10 | 105 | R | found | yes | – | 1,375 | 7 | 0.227 | – |
| T10 | 106 | G | found | yes | – | 919 | 1 | 0.176 | – |
| T10 | 106 | R | found | yes | – | 1,375 | 7 | 0.285 | – |
| T10 | 107 | G | found | yes | – | 919 | 1 | 0.234 | – |
| T10 | 107 | R | found | yes | – | 1,375 | 7 | 0.22 | – |
| T10 | 108 | G | found | yes | – | 919 | 1 | 0.166 | – |
| T10 | 108 | R | found | yes | – | 1,375 | 7 | 0.265 | – |
| T10 | 109 | G | found | yes | – | 919 | 1 | 0.242 | – |
| T10 | 109 | R | found | yes | – | 1,375 | 7 | 0.233 | – |
| T10 | 110 | G | found | yes | – | 919 | 1 | 0.164 | – |
| T10 | 110 | R | found | yes | – | 1,375 | 7 | 0.274 | – |
| T12 | 101 | G | found | yes | – | 935 | 1 | 0.222 | – |
| T12 | 101 | R | found | yes | – | 2,306 | 4 | 0.157 | – |
| T12 | 102 | G | found | yes | – | 935 | 1 | 0.236 | – |
| T12 | 102 | R | found | yes | – | 2,306 | 4 | 0.149 | – |
| T12 | 103 | G | found | yes | – | 935 | 1 | 0.22 | – |
| T12 | 103 | R | found | yes | – | 2,425 | 5 | 0.169 | – |
| T12 | 104 | G | found | yes | – | 935 | 1 | 0.218 | – |
| T12 | 104 | R | found | yes | – | 2,306 | 4 | 0.152 | – |
| T12 | 105 | G | found | yes | – | 935 | 1 | 0.216 | – |
| T12 | 105 | R | found | yes | – | 2,306 | 4 | 0.15 | – |
| T12 | 106 | G | found | yes | – | 935 | 1 | 0.227 | – |
| T12 | 106 | R | found | yes | – | 2,306 | 4 | 0.162 | – |
| T12 | 107 | G | found | yes | – | 935 | 1 | 0.225 | – |
| T12 | 107 | R | found | yes | – | 2,306 | 4 | 0.151 | – |
| T12 | 108 | G | found | yes | – | 935 | 1 | 0.216 | – |
| T12 | 108 | R | found | yes | – | 2,306 | 4 | 0.137 | – |
| T12 | 109 | G | found | yes | – | 935 | 1 | 0.222 | – |
| T12 | 109 | R | found | yes | – | 2,306 | 4 | 0.156 | – |
| T12 | 110 | G | found | yes | – | 935 | 1 | 0.217 | – |
| T12 | 110 | R | found | yes | – | 2,306 | 4 | 0.152 | – |
| T16 | 101 | G | found | yes | – | 4,092 | 5 | 1.159 | – |
| T16 | 101 | R | found | yes | – | 3,461 | 9 | 0.548 | – |
| T16 | 102 | G | found | yes | – | 4,092 | 5 | 1.103 | – |
| T16 | 102 | R | found | yes | – | 3,459 | 9 | 0.582 | – |
| T16 | 103 | G | found | yes | – | 4,092 | 5 | 1.162 | – |
| T16 | 103 | R | found | yes | – | 3,404 | 9 | 0.534 | – |
| T16 | 104 | G | found | yes | – | 4,101 | 5 | 1.124 | – |
| T16 | 104 | R | found | yes | – | 3,567 | 10 | 0.59 | – |
| T16 | 105 | G | found | yes | – | 4,101 | 5 | 1.196 | – |
| T16 | 105 | R | found | yes | – | 3,472 | 9 | 0.52 | – |
| T16 | 106 | G | found | yes | – | 4,092 | 5 | 1.158 | – |
| T16 | 106 | R | found | yes | – | 3,440 | 9 | 0.564 | – |
| T16 | 107 | G | found | yes | – | 4,092 | 5 | 1.216 | – |
| T16 | 107 | R | found | yes | – | 3,461 | 9 | 0.525 | – |
| T16 | 108 | G | found | yes | – | 4,092 | 5 | 1.136 | – |
| T16 | 108 | R | found | yes | – | 3,419 | 9 | 0.548 | – |
| T16 | 109 | G | found | yes | – | 4,101 | 5 | 1.15 | – |
| T16 | 109 | R | found | yes | – | 3,589 | 10 | 0.553 | – |
| T16 | 110 | G | found | yes | – | 4,101 | 5 | 1.126 | – |
| T16 | 110 | R | found | yes | – | 3,403 | 9 | 0.577 | – |
| T19 | 101 | G | found | yes | – | 1,579 | 6 | 0.202 | fallback: find returned nothing |
| T19 | 101 | R | found | yes | – | 1,324 | 5 | 0.189 | – |
| T19 | 102 | G | found | yes | – | 1,458 | 5 | 0.181 | fallback: find returned nothing |
| T19 | 102 | R | found | yes | – | 1,203 | 4 | 0.15 | – |
| T19 | 103 | G | found | yes | – | 1,458 | 5 | 0.176 | fallback: find returned nothing |
| T19 | 103 | R | found | yes | – | 1,203 | 4 | 0.155 | – |
| T19 | 104 | G | found | yes | – | 1,458 | 5 | 0.176 | fallback: find returned nothing |
| T19 | 104 | R | found | yes | – | 1,203 | 4 | 0.148 | – |
| T19 | 105 | G | found | yes | – | 1,458 | 5 | 0.174 | fallback: find returned nothing |
| T19 | 105 | R | found | yes | – | 1,203 | 4 | 0.153 | – |
| T19 | 106 | G | found | yes | – | 1,458 | 5 | 0.183 | fallback: find returned nothing |
| T19 | 106 | R | found | yes | – | 1,203 | 4 | 0.15 | – |
| T19 | 107 | G | found | yes | – | 1,458 | 5 | 0.173 | fallback: find returned nothing |
| T19 | 107 | R | found | yes | – | 1,203 | 4 | 0.146 | – |
| T19 | 108 | G | found | yes | – | 1,458 | 5 | 0.175 | fallback: find returned nothing |
| T19 | 108 | R | found | yes | – | 1,203 | 4 | 0.154 | – |
| T19 | 109 | G | found | yes | – | 1,579 | 6 | 0.2 | fallback: find returned nothing |
| T19 | 109 | R | found | yes | – | 1,324 | 5 | 0.175 | – |
| T19 | 110 | G | found | yes | – | 1,458 | 5 | 0.177 | fallback: find returned nothing |
| T19 | 110 | R | found | yes | – | 1,203 | 4 | 0.15 | – |
| T20 | 101 | G | found | yes | – | 2,758 | 3 | 0.284 | – |
| T20 | 101 | R | found | yes | – | 2,119 | 4 | 0.148 | – |
| T20 | 102 | G | found | yes | – | 2,826 | 3 | 0.272 | – |
| T20 | 102 | R | found | yes | – | 2,187 | 4 | 0.156 | – |
| T20 | 103 | G | found | yes | – | 2,736 | 3 | 0.277 | – |
| T20 | 103 | R | found | yes | – | 2,097 | 4 | 0.147 | – |
| T20 | 104 | G | found | yes | – | 2,756 | 3 | 0.267 | – |
| T20 | 104 | R | found | yes | – | 2,117 | 4 | 0.156 | – |
| T20 | 105 | G | found | yes | – | 2,800 | 3 | 0.272 | – |
| T20 | 105 | R | found | yes | – | 2,280 | 5 | 0.171 | – |
| T20 | 106 | G | found | yes | – | 2,832 | 3 | 0.275 | – |
| T20 | 106 | R | found | yes | – | 2,193 | 4 | 0.15 | – |
| T20 | 107 | G | found | yes | – | 2,814 | 3 | 0.276 | – |
| T20 | 107 | R | found | yes | – | 2,294 | 5 | 0.166 | – |
| T20 | 108 | G | found | yes | – | 2,791 | 3 | 0.275 | – |
| T20 | 108 | R | found | yes | – | 2,152 | 4 | 0.147 | – |
| T20 | 109 | G | found | yes | – | 2,779 | 3 | 0.272 | – |
| T20 | 109 | R | found | yes | – | 2,140 | 4 | 0.152 | – |
| T20 | 110 | G | found | yes | – | 2,748 | 3 | 0.269 | – |
| T20 | 110 | R | found | yes | – | 2,109 | 4 | 0.156 | – |
| T21 | 101 | G | unknown | yes | – | 2,868 | 6 | 0.172 | fallback: the index reports incomplete sources |
| T21 | 101 | R | unknown | yes | – | 2,599 | 5 | 0.161 | – |
| T21 | 102 | G | unknown | yes | – | 2,868 | 6 | 0.175 | fallback: the index reports incomplete sources |
| T21 | 102 | R | unknown | yes | – | 2,599 | 5 | 0.148 | – |
| T21 | 103 | G | unknown | yes | – | 2,868 | 6 | 0.172 | fallback: the index reports incomplete sources |
| T21 | 103 | R | unknown | yes | – | 2,599 | 5 | 0.149 | – |
| T21 | 104 | G | unknown | yes | – | 2,696 | 6 | 0.171 | fallback: the index reports incomplete sources |
| T21 | 104 | R | unknown | yes | – | 2,427 | 5 | 0.142 | – |
| T21 | 105 | G | unknown | yes | – | 2,696 | 6 | 0.168 | fallback: the index reports incomplete sources |
| T21 | 105 | R | unknown | yes | – | 2,427 | 5 | 0.15 | – |
| T21 | 106 | G | unknown | yes | – | 2,696 | 6 | 0.177 | fallback: the index reports incomplete sources |
| T21 | 106 | R | unknown | yes | – | 2,427 | 5 | 0.148 | – |
| T21 | 107 | G | unknown | yes | – | 2,697 | 6 | 0.164 | fallback: the index reports incomplete sources |
| T21 | 107 | R | unknown | yes | – | 2,428 | 5 | 0.141 | – |
| T21 | 108 | G | unknown | yes | – | 2,697 | 6 | 0.173 | fallback: the index reports incomplete sources |
| T21 | 108 | R | unknown | yes | – | 2,428 | 5 | 0.145 | – |
| T21 | 109 | G | unknown | yes | – | 2,697 | 6 | 0.175 | fallback: the index reports incomplete sources |
| T21 | 109 | R | unknown | yes | – | 2,428 | 5 | 0.145 | – |
| T21 | 110 | G | unknown | yes | – | 2,870 | 6 | 0.173 | fallback: the index reports incomplete sources |
| T21 | 110 | R | unknown | yes | – | 2,601 | 5 | 0.145 | – |
| T22 | 101 | G | not_found | yes | – | 2,325 | 4 | 0.156 | fallback: find returned nothing |
| T22 | 101 | R | not_found | yes | – | 2,070 | 3 | 0.118 | – |
| T22 | 102 | G | not_found | yes | – | 2,985 | 4 | 0.149 | fallback: find returned nothing |
| T22 | 102 | R | not_found | yes | – | 2,730 | 3 | 0.122 | – |
| T22 | 103 | G | not_found | yes | – | 2,032 | 4 | 0.147 | fallback: find returned nothing |
| T22 | 103 | R | not_found | yes | – | 1,777 | 3 | 0.117 | – |
| T22 | 104 | G | not_found | yes | – | 2,327 | 4 | 0.15 | fallback: find returned nothing |
| T22 | 104 | R | not_found | yes | – | 2,072 | 3 | 0.126 | – |
| T22 | 105 | G | not_found | yes | – | 2,033 | 4 | 0.151 | fallback: find returned nothing |
| T22 | 105 | R | not_found | yes | – | 1,778 | 3 | 0.117 | – |
| T22 | 106 | G | not_found | yes | – | 2,617 | 4 | 0.147 | fallback: find returned nothing |
| T22 | 106 | R | not_found | yes | – | 2,362 | 3 | 0.119 | – |
| T22 | 107 | G | not_found | yes | – | 2,323 | 4 | 0.162 | fallback: find returned nothing |
| T22 | 107 | R | not_found | yes | – | 2,068 | 3 | 0.118 | – |
| T22 | 108 | G | not_found | yes | – | 2,397 | 4 | 0.143 | fallback: find returned nothing |
| T22 | 108 | R | not_found | yes | – | 2,142 | 3 | 0.123 | – |
| T22 | 109 | G | not_found | yes | – | 2,691 | 4 | 0.148 | fallback: find returned nothing |
| T22 | 109 | R | not_found | yes | – | 2,436 | 3 | 0.119 | – |
| T22 | 110 | G | not_found | yes | – | 2,397 | 4 | 0.147 | fallback: find returned nothing |
| T22 | 110 | R | not_found | yes | – | 2,142 | 3 | 0.117 | – |
| T23 | 101 | G | found | yes | – | 772 | 1 | 0.224 | – |
| T23 | 101 | R | found | yes | – | 1,815 | 3 | 0.132 | – |
| T23 | 102 | G | found | yes | – | 772 | 1 | 0.217 | – |
| T23 | 102 | R | found | yes | – | 1,815 | 3 | 0.132 | – |
| T23 | 103 | G | found | yes | – | 772 | 1 | 0.218 | – |
| T23 | 103 | R | found | yes | – | 1,815 | 3 | 0.134 | – |
| T23 | 104 | G | found | yes | – | 772 | 1 | 0.225 | – |
| T23 | 104 | R | found | yes | – | 1,815 | 3 | 0.134 | – |
| T23 | 105 | G | found | yes | – | 772 | 1 | 0.216 | – |
| T23 | 105 | R | found | yes | – | 1,815 | 3 | 0.133 | – |
| T23 | 106 | G | found | yes | – | 772 | 1 | 0.221 | – |
| T23 | 106 | R | found | yes | – | 1,815 | 3 | 0.134 | – |
| T23 | 107 | G | found | yes | – | 772 | 1 | 0.22 | – |
| T23 | 107 | R | found | yes | – | 1,815 | 3 | 0.125 | – |
| T23 | 108 | G | found | yes | – | 772 | 1 | 0.243 | – |
| T23 | 108 | R | found | yes | – | 1,815 | 3 | 0.138 | – |
| T23 | 109 | G | found | yes | – | 772 | 1 | 0.222 | – |
| T23 | 109 | R | found | yes | – | 1,815 | 3 | 0.134 | – |
| T23 | 110 | G | found | yes | – | 772 | 1 | 0.226 | – |
| T23 | 110 | R | found | yes | – | 1,815 | 3 | 0.147 | – |
| T25 | 101 | G | found | yes | – | 2,023 | 3 | 0.375 | drift after command 1 |
| T25 | 101 | R | found | yes | – | 1,512 | 5 | 0.182 | drift after command 4 |
| T25 | 102 | G | found | yes | – | 2,023 | 3 | 0.362 | drift after command 1 |
| T25 | 102 | R | found | yes | – | 1,512 | 5 | 0.184 | drift after command 4 |
| T25 | 103 | G | found | yes | – | 2,023 | 3 | 0.37 | drift after command 1 |
| T25 | 103 | R | found | yes | – | 1,512 | 5 | 0.182 | drift after command 4 |
| T25 | 104 | G | found | yes | – | 2,023 | 3 | 0.363 | drift after command 1 |
| T25 | 104 | R | found | yes | – | 1,512 | 5 | 0.183 | drift after command 4 |
| T25 | 105 | G | found | yes | – | 2,023 | 3 | 0.375 | drift after command 1 |
| T25 | 105 | R | found | yes | – | 1,512 | 5 | 0.181 | drift after command 4 |
| T25 | 106 | G | found | yes | – | 2,023 | 3 | 0.371 | drift after command 1 |
| T25 | 106 | R | found | yes | – | 1,512 | 5 | 0.186 | drift after command 4 |
| T25 | 107 | G | found | yes | – | 2,023 | 3 | 0.372 | drift after command 1 |
| T25 | 107 | R | found | yes | – | 1,633 | 6 | 0.204 | drift after command 5 |
| T25 | 108 | G | found | yes | – | 2,023 | 3 | 0.366 | drift after command 1 |
| T25 | 108 | R | found | yes | – | 1,512 | 5 | 0.198 | drift after command 4 |
| T25 | 109 | G | found | yes | – | 2,023 | 3 | 0.357 | drift after command 1 |
| T25 | 109 | R | found | yes | – | 1,633 | 6 | 0.206 | drift after command 5 |
| T25 | 110 | G | found | yes | – | 2,023 | 3 | 0.376 | drift after command 1 |
| T25 | 110 | R | found | yes | – | 1,627 | 6 | 0.224 | drift after command 5 |

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
| `eval/results/2026-10-18/results.json` | 2026-10-18T01:56:56+00:00 | Seeds 101–110 | 7611cf5 | 300 |
| `eval/results/2026-10-18/dev/results.json` | 2026-10-18T01:34:59+00:00 | Seeds 1–3 | ba428b1 | 90 |
| `eval/results/2026-10-18/dev-d8e43d4/results.json` | 2026-10-18T00:40:25+00:00 | Seeds 1–3 | d8e43d4 | 90 |
