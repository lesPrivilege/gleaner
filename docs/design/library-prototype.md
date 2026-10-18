# Library prototype

Prototype: https://claude.ai/artifact/BtH7GhQ5MBrgyCeRLpLAt1 (private; share it from the page's Share menu)
Source: [prototype/project/](prototype/project/) — `Main.dc.html` (interactive library), `States.dc.html` (status vocabulary), `Mark.dc.html` (status mark component).

HTML stand-in for the native SwiftUI window. It walks the P0 scenario in [SPEC §2](../SPEC.md) on invented sample data. It is design exploration, not production UI, and it does not depend on Gate 1.

Verification: tag balance checked, and the prototype logic run in Node for all nine sample artifacts and the empty search. The rendered canvas was **not** viewed. The built-in browser was not signed in to claude.ai.

## Screens

**Library** (one interactive artboard)

- **Toolbar.** Search field and kind filters (All, Video, Web, Docs, Builds) with counts.
- **Results.** One card per artifact: type, name, project · place, the request that produced it, status, date of last delivery, and which fields the search matched.
- **Detail**, top to bottom:
  1. Preview area, labelled with what it is showing.
  2. Name, path, and git state.
  3. **On disk now** panel.
  4. "Not self-contained" warning, when it applies.
  5. **Hand off delivery N**: a draggable file tile carrying the version reference, plus Open / Show in Finder / Copy path / Save a copy.
  6. **Deliveries**, newest first. Each entry shows: when, provider, session, "You asked", the reply excerpt, whether it was seen at delivery, whether a copy is saved, any claim made in the reply, and the hash.

  Clicking the tile shows the hash check that runs as a real drag starts.

**Status vocabulary** — every status word, its mark, and what it means, grouped by the question it answers.

## States covered by the sample data

| Artifact | State shown |
|---|---|
| `ch3-agent-harness.mp4` | P0: changed since delivery 2. Delivery 2 has a saved copy you chose to keep. Delivery 1 was reference-only and its bytes are gone, so it offers "drag current file instead". |
| `ch3-storyboard/` | Folder delivered as a bundle, saved, unchanged |
| `codebase-review.md` | Saved and unchanged |
| `ux-review.html` | Not self-contained (loads `./figures/`) |
| `Gleaner-0.1.0-rc.2.dmg` | Worktree deleted, reference-only → lost; the reply's "notarized" claim is shown as unchecked |
| `Gleaner-0.1.0-rc.3.dmg` | Large build, reference-only and intact → "Save a copy" offered |
| `contract-redline.pdf` | Never observed; not on disk; in git history → "restore it from git first" |
| `onboarding-notes.md` | First seen after delivery (backfill), so "unchanged since first seen", with a caveat on drag |
| `release-notes.md` | Worktree deleted; saved copy available |

## Decisions

| Decision | Grounds |
|---|---|
| Every status is written as words beside its object. The mark repeats the words, and color never carries meaning alone. | Praxis `kit/design/foundations/standing.md` (rules 1, 5); SPEC §5.1 |
| Five marks, each with one meaning: solid = Gleaner checked it; hollow = known but not confirmed as the delivered bytes; dashed = not here, may exist elsewhere; triangle = needs your look; cross = gone. | `standing.md` (one drawing answers one question; solid/hollow endpoints for confirmed/unconfirmed; cross for rejected/gone) |
| The amber accent is reserved for "needs your look": changed since delivery, not self-contained, a version that can't be handed off. Selection uses a blue outline, never amber. | `standing.md` (the accent goes only where a person must decide; selection may use it only if kept separate) |
| Lost and gone versions stay in the list. | `standing.md` rule 7; SPEC §5.2 (keep the entry and its history) |
| Claims in a reply ("notarized") are quoted text and never become a status mark. The "Who says so" group separates the reply, Gleaner, and git. | `standing.md` ("who says"); SPEC §15 |
| A hand-off is always pinned to a version: name · delivery N · sha256. A version never silently becomes another. | `kit/design/foundations/anchoring.md` (object / version / scope; rule 6); SPEC §6 drag rule |
| The deliveries list is ordered only. A caption says "Spacing doesn't show time", and each entry carries its own date. | `kit/design/foundations/placement.md` (rules 1–3; order without a scale) |
| Hand-off sits above the delivery history and follows the selected delivery. | design critique (below): P0 ends in a drag, and the action was buried under the history |
| The tool's own storage is called a "saved copy", never just "copy". | ux-copy review: "dragging copies" collided with "copy kept" |
| ~~Search results say which fields matched~~; the request text is on every card. **Superseded** in part by [rulings §5](rulings.md#5-progressive-disclosure-preview-led-detail-with-three-levels): a row shows the request and date of the delivery that matched, and no list of matched fields. | SPEC §10; the user remembers the topic, not the file name |

## Review passes applied

**design:design-critique**

- 🔴 The drag action was the last block, below the full delivery history. It now sits under the On disk now panel.
- 🟡 "Drag to another app" was a button, not something draggable. It is now a file tile with a grip, type, name, and version reference.
- 🟡 The preview took up to ~350 px of height. It is capped at 240 px.
- 🟢 Filter chips raised from 36 to 40 px.

Left open: buttons are 40 px, below the artifact guideline of 44 px. That is deliberate macOS density, to settle in SwiftUI.

**design:ux-copy**

- One term for Gleaner's storage ("saved copy") and one for the action ("Save a copy").
- Error copy now follows what happened → why → what you can do: "Delivery 1 is no longer available. The file has changed since, and Gleaner didn't save a copy… You can drag the current file instead, but no agent handed you that version."
- The empty state gained a how-to line: "Try a word from your original request."

## SPEC changes from this prototype (applied 2026-10-17)

Applied to SPEC §5.1 (items 1–2), §6 (items 3–4), and the new §6.1 (item 5).

1. **§5.1 provenance:** add a third value, `never_observed`, for when the file was gone before Gleaner first looked. The prototype needed it for `contract-redline.pdf`.
2. **§5.1 / §7:** when the latest capture is `first_seen_after_delivery`, the "on disk" status must read "unchanged since first seen", never "same as delivery N".
3. **§6 drag rules:** add two cases:
   - Missing but in git history → Gleaner offers a restore command and never restores it itself (Invariant 2).
   - Delivered version gone but the source still exists → drag the current file only under an explicit "never delivered" label.
4. **§6 / UI vocabulary:** user-facing "saved copy" / "Save a copy" for snapshot / pin. Keep "snapshot" as the internal term.
5. **§15 → v0.1:** quoting reply claims (signed, notarized) as unchecked text applies to every delivery now, not only to release groups.

## Open questions for the SwiftUI build and Spike B

- **Hash on drag start:** a 412 MB video takes seconds to hash. Options: hash in the background and treat an unchanged size and mtime as a cache hit, or show progress on the tile. Which is honest enough?
- **Drag mechanics:** `NSFilePromiseProvider` versus a plain file URL per target (Finder, Claude Desktop composer, Codex, browser upload field). Can a folder be dragged as one item into chat composers, or must it be zipped?
- **Saved-copy drags:** they come from `~/Library/Application Support/Gleaner/objects/<sha>`. The receiving app should see the original file name, not the hash. Does the promise provider need to stage a renamed temporary file?
- **Quick Look gaps:** Markdown and interactive HTML. Does the preview for a folder bundle open `index.html`?
- **Dense list:** 40 px controls and the card height at hundreds of results. Does the list need grouping by project or date?
- **Search ranking:** the prototype uses AND across fields with no ranking. Gate 1 data should show whether matches on the request should rank above matches on the file name.
