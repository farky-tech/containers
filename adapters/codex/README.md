# Codex Adapter

## What Works Now

Codex 0.144.1+ can load both the plugin's skills and its host-specific lifecycle hooks through
`.codex-plugin/plugin.json`.

Active after plugin installation:
- `capability-routing` (absorbs the former trigger-calibration + runtime-capability-map)
- `no-silent-fallback`
- `session-close`
- `memory-routing`
- `skill-authoring`
- `capability-audit`
- `lapac`
- `using-container` (engine vs. memory guide)

Project template can be installed manually (use `--with-scripts` — without it the
templates reference backbone scripts you will not have):

```sh
scripts/install_project_template.sh --with-scripts /path/to/project
```

Lifecycle automation is packaged separately from Claude Code:

- `.codex-plugin/plugin.json` points to `adapters/codex/hooks.json`.
- `SessionStart` runs one sequential dispatcher so boot nerves cannot race each other.
- `UserPromptSubmit` captures the prompt through the redacting journal script.
- `PreCompact` surfaces a non-blocking continuity reminder.
- The dispatcher is inert unless the current project or an ancestor carries `memory/MEMORY.md`.
- A root `INDEX.md` with the `gen_index:auto` marker opts the project into the whole-repo map;
  otherwise only the memory manifest is injected.

Codex requires trust for the exact hook definition. After install or any hook change, open
`/hooks`, review the plugin-bundled commands and trust them. Trust is hash-bound, so a later hook
change correctly asks for review again.

## Deliberately Not Wired

- `Stop` remains retired: the old hook produced noisy mid-work close nags and did not enforce a
  real close.
- `SessionEnd` is not part of the current Codex lifecycle schema. Recovery therefore happens at
  the next `SessionStart`, while the main-head close remains governed by `AGENTS.md` and the
  `session-close` skill.
- `subagents/*.md` remain specs; Codex does not auto-register them from this plugin package.

If an expected Codex hook is missing, skipped or fails, report it as fallback.

## Recommended Codex Runtime Behavior

Use the plugin quietly:

- trigger `capability-routing` only for explicit container work, fallback/memory/close/audit/research, container-file work, or continuity-sensitive project work,
- use the Codex lifecycle adapter quietly after its definitions are trusted,
- treat subagent files as spec-only unless a host adapter installs them,
- do not narrate normal skill use,
- report missing hooks/subagents as fallback only when they were expected,
- use `lapac` for long-running chat work and visible handoff continuity (carry forward via `scripts/ledger_carry.sh`),
- use `session-close` for larger work or when fallback/durable learning occurred.

## Local Codex Marketplace Install

Codex installs plugins from configured marketplace snapshots. A local plugin folder with
`.codex-plugin/plugin.json` is not enough by itself; the parent marketplace root must contain
a supported marketplace manifest at `.agents/plugins/marketplace.json`.

Recommended layout for a local marketplace root:

```txt
/path/to/pluginy/
  .agents/plugins/marketplace.json
  farky-memory-container/
    .codex-plugin/plugin.json
    skills/...
```

Minimal `marketplace.json` entry:

```json
{
  "name": "farky-local",
  "interface": {
    "displayName": "Farky Local"
  },
  "plugins": [
    {
      "name": "farky-memory-container",
      "source": {
        "source": "local",
        "path": "./farky-memory-container"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      },
      "category": "Productivity"
    }
  ]
}
```

Install flow:

```sh
codex plugin marketplace add /path/to/pluginy
codex plugin add farky-memory-container@farky-local
codex plugin list
```

After installation or upgrade:

1. restart the ChatGPT desktop app or start a fresh Codex process,
2. open `/hooks`, review and trust the current FMC hook definitions,
3. start a new Codex task in an FMC project,
4. verify that the startup context contains STATE/capability/index information and no false
   `0 of 7 wired` report.

Existing running tasks do not retroactively reload a changed plugin or rerun `SessionStart`.
