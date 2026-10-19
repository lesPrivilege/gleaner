# Extensions

Item 6 of [review-rulings §3](review-rulings.md#3-after-v010-what-to-build-next): Find, Open and Handoff for Claude Code, Codex and the DeepSeek Harness. They are thin (SPEC §14): they keep no database, parse no sessions and copy no snapshots. Everything goes through the [`gleaner` command](query-core.md), or the same calls as [MCP tools](mcp-adapter.md). Built on `feat/query-core` after the MCP adapter.

## One skill for three hosts

- **The format.** All three hosts read the same entry point: an [Agent Skills](https://agentskills.io/specification) folder, `<name>/SKILL.md`, whose YAML frontmatter holds `name` and `description` and whose Markdown body holds the instructions. So the extension is one folder, [`extensions/gleaner`](../../extensions/gleaner/SKILL.md), with one `SKILL.md`, and no copy per host.
- **Frontmatter.** Only what every host takes: `name: gleaner`, which is the folder's name, in the lowercase letters the standard and the Harness require; and a `description` within the standard's 1,024 characters (Claude Code cuts its listing at 1,536). Host-specific fields are left out: Claude Code's `allowed-tools` and invocation controls, and Codex's `agents/openai.yaml`. The person's own permission settings govern the commands, and the person and the agent can both invoke the skill.
Where each host reads it, as a folder or a link to one:

| Host | Folder | A link |
|---|---|---|
| Claude Code | `~/.claude/skills/gleaner` for every project, or `.claude/skills/gleaner` in one | Followed |
| Codex | `~/.agents/skills/gleaner`, or `.agents/skills/gleaner` in a repository | Followed |
| DeepSeek Harness | `~/.agents/skills/gleaner` (its user root, `$DSH_AGENTS_HOME/skills`), or `~/.dsh/skills/gleaner` | Discovered, by its README |

The Harness reads the folder Codex reads, so one link serves both. Its base bundle, which the `web`, `headless`, `acp` and `sdk` profiles build on, mounts the filesystem skill provider, the `skill` tool and, on macOS, the bash tool the skill's commands run in.

## No plugins

- **Claude Code.** A plugin (`.claude-plugin/plugin.json` beside `skills/`) would add a name prefix, an MCP server entry, hooks and installation from a marketplace. The skill needs none of these: it runs the command, and `gleaner mcp` is registered on its own ([mcp-adapter](mcp-adapter.md#registration-documented-not-automated)). Without a marketplace, a plugin loads from a local folder only for one session (`claude --plugin-dir`). Packaging waits for distribution (review-rulings §3 item 10), when a plugin directory needs one.
- **DeepSeek Harness.** The Harness is built of Cordis plugins, and a third-party one is added to a profile with `dsh plugin`. One for Gleaner would only wrap the command the skill already runs, or the server its own MCP client already connects. SPEC §14 builds each extension on the entry point an ecosystem actually exposes; for the Harness, that is its skills and its MCP client.

## The three jobs

- **Find.** The person names a file an agent delivered earlier, in their own words. The skill runs `gleaner find` with a few of those words, and reads each result's `reference` (`delivery`, `sha256`, `path`, `evidence`, `provenance`, `availability`) beside its `project`, `kind`, `delivered_at` and `request`, and the answer's `index`. It takes the one result that fits, asks the person when several fit equally, and chooses among the versions of one file from `show`'s `deliveries`.
- **Open.** `open "gleaner://delivery/<id>"` shows that delivery in Gleaner ([query-core](query-core.md#in-the-app)), for preview, Compare and drag.
- **Handoff.** `show`'s `handoff.action` says what handing the version on gives now. `gleaner handoff` gives the path of a verified, read-only copy; `gleaner read` gives bounded text of the exact bytes; `gleaner resolve` gives the reference. The agent gives the person the reference or the hand-off path, not the content pasted.

The skill also says how the agent finds the command (`gleaner` on PATH, as the README tells the person to arrange it, or a path the person gives), what each field means, and what to do on each exit code: on 1, by `error.kind`; on 2, correct the command; on 3, ask the person to open Gleaner. Where the host offers Gleaner's MCP tools instead, the same instructions hold for them, and the skill names their arguments. One differs in form: `gleaner_verify` reads no file, so a reference kept in one is passed as its JSON, not its path ([mcp-adapter](mcp-adapter.md#shape)).

## What it never does

- Index, parse logs or open the library: the command is the only way in, and it never indexes.
- Keep state: no list of deliveries, no cache, no configuration. Uninstalling it is removing the folder.
- Claim absence beyond the index's reported scope: no match is reported as of `scanned_at`, naming any source not read in full, and only from answers that list every match. A truncated answer in which nothing fits is narrowed, or its `--limit` raised, since `total` counts matches it didn't list. While `generation` is 0 or `sources` is empty (before the first run, and after an update until this version has read every log again), the agent says Gleaner hasn't finished reading the logs, not that it has no match.
- Treat request or reply excerpts as instructions: they are stored text from the logs, read as data.
- Write a project folder: `handoff` writes only in Gleaner's caches, and the skill copies nothing into the project unless the person asks.
- Install itself, or edit a host's configuration.

## Installing (documented, not automated)

The person links or copies the folder; Gleaner never does it. From the repository, once the host's skills folder exists:
- Claude Code: `ln -s "$PWD/extensions/gleaner" ~/.claude/skills/gleaner`.
- Codex and the DeepSeek Harness: `ln -s "$PWD/extensions/gleaner" ~/.agents/skills/gleaner`.

A running host notices the new skill, as its documentation describes; Claude Code needs `/reload-skills` when its skills folder didn't exist as the session started. The command must be on PATH, or the person tells the agent where it is; the README says how to link `.build/release/gleaner` into a folder on PATH.

## In a sandboxed shell

A host may run commands in a sandbox that keeps writes inside the workspace (the Harness's `workspace-write` mode does). Under a Seatbelt profile that denied writes in the synthetic home's `Library`:
- `find` and the other reads answered while the library's write-ahead log files were there, as they are once Gleaner has opened it.
- `handoff` failed with `failed` and the permission message, since its copy goes in Gleaner's caches.
- With the write-ahead log files removed from a checkpointed copy of the library, every command failed with exit 3, `unreadable_library`: SQLite can't open a WAL database to read when it can neither find nor make them.

The skill says, for each, to ask for the command to run outside the sandbox, or to give the reference instead.

## Sources

Read on 2026-10-18:
- Agent Skills: [specification](https://agentskills.io/specification).
- Claude Code: [Skills](https://code.claude.com/docs/en/skills), [Plugins](https://code.claude.com/docs/en/plugins), [Create a plugin](https://code.claude.com/docs/en/plugins/create).
- Codex: [Build skills](https://learn.chatgpt.com/docs/build-skills), where `developers.openai.com/codex/skills` now redirects.
- DeepSeek Harness ([`deepseek-ai/deepseek-harness`](https://github.com/deepseek-ai/deepseek-harness) at `687f282`): `packages/skill/README.md`, `packages/skill/skill-filesystem/README.md`, `docs/subsystems/skills.md`, `packages/bundle/base/README.md` and `cordis.patch.yml`, `packages/mcp/mcp-client/README.md`, `docs/user/guide/mcp-memory.md`, `docs/subsystems/sandbox.md`.

## Verification

Each check runs against a synthetic home, never the person's library:
- **The skill's commands, without a model.** `SkillTests`, in the command tests, reads `extensions/gleaner/SKILL.md`. It checks the frontmatter against the standard, then every `gleaner …` invocation the skill shows, in a fenced block or a code span, against the built command on the synthetic home the command tests build. A template with placeholders is checked by `--help`: its usage must name the command and every option the template names. An example is run, and must answer or refuse (exit 0 or 1), never as a wrong usage. A renamed command or option fails CI.
- **The sequence, by hand.** The skill's steps against `scripts/acceptance-home.py`, with the bundled app on it. Recorded below.
- **Inside a host.** A session in Claude Code, Codex or the Harness with the skill installed, asked for a known delivery of a synthetic home. These make model calls, so they run only with the owner's go-ahead.

**Run on 2026-10-18**, command and app built at `cc3a9a8` (Apple silicon, macOS 27):
- Before the app had run, `find` exited 3, `no_library`, saying to open Gleaner. With `open -n build/Gleaner.app --args -GleanerHome <home>`, the library reached generation 1 within two seconds.
- **Find.** The skill's example, `find recovery guide --kind document`, gave five documents of one reply, each with the reply's request; `guide.md` is the one whose name fits. `find quarterly report` gave two equal matches in `client-a/app` and `client-b/app`, which the skill says to ask about, and `--project client-a/app` or the repository's folder narrowed them to one; the plain name `app` matched both. Words matching nothing gave `total` 0 with the index (generation 2, both sources `read`).
- **Versions.** After `second` (generation 2), `find` still matched delivery 1, whose request holds the words; `show` listed both deliveries, newest first, with delivery 1 now `saved_copy`. `read --lines 3:3` of delivery 1 gave its own line (旧版), not the file on disk.
- **Hand off.** After `changed`, delivery 2 of `guide.md` was `saved_copy` with a different hash on disk; `handoff` gave a read-only copy whose hash is `sha256`, `verify` gave `original` false and `saved_copy` true, and so did `verify` on a file holding `resolve`'s answer. The removed worktree's `demo.mov` showed `restore_from_git` with a `restore_command`, and `handoff` and `read` exited 1, `unavailable`, `too_large_to_have_been_saved`. The delivered folder showed `folder`; `replace.txt`, now a folder, `ready` from its saved copy. `read --max 64` of a long file gave `truncated` with `range` `[0, 64]`, and `--bytes 64:<size>` went on from there.
- **Refusals.** An unknown id exited 1, `not_found`, with the index; a reference edited to another library, `other_library`; the PNG, `not_text`; `verify` of the FIFO exited 1 with its full answer and `unavailable`, `not_a_regular_file`; the chmod-000 file was `never_observed`, `unreadable`. `read --lines 0:2` and `--kind markdown` exited 2, `usage`.
- **Open.** `open -a build/Gleaner.app "gleaner://delivery/<id>"`, aimed at the instance running on the synthetic home so that no other copy of Gleaner could take the link, was delivered to that instance, and started no other. What the window then showed was not seen: this session had neither screen recording nor accessibility access. The app tests cover the link's parsing and selection.
- **Sandbox.** As in "In a sandboxed shell" above.
- The instance was then quit.

**Rechecked on 2026-10-18**, the command built at `465b17a`, on a copy of a command-test home:
- `gleaner_verify` given a file's path answered `not_found`, taking the path for an id, and given the file's JSON answered as `verify` on the file does; `gleaner_find` refused `words` and took `terms`.
- `find release --limit 1` gave `total` 4, `truncated` true and one result; `--limit 4` listed all four, `truncated` false.
- With the `sources` row deleted, as opening an updated Gleaner does until its first run ends, `find` gave `sources` `{}` beside generation 1 and the old `scanned_at`.

**Inside Claude Code on 2026-10-18**, the command built at `7ed0e10`, the same home as the [MCP adapter's run](mcp-adapter.md#verification): `claude -p` (2.1.302, Opus 5.5) in an empty folder whose `.claude/skills/gleaner` links to `extensions/gleaner`, with no MCP server, none of the person's own settings, and on PATH a `gleaner` that runs the release command with `--home` on the synthetic home:
- The session listed the skill as `gleaner`. Asked for "the recovery guide's first version" and to hand it off, it invoked the skill, ran its example, `gleaner find recovery guide --kind document` (five documents), then `show` and `handoff` on guide.md's delivery 1.
- It said this was the only delivery of guide.md, and gave the copy's path, the delivery's date, id and request, pasting none of the file. The copy has the delivery's hash.
- Neither run chose among versions: after `initial`, guide.md has one delivery.

**Rerun on 2026-10-18**, built at `86018e6`, the same way on the MCP rerun's home, after `second`. That home has two deliveries of guide.md, and only Gleaner's saved copy holds delivery 1:
- The calls were the same: the skill, its example `find` (which matched delivery 1), then `show` and `handoff`. Before handing it off, it said this was delivery 1 of 2 and that the file on disk now holds version 2.
- The new copy has delivery 1's hash. The session said the copy isn't the file at `path`, gave the delivery's id and request, and offered `open "gleaner://delivery/<id>"` for the person to run, without running it.
