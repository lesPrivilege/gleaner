# Synthetic probe and evaluation blueprint

The isolated probe measures retrieval policies over a generated corpus. It does not execute Gleaner, call a language model, or establish real-user efficacy. It deliberately includes a competent direct-read baseline so bulk reading is not the only comparison.

## Reproduce

Python standard library only; writes synthetic files to a temporary directory, deletes that directory on completion, and persists measurements next to the script:

```sh
python3 /workspace/gleaner-research/probe/probe.py
```

[Script](probe/probe.py) · [raw results](probe/results.json). No personal logs, credentials, model API or downloaded package is used. Runtime in this run: Python 3.12.14, Linux x86-64.

## Corpus and policies

Ten projects, 120 delivery records, repeated filenames, three versions per file, long irrelevant sections and synthetic tool logs. Two projects share the label “Atlas”. The corpus contains 178 files totaling 13,020,546 bytes. Its capture store and exact hashes are available to every policy.

All policies receive the same task constraints. Six cases request exact sections from available versions; four expect a refusal or disambiguation: late observation, unavailable historical bytes, ambiguous project label and nonexistent project. Other cases cover old versions, another same-named project, deleted source, silent current edits and instruction-like text in evidence.

| Policy | Discovery | Content retrieval |
|---|---|---|
| Exhaustive | Return all synthetic logs, source material and saved files | Select from that material; verify chosen digest |
| Targeted + full | Parse the known project's log and return matching delivery records | Read the selected full document |
| Targeted + section | Same strong direct-log baseline | Return only the requested section after hash verification |
| Catalog | Query an already resident parsed delivery index | Return compact candidates, an outline and the selected section |

Project-qualified targeted reads are given the relevant log location; this favors a capable direct baseline. Ambiguous labels require scanning all logs. The catalog is built from those same synthetic delivery records, not from a separate answer key. However, all policies share selection and verification functions. This isolates access costs; it does not independently test competing extractors or agents' reasoning.

### What the scripts already know

Tasks supply the project key (or ambiguous label), version ordinal, fixed filename `report-0.md` and heading “Retry policy”. Strategies know the log format, capture layout, hash semantics and section delimiter. Targeted reads know each project's log filename; the catalog starts with logs parsed into memory. None discovers intent, infers deliveries or resolves renames.

The generator writes clean IDs, projects, versions, hashes, provenance and evidence locators into logs: easier inputs than raw sessions. Selection uses those logs, not the generated record list or task's `expected` field; the latter is checked afterward. Still, correctness is largely engineered by the fixture and shared resolver. The checks confirm designed answers/failures, not improved independent retrieval accuracy. There are 40 policy/task assertions after repeated timing, plus two fault assertions; not 600 separately asserted agent outcomes.

## Measured results

Totals below are one pass over ten tasks. Latency is the sum of each task's median from 15 repetitions; it is in-process retrieval/serialization time, not model or network latency.

| Policy | Expected outcomes | Bytes returned | Application bytes read | Sum of task medians |
|---|---:|---:|---:|---:|
| Exhaustive | 10/10 | 130,205,624 | 130,659,823 | 103.50 ms |
| Targeted + full | 10/10 | 394,437 | 4,921,575 | 11.84 ms |
| Targeted + section | 10/10 | 5,967 | 4,921,575 | 14.96 ms |
| Catalog | 10/10 | 4,885 | 454,363 | 0.62 ms |

“Expected outcomes” includes four correctly recognized inability/ambiguity states, not ten successful content reads. Available-version checks also assert the correct project, delivery ID and section marker.

The catalog emitted 1,082 fewer bytes than targeted section retrieval in this corpus. Most of the reduction against full-document reading comes from bounded content access, a capability the shell baseline can also use. A catalog can still save repeated log parsing and expose better version/provenance semantics. These measurements do not choose CLI versus MCP; both would call the same retrieval operations.

