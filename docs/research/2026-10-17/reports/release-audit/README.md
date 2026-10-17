# Pinned release review

Source task `01a14a67-d8bf-7604-a729-a087f8a2a019`; reviewed main `22dd07d926a764f0a2efcdeb093b78f0b9eab41b`. The parent read the transferred review. This is historical review evidence and proposed acceptance work, not a current product contract or an independently rerun native validation.

1. [Review](report.md): findings, scope and release decisions.
2. [Evidence appendix](evidence-appendix.md): source traces, probe classifications and proposed regressions.
3. [Native acceptance](native-acceptance.md): checks for the Mac owner; not executed by this assembler.
4. [Source-location index](source-locations.md): resolves abbreviated code citations at the audited SHA.

Supporting material received:

- [Synthetic probe](probes/probe.py) and [eight recorded outputs](evidence/probe-results.json). Evidence classes distinguish actual SQLite/Git/shell probes, Python transcriptions and a source branch trace. Python syntax and JSON structure were checked without running the probe. Its original `SOURCE` path is `/workspace/gleaner-review`; a rerun needs the pinned checkout there or an explicitly documented local path adjustment.
- [Four proposed Swift regressions](probes/AuditRegressionTests.swift), not compiled or run by the originating audit or assembler. One HTML-escaped return arrow was decoded in the materialized copy; the raw transfer remains in the receipt.
- [Fixture generator](probes/make_fixtures.py), syntax checked without execution by the assembler. The originating audit's smoke-test statements remain attributed to that audit.
- [Process log](process-log.md) and [source URL map](evidence/source-urls.tsv). The process log's shortened `source-urls.tsv` reference means this map. Apple entries record attempted downloads, not successfully retrieved pages.

All ten supplied source files now match the originating final SHA-256 hashes. Third-party source snapshots, PR patch archives and generated fixture-smoke data are excluded as instructed; they are not Markdown link targets or required probe inputs. All Markdown relative links among the assembled reader files resolve.

The [assembly record](../../evidence/assembly-record.md) records source fidelity; original transfer parts remain in the local assembly archive. Assembly joined their boundaries, applied the authorized source-index citation updates and Courtwork URL correction, and decoded transferred HTML entities where needed to match the originating hashes. Code shorthand refers to `Sources/GleanerCore` or `Sources/Gleaner` at the pinned revision; source traces and Python transcriptions are not Swift execution.

The process log's historical “No pending approval request exists” applies only to the original audit time. The parent later supplied explicit authorization to publish the public-safe review and research on an independent branch. No merge or release action is authorized.
