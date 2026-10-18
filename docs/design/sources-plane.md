# Sources as a control plane

Opus, 2026-10-18. The owner asked for the sources to reach, before the release, a control plane the person can see and manage:
- **Topology.** It is completed from what the logs say. The drawings are the providers' own marks, not drawings made for the occasion.
- **Connections.** Each one has a switch, much like a slide toggle, with a button to open the panel.
- **Reference.** Magpie (github.com/yetone/magpie), a menu-bar gateway that routes coding agents to other model vendors. It shows each agent with its vendor marks and switches.

This supersedes two items under "Not in this contract" in [projects-and-works.md](projects-and-works.md): pausing a source, and the agent topology (now only the agent → provider → model line; fork and delegation views stay out).

## What the logs say

Magpie's code (MIT, read at d783df4) and its tests show where each agent records the model behind a reply.

| Agent | Provider | Model |
|---|---|---|
| Claude Code | not in the session log. A gateway is set in `settings.json` (`ANTHROPIC_BASE_URL`), which Gleaner doesn't read: it would sit beside the token. | `message.model` on the assistant record: the model the provider answered with, such as `claude-fable-5` or `deepseek-v4-flash` |
| Codex | `session_meta.payload.model_provider`: `openai`, or a configured provider such as `magpie` | `turn_context.payload.model`: the model the turn asked for; through a gateway, its catalog reference (`moonshot/kimi-k2.5`) |

The adapters read these into `Turn.model` and `SessionInfo.modelProvider`. The registry keeps them on each delivery and session. Extractor version 14 reads the logs again once to fill them, keeping every capture. This is an adapter change: it merges only with the owner's review (AGENTS.md). The Codex fixture's two new keys follow the shape Magpie reads and Codex documents. They are not from a sanitized real log.

## Marks

A model is matched to its vendor by its family name, as Magpie's `icons.go` matches it:
- a gateway's `vendor/` prefix is dropped first;
- a short family (`o3`) counts only whole or before a dash;
- a model that matches no family gets no mark, never a guessed one.

The vendors' marks are lobe-icons' monochrome drawings (commit 8a1b282), the set Magpie bundles, generated into `VendorMarks.swift`: Anthropic, OpenAI, Google, DeepSeek, xAI, Moonshot, Zhipu, Qwen, Mistral, MiniMax. Agents are drawn in their own colors where they are named alone. Model vendors are always in one ink, a step below the agent, because the agent is what Gleaner reads.

## The plane

- **A switch per agent**, in the Sources list, at the top of its page, and in the toolbar's Sources popover (a module like the ones a menu-bar app or Control Center shows, with Sources… and Check Now).
  - **Off:** Gleaner neither lists, reads nor watches the agent's logs, and the window shows none of its deliveries.
  - **Nothing is removed.** A delivery leaves the library only when a log read whole no longer names it, and an agent turned off has no logs read.
  - **On again:** everything shows at once, and the logs are read.
  - **Where the choice lives.** It is kept with the library (`sources_off`), not in the app's preferences, so a library opened with `-GleanerHome` keeps its own and an acceptance run never changes the person's.
- **The topology line**, on each agent's page: the agent's mark, the provider when its logs name one, and the vendors of the models that wrote its replies, the most-used first. The line is solid while the agent is read and dashed while it is off, which is the kit's "not in effect".
- **Models**, under it:
  - each model with its vendor's mark, the provider it went through, and how many deliveries it wrote;
  - an agent that is off still counts its deliveries, which are marked hidden.
- **The Model row** in a delivery's Information: the vendor's mark and the model's name. The provider is named when it isn't the agent's own (Codex's `openai`).
- **Trouble** from an agent that is off is no longer reported, and Try Again ignores it.

## Checked

- **The suite.**
  - The adapters read the model and the provider (`AdapterTests`).
  - Both survive storage and a reread (`LibraryFlowTests`).
  - A source turned off hides its deliveries and keeps them, its logs go unread, the choice survives reopening, and on again shows all (`LibraryModelTests`).
  - Models are matched to vendors (`GlyphTests`).
- **The tour.** The synthetic home now routes Codex through a gateway named `magpie` to `moonshot/kimi-k2.5`, and one Claude Code reply through `deepseek-v4-flash`. The tour draws Codex's page connected and off, and the popover on its own.
- **Not checked:** the toolbar button in a running window (the tour draws no toolbar), switches by mouse and keyboard, and real logs routed through Magpie.
