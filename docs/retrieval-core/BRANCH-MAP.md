# Public branch and design map

Read-only checkpoint, 2026-10-19. `git ls-remote --heads origin` matched the fetched refs below. All ancestry and content comparisons use remote main **`2648094610facfd1ae1805f52a9de282043c808f`**, not this branch's working-tree prototype. No branches were merged, rebased or changed for this map; no private history was consulted. “Integrated” means reachable by Git ancestry; “adopted” requires a ruling or current contract. Neither means runtime validation occurred here.

## Branch inventory

Eleven of thirteen non-main remote branch tips are ancestors of main. Only the two rows marked **unmerged** have unique commits.

| Remote branch | Exact tip | Tip title | Status and retrieval relevance |
|---|---|---|---|
| `main` | `2648094610facfd1ae1805f52a9de282043c808f` | Find files by their folders in the project, and named ones first | Baseline; shared contextual search already exists |
| `feat/query-core` | `cdfe6f4e0ba473ba12309b310018734244efc37c` | Index a synthetic home without the window: gleaner-index | Integrated; main is three commits ahead. Catalog, CLI, MCP, E0 and synthetic indexer are reusable current code |
| `feat/capture` | `e4bd66efb3950fb61f679a9e297810e05eca6584` | Capture: admission by the person, work units, review verdicts, bundles first | Integrated; later main commits implement and refine these layers. The branch tip is not their final implementation |
| `feat/outline` | `730ce0f43bd22493865f7e4a0cb2cd2398d874cc` | Merge design/components: the outline draws with GleanerUI | Integrated; project/work/revision outline, distinct from the unmerged document-heading outline |
| `feat/sources-plane` | `16c9a065de330399801bd867a6804d16d622dfa8` | Merge design/window-polish: run CI on the stack | Integrated; source visibility/health and provider/model presentation |
| `design/components` | `4f9af41d8e8560f9ea8304fd70e5c813ecd1668f` | Answer the component review: first-tier marks, relations with ends, rows sized to their text | Integrated; visual vocabulary, not retrieval identity |
| `design/information-architecture-review` | `f38d65461b40e8d81aba30caa66b5d471194de30` | docs: rule on the design exploration | Integrated; original rulings, partly superseded by later explicit contracts |
| `design/window-polish` | `79fce063f4c838e9b1fde53fb73c2c99182e7ee4` | Merge fix/app-completeness: run CI on the stack | Integrated; presentation and interaction history |
| `fix/app-completeness` | `6981aa7c35728099de1c2dea6d77657ff1e568f3` | Run the tests on every push and pull request | Integrated; completion fixes and CI |
| `fix/release-review` | `314e0346965ac57d0b7b3dd77a011d89bf94e02e` | Build a synthetic home for acceptance checks; record what ran without the window | Integrated; exact-byte safeguards and acceptance fixtures |
| `fix/staging-search` | `d7249fb3242fb3f409dc30bdd672537d4ed74dd4` | Tie hand-off staging to its version; match search within one delivery | Integrated; selection/version and occurrence-local matching constraints |
| `polish/release-reduction` | `846190d67d3ec517a7d12a6dd92e79d41d5a9ed9` | Show library status as the window subtitle | Integrated; presentation reduction |
| `claude/structure-views` | `72a42993512281a8bcc36fd9c6f22566132258d9` | Show threads, outlines and the project timeline | **Unmerged**; one unique commit, 244 main-only commits |
| `cloud/gleaner-review-research-20261017` | `6a95aad5cc80593680360f875ab61fe2a70f9205` | Add Gleaner review and independent research reference [skip ci] | **Unmerged** report tree; one unique commit, 244 main-only commits; selectively consumed by subsequent main rulings |

Both unmerged branches diverge at `22dd07d926a764f0a2efcdeb093b78f0b9eab41b`. The previously audited main `3bcb6d76ec87f7e94149f4a7fbb32d23fcf0db8e` is followed on main's first-parent path by `ad697a5b868c75f0e82adc290a6b6b1710a4edf3` (query-core merge), `32e8594c4999f2fd2951dbb0feb7f8683ff09d51` (one app/CLI/MCP search), and current `2648094`. Old query-core reference `4e355d71e3ee7712a7637d4a1ab6d53620a26020` is “Record the host checks across two versions”; it is not the remote branch tip.

## Unmerged work: reuse and conflict

