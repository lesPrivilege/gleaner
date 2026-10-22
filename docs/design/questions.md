# Questions, levels and acceptance

Fable, 2026-10-22, drafted at the owner's request. This chapter defines what Gleaner is for in terms a person can check, so that the library's structure, the agent catalog and each acceptance task answer to the same list. It adds no object and no view. Where a question is already answered on main it says where; where it isn't, it names the gap. One ruling stays with the owner: the review row.

## The owner's statement

Owner, 2026-10-22, verbatim:

> Gleaner 当前的瓶颈，在于期待和验收都很模糊。Artifact library "知识/review 的天然结构"本身就是一个需要定义的主题，下一层才是如何在 local session-log 中补全找到这些内容的拓扑，尽管外部有很多成熟实践，但都在工程层面，而不是工程之外对于"Gleaner"这个功用本身，需对于人类，需要比 finder 翻阅更加实用、直达，对于 mcp，需要得到一些比 grep、rag 更有限的"渐进式目录"。

Read as three requirements:

1. **The structure is defined by use, not by data.** "The natural structure of knowledge and review" is the set of questions a person asks when they come back to earlier work. A level of structure earns its place by answering one of them. Precedents (session indexers, RAG, observability) are engineering answers to other questions and don't define this list.
2. **For a person: more direct than Finder.** Finder answers "where is the file"; the person doesn't start from a path. They start from what they asked for, when, and what they already judged. Each question must be answered in Gleaner alone, without the conversation or Finder.
3. **For an agent: a progressive catalog, narrower than grep or RAG.** grep and RAG are flat: they match content anywhere and return whatever matched. The catalog is a fixed set of levels, each bounded, each carrying the index it is evidence of, and each answer reads only what the level needs. An agent goes down a level; it never searches the whole corpus.

## The questions

Each row is one question, the level of structure that answers it, where the answer is on main today, and what is still missing. Levels are the ones [structure.md](structure.md) derived from the logs, plus the two the person adds ([review.md](review.md)). Nothing here is a new level.

