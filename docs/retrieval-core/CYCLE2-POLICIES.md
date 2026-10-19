# Cycle 2: isolated retrieval-policy experiments

These are competing development experiments, not product defaults or ratified object types.
The `GleanerRetrievalExperiments` target depends on `GleanerCore`; shipped core, app, CLI/MCP
defaults and storage schema do not depend on it. The root experiment runner/evaluator owns
workload labels and measurements, separately from these policy unit tests.

## First actionable layer

`FirstLayerPolicies.evaluate` obtains candidates and order only from `Organization.search`.
Its named-tier flag calls the same public `Artifact.isNamed` predicate with the same project and
collection context that the shared search uses. Project scope takes an existing project key.

| Alternative | First layer | Recoverable remainder | Open tradeoff |
|---|---|---|---|
| `baseline` | Existing named-first order, one work per card | Remaining matches in order | Useful context-only matches compete with co-delivery noise |
| `named_focus` | Only named matches when any exist; otherwise baseline | All omitted matches, including contextual intermediates | A wanted supporting document may need an extra broadening step |
| `native_reply_groups` | Groups by project, provider, session, log and reply line | Remaining groups' members | Fewer cards can hide more choices and require expansion |

Every result returns `allMatches`, `firstLayer`, and `deferred`, so exhaustive reachability can be
measured separately from first-layer wanted-object precision/recall. A reply group has members
and an anchor; it has no automatically authoritative representative. Unknown reply anchors and
kept observations stay singleton work cards. Equal timestamps never cause grouping. No extension,
filename such as “scratch,” cache label, hash equality or inferred completion state suppresses a
match. Tests deliberately retain a context-only appendix that focused presentation defers.

## State intent

`StatePolicies.evaluate` uses existing `Work`, `Reviews`, `Present` and `Review.standing` values.
It performs no filesystem reads or writes and does not make a stale observation current.

- `newest_delivery_control` deliberately selects the newest recorded delivery regardless of the
  requested state. It remains labeled as a delivery fact, exposing why this is an unsuitable
  general substitute for working/reviewed/published state.
- `explicit_intent` chooses the requested fact, including an explicit unknown when unavailable.
- `disclose_all_states` returns all facts and selects none. Any extra user/agent choice is part of
  the measured interaction cost; disclosure alone is not task success.

The intents distinguish current original, current working, last delivery, last review verdict,
and last publication. Current original needs a caller-selected member path and its observation.
Metadata-only `Present.listed` never supplies a hash. “Current working” always remains unknown
because the current core has no explicit working-state marker. It is never inferred from latest,
approved, published, timestamp overlap or an original's existence.

Last delivery excludes kept observations but retains folder-member evidence separately from
explicitly named files. Capture provenance accompanies its hash, so a later observed hash cannot
silently become delivery-time evidence. A latest review may request changes or reject; publication
is not approval. Review and publication standing on current bytes comes from `Review.standing`,
with no automatic carryover. Historical state selection does not establish current availability.

## Report-local identifier lookup

`SectionLookup.evaluate` pages through the existing `Catalog.outline` of one verified version.
`title_substring` delegates its terms to that core API. `exact_identifier` compares the heading's
first lexical token (letters, numbers, underscore and hyphen) case-insensitively. This convention
distinguishes R1 from R10 while leaving repeated R1 headings as multiple exact byte-scoped IDs.
It intentionally does not infer IDs embedded in prose or formatting, global finding identity,
cross-report relations or communicated rulings. Punctuation-heavy identifiers need a future
explicit convention; this small experiment does not establish a full identifier grammar.

## Reproduction

The runtime was directly checked using `docker exec gleaner-swift runuser -u gleaner -- swift
--version`: Swift 6.2.4 (`swift-6.2.4-RELEASE`), `x86_64-unknown-linux-gnu`. Prior commentary naming
Swift 6.0.3 was incorrect; the checked runtime and run records use 6.2.4.

```sh
docker exec gleaner-swift runuser -u gleaner -- swift test -j 4 \
  --filter 'RetrievalPolicyTests|ExperimentalSectionLookupTests'
```

The first compile attempts stopped in the package manifest's type checker before policy code
compiled; those attempts are not test failures or passing runs. Measured policy comparisons and
held-out results belong in their separate machine-readable evaluation reports, not in source
inspection claims. Current-original path/stat/hash comparisons are owned by the separate
`OriginalResolutionExperiment` in this development target.
