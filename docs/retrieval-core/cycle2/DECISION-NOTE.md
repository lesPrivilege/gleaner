# What the second cycle settles

There is enough evidence for a bounded implementation proposal for explicit current
original access and report-local identifier lookup. There is **not** enough evidence
to replace the first-layer selection policy. State separation is an existing contract,
not an ontology proposal awaiting a new ruling. All code in this cycle remains in an
experimental target; this note does not adopt product behavior.

Evidence: [independent evaluation](EVALUATION.md), [development measurements](development-results.json),
[methods](METHODS.md), [native diagnosis](NATIVE-FAILURES.md). Main remains
`2648094610facfd1ae1805f52a9de282043c808f`. No schema, provider adapter or shipped
app/CLI/MCP implementation changed after checkpoint `7e004a7`.

## Selection and effort

In the controlled nine-object development package, named focus changes expanded
first-layer precision from 1/5 to 1/1 when the wanted specification's name matches.
The baseline already returns that specification first: this is a noise reduction,
not improved task success. Project-context and request-only queries remain 0/5.
Reply grouping puts all nine objects in one group, recovering the wanted member
but yielding 1/9 member precision and another selection. A ten-object design package
similarly becomes one group containing two wanted outputs and eight helpers.

The independent set establishes a decisive counterexample: a named companion guide
causes focus to hide the wanted editable deck. First-layer recall falls from 1 to 0;
broader retrieval still contains the deck. The same policy improves booklet and CSV
tasks. It therefore cannot become a universal default on this evidence. Reply groups
preserve native anchors and candidate reachability, but neither improve object
identity nor demonstrate smaller payloads. Fewer groups must not be reported as
fewer irrelevant objects. A first-layer group limit does not bound its member list
or `allMatches` payload; a production adapter would need separate bounded expansion.

**Proposal:** keep existing shared candidate generation and work identity. If a
focused tier is explored in presentation, make the recoverable remainder explicit
and measure whether users discover it. The next ranking experiment should target
the demonstrated unnamed-but-useful counterpart and project-context noise, using
declared task intent and existing evidence fields. Compare a small deterministic
rerank before introducing an FTS migration. This cycle does not compare BM25 or
semantic retrieval and supplies no reason to require a model.

## State and current original

Independent explicit-intent selection gets 20/20 requested state facts correct;
disclosure preserves the same facts with a selection step. The deliberately naive
newest-delivery control gets 4/20 and is **not** main's baseline. Current bytes at a
selected locator, last recorded delivery, last review verdict and last publication
remain separately evidenced. Rejected review is still a review. A later capture
cannot become delivery-time evidence, and a listed child remains folder-member
evidence rather than an individually named handoff. Which joined path is intended
for continued work can remain unknown without making readable current bytes unknown.

All 21 independent original-mode observations preserve historical facts and perform
no registry writes. Hash-current satisfies 6/7 declared scenarios; its refusal of a
safe in-root symlink remains an access failure. Focused tests also reject concurrent
replacement, in-place modification, scope escape and excessive growth. Path-only
does not certify existence, metadata does not certify bytes, and a current hash does
not complete capture or guarantee that a later open reads the same bytes.

**Proposal:** introduce one shared-core primitive for an explicit, bounded current
observation/read, then expose it through existing Catalog and thin adapters. Retain
the current exact-historical `read` meaning. Return current observation time/hash,
source scope, capture provenance and historical availability separately. Do not call
capture completion, staging, review or reindex as a side effect. The experiment
returns observations/hashes only; returning bounded content from the same checked
read remains implementation work. A replacement implementation must address safe
native aliases: rejecting every symlink also rejects normal macOS `/tmp` and `/var`
spellings. Test authorized root identity and descriptor traversal on a Mac before
adoption. No whole-disk fallback search is proposed.

## Report IDs

Exact report-local leading-identifier matching removes the `R1`/`R10` false positive
and retains duplicate `R1` headings as separate version-bound ranges. Table-only
findings remain unretrieved, and global artifact search for body-only `R1` still
returns zero in the held-out fixture. No cross-report ruling is inferred.

**Proposal:** retain scoped ambiguity and exact byte references; add exact identifier
matching as a bounded report-navigation option. Before adoption, bound heading count
and parse once per request: the current prototype reparses and verifies a whole
source for each outline page, and its source-byte cap does not bound section-object
allocation. Test literal occurrences separately if table/prose evidence is needed;
do not silently label every occurrence a finding. Persistent finding identity and
cross-round authority remain outside this small change.

## Decisions experiments cannot make

Existing current-file-first detail need not be reconsidered. Product judgment is
still needed for how much initial response space goes to separate state references,
when to show a reply group, and how prominently the broader result tier is exposed.
The prototype's conservative symlink refusal is measurable but is not a suitable
silent definition of source availability. Final API names, default presentation
and visual choices remain with Opus. These choices should be reviewed against the
actual deck counterexample and joined-path ambiguity, not abstract hierarchies.

No synthetic result establishes superiority to Finder or an agent's raw library.
Native execution remains outstanding. [NATIVE-FAILURES.md](NATIVE-FAILURES.md) supplies
exact Mac checks, including the confirmed WAL assumption defect and the separately
observed package-metadata, path-alias and home-root limitations. Explained failures
remain failures; no test was suppressed to make the checkpoint green.
