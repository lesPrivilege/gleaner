# Control-panel review: evidence and limits

Current inspected revision: [`79d724d1228a4b748572958dcbdd22aa6b7da142`](https://github.com/lesPrivilege/gleaner/tree/79d724d1228a4b748572958dcbdd22aa6b7da142), fetched 2026-10-17. This review first inspected `d9818013a86e87c0d8efcaa5112550f635fd73ba`, then read the changes in `8ab9b795a2a763805b15071c5e5b3be4da78e44e` and `79d724d`. Current claims below cite the newer revision; resolved historical findings are marked explicitly. [Composition explorations](control-panel-explorations.md) remain alternatives, not adopted architecture.

## Rendering boundary

The existing interactive HTML prototype could not be captured: the cloud browser control API was not exposed, and the tracked component references an absent `support.js`. It uses custom template elements/bindings and a `text/x-dc` script; opening unprocessed HTML would not establish the intended interface. The notes report no prior rendered inspection. [Main:6–9, 47–51, 179–183][html] · [notes:3–8][notes]

No working-UI screenshots or reconstruction were produced, and the private hosted prototype was not accessed. The new native app uses SwiftUI/AppKit/Quartz, so it cannot be rendered or behaviorally verified by this cloud Linux inspection. This is a **source-based IA/interaction review**, not a completed visual audit. Perceived density, contrast, focus, motion, VoiceOver and cross-application drops remain unverified. Missing runtime and unavailable browser control are separate blockers; neither was an approval denial.

## What changed since the original review

| Earlier finding / missing capability | Current evidence and disposition |
|---|---|
| An older single-term match selected the latest delivery | Corrected in the prototype: `bestVersion`, matched request/label and selection now identify the older match. Native `SearchResult` also carries the matched delivery. The `captions` probe now selects delivery 1. Keep this as a regression scenario. [Main:380–428][html-search] · [LibraryModel:5–10, 92–105][model] |
| A saved copy first observed after delivery lost that caveat during handoff | Corrected in the prototype's late-observed saved-copy branch and preview caption. Native `Handoff.ready` carries `firstSeen`, and handoff/storage wording preserves it. Some neighboring labels still need consistency review below. [Main:340–343, 448–450][html-states] · [Library:195–209][core-state] · [Wording:92–143][wording] |
| Reverted bytes were called never delivered | Corrected for known earlier trusted hashes: both prototype and core distinguish rollback and offer the matching older delivery. Keep reversion as a regression scenario. [Main:305–307, 348–352][html-states] · [Library:182–207][core-state] |
| No native registry, capture store, preview or working action code | Now implemented in public source: SQLite registry, captures, saved copies, native list/detail, text/Quick Look previews, asynchronous observation and verified staging. This is implementation evidence, not proof of native usability or successful target drops. [Registry:15–27][registry] · [ContentStore:28–79][store] · [DetailView:106–179][preview] |

The three original probes were rerun against both revisions. The current prototype has ten sample artifacts, versus nine originally. Do not repeat the corrected cases as current defects.

## Flow coverage at current main

| Step | Source-based health | What remains to evaluate |
|---|---|---|
| 1. Enter and find project context | Partial: native search, kind filters and project/place/folder labels exist | Logical project affiliation and project navigation are not represented by those path heuristics. [LibraryView:9–22, 51–74, 104–105][list] · [Library:87–125][project] |
| 2. Search and recognize | Improved: matching requests and older-match labels exist | Multi-token evidence scope, latest-date versus match-date labels, manual selection under changed queries. [Library:212–230][search] · [LibraryView:98–117][list] |
| 3. Select and preview | Implemented in source: staged regular-file preview, text fallback and Quick Look | No observed native rendering. Text is limited to the first 64 KiB without a truncation label here; complete inspection and selected-source labeling deserve review. [DetailView:106–179][preview] |
| 4. Understand origin/version | Improved: provenance, storage, rollback and duplicate-content cues exist | Concise versus expanded evidence, consistent uncertainty across all labels, physical versus logical version organization. [DetailView:325–381][history] · [Wording:62–143][wording] |
| 5. Take away | Implemented staging and drag code; checking/error states exist | Successful Finder/Claude Desktop/Codex/browser drops are untested; keyboard equivalent, targets of neighboring actions, completion/retry feedback. [DetailView:190–322][handoff] · [LibraryModel:116–143][model] |
| 6. Empty, unavailable, recovered | Improved: native no-selection/no-match views, indexing progress/errors and recovery command exist | First-run versus empty/partial library composition, failed-access semantics and post-restore recheck clarity. [LibraryView:16–39, 71–74][list] · [LibraryModel:62–85][model] · [DetailView:259–315][handoff] |

## Current design findings

### 1. Project affiliation is the largest mismatch with current intent

`Artifact.id` is its path. `project` is derived from the latest delivery's cwd, the artifact directory and the first divergent path component. `projectName` uses folder names and known worktree-directory markers; `place` uses path patterns. None represents a logical project independently of those locations. [Library:67–125][project]

This makes the external agent-owned worktree, cwd-changing session and provider container spanning several repositories important design cases. Explore explicit/confirmed affiliation mechanisms without prescribing a full project-management schema. Keep project context visible globally; keep binding evidence, conflicts and correction scope secondary. No same-name-folder or matching-remote auto-merge is warranted.

### 2. Search still needs a clear evidence scope

Both current prototype and native core AND tokens across aggregated artifact fields, then choose the newest delivery containing any token. A query such as `captions intro` can be satisfied across two sample deliveries and select the newer one, while `captions` alone correctly selects the older one. This is a remaining match-scope question, not the original single-term bug. [Main:368–386][html-search] · [Library:212–230][search]

The native row shows the matched request and older-match label but dates the row with `artifact.latest.deliveredAt`. The model keeps an explicit `chosenDelivery` while selection stays the same, even when query text changes. These choices can be reasonable if they visibly distinguish matching evidence from a manually selected version. Otherwise the result, date and preview can tell different stories. Compare stable selection versus reset behavior; never silently substitute bytes. [LibraryView:98–117][list] · [LibraryModel:26–30, 90–105][model]

### 3. Preview and neighboring actions refer to different file roles

For regular files, preview and Open use staged bytes. Copy Path always copies the original artifact path. Reveal prefers the original source, then the staged copy, then the original parent folder. These are now concrete behaviors, not missing handlers. [DetailView:112–121, 200–202, 291–321][handoff]

Explore explicit target labels when an old saved version is selected. A path to today's changed source is not the same take-away as the selected staged bytes. The preview has no persistent source/version caption in `PreviewPane`; the header shows source path and current observed size. A nearby chosen-version/source label could make their different roles legible. Text preview reads at most 64 KiB; an excerpt/full-content boundary needs to be clear during human review. [DetailView:49–57, 106–164][preview]

### 4. Good state distinctions need consistent composition

The native handoff panel and storage label preserve late-observation uncertainty. But `OnDisk.missingWithSavedCopy` carries only a delivery number, and its wording says a copy “of delivery N”; `tileCaption` can also label late-observed bytes as “delivery N.” Treat this as a bounded remaining label inconsistency, not a claim that the corrected handoff resolver still loses provenance. [Library:145, 171–174][core-state] · [Wording:76–77, 101–103, 131–138][wording] · [DetailView:247–255][handoff]

Known rollback is correctly distinguished. When no known capture matches, “No agent handed you this version” remains stronger than the evidence of an incomplete/provisional index. Compare wording bounded to recorded deliveries. This matters especially while Gate 1 is unmeasured. [Wording:73–75, 107–109][wording]

### 5. Progressive disclosure can reduce repeated explanation

The native detail order is preview → identity/path/git → current disk → handoff → full delivery cards. Each card contains request, all evidence excerpts, provenance/storage, same-content cue and full hash. Result rows include project/place/folder, request and date. These are source-derived information-order facts, not claims about crowded pixels. [DetailView:17–33, 348–381][history] · [LibraryView:98–121][list]

Compare project output catalogs, delivery ledgers and personal review shelves. Compare preview-led and evidence-led detail separately. Keep origin, matched evidence and decisive caveats available; make full path/hash, other deliveries and affiliation evidence expandable. No content outline or generated synopsis is needed merely to fill a panel.

### 6. Availability, folders and feedback remain review tasks

There is native checking progress, disabled Open when no suitable URL exists, staging failure text, indexing status and an explicit recovery command. Do not describe all feedback or empty states as absent. A dedicated retry/cancel on the staging result and save/path-copy completion feedback are not present in the shown handlers. The no-selection view says “Pick a delivery”; a genuinely empty or incompletely indexed library may need different next actions. [DetailView:200, 231, 259–321][handoff] · [LibraryModel:62–85, 116–143][model]

Folders currently bypass regular-file staging and are labeled as current, unversioned and not hash-verified; the earlier prototype's saved-folder example is not a native capability claim. Native HTML dependency warnings are not shown in this detail source. Keep those limits visible when testing mixed original outputs. [Library:162–163, 195–196][core-state] · [DetailView:112–114, 219–241][handoff] · [Wording:83–85, 116–118][wording]

### 7. Accessibility and visual polish remain unverified

The native list has selection, delivery cards add a selected trait, status marks accompany text, text can be selected, and the drag tile has an accessibility label. These are useful implementation signals; they do not prove keyboard take-away, focus order, VoiceOver behavior, reflow or contrast. [LibraryView:51–54][list] · [DetailView:239–244, 340–343][history] · [Wording:43–54][wording]

Compare density, field emphasis and disclosures in the native app before choosing typography or motion. Do not infer macOS target-size failure from the HTML prototype's 40-pixel controls, or copy a reference product's pane layout without task evidence.

## Implementation boundary

The current registry stores sessions, deliveries and captures; captures retain hash, size, observation/saved times, provenance and directory state. The indexer ingests provisionally admitted candidates and captures new deliveries. Regular-file saves/staging hash copied bytes. Native source provides preview, observation, preservation and drag support. [Registry:15–27, 79–117][registry] · [Indexer:107–154][indexer] · [ContentStore:28–79][store]

Remaining design/capability boundaries include logical project affiliation, cross-path deliverable identity/lineage, content outlines, complete preview affordances, folder versioning and validated native interactions. The source includes library-flow fixture tests; they were read, not run in this Linux design review, and they do not establish successful target-app drops. [LibraryFlowTests:80–196][tests]

**Two gates remain open:** extractor precision/recall is unmeasured until human labeling of candidates and recall samples; cross-application dragging into Finder, Claude Desktop, Codex and browser upload has no established successful drop. The spec acknowledges that native library work preceded labeling and calls admission provisional. No private `out/` data or personal logs were used for this review. [SPEC:173–206][gates]

## Primary references and transfer limits

| Reference consulted | Transferable principle | Limit |
|---|---|---|
| [Zotero: Collections and Tags](https://www.zotero.org/support/collections_and_tags) | Organization need not duplicate or move underlying items; an all-items route stays useful. | Project affiliation is more than a playlist. Do not import arbitrary nested collections or reference-management workflow. |
| [Obsidian: Outline](https://obsidian.md/help/plugins/outline) | Navigate headings actually present in the active content. | Do not import editing/reordering behavior or invent structure. |
| [Apple: Quick Look](https://support.apple.com/guide/mac-help/preview-a-file-mh14119/mac) | Fast inspection from selection, including Space-bar interaction, reduces context switching. | Gleaner's no-source-modification boundary takes precedence over Quick Look's editing features; format support still needs validation. |

These inform alternatives, not branding or settled taste. [Reproduction details](review-verification.md) are separate.

[html]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/docs/design/prototype/project/Main.dc.html#L6-L183
[notes]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/docs/design/library-prototype.md#L3-L8
[html-search]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/docs/design/prototype/project/Main.dc.html#L368-L428
[html-states]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/docs/design/prototype/project/Main.dc.html#L305-L450
[list]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/LibraryView.swift#L9-L121
[model]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/LibraryModel.swift#L5-L143
[project]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Library.swift#L67-L125
[search]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Library.swift#L212-L230
[core-state]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Library.swift#L139-L209
[wording]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/Wording.swift#L43-L143
[preview]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/DetailView.swift#L49-L179
[handoff]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/DetailView.swift#L112-L322
[history]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/DetailView.swift#L17-L381
[registry]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Registry.swift#L15-L117
[indexer]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Indexer.swift#L107-L154
[store]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/ContentStore.swift#L28-L79
[tests]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Tests/GleanerCoreTests/LibraryFlowTests.swift#L80-L196
[gates]: https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/docs/SPEC.md#L173-L206
