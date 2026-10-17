# Assembly and verification record

Date: 2026-10-17. This edition assembles five independent streams at Gleaner main `22dd07d926a764f0a2efcdeb093b78f0b9eab41b`. All requested main and ancillary transfers were received and verified. This record concerns packaging; it does not add source research or independently reproduce originating results.

## Source fidelity

- Release audit: [ten originating hashes](release-audit-origin-hash-check.json). Transfer boundaries were joined, authorized source-index/Courtwork citation fixes applied and HTML entities decoded to reproduce the final source hashes. The wrapper README is an assembler edition.
- CLI/schema: its [original payload manifest](../reports/cli-schema/manifest.sha256) verifies the copied package. The original research archive remains unchanged with SHA-256 `348cb55aa655bf41d68910dbc5245bb82b4277fdbec6df2619362c1a9c535e8d`.
- Benchmark: [protocol/code/registration/results checks](benchmark-assembly-checks.json). Decode transport entities; restore two terminal LF bytes for chunks 01–09 and one for chunk 10; concatenate without separators. Complete protocol SHA-256 is `f2fe644270d99435301eb1eeb1f4367b8124af5a0b90bb06101cce11d68cd333`. Code concatenation removes one transport-added final LF to match `8c4b6cc1625f62da1d54edf72fc66e8eb70aa608d38acdeea16c74802d5f06f4`. Readable sections are editorial splits, not individually verified original files.
- Provenance: [fifteen main payload hashes](provenance-origin-hash-check.json), with HTML entity decoding where required. The supplied results are minified JSON; its recorded original pretty-printed digest is retained. The [README wording correction](provenance-readme-edition.json) distinguishes public source inspection from private/workspace access.
- Prior art: [six originating hashes](prior-art-origin-hash-check.json), including transport entity decoding in the process log. No capability claim was upgraded during assembly.
- Ancillary files: [first five checks](ancillary-hash-checks-1.json) and [remaining four checks](ancillary-hash-checks-2.json). These cover all three benchmark and six provenance files requested.

[Editorial changes](editorial-changes.json) separately record public minimization of revision metadata, a local-transfer link repair and omission of duplicate non-standalone chunk bodies. Original transfers remain in the local assembly archive. Report conclusions and original test results were not rewritten to imply new validation.

## Public scope

Only authored reports, concise source indexes, synthetic probe material, supplied measurement/configuration manifests and assembly checks are included. Private discussions, authorization transcripts, personal identifiers unnecessary to the reports, credentials, private logs, source-code snapshots, full papers, dataset shards and raw retrieval responses are excluded. No new license is selected by this edition.

The private archive has not been uploaded or delivered. Earlier reports' pending-approval statements describe their original research time; later explicit authorization permits this independent public report branch. No implementation, merge, release, CI enablement or model trial is authorized by publishing these reports.

## Validation boundaries

The assembler verifies source hashes, complete benchmark reconstruction, 26 unique task IDs, Python syntax without execution, JSON parsing, local Markdown targets, payload scope and the final SHA-256 manifest. Original report-specific execution counts remain separate. No Swift compile, macOS app test, provider-runtime test, model trial, competitor benchmark or private-log evaluation was run during assembly.

External references retain their source-specific access dates and pins; assembly does not claim a new crawl of every URL. Raw caches referenced by process records are excluded or explicitly identified as not supplied in the [receipt register](../sources/report-register.md).

Run the portable packaging check from the bundle root with `python evidence/validate_bundle.py`. See [validation output](validation.json) for this edition. It validates this bundle's relative file links and manifest, not external source truth or product behavior.
