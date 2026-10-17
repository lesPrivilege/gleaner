# Source atlas: identity, catalogs and schema research

Logical identity, representation, provenance and query context are separable concerns. These sources support those distinctions. They do not determine Gleaner's object boundaries or prove that a richer schema is worth its maintenance cost.

## Open Containers Initiative: identify content without equating it to a work

**Works:** an Open Containers Initiative (OCI) descriptor carries media type, digest and size; consumers can verify referenced bytes. [Versioned descriptor specification](https://github.com/opencontainers/image-spec/blob/v1.1.1/descriptor.md).

Adapted shape, illustrative values:

```json
{"mediaType":"text/markdown","digest":"sha256:…","size":4096}
```

**Transfer:** a small exact-content reference is enough for verification and transport. Add Gleaner's delivery/capture context because digest equality cannot distinguish separate roles, projects or intentions. Do not import container manifests or registry infrastructure just to use this pattern.

**Context:** a mature industry specification; the linked release is a semantic reference, not a recommendation to add an OCI library. Gleaner already has SHA-256 content storage.

## DCAT 3: logical resource, distribution and version are different

**Works:** the W3C Data Catalog Vocabulary models datasets separately from distributions and access services. Version relationships can connect an abstract resource with particular revisions. [Original recommendation](https://www.w3.org/TR/vocab-dcat-3/).

**Transfer:** “the report”, “this revision” and “this PDF” can be separately addressable without confusing filename, content hash or access URL. A stable logical ID can coexist with multiple concrete representations.

**Boundary:** DCAT describes catalogs; it does not infer that two files represent the same work. Its version semantics need local interpretation for delivery events. A thin JSON projection may use the distinctions without adopting RDF, an ontology or a new database. Formal metadata is useful only when maintained and relevant to retrieval.

## PROV-DM: distinguish evidence, activity and attribution

**Works:** PROV's data model separates entities, activities and agents, and provides derivation, attribution and specialization relations. A time-specific page can specialize a more general page identity. [Original recommendation](https://www.w3.org/TR/prov-dm/).

**Transfer:** the bytes observed, the delivery event and the actor asserting a relationship should not collapse into one object. Record whether a link is source-asserted, observed or user-confirmed. Preserve where the assertion came from.

**Boundary:** a provenance relation is a claim to represent faithfully, not proof of truth. Gleaner need not implement the complete PROV vocabulary; delivery/capture provenance is narrower than an enterprise lineage graph.

## Zenodo: concept, record and files are separate addresses

**Works:** its documented API distinguishes `conceptrecid`, individual record IDs and files. File metadata includes checksum, size and version ID. Deposit listing supports `all_versions`, page and size controls. [Official API](https://developers.zenodo.org/).

Adapted read request pattern from the deposit API (requires appropriate access; not executed):

```text
GET /api/deposit/depositions?all_versions=true&page=1&size=10
```

**Transfer:** a discovery address and an exact version reference can differ. An artifact may involve several files, each independently described. An agent handoff should identify selected bytes rather than pass only a mutable concept address.

**Boundary:** research publication deposits are explicitly curated; local delivery logs are noisier. It does not imply publishing, minting Digital Object Identifiers (DOIs), or adopting Zenodo.

## DataHub: governed metadata can survive ingestion

**Works:** entities have keys and metadata aspects; schema definitions drive ingestion, serving and indexing. [Official model](https://docs.datahub.com/docs/metadata-modeling/metadata-model). The tagged [DatasetKey](https://github.com/datahub-project/datahub/blob/v1.6.0.3/metadata-models/src/main/pegasus/com/linkedin/metadata/key/DatasetKey.pdl) separates a platform-qualified key from display properties. Most directly useful: [EditableSchemaMetadata](https://github.com/datahub-project/datahub/blob/v1.6.0.3/metadata-models/src/main/pegasus/com/linkedin/schema/EditableSchemaMetadata.pdl) keeps human changes apart from ingested schema metadata and includes change audit stamps.

**Transfer:** if a user corrects project affiliation or logical identity, keep that correction separate from extractor-owned fields so a rescan does not erase it. Typed facets can add retrieval value incrementally without replacing the underlying evidence.

**Boundary:** Gleaner currently has no such correction workflow. DataHub's enterprise catalog, services and full metadata model would be disproportionate dependencies. **Context:** Apache-2.0; release activity includes `v1.6.0.3` and `v1.8.0rc5`. [Repository](https://github.com/datahub-project/datahub), [releases](https://github.com/datahub-project/datahub/releases).

## Agent2Agent: task artifacts are not global artifact identity

**Works:** the Agent2Agent (A2A) protocol distinguishes task/context IDs, produced artifacts and their content parts. An artifact ID is unique within its task. Agent Cards advertise capabilities; file parts can refer to content by URL. [Original specification](https://a2a-protocol.org/latest/specification/).

Adapted artifact fragment using the inspected specification's fields:

```json
{"artifactId":"a1","name":"report.md","parts":[{"url":"https://example.invalid/report.md","filename":"report.md","mediaType":"text/markdown"}]}
```

**Transfer:** an exact handoff needs scope and a retrievable representation. Preserve a task-scoped artifact identifier together with its producer/task namespace; do not treat it as globally unique.

**Boundary:** A2A addresses remote agent collaboration, not persistent cross-session artifact lineage. A local path is not a transferable remote reference. Gleaner need not adopt A2A for two local agents to call the same CLI. No remote transfer was attempted.

## Rahm and Bernstein: schema matching is a correspondence problem

**Work:** Erhard Rahm and Philip A. Bernstein, *A survey of approaches to automatic schema matching*, The VLDB Journal 10, 334–350 (2001). [Publisher original, DOI 10.1007/s007780100057](https://link.springer.com/article/10.1007/s007780100057).

**Substantiates:** the paper organizes matching approaches by schema versus instance evidence, element versus structure, and linguistic versus constraint evidence. The inspected publisher abstract supports those distinctions; full text was not available there.

**Transfer:** names, shape, content and surrounding relationships are different evidence signals. A matching suggestion should show its basis and remain correctable.

**Boundary:** schema correspondence is not artifact identity. This survey does not establish that similar documents are revisions, that modern models can infer reliable lineage, or that Gleaner needs an automated matcher. It provides vocabulary for evaluating a future suggestion system.

## Buneman, Khanna and Tan: why a result exists versus where a value came from

**Work:** Peter Buneman, Sanjeev Khanna and Wang-Chiew Tan, *Why and Where: A Characterization of Data Provenance*, ICDT 2001. [Author-hosted paper](https://homepages.inf.ed.ac.uk/opb/papers/ICDT2001.pdf), [publisher DOI](https://link.springer.com/chapter/10.1007/3-540-44503-X_20).

**Substantiates:** it distinguishes source data influencing a query result's presence from source locations supplying a value, using a formal model of query-derived data.

**Transfer:** explain why a delivery matched separately from where its excerpt/content came from. A result can identify matching fields, while a content range points to a capture and exact location. Corrections need the latter, not only a relevance score.

**Boundary:** this is database-query provenance research, not a model for attributing generated natural-language claims or evidence that an assistant's account is correct. Gleaner can adopt the distinction without the formal query calculus.

## Curino, Moon and Zaniolo: schema evolution affects clients, not just storage

**Work:** Carlo A. Curino, Hyun J. Moon and Carlo Zaniolo, *Graceful Database Schema Evolution: the PRISM Workbench*, Proceedings of the VLDB Endowment 1(1), 761–772 (2008). [Author-hosted original](https://www.cs.ucla.edu/~zaniolo/papers/prism-vldb2008-cameraready.pdf), [publisher record](https://doi.org/10.14778/1453856.1453939).

**Substantiates:** Schema Modification Operators make changes explicit; the system addresses data migration, old-query rewriting and evolution history. Its scope is relational schema change under stated operator semantics.

**Transfer:** distinguish public result-schema version, storage migration version, extraction-rule version and artifact revision. Test old references and clients after changes. A rename/split of a semantic object has consequences beyond changing a label.

**Boundary:** this is a research system, not a maintained dependency recommendation or proof that arbitrary migrations are reversible. Gleaner's scale may need only explicit migrations and compatibility fixtures. The paper's ambitions should not become a requirement list.

These works do not prescribe a universal “schema engineering” method. Choose distinctions by retrieval benefit and correction/migration cost.
