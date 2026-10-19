# Durable corrections and reconstruction boundaries

The existing core preserved human corrections and their retrieval effects in these
synthetic tests. No production behavior, reset API, migration, policy or identity
scheme was added. This is development evidence, separate from the sealed held-out
evaluation, on the Cycle 3 branch based on main
`2648094610facfd1ae1805f52a9de282043c808f`.

The governing contracts are [SPEC §§5.1a, 5.3 and 5.5](../../SPEC.md),
[projects and works](../../design/projects-and-works.md), and
[capture](../../design/capture.md). Observations record what was found at an earlier
time; they are evidence, not disposable cached search results.

## Fixture and measured results

[Cycle3CorrectionTests.swift](../../../Tests/GleanerRetrievalExperimentTests/Cycle3CorrectionTests.swift)
uses actual `Indexer.run`, `Registry` correction/review APIs and
`Organization.search`, with the frozen `Cycle3Selection` experiment over that
shared search. Four supported synthetic Claude records deliver four paths across
two independent workspaces. One Markdown file and one HTML file become one Work
only after the human's `sameWork` correction. Another workspace's byte-identical
Markdown file stays a separate Work, including after its project is combined.

The person creates and renames a project, joins the representations, moves the
joined work into that project, combines the other derived project into it, places
the joined work in a collection, and renames that collection. An explicit approval
of the HTML bytes is recorded before correction comparisons. No correction writes
a capture or changes a review.

| Stage | Logs actually read | Shared broad matches | Project-name matches | Collection-name matches |
|---|---:|---:|---:|---:|
| Before placement/join corrections | 4 | 4 | 0 | 0 |
| After corrections | 0 | 3 | 2 | 1 |
| Append recognized titles; reread all changed logs | 4 | 3 | 2 | 1 |
| Invalidate every cursor; reread unchanged logs | 4 | 3 | 2 | 1 |
| Reconstruct log projection with evidence retained | 4 | 3 | 2 | 1 |

Every selection arm receives the same explicit project/collection/state scope and
a limit of 10, large enough to avoid truncation in this durability experiment.
Baseline, diversified and task-conditioned selection all change from 0 to 2 for
the corrected project, and from 0 to 1 for the corrected collection. Requiring
approved bytes in that collection also selects the joined work. Its candidate
retains both representations. Selected Work IDs, matched delivery IDs and scoped
selection order remain identical after the corrections through both rereads and
projection reconstruction. This demonstrates correction effects and parity, not
superiority of a ranking policy or first-page precision on a larger library.

The test compares every column of retained rows, including hashes, provenance and
timestamps. Corrections, projects, units, reviews, captures, observations and span
state remain unchanged; the library namespace and correction keys survive reopening
the database. The restored projection contains four delivery rows, while
`Report.newDeliveries` is **0** because the core counts newly captured deliveries
and reuses all four existing captures. Machine results:
[correction-results.json](correction-results.json).

## What was reconstructed

There is no public full-library reset API. The safe arm is explicitly test-only SQL
on a disposable synthetic registry: delete `log_files`, `sessions`, `deliveries`
and run-status metadata (`generation`, `scanned_at`, `sources`), then execute the
real indexer. It retains `spans`, `observations`, `captures`, `listings`, `members`,
`kept`, corrections, projects, units, reviews, source preferences and the library
namespace. The namespace survives; run generation is deliberately restarted by
this harness. This is reconstruction of the log projection with retained evidence,
not a full database reset, a migration proof or recovery of historical observations
from current files. Folder listing/member tables are retained but empty in these
fixtures, so nonempty folder-history durability is not claimed here.

A separate negative control makes the distinction observable. A person keeps and
approves an unmentioned observed file; the fixture then moves its original outside
the recorded workspace. Safe projection reconstruction rereads four logs and keeps
the Work, its kept evidence type, delivery ID and hash. The deliberately unsafe arm
additionally deletes observations and spans, then rereads all four logs. The kept
Work disappears from retrieval even though its correction, review and kept hash
rows remain. `Registry.kept` needs the native observation it joins to the correction;
the missing original cannot recreate it. This is an expected counterexample to an
unsafe reset proposal, not a failing supported operation. Machine results:
[correction-evidence-loss-results.json](correction-evidence-loss-results.json).

## Identity and limits

`Work.id` is the path of its earliest delivered member. An explicit join can change
the former later member's Work ID; the IDs are stable here after the join, with the
same native delivery evidence and namespace. User project and collection IDs remain
their stored keys. No global identity stability across arbitrary joins, renames,
deleted logs or replacement libraries is claimed. Equal hashes never authorize
joining contexts. A project move, collection placement or approval does not assert
that a representation is the authoritative current working file.

The safe arm retains nonempty native observations. Its indexed synthetic session
clock is beyond the 60-second span grace before snapshots, so a later run has no
legitimate pending workspace walk. An initial harness run incorrectly expected span
walk timestamps to remain fixed while still inside that grace, and interpreted
`newDeliveries` as restored row count. Those harness assumptions were corrected;
no core or policy change was made in response.

## Execution and reproduction

Executed on Linux x86_64, Swift 6.2.4, as the container's unprivileged `gleaner` user:
**2 tests passed in 0.105 seconds**, build 2.58 seconds. This is portable core
execution; no macOS UI or native filesystem execution is implied. The first compile
also caught a test-only `Work.latest` versus `Artifact.latest` property-access error,
fixed before execution. No held-out label or policy adjustment was involved.

From the repository root, in an environment with the required Swift toolchain:

```sh
GLEANER_CYCLE3_RESULTS_DIR="$PWD/docs/retrieval-core/cycle3" \
  swift test -j 4 --filter Cycle3CorrectionTests
```

The actual cloud command was:

```sh
docker exec -w /workspace/gleaner-cloud \
  -e GLEANER_CYCLE3_RESULTS_DIR=/workspace/gleaner-cloud/docs/retrieval-core/cycle3 \
  gleaner-swift runuser -u gleaner -- \
  swift test -j 4 --filter Cycle3CorrectionTests
```

Without the export environment variable, the same two tests run without writing
reports. Exported records contain fixture-relative labels and counts, not machine
paths, private conversations or actual library IDs. Re-run the same filter on macOS
as part of native validation; no platform exclusion was added for these tests.
