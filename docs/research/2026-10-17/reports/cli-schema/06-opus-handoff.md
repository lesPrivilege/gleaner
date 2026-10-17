# Handoff to local Opus

This is an independent exploration, not a release gate or product contract. Main was inspected at `22dd07d926a764f0a2efcdeb093b78f0b9eab41b`. PR #4 is open at `72a42993512281a8bcc36fd9c6f22566132258d9` and remains separate; its threads/outline/timeline are not counted as main capabilities.

The strongest near-term option is a small shared query/read surface over GleanerCore, initially exposed through whichever client path is easiest to test. A structured CLI fits shell agents. A thin MCP layer is useful when actual hosts make discovery simpler. Neither requires new storage or inferred lineage. Existing capture and staging semantics are more valuable than the transport choice.

The new positioning hypothesis is viable: a logical object can be the first semantic unit while project remains the first navigation context. Compare it against current file-first and project-scoped delivery-first alternatives. A persistent logical identity earns its cost when users need continuity across names, agents and representations; it also creates obligations around uncertain links, splitting mistaken groups and preserving old references.

Decisions to make with concrete tasks:

1. Which consumer first: local shell, a specific MCP host, or both? The official Swift SDK's inspected release documents 2025-11-25 support while the current spec is 2026-07-28. Test a negotiated version, not an assumed universal capability.
2. What stability does a public ID promise? Today's path identity and log-path/line-derived delivery IDs do not establish cross-path or cross-library persistence.
3. Is “read this observed copy” enough, or does a task require proof of bytes at delivery? Preserve `first_seen_after_delivery` either way.
4. Does an optional, evidence-backed relationship overlay solve continuity needs before first-class logical-object state is necessary? Do not merge on filename or hash alone.
5. Who owns freshness and reads? Current registry initialization mutates schema/cursors. Choose a read-only opening path or app-owned endpoint before calling it a read API.
6. Are headings/line ranges enough initially? Broader content search, semantic typing and generated interpretation need their own demonstrated jobs.

Optional experiments:

- A fixture-only CLI with find → inspect → bounded read → exact handoff, using the same selected digest throughout.
- A thin stdio MCP adapter with a few tools; test whether resource links/templates are usable by the intended hosts.
- Three identity views over identical cases: path-first, delivery-first and a reversible object overlay. Include one intentionally wrong link that must be split.
- Reindex/migration fixtures proving that verified captures and future human corrections are not confused with re-derived evidence.

The executed synthetic probe gives a useful restraint: all four scripted policies reached the expected outcomes. Catalog responses totaled 4,885 bytes versus 5,967 for competent session filtering plus section reads. The large gains against bulk/full-document access do not establish superiority over skilled shell retrieval. No model token or real-user efficacy claim is supported.

Start with [synthesis](01-synthesis.md) and [identity options](04-logical-object-options.md); consult [interface precedents](02-interface-retrieval-atlas.md), [schema research](03-identity-schema-atlas.md) and [evaluation](05-evaluation.md) for details. Exact commands, access limitations and source checks are in [evidence](evidence/check-record.md). Product source and Praxis were not modified; nothing was committed or pushed.
