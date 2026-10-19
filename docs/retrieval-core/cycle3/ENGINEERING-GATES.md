# Engineering gates before adopting a retrieval slice

These are contract examples and acceptance conditions, **not newly executed tests**.
They turn observed gaps into obligations without choosing a default discovery or
clarification policy. [EVALUATION](EVALUATION.md) and [CORRECTIONS](CORRECTIONS.md)
contain the actual executions.

## 1. Declare discovery scope before measuring recall

Declare wanted logical objects and the authorized source universe before filtering
to admitted Works. Report end-to-end discovery/task recall and within-index matching
separately. An unadmitted wanted object cannot disappear from the task denominator
merely because shared search excludes it. Nor does counting every cache file improve
task coverage. Partial or unobserved scope stays unknown, with coverage stated.

| Synthetic task example | Required interpretation |
|---|---|
| An observed, unkept analysis notebook is the wanted intermediate | Observation proves discovery, not explicit delivery. Current Work search excludes it. A delivery-only result can be correct within that declared scope while broader task retrieval remains incomplete. A broader mode must retain evidence type and authorization. |
| A current report exists under an authorized project but was created after the completed scan, with no delivery | Directory access can find it; the old index cannot establish absence. Record freshness/admission and current-file task failure separately from ranking. No scan beyond authorized roots is implied. |
| One human-joined Work contains an approved field rendition and a later unreviewed text rendition | Work discovery can be 1/1 while approved-representation selection is 0/1. Reaching approved bytes by leaving the result constraint does not complete the approved task. |

The default universe is an Opus choice. Implementing its declared scope faithfully,
exposing health and using honest denominators are engineering requirements.

## 2. Define representation and byte-state candidates

`Cycle3Selection` checks only the query-matched capture's hash through
`Review.standing`; it does not search other joined representations for approved
captures. Before adopting approved retrieval, distinguish **filter the matched
captured rendition** from **find a qualifying rendition/version in a matched Work**.
The latter must enumerate its permitted representation/version candidates; marking
the whole Work approved is insufficient.

A state-qualified result must identify Work, representation/path, delivery/version,
captured hash and capture provenance, plus the verdict or publication record on
those exact bytes. Preserve native matching context if another rendition is chosen.
Unknown bytes, a superseded verdict or a later unreviewed rendition cannot inherit
approval. Approved capture does not mean current disk or authoritative working
version. Qualifying alternatives must be explicit and bounded.

Example: field.pdf has approved hash A and later.txt has unreviewed hash B in one
accepted Work. An approved-rendition operation must return the A/version/review
reference or a truthful availability failure for A. Returning B, reporting an empty
selection as success, or recovering A only outside the constraint fails that task.
No new state ontology is required.

## 3. Verify the current bytes actually returned

Physical-path native tests do not prove compatibility with core-shortened `/var`
aliases or safe internal symlinks. Define authorized root identity and alias
handling before adoption. Authority comes from application/caller authorization,
not log cwd, tool arguments or source text. Preserve scope checks, bounded I/O,
descriptor identity and mutation refusal; an alias must not expand authority.

The prototype returns hashes/metadata, not content. A content operation must return
bytes from the same verified descriptor read. Specify whether each hash covers the
whole observed file or the returned span, with input-I/O and output bounds enforced
separately. A later path open cannot borrow an earlier hash's guarantee.

## 4. Bound full responses and continuation

A selected-row limit does not bound raw/eligible/deferred/unmatched arrays, reason
maps, representations, context overview or serialized bytes. Define per-response
budgets and separately bounded representation/history expansion. Counts or summaries
must not imply complete enumeration if the source or computation was truncated.

Continuation must bind the library, query/scope and relevant ordering state. If
indexing, corrections or reviews change results, either preserve a stated snapshot
or return a stale-continuation outcome and restart rule. Applying an old offset to
a changed result must not silently skip or repeat objects. Current generation guards
do not establish that contract; arbitrary cursor continuity remains untested.

Report-ID access must also cap input bytes, heading/occurrence allocation and emitted
ranges, and parse/verify once per request. A small page is not a resource bound if
each heading or page repeatedly reparses the source. Bind report continuation to
exact version/hash; distinguish truncation from no matching identifier.

## 5. Prove migration separately from rereading

The correction experiment preserves native observations, spans and captures while
reconstructing log projections. Its retained folder listing/member tables are empty.
Migration claims need nonempty delivered-folder history, missing originals, durable
reviews/corrections, changed identity anchors and interrupted/restarted migration.
Preserve evidence that cannot be recreated from today's filesystem. Fixed-after-join
IDs in these tests do not prove arbitrary move/join identity stability.

The extraction prototype leaves `Registry.extractorVersion` at 20. Adopting changed
extraction requires reviewed version/rederivation and durable-state checks; the
missing bump is an adoption blocker, not a presentation choice. Neither safe
projection reconstruction nor native unit tests establish cursor continuity or
real-library migration safety.