**Structure views.** [The exact commit](https://github.com/lesPrivilege/gleaner/commit/72a42993512281a8bcc36fd9c6f22566132258d9) adds `Handovers`, `LibraryOrder`, `ThreadView`, a `MarkdownBlock.headings` helper and corresponding tests (11 files, 541 additions, 29 deletions). Its heading helper preserves source headings and could inform progressive section access, but its block-index IDs are document-local, not persistent hash-pinned external references. Its `Handovers.all` groups by log plus delivery timestamp and sorts members by filename. Current [review-rulings A8](../design/review-rulings.md) requires the reply/turn key and reply order; [projects-and-works](../design/projects-and-works.md) relocates timeline entry into the project outline. The old view changes also predate work joins, corrections, collections and source visibility. Rebase/reimplementation would need those semantic adaptations; Git ancestry alone cannot establish UI compatibility. No merge conflict simulation or native execution was performed.

**Research bundle.** [The pinned research entry](https://github.com/lesPrivilege/gleaner/blob/6a95aad5cc80593680360f875ab61fe2a70f9205/docs/research/2026-10-17/README.md) contains five streams: release audit, CLI/schema, benchmark, provenance and prior art, plus manifests and probes. Its [cross-stream handoff](https://github.com/lesPrivilege/gleaner/blob/6a95aad5cc80593680360f875ab61fe2a70f9205/docs/research/2026-10-17/decisions/opus-handoff.md) expressly describes options, not an adopted future architecture. Main's review-rulings cites this branch and adopts a shared query core, exact references and separate derived state. Therefore the bundle is unmerged, **not wholly unconsumed**. Whether anyone read individual uncited pages cannot be inferred.

Useful material without demonstrated full integration:

- [Logical-object alternatives](https://github.com/lesPrivilege/gleaner/blob/6a95aad5cc80593680360f875ab61fe2a70f9205/docs/research/2026-10-17/reports/cli-schema/04-logical-object-options.md): file-first, delivery-first and reversible relationship overlays; role/project equality counterexamples; path reuse and branching versions. Main now implements user joins, but does not thereby adopt persistent section/message objects or all proposed relations.
- [Provenance proposal register](https://github.com/lesPrivilege/gleaner/blob/6a95aad5cc80593680360f875ab61fe2a70f9205/docs/research/2026-10-17/reports/provenance/research/11-proposals-and-opus-handoff.md): natural evidence selectors, narrow reconstruction, identity candidates and explicit resolver outcomes. These are registered research, not a prescribed graph schema or generic workflow engine.
- [26-task benchmark protocol](https://github.com/lesPrivilege/gleaner/tree/6a95aad5cc80593680360f875ab61fe2a70f9205/docs/research/2026-10-17/reports/benchmark/deliverables): useful unimplemented task families include explicit continuity/derivation, independent bundle members, contradictory tool results, authored authority and uncertain recovery. Re-label against current capabilities rather than copying old exclusions.

## Contracts, experiments and drift

| Evidence | Status at current main | Consequence for convergence |
|---|---|---|
| [SPEC](../SPEC.md), [projects-and-works](../design/projects-and-works.md), [review](../design/review.md) | Current contracts with explicit supersession and as-built additions | Preserve evidence/capture/correction separation, project/work distinction and independent byte-bound review/published state |
| [Original rulings](../design/rulings.md) | Adopted historical choices; manual-filing deferrals explicitly superseded by projects-and-works, then collections in review | Do not revive the obsolete “no grouping beyond projects” boundary; automatic identity remains unadopted |
| [Capture](../design/capture.md) | Layered contract and as-built sections, followed by review layer 3 | Observation is not delivery or authorship; live capture and written-by evidence remain future layers. Early layer text that says candidates are not yet in the window is historical |
| [Query core](../design/query-core.md), [MCP adapter](../design/mcp-adapter.md) | Implemented shared surface; opening text still refers to the old branch/release order | `outline`, content search and pagination are explicitly outside that contract. New prototype operations require an intentional amendment, not silent acceptance |
| SPEC §3 says MCP deferred | Documentation drift after `ad697a5` merged MCP | Report the contradiction; executable targets, adapter and wire tests establish code presence. Do not reopen release or merge gates to resolve wording |
| [Control-panel](../design/control-panel-explorations.md), [project editorial](../design/project-knowledge-explorations.md), [architecture precedents](../design/architecture-precedents.md) | Explorations and mechanisms, not a cumulative feature checklist | Minimal reduction was selected; briefs/dossiers/generated summaries were declined or left research. They can inform comparisons without becoming implementation requirements |
| [Library HTML prototype](../design/library-prototype.md), [source artboards](../design/prototype/project/) | Public illustrative source; original private hosted URL is not needed or accessed | Three artboards refer to absent `support.js`; prior notes disclaim rendered validation. Old status/action examples can be superseded by later exact-byte rulings. Do not treat them as current UI acceptance |
| [E0 design](../design/evaluation-e0.md) and [recorded results](../../eval/results/2026-10-18/report.md) | Executed historical scripted evaluation on macOS at `7611cf5`, not rerun here | Both policies scored 150/150; catalog arm read fewer bytes but was slower including and excluding preparation. Same task templates across seed splits limit generalization. Current authored-state/bundle support postdates old exclusions |
| This delivery branch's portable/core/API code | In-progress prototype outside the mapped baseline | Preserve for review. Presence or passing tests does not select architecture or amend the product contract |

## Next research decision

Choose the concrete missing retrieval unit and task before further API expansion: **(a)** broad discovery of useful observed files, **(b)** locating report sections/message-backed findings with exact parent context, or **(c)** following explicitly linked work through revisions. Compare these using current shared search and current corrections/review semantics. The branch record already settles that CLI/MCP should share the core; it does not settle logical section identity, inferred relations, ranking or the best human presentation.

Reproduction: `git ls-remote --heads origin`; `git for-each-ref --format='%(refname:short) %(objectname) %(subject)' refs/remotes/origin`; for each branch, `git merge-base --is-ancestor <branch> origin/main`, `git rev-list --left-right --count origin/main...<branch>`, and `git diff --stat origin/main...<branch>`. Read historical files with `git show <revision>:<path>` so local prototypes cannot contaminate the baseline.
