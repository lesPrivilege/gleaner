# Gleaner design exploration

**Ruled:** see [rulings](rulings.md) for the alternatives adopted, deferred and declined, and the order of work.

**Built after the completion review (2026-10-18):** [projects, works and sources](projects-and-works.md), the contract the window now keeps for logical work, corrections, opening actions and source management. The window draws with [GleanerUI](components.md), its own component library, with a gallery of every component in light, dark and Increase Contrast. [The outline](outline.md) sets its levels, the conventions each keeps, and the empty states that show the next step.

**Capture from the session (2026-10-19):** [capture](capture.md) takes what every session gives (its requests and replies, its workspace and time span) and finds on the disk what appeared or changed during it, kept as observations beside the deliveries, never as deliveries. Layered: observations, the window, live capture, written-by evidence, acceptance.

**Reviewing (2026-10-19):** [review](review.md) is capture's layer 3: work units the person makes (collections in the window, a series and its episodes), keeping a file observed during a session, verdicts and published marks bound to the exact bytes they were made on, the four states kept apart, and To Review, the queue drawn from the person's own acts. The window shows them: To Review and each project's collections in the sidebar, a collection's review page with each work played, heard and shown in place, Observed in a project's outline, and a work's Review section.

Draft reference for Opus, grounded in public source at [`79d724d1228a4b748572958dcbdd22aa6b7da142`](https://github.com/lesPrivilege/gleaner/tree/79d724d1228a4b748572958dcbdd22aa6b7da142), 2026-10-17. These are alternatives for improving an already useful small product, not an adopted architecture or implementation plan.

**Project is the primary affiliation. The next round should reduce presentation burden and make movement between levels coherent.** Several agents, conversations, repositories and worktrees can contribute to one project. Global results retain that context; storage entities do not each need a navigation destination. People should reach original evidence and exact selected bytes without reading process noise or moving originals. Keep ordinary interface words stable and any provider integrations thin around the independent local core.

## Choose the question you want to explore

| Question | Read |
|---|---|
| What can disappear from the persistent screen, and how should enter/back/switch work? | [Control-panel composition](control-panel-explorations.md): minimal reduction, handover grouping, personal selections; field emphasis, naming, preview/action depths and manual-filing boundaries |
| Would an outline help someone resume weeks of project work? | [Project editorial organization](project-knowledge-explorations.md): delivery shelf, editable work brief and bounded topic dossiers, compared with one synthetic project |
| What identity or relationship structure would those views actually need? | [Optional reference notes](control-panel-reference-notes.md): affiliation and cross-agent instance alternatives; not a canonical schema or feature checklist |
| How should evidence, personal filing and preserved bytes behave over time? | [Evidence and lifecycle](evidence-and-lifecycle.md): rescan/reset semantics, unknown relationships and optional assemblies |
| What makes the small native app coherent in daily use? | [Native interaction](native-interaction.md): access recovery, keyboard/menu behavior, lifecycle, exact action targets and validation scenarios |
| What does current code establish? | [Source-based review](design-review-evidence.md): numbered flow assessment, exact file/line evidence, resolved findings and remaining composition risks |
| Which precedents inform the alternatives? | [Source index](source-index.md), with [pinned architecture mechanisms](architecture-precedents.md); transferable lessons and limits |
| How were claims checked? | [Verification appendix](review-verification.md): revision comparison and reproducible probes |

## Compare alternatives without accumulating modes

Start with the **minimal reduction**: keep the existing list/detail, establish project context once, make matching purpose and selected version legible, and disclose full history/location/metadata when needed. The selected preview, byte source, action and decisive caveat belong together.

Handover groups can help review outputs from the same request. A personal selection can bring a few outputs from different contributions together. The editorial research asks a different question: whether a delivery shelf suffices, or a small question-oriented work brief or bounded topic dossier reduces repeated reconstruction. These need not become separate tabs, graphs or new core objects.

Two concrete scenarios support comparison: Atlas's report/diagram/patch/installer tests first glance, selected inspection and take-away; CedarSearch's four-week corpus tests alternatives, changed comparison reports, decision claims and unavailable release bytes. Original reply order, source-document order, chronology, search relevance and personal reading order have different meanings.

Filename, logical title, alias and contextual label are possible roles. Display changes do not rename originals, and exported-copy naming is a separate explicit choice. Personal filing and saved views should survive ordinary rescans without changing observed evidence. A position pin is distinct from saving bytes.

No generated summary is needed for the minimum model. Source excerpts help establish relevance; actual content supports review. A personal or generated note, if useful later, keeps its source basis, coverage and uncertainty and cannot replace preview or provenance.

## Current evidence and limits

The native library now implements registry/captures, saved regular-file copies, preview code and verified staging. The earlier single-term old-match, late-observed saved-copy handoff and known-hash rollback cases were corrected; they remain regression scenarios. Remaining questions include logical affiliation, ambiguous match/selection scope, labels spanning original and staged files, repeated metadata and native lifecycle behavior. Rapid selection during preparation is a source-derived risk to test, not a reproduced failure.

**No rendered visual audit was possible:** the cloud browser control tool was unavailable, the HTML prototype references absent `support.js`, and cloud Linux cannot validate native macOS behavior. No working-UI screenshots or substitute reconstruction were produced.

**Two checks wait for after release:** extractor precision and recall are measured on broader feedback after release (SPEC §12, Gate 1), so admission remains provisional; drops into Finder, Claude Desktop, Codex and browser upload are checked in post-release use. Public source and fixture tests do not close those gates. No private logs or `out/` data are part of this package.

For Opus: **first choose information organization, then walk real retrieval/review/takeaway tasks, then refine visual and motion polish.** Compare alternatives using the same tasks; observe unnecessary expansion, lost place and mistaken-version selection. Validate native interaction before judging density, focus, typography and motion. Preserve meaningful differences between proposals and keep only customization that earns its cost. Final choices remain with Opus.
