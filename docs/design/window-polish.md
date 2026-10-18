# Window polish

Opus, 2026-10-18, on the window built in [projects-and-works.md](projects-and-works.md), in two passes.
- **First pass.** The person asked for a more polished and beautiful window, using the grammar and references of the Praxis design kit (`Praxis/kit/design`). The kit's grammar applies directly. Its values (pixels, colors, durations) were written for explanatory web pages, so they are read for a native window rather than copied.
- **Second pass.** The person found the window still wordy. They asked for:
  - information carried by levels of control and layout instead of sentences;
  - stable meanings drawn as marks;
  - short text reworked, rather than left as drafted sentences;
  - each agent shown by its own icon;
  - the hierarchy and depth of a classic first-party Mac app.

## What the kit decides here

| Rule (Praxis kit) | In Gleaner |
|---|---|
| A state is written as words beside its item. The mark repeats the words, and color never carries a difference alone (`foundations/standing.md` 1, 5; `marks` grammar §2). | Every mark has a silhouette that holds up in grey: filled and hollow endpoints, brackets, a slashed square, a triangle, an octagon, a diamond, a crossed circle. Words go with every state that needs a look. A state that is as it should be may show its mark alone, with its words in the help tag and for VoiceOver (Fewer words, below). |
| One drawing answers one question. A dash means "not in effect"; the endpoint says whether something is confirmed (`standing.md`, default allocation). | The endpoints mean only one thing: the filled one says Gleaner saw the bytes at delivery or verified them, the hollow one that it first saw them later. Other states use their own marks: a folder is "doesn't apply" (slashed square), a read is done (check), a check under way is running (three dots). A suggestion's banner is dashed, because it is not in effect. The versions of a work hang on a solid line with filled ends, because the person joined them. A pair kept apart keeps a dashed line ending in a cross. |
| The accent marks only what waits on the person (`standing.md`, counter-example 2; components §11). | `Palette.awaiting` appears only on suggestions: their diamond, the word "Suggested", and the banner's outline. Links are ink with a standing underline, as the kit's own pages draw them, so they never borrow the accent. The list's selection stays the system's. |
| Declined and expired items stay in view (`standing.md` 7). | A work's Project section lists each pair the person kept apart, with its Undo, beside the joins. Sources → Corrections lists every decision. |
| Necessary information is never hover-only (`interaction/states.md`; components §2.8). | The sentence behind a short label opens from its ⓘ by click or keyboard. It is also in the help tag and read by VoiceOver. The outline's suggestions say once, under their section, that joining never moves or changes a file. |
| "Latest" is not a version (`foundations/anchoring.md`). | A suggestion's full reason names the deliveries it compared ("revenue-v2.png delivery 1 has the exact bytes of revenue.png delivery 2"). |
| Group with space, alignment and type, not boxes in boxes (references U04). | Cards stay only for things that are one object: the preview page, a suggestion banner, and a tinted statement that needs a look. Information, Versions and Project are sections with a heading and a rule. |
| Results are announced (`interaction/feedback.md`). | Joining, keeping apart, moving, putting back, showing inside, undoing and copying are each announced to VoiceOver once, in the words of the Corrections list. |
| No percentage or end time without real progress (U06). | "Reading agent logs…", "Checking…" and "Verifying…" show the running mark, never a number. |

## Fewer words

A state is said in three tiers, and only as far as it needs.

1. **The mark.** It is drawn for a meaning that recurs and doesn't change:
   - whether the bytes were seen at delivery, in each Versions row;
   - which agent delivered, in each row and under Information;
   - a project's origin;
   - join, keep apart, show apart;
   - a source that needs a look, at the end of the sidebar's Sources row (Mail marks a mailbox it couldn't read the same way).

   A state that is as it should be shows its mark alone, or nothing. Mac lists mark the exception, not the rule.
2. **The label.** One to three words beside the mark, for a state that needs a look: "Changed", "Not on disk", "Unavailable · not on disk", "First seen later". Status labels use sentence case and controls use title case (HIG).
3. **The sentence.** Why, behind ⓘ, in the help tag and for VoiceOver. It goes inline only in a tinted panel, where something can't be handed over and the person must decide what to do.

Every sentence was rewritten to say one thing once.
- **Who is speaking.** "Gleaner" appears only where it matters who checked.
- **Undo.** "Can be undone" became Edit › Undo, which takes back a join, a keep-apart or a move, as a Mac app's edits do.
- **Names.** The decisions and controls are named as verbs: Join and Keep Apart (was Same Work and Not the Same), Project (was Where This Belongs), Information and More Info (was Details: path, hashes, session log), Corrections (was Your Corrections). The Corrections list, the announcements and the undo names use the same verbs: "Joined", "Kept … apart", "Moved … to".

The invariants the reviews set still hold, each tested in `WordingTests`:
- an unreadable path is never called changed, gone or seen;
- every label naming a delivery keeps "first seen later";
- "no longer" is said only of bytes Gleaner had.

## Hierarchy, after first-party apps

