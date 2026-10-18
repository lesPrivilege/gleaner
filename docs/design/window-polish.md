# Window polish

Opus, 2026-10-18, on the window built in [projects-and-works.md](projects-and-works.md). The person asked for a more polished and beautiful window, using the grammar and references of the Praxis design kit (`Praxis/kit/design`). The kit's grammar applies directly. Its values (pixels, colors, durations) were written for explanatory web pages, so they are read for a native window rather than copied.

## What the kit decides here

| Rule (Praxis kit) | In Gleaner |
|---|---|
| Every state is written as words beside its item. The mark repeats the words, and color never carries a difference alone (`foundations/standing.md` 1, 5; `marks` grammar §2). | Every `StatusLabel` keeps its words. Its marks now have different silhouettes that hold up in grey: filled and hollow endpoints, brackets, a triangle, an octagon, a diamond, a crossed circle. |
| One drawing answers one question. A dash means "not in effect"; the endpoint says whether something is confirmed (`standing.md`, default allocation). | The filled endpoint means Gleaner saw the bytes at delivery; the hollow one, first seen later. A suggestion's outline is dashed, because it is not in effect. The versions of a work hang on a solid line with filled ends, because the person joined them. A declined pair keeps a dashed line ending in a cross. |
| The accent marks only what waits on the person (`standing.md`, counter-example 2; components §11). | `Palette.awaiting` replaces the old selection blue and appears only on suggestions: their diamond, their lead words and their outline. A selected delivery is shown by weight, a darker border and the words "shown above". The ready tile is shown by its status words, not by blue. |
| Declined and expired items stay in view (`standing.md` 7). | Where This Belongs lists each "not the same" the person said, with its Undo, beside the joins. |
| Necessary information is never hover-only (`interaction/states.md`; components §2.8). | What a choice does is written under the suggestion's buttons: "Nothing on disk changes, and either answer can be undone." Who says it comes first: "Gleaner suggests · not joined". |
| "Latest" is not a version (`foundations/anchoring.md`). | A suggestion's reason names the deliveries it compared ("delivery 1 has the exact bytes of report.md delivery 2"). The project header's links read "Delivered last". |
| A list's order is written into it (`foundations/placement.md` 2). | "Deliveries, newest first" and "Versions of this work, oldest first". |
| Group with space, alignment and type, not boxes in boxes (references U04). | A status statement stands in a tinted box only when it needs a look (amber) or something is gone (red). Otherwise it is plain text. Reply excerpts are quoted beside a rule. Where This Belongs is a section, not a card. The hand-off tile stays a card, because it is the object you drag. |
| Disclosure titles say what is hidden (`interaction/navigation.md`). | "Details: path, hashes, session log". |
| Results are announced (`interaction/feedback.md`). | Joining, keeping apart, moving, putting back, undoing and copying are each announced to VoiceOver once. |
| No percentage or end time without real progress (U06). | "Reading agent logs…" shows the running mark, three dots, never a number. |

## Marks

`Sources/Gleaner/Glyphs.swift` draws Gleaner's marks natively from SVG path data. Each is on the kit's 24-point grid, with a 1.5 stroke that scales with the size, round caps and joins. The renderer reads SVG path syntax, elliptical arcs included. Twenty-six marks are copied from the kit's `glyphs.svg`. Two are Gleaner's own, drawn to the same grid:
- **repository**: three nodes and a branch, for git projects;
- **work**: a file with another behind it, for one work in several files.

Marks are used where they carry one of Gleaner's meanings:
- **the sidebar:** All Deliveries, project origins, Sources;
- **the hand-off tile:** the artifact mark, where the drag starts;
- **the conversation row:** the terminal mark;
- **Same Work and Join:** the merge mark;
- **Show Apart:** the branch mark;
- **status words;**
- **empty states.**

Native chrome keeps the system's symbols: the toolbar, menus, and Check for New Deliveries. Marks beside words use a plain secondary label color, because the sidebar's material blends away the hierarchical style.

## Space, radius and motion

`Sources/Gleaner/Style.swift` sets these:
- **Space:** a 4-point step (4, 8, 12, 16, 24).
- **Radius:** two values, 4 for tags and 10 for cards.
- **Motion:** three durations, each named for what it shows, after the kit's tokens:
  - 120 ms for hover and press;
  - 200 ms for a state switching or something arriving or leaving;
  - 240 ms for something moving to where it now is.

Motion follows the model, which has already changed. A new click reverses or replaces an animation, and nothing waits for one. Under Reduce Motion there is no motion, but the words and marks still change.

Where motion shows something:
- **Arrivals and departures:** a suggestion arriving, a join or decline line appearing, and Show All's extra files rise 8 points as they fade in. They leave by fading only.
- **State switches:** a status statement crossfades when its words change. Copy Path and Copy Resume Command switch to "Copied" with the done mark, then back.
- **Hover:** the hand-off tile's border darkens under the pointer, and links underline (color isn't the only sign they go somewhere).

Not moved:
- **Selection changes** swap at once.
- **Counts** change at once, never tweened.
- **Nothing flies** across the window.

## Checked

- **The tour.** `GLEANER_TOUR=<folder> swift test --filter TourTests` draws each step of the board walk in light and dark, and a sheet of every mark at 32, 16 and 11 points.
- **Not checked:**
  - VoiceOver listening;
  - real hover and drag in a running window;
  - Increase Contrast;
  - large text;
  - narrow widths.

  These need a person at the window.
