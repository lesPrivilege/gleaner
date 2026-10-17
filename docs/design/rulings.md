# Rulings on the design exploration

Opus, 2026-10-17, on the exploration in this folder (baseline `79d724d`). Each ruling picks one alternative and says why. The others stay in their chapters as reference; they are not on the roadmap. The order of work: settle information organization, walk real tasks in the native app, then polish.

The test for every choice is Gleaner's product contract (SPEC §2): find an old delivery by what you asked for, tell which version you are looking at, and hand the exact bytes to another app. A choice that doesn't serve one of those three is out of v0.1.

## 1. Organization: minimal reduction (option A)

**Adopted:** keep list/detail and reduce what each level shows ([composition](control-panel-explorations.md#three-convergence-options), option A).

**Not adopted:**
- **Handover groups (B) as a mode.** The selected output's detail lists the other files named in the same reply ("Delivered with …"). That gives the co-delivery context without a second navigation system. It derives from evidence already stored.
- **Personal review selection (C).** No observed task needs it yet.
- **Work brief and topic dossiers** ([editorial](project-knowledge-explorations.md)). They make Gleaner an authoring tool, which is outside the product boundary (SPEC §1.1). The delivery shelf is option A.

## 2. Project affiliation: derived from git, no manual filing yet

**Adopted:** derive the project from the repository, not from folder names.
- A delivery's project is the repository holding the file, else the one its cwd belongs to. Gleaner finds it by reading `.git` entries (a worktree's `.git` file and its `commondir`), without running git. Every worktree of a repository therefore folds into one project, wherever the agent keeps it, and a deleted worktree resolves through the folder that held it.
- Outside git, the project stays the cwd's folder name.
- The value is computed once per distinct cwd at load and kept in memory. No schema change.
- The list gets a project scope next to the kind filter. Global results keep the project label.

**Deferred:** reassigning or additionally linking a delivery to another project (the [assignment and link alternatives](evidence-and-lifecycle.md#personal-organization-should-survive-a-rescan)). Revisit when real use shows misfiled outputs that git can't resolve. Until then, an output whose path lies outside its cwd's repository is labeled by its own repository, as today.

## 3. Search: all terms must match within one delivery

**Adopted:** a result matches when every term is found in one delivery's own words, together with the artifact's name and project. Words from two different deliveries no longer combine into a match.
- That delivery is the one the result opens, and its date is the date the row shows. Today the row shows the latest delivery's date.
- Each result then tells one story: one request, one date, one version.
- A query whose terms span deliveries returns nothing. That is honest, and the person refines the query.
- **Not adopted:** history-wide matching labeled "Matches across 2 deliveries".

**Selection:** changing the query resets an explicitly chosen delivery to the one that matched (SPEC §10). Choosing another delivery holds only while the query is unchanged.

## 4. Naming: original filename only

**Adopted:**
- The label is the original filename. When two results share a name, the row adds the shortest folder suffix that tells them apart.
- Hand-off copies keep the original filename.

**Not adopted for v0.1:** logical titles, display aliases, and renamed export copies. An alias is personal state that has to survive rescans; filename plus project plus request excerpt has been enough to recognize outputs on real data.

## 5. Progressive disclosure: preview-led detail with three levels

**List row**, in order:
1. type badge and filename;
2. project, plus place only when it isn't the main checkout;
3. the matched request (two lines);
4. the matched delivery's date;
5. one status mark, only when something needs attention: not on disk, changed, or first seen after delivery.

The full folder appears only to tell two same-named files apart.

**Detail, always visible**, in order:
1. the preview;
2. one caption naming the bytes shown ("Delivery 2 · saved copy", "Delivery 2 · current file, unchanged");
3. the hand-off tile and its caveat;
4. the matched request and reply excerpt.

The preview, the bytes it shows, the action that hands them off and any caveat about them sit together and always describe the same selection.

**Detail, on demand:**
- **Deliveries:** collapsed to one line each (number, date, agent, provenance mark). Selecting one switches preview and hand-off together.
- **Details:** the full path, git state, size, hash and capture times.

**Not adopted:** evidence-led detail order. Search already opens the matched delivery and the caption names it, so the evidence order adds no information.

## 6. Customization and reset: none beyond filters

**Adopted:**
- Sorting stays newest delivery first.
- The filters are kind and project.
- There are no saved views, density presets, pins or aliases.

The three reset meanings in [evidence and lifecycle](evidence-and-lifecycle.md#personal-organization-should-survive-a-rescan) are recorded as the contract for when such controls exist:
- **Reindex** rereads logs and keeps captures. It is the only reset in v0.1.
- **Clearing hand-off copies** is safe: they live in Caches.
- **Deleting saved copies** is destructive and is not offered.

## 7. Preview and external review

**Adopted:**
- Quick Look for most formats, and the text view for text.
- Markdown is the one exception to "no format-specific renderers": it is most of what agents deliver. Gleaner renders its block structure (headings, lists, quotes, code blocks, tables) with Foundation's parser. Nothing is fetched: images show as alt text.
- When text preview stops at 64 KB, it says so and points to Open.
- No format-specific renderers.
- No HTML dependency crawling.
- Executables and installers are never opened by selection.

**Action targets:** each action states which file it acts on. Open and drag use the verified copy of the selected delivery. Show in Finder and Copy Path act on the original location, and they are grouped under the original's path so the difference is visible.

## 7a. Kinds: a fixed set by what you do with the file

**Adopted:** ten kinds, chosen by what a person does with a file rather than which field produced it: Documents, Images, Video & Audio, Web Pages, Code, Data, 3D & CAD, Builds & Archives, Folders, Other.
- A file's kind comes from the system's type tree (`UTType` conformance), checked from specific to general. Unknown formats fall into the nearest kind, or Other, without code changes.
- A short extension table covers formats the system doesn't type: CAD and 3D (STEP, DWG, STL, glTF…), and TS/JSX, YAML, Parquet.
- The badge keeps the exact extension, so merging video and audio loses nothing.
- Other is permanent: an unrecognized file still gets a row, a hash and the drag tile.
- The kind filter is a menu beside the project menu; a segmented control does not fit ten kinds.

**Not adopted:** a kind per domain (engineering drawing, simulation, notebooks…). New fields map onto these ten; a new kind needs a new action, not a new format.

## 8. Native interaction

**Adopted:**
- **Window:** keep the single `Window`. Closing it quits, and watching stops with it. No menu-bar or login item in v0.1.
- **Keyboard hand-off:** with a result focused,
  - ⌘C puts the verified copy on the pasteboard as a file;
  - ⌘O opens it;
  - ⌘R stays Check for New Deliveries.
- **Empty states:** the library tells apart four cases:
  - first index still running;
  - no agent log folders found (it names the folders it looked in);
  - library empty;
  - no matches (it offers to clear search and filters).

**Fix first — confirmed defect.** Hand-off staging isn't tied to the selection it was prepared for.
- **Cause:**
  - `LibraryModel.stage` writes `staging = .ready(url, sha:)` after a detached copy finishes;
  - cancelling the view's `.task(id:)` doesn't stop that write;
  - the preview, tile and Open read any `.ready` URL without comparing its sha to the selected plan.
- **What happens:** select delivery A, which starts a slow copy, then switch to B before it finishes. A's bytes can appear in B's preview and tile under B's label.
- **Fix:** consumers accept a staged URL only when its sha equals the selected plan's sha, and `stage` drops results after cancellation.
- Sources: [LibraryModel.swift:116-129](../../Sources/Gleaner/LibraryModel.swift), [DetailView.swift:35-44, 112-116, 219-223, 291-293](../../Sources/Gleaner/DetailView.swift).

## 9. Wording fixes

- **"No agent handed you this version"** claims more than a provisional index knows. It becomes "Not among the deliveries Gleaner found", in `Wording.swift` lines 75 and 109.
- **Saved copies first seen after delivery** keep that qualifier in every label that names a delivery number. That covers "Not on disk" (line 77) and the tile caption. Delivery numbers stay, followed by "first seen later".

## Order of work

1. Fix the staging defect and the wording (sections 8–9).
2. Change search to match within one delivery, and reset the chosen delivery when the query changes (section 3).
3. Add the reduced row and detail composition and the project scope (sections 2, 4, 5, 7).
4. Add keyboard hand-off and the empty states (section 8).
5. Walk the native validation scenarios in [native interaction](native-interaction.md#preview-maintenance-and-visual-polish) on real data, then judge density, type and motion.

Gates 1 and 2 (SPEC §12) stay open and are not affected by these rulings.