| Place | Laid out as | What it holds |
|---|---|---|
| Content list | Mail's message list | Each row has, in order: the file's own icon; its name in semibold, with the agent's mark and the date at the end (the time today, then the day, then the full date); your request in secondary text; and only when needed, a line with its place and anything that needs a look. |
| Detail | Finder's preview pane | **The file.** Its icon (48 pt) and name are the thing you drag, with the grab pointer and a hover wash. Under it, one line: the hand-off state, which bytes, and their hash. Open and Show in Finder sit beside it; Quick Look, Copy Path, Copy Resume Command and Save a Copy are in its menu. Under it come a suggestion banner, and a tinted panel only when the version can't be handed over or comes with a caveat. **The preview.** A page as tall as its text, up to 480 pt, scrolling past that. **Information.** Labels right-aligned, as Get Info aligns them: Request, Reply, Agent, Delivered, On Disk, Location, Delivered With. **Versions.** One table, with fixed columns and a Compare column kept on every row. **Project.** **More Info.** |
| Outline | A Finder window's grouped list | The project header (name, counts, folder, Recent). Suggestions, with their count and one footer. Then each folder as a section. A work the person moved in says so on its row. |
| Sources | A System Settings pane, `Form` with `.grouped` style | The agent's mark and folder; Status with ⓘ, Last Read and Deliveries; Read Again; each read problem as its own section; what Gleaner reads and what it skips, as rows. Corrections and Storage are panes of the same kind. |
| Sheets | System sheets | One line of explanation, a list, and Cancel and the default button. |

Files are drawn with the icon Finder uses for their type (`NSWorkspace.icon(for:)`), so the extension stays in the file's name and needs no badge. The icon depends on the apps installed, as it does in Finder.

## Agents' marks

`Sources/Gleaner/ProviderMarks.swift` draws Claude Code and Codex from the `claudecode` and `codex` drawings of [lobe-icons](https://github.com/lobehub/lobe-icons) (MIT). That is the set [Magpie](https://github.com/yetone/magpie) bundles for agents and model vendors, byte-identical to the lobe master in the files compared. The marks belong to Anthropic and OpenAI. Gleaner uses them only to say which agent's logs a delivery came from, and the agent's name stays in the help tag and for VoiceOver. Each mark is drawn in two ways:
- **Color** (Claude's orange; Codex's tile and gradient), where the agent is named on its own: Information, Sources.
- **One ink**, where it repeats on every row.

## Marks

`Sources/Gleaner/Glyphs.swift` draws Gleaner's marks natively from SVG path data. Each is on the kit's 24-point grid, with a 1.5 stroke that scales with the size and never draws under 1 point, round caps and joins. The renderer reads SVG path syntax, elliptical arcs included, stops at numbers after a close rather than repeating it, and takes any whitespace between numbers. `GlyphTests` checks that every mark and agent mark draws inside its grid. Twenty-six marks are copied from the kit's `glyphs.svg`. Two are Gleaner's own, drawn to the same grid:
- **repository**: three nodes and a branch, for git projects;
- **work**: a file with another behind it, for one work in several files.

In a sidebar, a mark follows the row as an SF Symbol would: it uses the size set for sidebar icons, and turns white on an emphasized selection. Native chrome keeps the system's symbols: the toolbar, menus, ⓘ, and the empty states that are the system's own.

## Space, radius and motion

`Sources/Gleaner/Style.swift` sets these:
- **Space:** a 4-point step (4, 8, 12, 16, 24, 32). Sections of the detail are 24 apart, and items inside them 8.
- **Radius:** two values, 4 for tags and 10 for cards.
- **Motion:** three durations, each named for what it shows, after the kit's tokens:
  - 120 ms for hover and press;
  - 200 ms for a state switching or something arriving or leaving;
  - 240 ms for something moving to where it now is.

Motion follows the model, which has already changed. A new click reverses or replaces an animation, and nothing waits for one. Under Reduce Motion there is no motion, and an arrival only fades; the words and marks still change.

Where motion shows something:
- **Arrivals and departures:** a suggestion arriving, a join or keep-apart line appearing, and more Delivered With files. They rise 8 points as they fade in and leave by fading only.
- **State switches:** a statement crossfades in place when its words change for the same delivery. Copy and Copy Resume Command switch to "Copied" with the done mark, then back; both labels keep one width, and a second click starts the moment again.
- **Hover:** the file at the top of the detail washes under the pointer, and links darken their underline.

Not moved:
- **Selection changes** swap at once. The detail's file and each work's Project section are new views for each selection, so nothing animates between two files.
- **Counts** change at once, never tweened.
- **Nothing flies** across the window.

## Checked

- **The tour.** `GLEANER_TOUR=<folder> swift test --filter TourTests` draws each step of the board walk in light and dark. It also draws a sheet of every mark at 32, 16 and 11 points, the agents' marks in color and in one ink, and four file icons.
- **The suite.** 213 tests pass, `WordingTests` and `GlyphTests` included.
- **Not checked:**
  - VoiceOver listening;
  - real hover, drag and the ⓘ popovers in a running window;
  - the sidebar's marks on a focused selection, and at each sidebar icon size;
  - Increase Contrast;
  - large text;
  - narrow widths.

  These need a person at the window. The tour's pictures leave out the toolbar and draw the sidebar's selected row as a black bar. They draw content under the toolbar's band faded, and Quick Look's previews blank. The window itself draws all of these.
