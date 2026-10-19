# Convergence checkpoint handoff

Start with [CONVERGENCE.md](docs/retrieval-core/CONVERGENCE.md): intent → public
declaration → implementation matrix, superseded decisions, experiments versus
owner rulings and recommended next questions. This checkpoint follows the later
user instruction to digest and reconcile before formal build. It is **not** the
completed useful-object goal, an accepted architecture or a release candidate.

## Revisions and preserved work

Delivery branch: `cloud/gleaner-retrieval-core-20261019` in
`https://github.com/lesPrivilege/gleaner`. Base fetched and rechecked:
`2648094610facfd1ae1805f52a9de282043c808f`. Old query branch:
`cdfe6f4e0ba473ba12309b310018734244efc37c`, already merged into main.

| Checkpoint | Purpose |
|---|---|
| `b4fdad1` | Early goal spec and resume notes |
| `2d6319b` | Linux execution experiment; exact baseline portability patch |
| `7cb1983` | Locator syntax prototype, extraction-only evidence |
| `44624ba8ed9c189fe903710d16f0b4f534ef8c0e` | Project/outline/section/pagination prototype; exact implementation benchmark revision |
| Branch tip | Convergence report, independent review, fixture/results preservation and this handoff |

No main merge, tags/releases, workflow enablement, credentials or personal author
identity changes. Author and committer are repository-local
`GPT Task <gpt-task@example.invalid>`. The unrelated mounted repository was left
untouched and was not mounted into the execution container. Only public-source
notes, synthetic tests/results and implementation are included.

## What the checkpoint establishes

- Main already has shared app/CLI/MCP search and headless indexing. Eleven of
  thirteen non-main remote branches are integrated. The unmerged structure and
  research branches contain reuse material, not missing architecture to merge.
  [BRANCH-MAP.md](docs/retrieval-core/BRANCH-MAP.md)
- Current contracts deliberately keep observed candidates unsearched until kept,
  and remain file/work-centric. Broader useful discovery and logical findings
  require an explicit scope decision. Native event preservation is partial;
  tool-call evidence is not a complete graph. [Independent review](docs/retrieval-core/CONVERGENCE-REVIEW.md)
- Current search finds project-parent context; the known historical failure is
  not a fresh baseline miss. Same-request noise, body-only finding queries and
  vocabulary mismatch remain. More captured names alone is not better selection.
- Byte-pinned report sections work as a bounded experiment. They do not make
  message findings globally searchable, infer rulings, or solve cross-report
  lineage. Generation guards are not consistent snapshot pagination.

## Executed evidence

[Evaluation README](eval/retrieval/README.md) gives commands, task labels, limitations
and links to all machine-readable results.

- Actual main plus identical portability patch versus actual prototype, no second
  retrieval algorithm. Development intended index membership **13/40 → 40/40**;
  usable-exact-version tasks **3/8 → 4/8**. The gain is dominated by proposed explicit
  range syntax; not a general recall estimate.
- Independent 12 CLI scenarios per revision, no runner errors, with first-layer
  precision, scope, versions, originals and effort separate. No production tuning
  from held-out outcomes. Same-request first-five precision remains **1/5**.
- Independent folder discovery **6/6**, but first-page exact original availability
  **0/5** in both: `listed` captures are not completed by read-only Catalog.
- Four independent Swift invariants pass on each revision. Extractor-only smoke
  **4/10 → 10/10** is syntax feasibility, not retrieval usefulness.
- Full portable baseline **306/324 passed**; final prototype plus held-out tests
  **328/346 passed**, the same **18 failures / 25 issues**. All added tests and
  CLI/MCP checks pass in this boundary. See [PORTABILITY](docs/retrieval-core/PORTABILITY.md)
  and [results](docs/retrieval-core/portable-test-results.json).
- Current official MCP research is recorded, but the prototype retains SDK
  0.12.1's legacy negotiated protocol; no claim of latest-protocol support.
  [Sources](docs/retrieval-core/SOURCES.md), [RAG mechanisms](docs/retrieval-core/EXPLORATION.md)

No Finder comparison, human-effort trial, broad-scale run, semantic-model arm,
native UI/FSEvents/APFS validation, or release check was executed. Those are
unperformed work, not passes or hidden blockers.

## Prototype boundaries before any adoption

1. Extraction semantics changed without bumping `Registry.extractorVersion` (20).
   Use fresh synthetic registries only. A production change requires explicit
   migration/rederivation review and preservation checks, not opening a real
   library with this experimental branch.
2. Capture's public design replaced case-fitting range proposals. Keep relative
   folder/glob/NUL corrections separable from range expansion when deciding scope.
3. `projects`, `outline`, `section`, offset/generation options and the new 1,000
   `find` limit extend previously deferred contracts. They are provisional APIs.
4. Linux shims preserve unknown creation dates and exclude native presentation /
   watcher code. They are validation infrastructure, not Linux product support.
5. Shared search ranking, automatic identity joining, model assistance and review
   semantics were not changed. Ambiguous relative paths and natural-language
   shorthand remain unresolved, with no broad scan or shell expansion fallback.

## Resume and next handoff

Read the convergence report, branch map and independent review before adding code.
The next coordinated discussion should settle: searchable observation tiers;
navigation passage versus persistent finding identity; selective first layer;
exact-current versus exact-historical agent access; and evidence-authorized
relationships. Then select small experiments and formal implementation priority.
The matrix also incorporates the parent's refined requirements: five distinct
current-state meanings, durable scoped names, explicit reset semantics, and shared
human/agent semantics. Historical command/storage/model proposals remain options.
Final product and visual rulings remain with Opus; private conversation recall is
the parent's separate responsibility.

Cloud checkout: `/workspace/gleaner-cloud`. Baseline worktree:
`/workspace/gleaner-baseline`. Persistent container: `gleaner-swift`, Swift 6.2.4.
Only these checkouts and synthetic evaluation directory are mounted. Recreate from
PORTABILITY.md if the environment is lost; committed sources/results are sufficient.

Before formal acceptance, request an authorized Mac validation handoff through
the parent, on a separate checkout and synthetic home: run native `swift test`,
then the same labeled CLI/MCP cases; check creation dates, case aliases, packages,
permissions, FSEvents and Markdown behavior. Later native user-flow testing covers
selection, current-vs-delivered captions, Quick Look, drag and accessibility. No
signing, notarization or release action is requested here.

Existing `.github/workflows/test.yml` runs `swift test` on `macos-26` for each push
and PR. The checkpoint push triggers that normal test job; no other automation is
enabled. Remote delivery and any observed CI outcome are reported in the final
checkpoint response rather than inferred from a local commit.
