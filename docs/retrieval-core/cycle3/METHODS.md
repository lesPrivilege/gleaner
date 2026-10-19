# Cycle 3: first-layer default, without a universal relevance claim

Method proposals only, 2026-10-19. Baseline remains remote main
`2648094610facfd1ae1805f52a9de282043c808f`. No shipped behavior, ontology, model
dependency or new authority rule is selected here. Governing sources:
[SPEC §10](../../SPEC.md#10-search), [query core](../../design/query-core.md),
[cycle 2 decision](../cycle2/DECISION-NOTE.md) and
[independent evaluation](../cycle2/EVALUATION.md).

The baseline already returns one result per `Work`, with contextual name/path
matches before request/reply mentions and newest first within each tier. Current
outline grouping and search ordering are different contracts. The question is
which first layer best serves a stated interaction, not whether to invent another
object identity or declare all nonleading results unimportant.

## What the evidence permits

Cycle 2's named focus helped booklet/CSV tasks but hid the wanted editable deck
behind its companion guide: first-layer recall fell from 1 to 0 while reachable
recall stayed 1. A native reply group preserved candidates but added a selection;
its full member payload did not demonstrate reduced transfer or inspection cost.
Thus named suppression and reply grouping are neither equivalent nor universally
better than current shared search. A group containing one wanted and five unwanted
members is not one relevant object.

Three primary-source mechanisms sharpen this question:

| Source | Transferable mechanism | Limit |
|---|---|---|
| [Carbonell and Goldstein, MMR](https://www.cs.cmu.edu/~jgc/publication/The_Use_MMR_Diversity_Based_LTMIR_1998.pdf) | Balance query relevance against similarity to already selected results; browsing for coverage and drilling into one topic can favor different balances. | This is reranking of retrieved candidates, not recall repair or identity resolution. Its small historical study does not establish Gleaner preferences. Similarity need not use embeddings. |
| [TREC 2009 Web Track](https://trec.nist.gov/pubs/trec18/papers/WEB09.OVERVIEW.pdf) | Judge each query interpretation separately; report coverage of interpretations alongside relevance. Query text and the full information need are distinct inputs. | Equal intent weights are an evaluation assumption, not observed user probabilities. A union of relevant subtopics is not precision for one declared task. |
| [Elastic field collapse](https://www.elastic.co/docs/reference/elasticsearch/rest-apis/collapse-search-results) | A representative under a known key can have separately requested, bounded member expansion. | Grouping requires a trustworthy key. Expansion costs additional work; group counts and document counts are different. No Elastic stack is proposed. |

The following alternatives are local inferences from those mechanisms and current
contracts. They use the shared candidate set and existing native fields.

## Minimal alternatives

| Alternative | Mechanism and cost | Failure to retain in evaluation |
|---|---|---|
| **Neutral overview** | When no task is declared, expose a bounded spread of existing contexts, with concrete selectable works and an explicit remainder. Compare baseline ordering with a light diversity penalty using existing collection/reply/context fields; retain full order for expansion. A bounded greedy pass costs roughly candidates × visible slots. | Different replies are not necessarily different useful outcomes. A single reply can contain every desired output. Excess diversification hides similar-but-required episode members or versions; uniform quotas can overexpose an irrelevant context. “Neutral” means no assumed task, not absence of ordering choices. |
| **Declared-task rerank** | Accept the caller's actual purpose or explicit filter, use a small transparent feature comparison, and retain candidates. Uncertain feature evidence contributes no decisive preference. No model or automatic intent classifier is required. | Editable can mean source code, native design, a spreadsheet or an ordinary document. Extension and “final” naming are fallible hints. A declared edit task must not inherit a generic preference for finished media. Missing native evidence must remain unknown. |
| **Conservative first objects with contextual expansion** | Preserve current shared order for directly actionable results; add bounded expansion into existing collections or proven reply groups. Show omitted counts and retain direct scoped queries. Little ranking change; added interaction/serialization work. | The newest named helper can still dominate. An opaque group title can conceal the deck, and expanding an oversized group can cost more effort than a flat page. All members must not be shipped invisibly in every response. |

These arms can be compared independently. A hybrid may eventually use an overview
when intent is absent and task ranking when supplied, but the experiment must not
quietly give only that arm access to the evaluator's relevance labels. A task hint
is an input only if the actual caller supplies it. Apply explicit scope filters
equally before comparison; each ranker then preserves the same scoped candidates.
Exact-name requests, broad
project browsing and “all episodes” are distinct workloads; do not average away
their different failure costs.

**Suppression** removes or defers an object from the first layer. **Grouping** changes
its access path. **Diversification** changes order to cover additional contexts.
None changes identity or proves semantic redundancy. Byte-identical objects in
different projects retain their meanings. A bounded first layer must retain a
documented path to the complete authorized candidate set, including relevant
intermediates; reachability alone does not demonstrate that people find that path.

## Comparison and falsification

Seal independent tasks/labels before viewing outputs. Use the same query with
different declared purposes: edit the deck versus read its guide; inspect the
release specification versus debug its generator; review one episode versus obtain
the complete series; inspect current work versus a rejected prior version. Include
unknown purpose and competing plausible purposes. Ambiguous overview cases receive
separate plausible-task labels, not a fabricated single correct object.

Report, per task and domain:

- Candidate recall, first-layer recall, precision among displayed objects and
  useful-object yield at the same slot budget. A one-result answer's 1/1 precision
  must not conceal omitted required results or be compared to a larger page alone.
- For overview cases, coverage across declared plausible needs and the worst-case
  missing need, with any averaging weights disclosed. This is not task precision.
- Directly selectable wanted objects, hidden wanted members, expanded-member
  precision, actual requests and serialized bytes. Count previews as viewed content;
  group-only rows are navigation until expanded.
- Time/reads to verified usable evidence, p50/p95 ranking latency and resource cost.
  Scripted ideal expansion counts are proxies, not measured human effort.

Metamorphic checks add irrelevant files, duplicate evidence, a misleading named
companion, another similar episode, and a same-hash work in another project. Change
extensions only when the fixture's semantic affordance really stays the same;
renaming an editable native file to a rendered format is not a valid invariant.
Reordering imports must not alter established native evidence or user corrections.

## Competent directory and direct-query comparators

Keep actual `Organization.search` as the algorithm baseline. Additional filesystem
comparators answer the practical effort question; they do not replace that control.
Freeze their capabilities and stopping rules before held-out evaluation:

1. **Equal information and scope.** Supply the same task wording and authorized
   starting project/root, not the target filename only to Gleaner or the comparator.
   Test known-location and unknown-location tasks separately. Both may use folder
   names, native filenames and ordinary metadata; neither receives relevance labels.
2. **Competent operations.** A directory arm can navigate, sort by name/date/type,
   search filenames and relative paths, filter and preview. A direct-query arm can
   perform scoped literal text/path searches and inspect bounded originals and the
   supplied source records. Allow ordinary query reformulation under the same
   attempt/output budget. Do not handicap it to basename-only matching or a random
   directory listing. Use safe argument APIs; source text is never executable code.
3. **Count real work.** Record operations, candidates inspected, bytes transferred,
   failed opens, checks needed to identify the intended version, and time. For a
   provenance task, provide the same authorized evidence corpus or explicitly label
   the directory-only arm unsupported; a withheld record is not a retrieval loss.
4. **Match the starting state.** Report fresh-index construction separately from
   warmed lookup, and stale/partial-index behavior separately from both. Filesystem
   tools may find current unindexed files; that advantage must remain visible.
   Conversely, a saved historical version absent from disk is a different access
   capability. Publish corpus, tool versions, exact query plans and output limits.
5. **Prevent oracle shortcuts.** Freeze scripted navigation/query policies before
   labels or use blinded independent operators with randomized task order. Record
   reformulations and stopping decisions. A script that opens the known target
   directly is an ideal-path bound, not a competent-user measurement.

This protocol supports a synthetic directory/direct-query comparison only. It does
not measure Finder, human usability, or general superiority to an agent's library.
Experiments can reveal tradeoffs and harmful defaults. Which neutral view deserves
initial space, whether task intent is requested or optional, and how prominently
to expose the remainder remain product decisions with Opus.