The one-time synthetic index build read 2,481,788 bytes, produced 57,089 bytes of compact JSON and took 6.80 ms. This excludes capture acquisition, hashing every capture and disk persistence. For this ten-task pass, adding build reads to catalog reads gives 2,936,151 bytes, compared with 4,921,575 for targeted direct retrieval. For a single known-project job, scanning one log can cost less than building the whole index. Gleaner's already-existing index changes the practical amortization, but that was not measured here.

That build timer includes reading/parsing the synthetic JSON logs and serializing the resulting list to JSON bytes in memory. It excludes corpus generation, saving historical copies, their initial hashes, real-session extraction and validation, persistent index writes, incremental refresh, migrations, access checks and client discovery/setup. Retrieval timing includes hashing the entire selected file even when only a section is returned. Neither returned-byte totals nor timings include process startup, tool-schema exchange, model calls or network transport.

Application read bytes are counts from `read_bytes()`, not physical disk I/O. Returned bytes are modeled tool payloads, not actual model input. No tokenizer ran; no token-saving claim is made. Repeated runs use filesystem caches and a resident catalog, methods run in fixed order, and there are no startup, IPC or remote transport costs. The latency differences are descriptive; no statistical significance is claimed.

## Failures deliberately exercised

- A corrupted saved copy was refused, despite a valid record and digest expectation.
- Removing a current record from the catalog reproduced a false negative for a version still present in the source logs. This demonstrates why freshness and coverage belong in responses.
- A known hash without surviving matching bytes returns unavailable, not the current file.
- A capture first observed after delivery does not satisfy an exact-at-delivery request.
- A duplicated project label returns ambiguity rather than choosing the first match.

Instruction-like evidence was returned as data and never executed by the script. That case is **not** a prompt-injection robustness result for an agent. The probe does not implement pagination, authorization, logical identity, migrations, real Markdown parsing, binary handling or MCP. Those remain separate tests below.

## Next: use real consumers on the same controlled tasks

Run a small counterbalanced experiment with the intended local Opus and another target client, using only synthetic or explicitly consented/redacted corpora. Fix the task wording and answer key before the run. Allow competent shell tools, indexes and bounded reads in the direct condition. Give every condition access to the same historical bytes.

Compare: (a) file/session exploration; (b) structured CLI; (c) identical core through MCP; optionally (d) a logical-object overlay. Include discovery/setup cost. Separate first-use/cold, warm and stale-index runs. Record every request and response, correct project/object/version, correct refusal, total UTF-8 payload bytes, actual model token usage if reported by the client, wall-clock completion, retries and failure category. Count all setup/schema/context overhead and unsuccessful searches. Do not convert bytes to model tokens by a fixed ratio.

| Task family | Required challenge | Pass condition |
|---|---|---|
| Project identity | Same basename, worktree moved/deleted, output outside cwd | Correct scope or explicit ambiguity |
| Versions | Same path changed; same bytes redelivered; late capture; missing snapshot | Exact requested bytes or honest inability |
| Progressive reads | Duplicate headings, headings in code fences, long section, non-UTF-8 | Bounded correct range, explicit truncation/continuation |
| Search | Terms split across deliveries; body-only term; empty/stale/partial index | Declared semantics and coverage, no false certainty |
| Paging | Index changes between pages; identical timestamps; invalid cursor | No silent omissions/duplication, or explicit restart |
| Handoff | File changes during staging; cache cleared before receiver reads | Hash verified by receiver or retriable unavailable reference |
| Privacy | Restricted project, path traversal, symlink escape, private evidence | No unauthorized content; rejection does not leak hidden candidates |
| Evidence | Source log missing; redaction removes a term; source assertion conflicts | Attribution and limitations preserved |
| Identity options | Rename, reused path, multiple representations, mistaken link | Correct grouping or unknown; reversible correction |
| Compatibility | Old response schema, reindex, migrated identities | Old exact references remain valid or fail explicitly |

For human comparison, measure time, mis-selection and correction effort; model tokens are irrelevant. For agent comparison, distinguish an interface failure from a model's wrong interpretation. Adopt richer identity or indexing only when it fixes observed errors without creating greater correction burden.
