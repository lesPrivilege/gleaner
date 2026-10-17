# Decisions for local Opus

The five streams support a bounded experiment in reliable artifact consumption. They do not select a future architecture or expand the v0.1 release contract. Start with the [release audit](../reports/release-audit/report.md) for current defects and the [native acceptance work](../reports/release-audit/native-acceptance.md) that remains to be run on macOS.

## Architecture choices

| Option | Smallest useful form | Tradeoff to test |
|---|---|---|
| Expand the existing command-line interface (CLI) | Structured project/delivery discovery, explicit revision selection and bounded reads | Easy shell composition; requires discoverable help, stable output/error contracts and read-only registry access |
| Add a thin Model Context Protocol (MCP) adapter | A few tools over the same queries; resource links/templates where the chosen host supports them | Host discovery can improve access; adds protocol lifecycle/version negotiation and host-specific behavior |
| First establish a shared query/read core | Project → delivery → observed version → section/evidence read → exact handoff | Prevents transport semantics diverging; needs only the operations justified by selected tasks |

The [CLI/schema stream](../reports/cli-schema/01-synthesis.md) favors a small shared surface, exposed through whichever real client is easiest to evaluate. This is a recommendation, not an adopted dependency or a mandate to implement both transports. Existing captures, original filenames and explicit version semantics should carry through every path. Navigation metadata, factual previews and actual content have different costs and evidentiary value.

## Where the streams qualify one another

- **Progressive access is established practice.** The [nearest-neighbor review](../reports/prior-art-novelty/02-comparison-matrix.md) identifies Cass, AgentsView, Obelisk and research retrieval interfaces as necessary comparators. A narrower hypothesis is declaration-gated artifact selection and version-correct handoff under incomplete evidence. Absence of an exact match does not prove novelty.
- **Exact bytes and historical association differ.** The [provenance feasibility matrix](../reports/provenance/research/06-reconstruction-feasibility.md) separates a declaration, intended write, execution report, observation, conditional reconstruction and delivery binding. This reinforces the CLI stream's requirement to preserve late-observation status. A hash alone supplies neither logical identity nor historical delivery proof.
- **Logical identity remains optional research.** The [identity alternatives](../reports/cli-schema/04-logical-object-options.md) compare path-first, delivery-first and reversible logical-object views. The [provenance model](../reports/provenance/research/05-minimal-model.md) sketches richer assertions and authored decisions. Its conceptual breadth is not a requirement for the first read interface. No new database or ontology is demonstrated necessary.
- **Measured evidence is narrow.** The CLI stream's deterministic policies returned 4,885 catalog bytes versus 5,967 for competent targeted section reads in ten synthetic tasks. Its shared resolver and enriched fixture constrain inference. The separate [26-task protocol](../reports/benchmark/deliverables/01-claims-and-design.md) is a design, with only ten fictional contract checks executed. Neither establishes model token savings or real-user efficacy.
- **Protocol dialects and access depth stay explicit.** The prior-art atlas cites MCP 2025-06-18; the CLI stream separately inspects the 2026-07-28 specification and Swift SDK documentation for 2025-11-25. These are different evidence targets, not interchangeable compatibility claims. The provenance stream found full schema-matching paper text where the CLI stream recorded more limited access; preserve both access records.
- **Retrospective provenance is prior art.** Git2PROV, YesWorkflow and possible-provenance research constrain broad novelty claims. Provider checkpoint documentation does not establish retention or recoverability for a particular user's session. No provider runtime or private account was tested.

## Open choices and optional experiments

1. Pick the first consumer and one primary job: locate the right delivery, select exact bytes, compare versions, or continue another agent's work. Use a concrete host/runtime when testing MCP.
2. Define the declaration's audience and event boundary. Keep inventory admission distinct from query ranking, and measure useful artifacts the gate excludes.
3. Decide what a public identifier promises across project moves, worktrees, reindexing and source rewrites. Preserve ambiguity and reversibility before adding automatic cross-path links.
4. Test find → inspect → bounded read → exact handoff on identical inputs with a strong raw-search baseline. Include stale pointers, missing originals, reused paths, equal-content distinct objects and partial scans. Charge index preparation and updates.
5. Separate the benefit of an index from newly preserved evidence. Raw and catalog arms must receive the same captures and authored records within each information condition. Use independent labels and retain failed or unanswerable episodes.
6. If reconstruction becomes a real job, start with immutable Git bytes or a complete base plus a narrowly defined exact edit. Require an assumption/coverage report and abstention; never replay arbitrary historical commands.

Direct code and session reading remains necessary for implementation questions, causal explanations absent from the catalog, unsupported formats, disputed extraction and incomplete coverage. Retrieved text is evidence to inspect, not instructions to execute. A catalog miss supports only a negative statement within its checked scope.

The next implementation, real-data corpus, model budget, authored-governance policy and enterprise permission work remain decisions for Opus and the user. Publication of these reports adopts none of them.