| # | The person asks | Level | In the window (main) | In the catalog (main) | Missing |
|---|---|---|---|---|---|
| Q1 | Which of these did I mean? | Work, by the words of its deliveries | Search, best first, with the total | `find` | Nothing. Measured by E0. |
| Q2 | That time I asked for X: what did I get? | Handover: one reply and every file it named, with its request | Delivered With | `show.delivered_with` | Nothing. |
| Q3 | Where did that conversation leave off? | Thread: one log's handovers in order | Thread, from the Agent line | None: `show.evidence` gives a log path and line, and the catalog reads no logs | A thread level in the catalog, or a ruling that a thread stays in the window. |
| Q4 | What has happened in this project lately? | Project stream: handovers across logs and agents | A project's head and its Timeline | None: `find` needs words; `--project` only narrows them | A browse level without words: the projects, then one project's latest handovers, bounded. |
| Q5 | What is in this document? | Contents: the version's own headings | Contents, on a Markdown preview | `outline`, with ranges for `read` | Nothing. |
| Q6 | Which version is real, and can I have its bytes? | Version: deliveries, provenance, availability | Versions, the caption, the tile | `show.deliveries`, `read`, `handoff`, `verify` | Nothing. Measured by E0 (T09, T10, T23, T25). |
| Q7 | What belongs together, and what have I judged? | Work unit and verdict: the person's | Collections, the four states, To Review | `show.reviews` per delivery; no units, no queue | **Owner's ruling** (below). |
| Q8 | What else did that session leave that nobody handed over? | Observation, kept by the person | Observed, under the session; Keep | Kept files are works and answer `find`; unkept ones are not answered | Nothing: an unkept observation is out of the catalog by [retrieval rulings §1](retrieval-rulings.md#1-the-ledgers-four-questions). |

Two lines the table assumes:

- **Derived levels never need the person.** Q1 to Q6 and Q8 are built from the logs, the disk and git, as [capture.md](capture.md) and SPEC §5 keep them. Q7 is the person's and stays appended apart from them (review rulings §3, foundation 2).
- **The handover is the unit of memory.** The person remembers the request and what came back, not the file. Q2 to Q4 are the handover at three widths: one reply, one conversation, one project. The table has no row for "a file's history" because that is Q6, and none for lineage across paths because Gleaner doesn't infer it.

## The catalog

The catalog is the `gleaner` command and the same calls as MCP tools ([query-core](query-core.md), [mcp-adapter](mcp-adapter.md)). What makes it progressive, and what makes it narrower than grep or RAG, stated once:

| Level | Call | Reads | Returns | Bound |
|---|---|---|---|---|
| Works | `find` | The index | Works that match every word, best first | `limit`, `total`, `truncated` |
| One delivery | `show` | The index, one file's state | Its versions, what came with it, its verdicts, its hand-off plan | One work |
| Inside one version | `outline` | That version's bytes, once | Its headings with byte and line ranges | 4 MB parsed, 50 headings, 500 at most |
| A range of one version | `read` | That version's bytes, checked | Exact text of a range | `max`, default 16 KB |
| The bytes themselves | `handoff`, `resolve`, `verify` | That version's bytes, hashed | A verified copy, a reference, a check | One file |

Three properties, each already a rule on main, that the catalog must keep at every level, including any level added for Q3 or Q4:

- **Scope in every answer.** `index` names the library, its generation, when it was read and which sources were incomplete. An empty answer is evidence only within that scope.
- **Exact bytes or nothing.** A level that returns content names the hash it came from, and never substitutes the current file for a version.
- **A bound in every list.** `limit`, `total` and `truncated`, never a cursor until there is a continuation contract (retrieval rulings §2).

**The gap is the top.** Every level starts from words (`find`) or from an id. A person's Q4 ("what happened in atlas lately?") and an agent's first move in a new session ("what did earlier sessions in this repository deliver?") have neither. A browse level would list the projects, then one project's handovers newest first, each with its request and the files it named, under the same three properties. It is the catalog's counterpart of the window's project head and Timeline, and nothing more: no summary, no ranking, no content. Retrieval rulings §1 declined a *context overview at `find` time*; a browse level is a different call, taken before `find` or instead of it, and its ruling is open. Q3 (a thread) is the same list narrowed to one log, so one call with a `--log` or `--project` scope would answer both.

## Acceptance

Each question becomes a task with a known answer on a frozen corpus, measured two ways. A task passes when both measures hold. No measure needs a model.

**For a person.** The task is worded as the person would say it (the P0 wording in SPEC §2 is the model). The measure is the number of actions (a click, a keystroke sequence, a drag) from the open window to the answer, and whether the conversation or Finder was opened on the way. Pass: answered in Gleaner alone, within the task's budget. The baseline is the same task with Finder and Spotlight on the same home, counted the same way. The walk is native, on a synthetic home, as the manual checks in [release.md](../release.md) §1 are; it cannot run in CI.

**For an agent.** The measure is E0's ([evaluation-e0.md](evaluation-e0.md)): correct against mechanical gold, within the evidence it saw, with the bytes read and the calls made. The baseline is E0's raw recipe R. Pass: correct, within evidence, and fewer bytes than R. This runs in CI once [headless indexing](headless-indexing.md) stands.

**Corpora**, from smallest to the owner's own:

| Corpus | Holds | Serves |
|---|---|---|
| `scripts/acceptance-home.py` (initial, second, changed) | One Claude Code log with two handovers, two same-named repositories, a Codex worktree later removed, an unreadable file | Q2, Q6, Q8; a person's walk |
| E0 worlds (15 tasks) | Frozen homes with gold, one per task | Q1, Q2, Q6, and the honest-empty cases (T04, T19, T21, T22) |
| CedarSearch ([project-knowledge-explorations](project-knowledge-explorations.md#a-four-week-synthetic-project)) | Eight handovers over four weeks, human-labeled, in one project across worktrees | Q3, Q4: the only corpus long enough for a thread and a stream. It is prose today, not a home. |
| The owner's series (reading-list-series) | Six episodes plus a compilation, real logs, Git-ignored media | Q7, Q8; owner-run only, never read without the owner |

**The tasks**, one per question, in the person's words, with the gold:

| # | Task | Gold | Corpus |
|---|---|---|---|
| Q1 | "The retry-policy file for North's timeout request, and its retries value in that version" | The North delivery and its captured bytes, not South's and not the live file (E0 T01) | E0 |
| Q2 | "The files that came with the latency review" | Exactly the reply's three files (E0 T03) | E0 |
| Q3 | "Where did the ranking conversation leave off?" | The last handover of that log: Oct 2, `follow-up.md` and `multilingual.svg`, with its request | CedarSearch, once it is a home |
| Q4 | "What happened in CedarSearch in the last two weeks?" | The handovers from Sep 19 on, newest first, across the ranking and release worktrees; nothing older | CedarSearch, once it is a home |
| Q5 | "The Limitations section of the baseline report" | That heading's range in the Sep 7 bytes, and its text; `R1` never finds `R10` | CedarSearch; the `outline` tests today |
| Q6 | "The guide as first delivered, now that it has changed" | Delivery 1's saved copy, its hash, and that the file on disk is delivery 2 (the MCP run of 2026-10-18 already did this) | acceptance-home after `second` |
| Q7 | "Review episode 3 without the conversation or Finder: the video, narration, both covers, the script, and record a verdict" | The episode's collection shows all five in place; the verdict binds to those bytes; To Review drops it | Owner's series |
| Q8 | "The PNG the session rendered that no reply named" | Listed under Observed for that session; kept, it answers `find` by name; unkept, it doesn't | acceptance-home, or the owner's series |

Budgets for a person's walk are set when the walk is first recorded, not here: the first recording is the baseline, and the budget is what beat Finder.

## What this fixes, and what it leaves

- **Expectation**: the eight questions. A proposal that answers none of them is out of scope, whatever a precedent does.
- **Acceptance**: a task per question with gold, and two measures with baselines. "More direct than Finder" and "narrower than grep" are the two baselines, not adjectives.
- **The topology work that remains** is Q3 and Q4 in the catalog, and CedarSearch as a frozen home so they can be measured. Everything else the table marks as answered is measured already or needs only a recorded walk.

## Open rulings for the owner

1. **Q7 in the catalog.** Today an agent sees a delivery's verdicts through `show.reviews`, so "the version I approved" works. It does not see collections, nor To Review. Options: leave review in the window only (an agent is handed what a person judged, never what is waiting on them); or expose units and the queue read-only, so an agent can say "episode 3 is the only one unreviewed". An agent never writes a verdict in either case.
2. **The browse level** for Q3 and Q4: one call, scoped by project or log, or a ruling that those two questions stay in the window.
3. **CedarSearch as a home.** The thread and stream tasks need a corpus longer than one or two turns. Building it from the prose table is a day's work on `eval/worlds.py`.
