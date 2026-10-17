# Control-panel composition: fewer facts, clearer transitions

Independent exploration, 2026-10-17. Inspected current main: [`79d724d1228a4b748572958dcbdd22aa6b7da142`](https://github.com/lesPrivilege/gleaner/tree/79d724d1228a4b748572958dcbdd22aa6b7da142). Project is the primary affiliation. Concrete layout, grouping and naming choices remain with Opus.

The current functional design is largely sufficient for this round. The design opportunity is to govern what appears, when it appears and how a person moves between levels. Backend completeness does not require displaying every record. The proposals below are alternatives for the existing small product, not a list of new features to build.

No rendered screenshots were possible. These are source-derived composition hypotheses, supported by the [current-code review](design-review-evidence.md). Broader identity/schema/lineage ideas are deliberately kept in [optional reference notes](control-panel-reference-notes.md).

## Three convergence options

| Option | Change to the existing surface | Useful task | Tradeoff to test |
|---|---|---|---|
| **A. Minimal reduction** | Keep list/detail. Shorten rows; keep the selected preview, version/action and decisive caveat together; reveal full origin/history/metadata on demand. Project remains visible context. | Find an old output and take the correct version away without reading all deliveries. | Some comparisons need expansion. Can the person still explain origin and certainty before acting? |
| **B. Project handover groups** | Within a project, group outputs by the request/reply that actually handed them over; expand only the selected group. Global search remains direct and project-labeled. | Review a report, diagram and patch delivered together or relate several agents' contributions. | Repeated handovers can duplicate rows. Does grouping reduce scanning more than it adds navigation? |
| **C. Small personal review selection** | Keep a short, explicitly personal set of project outputs above a direct route to the complete view. No new workflow state is implied. | Revisit a report, diagram and release from different handovers as one review set. | Curation and stale-version choices add complexity. Try this only if repeated tasks justify it. |

These are not three compulsory tabs. Option A can be tried without new durable objects. B can derive actual handover groups from evidence. C may start as a personal arrangement rather than a new core schema. An authored work brief or topic dossier is a [separate editorial exploration](project-knowledge-explorations.md); do not introduce either merely to conceal an overfull list.

## Before and after information burden

The native source currently renders preview → path/git/current-size header → on-disk panel → handoff panel → every full delivery card. Each history card repeats request, evidence, provenance, storage and full hash. Result rows show name/type, project/place/folder, request, latest date and sometimes an older-match label. These are source facts, not measured visual density. [DetailView:17–33, 348–381](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/DetailView.swift#L17-L381) · [LibraryView:98–121](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/LibraryView.swift#L98-L121)

| Review level | Candidate reduced composition | What moves out of the persistent path |
|---|---|---|
| **First glance: list** | Name/type; project in global views or clearly inherited project scope; one matching purpose excerpt with its delivery/date; any known decision-changing exception | Full folder/worktree strings unless needed for collisions; provider/session IDs; hashes; complete history; parser counts |
| **Selected output** | Actual preview or precise absence reason; chosen instance/delivery and preview source; one short relevance/origin cue; primary take-away; uncertainty or unavailability beside it; a visible way to choose other deliveries | Full path/git/current-size block, expanded request/reply, all nonselected history cards |
| **Contextual expansion** | Selected request and delivery evidence, other deliveries, source location, affiliation explanation; content Contents only when useful | No need for whole transcripts, tool/process activity or generated prose |
| **Detailed inspection** | Full retained excerpts, exact capture/verification times, full hash, original locator, binding evidence and correction scope | Operational logs remain in diagnostics, outside the review flow |

A collapsed section must not hide the fact that it contains alternatives. Missing bytes, late observation and dependency limitations should not first appear after expansion. A saved copy is not proof of delivery timing or quality. Omit empty fields rather than filling them with speculative summaries.

Compare two detail orders: **preview-led** for visual recognition, or **matching-evidence-led** for ambiguous names and older hits. Both retain actual preview and exact file choice. A compact row versus expanded card is a separate density experiment. No generated synopsis is needed: excerpts establish relevance; original content supports assessment.

## Make levels interact fluidly

1. **Enter from search.** Preserve query and project context. Open the matching delivery, show why it matched, and label preview bytes. The older single-term case is fixed in current main; preserve it while exploring multi-token matches.
2. **Expand evidence or location.** Use a labeled disclosure, inline region, inspector or sheet. Compare those forms locally. Keyboard, pointer and tap should all reach the content; hover is optional convenience. Dismissal returns focus to its trigger.
3. **Switch output.** Keep the list's query, grouping and scroll position. Update preview, selected-version label and actions as one conceptual selection. Do not leave another output's expanded evidence looking current.
4. **Switch delivery/instance.** Retain artifact/project context; change selected bytes and caveats together. An unavailable choice stays understandable rather than silently substituting today's file. Returning to the list preserves the chosen match.
5. **Sort or filter.** Sorting moves the selected row, not its identity. If a filter excludes it, compare an explicitly retained “outside this filter” detail with a clearly explained cleared detail. Do not silently pick another file. Newly indexed results should not replace an open selection.
6. **Take away, then continue.** Native staging already exists. Make failure/retry and the distinction between a prepared file and an accepted drop intelligible. Restore focus and selection after the action. Explore a keyboard/click equivalent to drag using the same exact bytes.

The current native preview/Open use staged bytes while Copy Path always uses the original source; Reveal has source/staged/parent fallbacks. Label these roles when ambiguous instead of exposing a generic row of equally weighted actions. [DetailView:190–321](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/DetailView.swift#L190-L321)

## Arrangement and customization that might earn their cost

| Choice | Benefit | Cost / guardrail |
|---|---|---|
| Recent delivery first | Find recent agent outputs | Old foundational work sinks. File modification time is not delivery time, and newest is not authoritative. |
| Group by actual handover | Review several outputs with their common request | Repeated deliveries recur; separate replies are not one task without evidence or user arrangement. |
| Kind/name order | Scan diagrams, documents or builds | Separates related outputs. Keep their project and handover reachable. |
| Keep at top | Return to a small personal set | Label whether it follows a deliverable or fixes an exact instance. It does not mean “Save a copy.” |
| Compact/expanded density | Scan many similar outputs versus read evidence | Test two presets before a column editor. Preserve decisive caveats in either. |
| Saved personal view | Reuse a successful scope/order | Remembering the current view may suffice. A named-view manager is optional, not assumed. |

A view preference changes presentation, not original records, project affiliation or files. Visible fields can be reduced, but a global result still needs project context and an action still needs an exact target. Preview the selected match; for a multi-output handover, compare source mention order with explicit personal order. Do not silently sort a historical selection into the newest bytes or autoplay/open executable content while stepping through items.

## Names have different jobs

| Naming role | Where it helps | Minimum-coupling cost |
|---|---|---|
| **Original filename as label** | Familiar inside a project; preserves physical correspondence | `spec.md` or `final-v7-new.md` can be ambiguous globally. Use context before inventing a new identity. |
| **Logical deliverable title** | One continuing work has several files/exports/branches | Requires confidence that the files belong together. Keep that grouping explicit or unresolved; title alone cannot establish it. |
| **Editable display alias** | A messy name obstructs repeated review | Scope the alias to the output/group/view and search both alias and original. It changes display, not source content or filename. |
| **Contextual composed label** | Global search or export loses surrounding project context | Add only needed project/version context. Do not bake project names into every local title or introduce four required entities. |

Within Atlas, `spec.md · delivery 3` can be concise when the project is already clear. Global search can show `Atlas / spec.md` beside `Beacon / spec.md`, with a short repository/location qualifier only when Atlas itself has collisions. An alias such as “Recovery guide” may help, but the original name remains visible on selection and easy to inspect. Search can identify whether a match came from alias, filename or source evidence.

When leaving the app, preserve the original filename by default or let the person explicitly choose an exported-copy name such as `Atlas — Recovery guide — draft B.md`. The receiving app will not inherit Gleaner's sidebar context. Clarify any collision or naming change before copying. A display alias does not rename originals, and export naming is a separate choice; dependency-bearing bundles need appropriate care before changing member names. Current staging uses the original artifact name, so contextual export naming would be optional future work, not existing behavior.

## Mixed-output walkthrough

Synthetic **Atlas** spans two repositories and one non-Git diagram folder. These are explicit affiliations, not inferred from folder names. Two agents contributed four originals in three handovers.

| Output | First glance | Second level | Detailed inspection |
|---|---|---|---|
| `review.md` report | Purpose excerpt, delivery 2, saved bytes available | Actual selected report and short source evidence; Contents if derived from these bytes | Full retained evidence, capture time/hash, original location, delivery 1 |
| `recovery-flow.svg` diagram | Same-handover cue with report; known availability | Actual diagram, zoom and original reply | Source/worktree, verification details; no invented diagram outline |
| `retry.patch` code | Explicit output; source changed, delivered copy available | Selected patch/text, chosen delivery and uncertainty; Open if preview unsupported | Full patch and actual parsed hunks if supported; no inferred test-pass badge |
| `Atlas-rc.2.dmg` release | Source unavailable; no saved bytes | Evidence and absence reason; no fake preview or apparently usable transfer | Any real recovery evidence; “signed” remains an attributed reply claim |

Recent order may put the build first; handover grouping keeps report and diagram together; a personal selection may prefer report → diagram → patch → build. Test which arrangement helps the task without revealing every metadata field. At first glance, the person should notice the build cannot be taken away and the patch's source has changed. Expansion supplies reasons, not a hidden reversal of the first impression.

For one logical deliverable revised across agents, compare an expandable deliverable with physical instances, a lighter related-output list, and explicit user grouping. Do not infer sequence from time: branches, duplicates, merges, exports and unknown relationships remain distinct. Exact preview/transfer selection must work even before logical relationships are resolved. Detailed tradeoffs are in the optional notes; no graph is required for this presentation round.

## Preview and serious review are different depths

Compare quick identification, embedded inspection and external review as task-dependent depths, not three compulsory screens. At project overview, show useful group/purpose/availability context. In results, identity, matching evidence and a small thumbnail only where it helps recognition may suffice. At the selected deliverable, show a useful preview and exact instance selector. At exact-version/provenance depth, show the byte source, certainty and supporting evidence. Moving deeper should preserve selection and back position.

Use native preview and the associated app before considering a format-specific renderer. Current code already uses text and Quick Look previews; the matrix below proposes review defaults to compare, not a statement that every format has been tested.

| Example type | Quick identification / embedded default to compare | Serious review or fallback | Optional alternative and cost |
|---|---|---|---|
| Text / Markdown | Selected excerpt or readable text; make truncation apparent | Open selected copy in the associated app for full reading | Parsed headings/full document view if repeated review warrants it; no generated summary substitute |
| PDF | Native preview when available, with a way to inspect beyond a thumbnail | Default PDF app for detailed reading/annotation | Page navigation/bookmarks from actual content; added controls and accessibility work |
| Images / diagrams | Actual image with useful zoom when supported | Associated image/design app for fine detail or editing | Format-specific layers/diagram interactions only with demonstrated demand |
| HTML | Identify the page and dependencies; use a safe supported preview or explicit external review | Open selected content with clear dependency/version scope | In-place active preview or captured bundle support costs dependency handling and a clear execution boundary; no automatic crawling/execution during indexing |
| Code / multi-file folders | Text where useful; actual member/changed-file structure only when available | Editor for multi-file navigation; explicit current-folder opening when no captured version exists | Diff/hunk or bundle viewer can help, but is not required to become an IDE or reconstruct a project |
| Audio / video | Poster/basic system playback where supported; no autoplay on row navigation | Associated media app for long-form or detailed review | Waveforms, chapters or transcripts require reliable source structure or additional processing; do not invent them |
| 3D / specialized documents | System preview if available; otherwise type, name and evidence | Associated specialist app with the selected file | Building a renderer is high cost and outside a small control panel unless core tasks demand it |
| Installers / executable packages | Identity, size, version evidence and availability; no automatic launch | Explicit Open/launch action when intentionally requested | Package inspection or verified signing metadata is separate future work, not inferred from agent claims |

Preview failure does not imply missing bytes. Show “preview unavailable” with an appropriate Open action when the selected file exists; explain absence when it does not. A saved captured copy can still support review after the original disappears. A thumbnail cache alone cannot supply lost full content. Keep format-specific limits next to the affected action rather than adding blanket warning text.

| Action | Role to make clear at the selected level |
|---|---|
| Preview | Displays the chosen instance/bytes or clearly says it is current, unversioned content; it does not silently switch to the live source. |
| Open | Serious review in an external app. Current regular-file behavior opens the staged selection. A separate Open original choice, if useful, would explicitly address today's source and be unavailable when missing. |
| Reveal | Shows a location, not the artifact's content. Distinguish source location from staged/saved-copy location; do not obscure fallback to a parent folder. |
| Copy path / reference | Copies a reference whose target may change or be unavailable. Label original-source reference versus an exact prepared-copy reference; neither is automatically equivalent to copying the file. |
| Drag / copy out | Transfers the explicitly selected bytes with copy semantics. Current regular-file staging is implemented, but target-app acceptance is unverified; current folders are unversioned and need separate validation. |

Apple's [Quick Look documentation](https://support.apple.com/guide/mac-help/preview-a-file-mh14119/mac) supports fast selection-to-inspection and explicit Open with an app. Transfer that division of labor; do not inherit its editing features or claim universal format support.

## Personal filing without losing evidence

Compare two small mechanisms: **add a personal project link/selection** while keeping detected affiliation visible, or **override the displayed filing** with a separately stored, reversible choice. The former is the smallest alternative when the task is simply “put this where I review Atlas”; the latter helps correct a misleading primary affiliation but needs clearer conflict/reset semantics. Neither should rewrite delivery evidence, move originals or depend on a heavyweight event history.

Synthetic example: an Atlas report in an external agent worktree is initially labeled from `agent-store`. The person files it under Atlas, adds “Recovery review” as a display alias and keeps it at the top. A rescan updates availability and new delivery evidence but should not silently erase those choices. If a later renamed path appears, preserve the old arrangement as unresolved until a trustworthy relation or user confirmation reconnects it; do not attach the alias to any matching filename/hash automatically. New contradictory affiliation evidence can be shown in context without silently overriding a scoped personal choice.

Compare **Restore suggested filing for this item** with a broader reset only if real use needs it. Preview the affected items and say whether aliases, top-of-list choices and saved views are retained. A narrow filing reset can remove only the personal affiliation override; a separate view reset can restore sort/group/density. A renamed or no-longer-linked target should remain inspectable rather than disappearing from personal organization on rescan. Undo can be a simple reversible edit, not an event-sourcing system.

Keep reset meanings distinct: recomputing a derived index should preserve source observations/captures and personal choices or report unresolved links; clearing expendable preview/staging cache should preserve saved captures and avoid active transfers; deleting preserved captures is a separate destructive storage action, not a synonym for reset. Explain loss of an available saved version before any such action. No cache can recover an original that was deleted before its bytes were captured. Detailed alternatives are in [evidence and lifecycle](evidence-and-lifecycle.md#personal-organization-should-survive-a-rescan); they do not require a permanent settings dashboard.

## What to validate next

Start with the minimal reduction and the same review tasks in the other compositions; Opus chooses the result. Measure information a person had to expand, mistaken-version choices, lost place on back/switch, and unnecessary navigation. Then inspect native focus, text scaling, density, contrast and reduced motion. The [native interaction chapter](native-interaction.md) adds source-access recovery, keyboard/menu behavior, window lifecycle and interruption scenarios.

Two gates remain open: human-labeled extractor precision/recall, and successful cross-application drops into Finder, Claude Desktop, Codex and browser upload. Public code contains native preview, registry/capture and verified staging, but source inspection does not validate macOS interactions. Admission remains provisional. No private logs or `out/` data belong in this package.
