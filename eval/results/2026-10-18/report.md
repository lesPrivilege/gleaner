# Evaluation E0: results

Seeds 1, 2, 3; 15 tasks; policies R, G. Run 2026-10-18T00:40:25+00:00 on macOS 27.0.1 at commit d8e43d4, with ripgrep 15.1.0, jq-1.7.1-apple, git version 2.50.1 (Apple Git-155) and Python 3.14.2. Seeds 1–3 are the development seeds, where the raw recipe is tuned and locked. 

How it was made: [docs/design/evaluation-e0.md](../../../docs/design/evaluation-e0.md) and [eval/README.md](../../README.md). Every episode, with its commands and answer, is in `results.json`.

## What this can and cannot show

Two scripted, deterministic policies answer the same questions over the same worlds. It shows whether each answer is correct against mechanical gold, whether it stays within its evidence, and how many bytes and commands each policy needed, with what the catalog cost to prepare. It cannot show how a model would do, token savings, or benefit to real users. The worlds are synthetic and few; nothing here is a production rate.

## How the policies ran

- **R**: `rg -l` over the two log folders for each word, sub-agent transcripts left out; a `jq` projection of each log that holds them all; the turn whose request, title, final reply and project hold every word; each path the final reply names, resolved against its record's cwd; then `stat` and `shasum -a 256` of the file and of the turn's logged write of it, and `git log` for a file that is gone. The logged write stands for the delivered bytes only while the file still has them, or changed after the reply.
- **G**: `gleaner find` with the words, then only what the question needs: `read` for a value, `show` for the other versions or a hand-off plan, `handoff` for bytes, `verify` for a pointer. It falls back to R, counted in full, when the index reports a source read with problems or find returns nothing. For what the catalog does not record (the delivering turn's tool output, later turns) it reads the log the delivery's evidence names, with R's projection.
- Two points go beyond evaluation-e0.md, which has G always call `show` and names only the two fallback conditions: G skips `show` when the answer does not need it, and it reads the delivering log for what is outside the catalog.

## Summary

| Policy | Correct | Hard failures | Fallbacks | Bytes read | Bytes, home as ~ | Commands | Wall time (s) |
|---|---|---|---|---|---|---|---|
| R | 45 of 45 | 0 | 0 | 146,765 | 112,425 | 261 | 5.482 |
| G | 45 of 45 | 0 | 12 | 157,053 | 113,320 | 126 | 10.763 |

Bytes read, G over R: **1.07** overall; B (fallback) 1.205; E (shared information) 0.892; S (recorded state) 2.059.

With the home folder's path counted as ~, G over R: **1.008** overall; B (fallback) 1.22; E (shared information) 0.821; S (recorded state) 1.754.

Preparing the catalog, charged to G: 45 worlds, 51 index runs, 18.484 s of indexing, 17,599,169 library bytes on disk (391,092 per world), 307 saved copies. R prepares nothing.

## By family

| Family | Policy | Correct | Hard failures | Fallbacks | Bytes read | Bytes, home as ~ | Commands |
|---|---|---|---|---|---|---|---|
| B (fallback) | R | 18 of 18 | 0 | 0 | 40,923 | 30,318 | 75 |
| B (fallback) | G | 18 of 18 | 0 | 9 | 49,302 | 36,980 | 60 |
| E (shared information) | R | 24 of 24 | 0 | 0 | 94,440 | 72,523 | 159 |
| E (shared information) | G | 24 of 24 | 0 | 3 | 84,274 | 59,529 | 51 |
| S (recorded state) | R | 3 of 3 | 0 | 0 | 11,402 | 9,584 | 27 |
| S (recorded state) | G | 3 of 3 | 0 | 0 | 23,477 | 16,811 | 15 |

## By task

| Task | Asks | R correct | R bytes | R commands | G correct | G bytes | G commands | G/R bytes |
|---|---|---|---|---|---|---|---|---|
| T01 | value | 3 of 3 | 3,763 | 7.0 | 3 of 3 | 3,083 | 2.0 | 0.819 |
| T02 | value | 3 of 3 | 5,044 | 7.0 | 3 of 3 | 3,188 | 2.0 | 0.632 |
| T03 | files | 3 of 3 | 3,889 | 3.0 | 3 of 3 | 4,760 | 1.0 | 1.224 |
| T04 | delivery | 3 of 3 | 4,554 | 6.0 | 3 of 3 | 5,121 | 7.0 | 1.124 |
| T07 | same_item | 3 of 3 | 3,872 | 9.0 | 3 of 3 | 3,718 | 1.0 | 0.96 |
| T09 | current_match | 3 of 3 | 5,467 | 10.0 | 3 of 3 | 5,012 | 2.0 | 0.917 |
| T10 | provenance | 3 of 3 | 2,022 | 7.0 | 3 of 3 | 1,595 | 1.0 | 0.789 |
| T12 | delivery | 3 of 3 | 2,866 | 4.0 | 3 of 3 | 1,614 | 1.0 | 0.563 |
| T16 | recover | 3 of 3 | 3,800 | 9.0 | 3 of 3 | 7,825 | 5.0 | 2.059 |
| T19 | delivery | 3 of 3 | 1,895 | 4.0 | 3 of 3 | 2,462 | 5.0 | 1.299 |
| T20 | handed_over | 3 of 3 | 2,613 | 5.0 | 3 of 3 | 3,457 | 3.0 | 1.323 |
| T21 | decision | 3 of 3 | 2,408 | 4.0 | 3 of 3 | 2,989 | 5.0 | 1.241 |
| T22 | referenced | 3 of 3 | 2,319 | 2.0 | 3 of 3 | 2,886 | 3.0 | 1.244 |
| T23 | verify | 3 of 3 | 2,302 | 5.0 | 3 of 3 | 1,305 | 1.0 | 0.567 |
| T25 | bytes | 3 of 3 | 2,102 | 5.0 | 3 of 3 | 3,333 | 3.0 | 1.586 |

Bytes and commands per task are means per episode.

## Every episode

| Task | Seed | Policy | Status | Correct | Hard failures | Bytes | Commands | Seconds | Notes |
|---|---|---|---|---|---|---|---|---|---|
| T01 | 1 | G | found | yes | – | 3,083 | 2 | 0.249 | – |
| T01 | 1 | R | found | yes | – | 3,851 | 7 | 0.127 | – |
| T01 | 2 | G | found | yes | – | 3,083 | 2 | 0.238 | – |
| T01 | 2 | R | found | yes | – | 3,677 | 7 | 0.103 | – |
| T01 | 3 | G | found | yes | – | 3,083 | 2 | 0.238 | – |
| T01 | 3 | R | found | yes | – | 3,763 | 7 | 0.116 | – |
| T02 | 1 | G | found | yes | – | 3,188 | 2 | 0.243 | – |
| T02 | 1 | R | found | yes | – | 4,950 | 7 | 0.101 | – |
| T02 | 2 | G | found | yes | – | 3,188 | 2 | 0.249 | – |
| T02 | 2 | R | found | yes | – | 5,092 | 7 | 0.113 | – |
| T02 | 3 | G | found | yes | – | 3,188 | 2 | 0.244 | – |
| T02 | 3 | R | found | yes | – | 5,092 | 7 | 0.1 | – |
| T03 | 1 | G | found | yes | – | 4,760 | 1 | 0.264 | – |
| T03 | 1 | R | found | yes | – | 3,936 | 3 | 0.072 | – |
| T03 | 2 | G | found | yes | – | 4,760 | 1 | 0.251 | – |
| T03 | 2 | R | found | yes | – | 3,621 | 3 | 0.069 | – |
| T03 | 3 | G | found | yes | – | 4,760 | 1 | 0.261 | – |
| T03 | 3 | R | found | yes | – | 4,111 | 3 | 0.071 | – |
| T04 | 1 | G | not_found | yes | – | 4,939 | 7 | 0.101 | fallback: find returned nothing |
| T04 | 1 | R | not_found | yes | – | 4,372 | 6 | 0.084 | – |
| T04 | 2 | G | not_found | yes | – | 5,155 | 7 | 0.104 | fallback: find returned nothing |
| T04 | 2 | R | not_found | yes | – | 4,588 | 6 | 0.081 | – |
| T04 | 3 | G | not_found | yes | – | 5,270 | 7 | 0.099 | fallback: find returned nothing |
| T04 | 3 | R | not_found | yes | – | 4,703 | 6 | 0.084 | – |
| T07 | 1 | G | found | yes | – | 3,718 | 1 | 0.313 | – |
| T07 | 1 | R | found | yes | – | 3,872 | 9 | 0.161 | – |
| T07 | 2 | G | found | yes | – | 3,718 | 1 | 0.311 | – |
| T07 | 2 | R | found | yes | – | 3,872 | 9 | 0.139 | – |
| T07 | 3 | G | found | yes | – | 3,718 | 1 | 0.314 | – |
| T07 | 3 | R | found | yes | – | 3,872 | 9 | 0.15 | – |
| T09 | 1 | G | found | yes | – | 5,012 | 2 | 0.234 | – |
| T09 | 1 | R | found | yes | – | 5,462 | 10 | 0.142 | – |
| T09 | 2 | G | found | yes | – | 5,012 | 2 | 0.256 | – |
| T09 | 2 | R | found | yes | – | 5,751 | 10 | 0.146 | – |
| T09 | 3 | G | found | yes | – | 5,012 | 2 | 0.238 | – |
| T09 | 3 | R | found | yes | – | 5,190 | 10 | 0.139 | – |
| T10 | 1 | G | found | yes | – | 1,595 | 1 | 0.157 | – |
| T10 | 1 | R | found | yes | – | 2,117 | 7 | 0.135 | – |
| T10 | 2 | G | found | yes | – | 1,595 | 1 | 0.137 | – |
| T10 | 2 | R | found | yes | – | 1,975 | 7 | 0.122 | – |
| T10 | 3 | G | found | yes | – | 1,595 | 1 | 0.157 | – |
| T10 | 3 | R | found | yes | – | 1,975 | 7 | 0.132 | – |
| T12 | 1 | G | found | yes | – | 1,614 | 1 | 0.144 | – |
| T12 | 1 | R | found | yes | – | 2,866 | 4 | 0.085 | – |
| T12 | 2 | G | found | yes | – | 1,614 | 1 | 0.149 | – |
| T12 | 2 | R | found | yes | – | 2,866 | 4 | 0.089 | – |
| T12 | 3 | G | found | yes | – | 1,614 | 1 | 0.145 | – |
| T12 | 3 | R | found | yes | – | 2,866 | 4 | 0.085 | – |
| T16 | 1 | G | found | yes | – | 7,833 | 5 | 1.07 | – |
| T16 | 1 | R | found | yes | – | 3,781 | 9 | 0.407 | – |
| T16 | 2 | G | found | yes | – | 7,822 | 5 | 1.064 | – |
| T16 | 2 | R | found | yes | – | 3,711 | 9 | 0.397 | – |
| T16 | 3 | G | found | yes | – | 7,822 | 5 | 1.081 | – |
| T16 | 3 | R | found | yes | – | 3,910 | 9 | 0.409 | – |
| T19 | 1 | G | found | yes | – | 2,368 | 5 | 0.093 | fallback: find returned nothing |
| T19 | 1 | R | found | yes | – | 1,801 | 4 | 0.083 | – |
| T19 | 2 | G | found | yes | – | 2,510 | 5 | 0.095 | fallback: find returned nothing |
| T19 | 2 | R | found | yes | – | 1,943 | 4 | 0.083 | – |
| T19 | 3 | G | found | yes | – | 2,510 | 5 | 0.097 | fallback: find returned nothing |
| T19 | 3 | R | found | yes | – | 1,943 | 4 | 0.082 | – |
| T20 | 1 | G | found | yes | – | 3,430 | 3 | 0.166 | – |
| T20 | 1 | R | found | yes | – | 2,586 | 5 | 0.091 | – |
| T20 | 2 | G | found | yes | – | 3,508 | 3 | 0.163 | – |
| T20 | 2 | R | found | yes | – | 2,664 | 5 | 0.087 | – |
| T20 | 3 | G | found | yes | – | 3,435 | 3 | 0.166 | – |
| T20 | 3 | R | found | yes | – | 2,591 | 5 | 0.09 | – |
| T21 | 1 | G | unknown | yes | – | 3,131 | 5 | 0.081 | fallback: the index reports incomplete sources |
| T21 | 1 | R | unknown | yes | – | 2,550 | 4 | 0.072 | – |
| T21 | 2 | G | unknown | yes | – | 2,918 | 5 | 0.084 | fallback: the index reports incomplete sources |
| T21 | 2 | R | unknown | yes | – | 2,337 | 4 | 0.071 | – |
| T21 | 3 | G | unknown | yes | – | 2,918 | 5 | 0.084 | fallback: the index reports incomplete sources |
| T21 | 3 | R | unknown | yes | – | 2,337 | 4 | 0.072 | – |
| T22 | 1 | G | not_found | yes | – | 2,443 | 3 | 0.071 | fallback: find returned nothing |
| T22 | 1 | R | not_found | yes | – | 1,876 | 2 | 0.059 | – |
| T22 | 2 | G | not_found | yes | – | 2,959 | 3 | 0.069 | fallback: find returned nothing |
| T22 | 2 | R | not_found | yes | – | 2,392 | 2 | 0.06 | – |
| T22 | 3 | G | not_found | yes | – | 3,258 | 3 | 0.071 | fallback: find returned nothing |
| T22 | 3 | R | not_found | yes | – | 2,691 | 2 | 0.059 | – |
| T23 | 1 | G | found | yes | – | 1,305 | 1 | 0.145 | – |
| T23 | 1 | R | found | yes | – | 2,302 | 5 | 0.132 | – |
| T23 | 2 | G | found | yes | – | 1,305 | 1 | 0.145 | – |
| T23 | 2 | R | found | yes | – | 2,302 | 5 | 0.139 | – |
| T23 | 3 | G | found | yes | – | 1,305 | 1 | 0.138 | – |
| T23 | 3 | R | found | yes | – | 2,302 | 5 | 0.131 | – |
| T25 | 1 | G | found | yes | – | 3,333 | 3 | 0.27 | – |
| T25 | 1 | R | found | yes | – | 2,044 | 5 | 0.106 | – |
| T25 | 2 | G | found | yes | – | 3,333 | 3 | 0.256 | – |
| T25 | 2 | R | found | yes | – | 2,044 | 5 | 0.102 | – |
| T25 | 3 | G | found | yes | – | 3,333 | 3 | 0.258 | – |
| T25 | 3 | R | found | yes | – | 2,218 | 5 | 0.104 | – |

## Measurement

- Bytes read are every byte of standard output and standard error of every command a policy ran. The question itself is not counted. A pipeline counts what it prints, not what its stages pass between them; `rg` and `git` read more than they print, so what they scan is not counted.
- The worlds live deep in the repository, so every absolute path carries a long prefix. The second count writes the home folder's path, and its spelling in Claude Code's log folder names, as `~`, so where a world was written weighs nothing. R already writes it so in its projection; G prints absolute paths.
- R projects log records with `jq` before reading them. G reads each `gleaner` answer whole, the index block included.
- G falls back to R, counted in full, when find reports incomplete sources or returns nothing.
- Wall time includes starting each command and the policy itself.
- The earlier synthetic comparison (4,885 catalog bytes against 5,967 for targeted section reads) is motivation only; its definitions were not supplied, so its numbers are not comparable with these.
