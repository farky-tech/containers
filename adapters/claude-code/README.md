# Claude Code Adapter

This adapter describes how the plugin assets become Claude Code runtime behavior.

## Intended Mapping

- `hooks/session-start.md` -> SessionStart hook behavior.
- `hooks/user-prompt-submit.md` -> UserPromptSubmit hook behavior.
- `hooks/post-tool-use.md` -> PostToolUse hook behavior.
- `hooks/stop.md` -> RETIRED (historical spec; do not wire — see the file).
- `hooks/session-end.md` -> SessionEnd hook behavior.
- `hooks/pre-compact.md` -> PreCompact hook behavior.
- `subagents/*.md` -> `.claude/agents/<name>.md`.
- `templates/memory-folder/` -> project `memory/`.

What is active immediately after `/plugin install`: the 8 `skills/`, the 3 agents, and the
read-only kernel SessionStart hooks from `hooks/hooks.json` (sentinel + capability self-report).
Everything invasive is opt-in — see "Turn on the nerves" below.

## Install — public flow [verified 2026-07-13]

This repo is **both the plugin and its own marketplace** (`.claude-plugin/marketplace.json`
with `source: "./"`), so a stranger needs exactly two commands plus the seeder:

```txt
/plugin marketplace add <github-user>/<this-repo>    # or a local clone path
/plugin install farky-memory-container@fmc
```

Then seed your project's `memory/` (from the plugin cache dir or your clone):

```sh
bash scripts/install_project_template.sh --with-scripts /path/to/your/project
```

Versioned pull (how an upgrade reaches you):

```sh
/plugin marketplace update fmc     # re-scans; a bumped plugin.json version becomes installable
/plugin update farky-memory-container@fmc
```

Auto-update is **OFF by default** for non-Anthropic marketplaces — the pull is deliberate, so
the source never silently overwrites a running install. That is intended honest-opt-in behavior.
Note: a release made while your session is RUNNING does not reach that session — the plugin
root is resolved at session start; finish the session and start a new one on the fresh engine.

**Engine vs. memory:** installing/upgrading delivers only the **engine** (scripts, skills,
agents, hooks). Your **memory** — the project `memory/` folder — is your data; it is written via
`--memory-dir ./memory` and never shipped or overwritten by an install/update. See the
`using-container` skill and README "Structure — engine vs. memory".

*(Maintainer-internal note: the source machine also runs a private directory marketplace
`farky-local` over the parent `pluginy/` folder — same mechanism, different catalog. Adopters
don't need it.)*

## Turn on the nerves — self-improvement close-loop (OPT-IN)

`scripts/close_state.sh` + the SessionStart/SessionEnd/PreCompact hooks form a close-debt loop:
a session that did real work without a conscious close leaves a marker, and the next boot
surfaces it for catch-up (`/close --auto <SID>`) — the debt is never silently lost. It is
**opt-in and NOT force-wired into `hooks/hooks.json`** — these hooks write memory-state and
would cross the trust boundary if inherited automatically. Enable: paste the close-loop blocks
from `settings-fragment.example.json` into your settings and have your project CLAUDE.md close
rule call `close_state.sh --close-done` at the end of a conscious close. The close itself stays
the MAIN HEAD's job (retro); the machinery only tracks and catches up.

## Turn on the nerves — boot info-injection (OPT-IN)

Four *injector* scripts turn boot from "reminders to open files" into **ready facts in context**
(info-injection > reminder). All are **opt-in and NOT force-wired** for the same trust-boundary
reason. Enable by pasting the boot-nerve blocks from `settings-fragment.example.json`:

- `scripts/state_inject.sh` (SessionStart) — inject `memory/STATE.md` (orientation, read-first).
- `scripts/capability_inject.sh` (SessionStart) — inject the FMC backbone + capability **drift**
  since last boot (new / gone) + a reminder of unprocessed `.capability-inbox`. No bare counts.
- `scripts/index_inject.sh` (SessionStart) — inject a folder-INDEX map (what lives where);
  refreshes each folder's `INDEX.md` and injects only the manifest table. Default scope =
  `memory/` only (boot diet); **opt-in `--whole-repo`** (= `--scope repo`) injects the whole-repo
  map — all tracked top-level folders (tracked = has an `INDEX.md`) + a root rollup (0.1.31).
  Root marker `gen_index:tree` upgrades this to the recursive safe tree; managed
  `ostatni-v-repu/INDEX.md` with `gen_index:root-files` owns loose root files (0.3.4).
- `scripts/journal_prompt.sh` (UserPromptSubmit) — silently feed each prompt into
  `memory/session.md` (write-only: no stdout, never non-zero; secret-redacted before write
  since session.md is git-tracked).

Engine paths in the fragment: `${CLAUDE_PLUGIN_ROOT}` resolves ONLY inside hooks the plugin
itself ships (hooks/hooks.json) — in hooks pasted into your project settings (this fragment) it
is empty, so the FALLBACK segment is what actually runs. Fill it in always, and never point it
at a versioned marketplace cache path (the version segment changes on every upgrade and the
hooks go silently dead) — see the fragment's `_comment` (field report cc_chobotnice
2026-07-16). Keep injector output
lean — the cost is **attention**, not tokens. If an injector grows into a doc dump, that breaks
the SessionStart "must not dump full plugin docs" rule.

## Safety

Do not overwrite existing `.claude/settings.json` or `.claude/agents/` automatically.

**Hook install needs an explicit, in-turn user instruction.** Claude Code's auto-mode
classifier denies an agent editing its own `.claude/settings.json` (hooks / permissions)
unless the user explicitly asks for it in that turn — the agent cannot self-wire hooks
silently. In practice: the user says "wire the hook" / "write it", pastes
`settings-fragment.example.json` themselves, or uses `/hooks`. If a project's settings.json
uses `bypassPermissions`/broad allow-lists, put the hooks in `settings.local.json`
(hooks-only) instead — the classifier blocks even surgical edits of the former. Treat a
blocked hook install as a reportable fallback (it would have changed behavior), not a
silent skip. *(Field-verified by early adopters, 2026-06.)*

## Fallback

If a Claude Code runtime does not support one of these hooks, the main agent must report the
missing expected hook as fallback only when that hook would have changed behavior.
