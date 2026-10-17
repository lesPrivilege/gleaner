# 10. Personal-local and enterprise permission boundaries

These are architectural requirements to investigate, not a claim of compliance or a deployment proposal. The provenance itself can disclose sensitive information. [Cheney and Perera's survey](https://arxiv.org/html/1405.5777) explains why redaction and abstraction can also damage the meaning of a provenance account; hiding nodes is not enough to guarantee a truthful or confidential explanation.

## Two operating environments

| Concern | Personal-local catalog | Enterprise/shared catalog |
|---|---|---|
| Source scope | User-selected directories/accounts and explicit local read scope | Tenant, connector, source identity, group/role membership and source-level policy |
| Search discovery | Local owner normally sees their authorized index | Titles, filenames, snippets, counts, facets and candidate existence must be policy-filtered |
| Evidence access | Opening the original can be checked with local permissions; stored copies need their own policy | Every evidence unit, derived assertion, attachment and representation needs a disclosure decision; service-account ingestion is not end-user authorization |
| Cached content | User-controlled storage/retention; clear indication if a copy survives deletion of original | Tenant isolation, encryption, retention/purge policy, revocation handling, authorized backups and export controls |
| Review authority | User decision for an explicit representation/purpose | Actor identity, role at decision time, delegated authority, scope, expiration/revocation, separation of duties if required |
| Audit | Local correction/observation history | Access and change audit with controlled visibility and retention; audit logs themselves contain sensitive metadata |
| Unknown policy | Explain inability to read; retain only allowed metadata | Deny or present a deliberately coarse result; avoid leaking whether a restricted object exists |

The distinction is not simply “local safe, cloud unsafe.” A local snapshot can contain secrets, removed client data, or material the user may no longer share. A shared source can have careful isolation. Decide policy for concrete principals, sources and uses rather than deployment labels.

## Source-aware disclosure

Store opaque source-policy references and provenance of permission observations; avoid materializing broad user/group lists into every artifact row. Check access when resolving or disclosing sensitive metadata, including autocomplete, counts, graph edges, inferred candidates, error messages, search snippets, exports and previews. Filtering after retrieving and summarizing unauthorized data is too late.

For a claim derived from multiple restricted sources, a conservative initial policy is to require authority to disclose every relevant support, unless a separately authorized declassification or safe aggregation policy exists. Do not invent a universally correct intersection rule: legitimate workflows may permit publishing an output while restricting its inputs. Model that as an explicit publication/disclosure decision with its basis.

If details must be hidden, say only what policy allows about incomplete provenance. Do not manufacture a direct causal edge across hidden steps unless that abstraction's semantics are explicit. A public derived artifact does not automatically make its source filenames, author identities, credentials, business relationships, or transformation parameters public.

## Permission time and retention

Separate: permission to collect at time T1; permission to retain; permission to display now; permission to share with a destination; and historical approval of a representation. Revoking source access may require suppressing cached evidence even though the observation remains historically true. Deleting a source may mean intentional removal, retention expiry, lost access or a transient outage; those have different retention consequences.

A future resolver should record policy freshness and invalidate cached decisions when source membership, classification or account state changes. Where revocation signals are unavailable, define a bounded revalidation policy and its residual risk. Never claim instantaneous source-permission equivalence unless the connector and enforcement path actually provide it.

Snapshots need explicit treatment: automatic cache eviction must not silently erase the only preservation copy a user elected to keep; preservation intent must not override source restrictions. Tenant-wide deduplication can leak equality across access boundaries, so do not expose shared hashes or deduplication behavior across principals without a justified design.

## Evidence minimization

Capture only evidence necessary to support a claim. Retain source pointers and verified minimal excerpts where possible; make full transcripts optional and policy-bound. Redaction is a derivative representation with a redaction rule/version and known loss of detail. Secret-shaped-string detection alone is not a confidentiality guarantee: ordinary paths, titles, prose and hashes can disclose sensitive facts.

Keep authored corrections and approvals separately from disposable indexes, but allow policy-governed redaction/tombstoning when indefinite retention is not permitted. “Append-only” does not require public permanence of personal content. Preserve an audit of the redaction operation to the extent allowed, without retaining the prohibited material in the audit reason.

## Personal-local first experiments

The next safe research step is a synthetic or explicitly consented local corpus, restricted to selected sessions and their referenced files. Run parsers against copies, prohibit implicit network retrieval, disable side-effectful replay, and record acquisition limits. Assess what minimum evidence improves retrieval without collecting whole conversations unnecessarily.

Enterprise work should wait for a real source with real policy semantics and representative revocation cases. A second coding-agent provider only tests a decoder boundary. A second domain, such as an actual approved document-export workflow with its own ACLs and approval semantics, can reveal which identity/evidence/resolver abstractions are reusable. It must be a genuine partner use case, not an invented justification for a platform.
