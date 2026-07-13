# Codex Adapter

## What Works Now

Codex can load the plugin's `skills/` through `.codex-plugin/plugin.json`.

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

## What Is Spec-Only In Codex

These files are included for routing and future adapter work, but are not automatically active in Codex:

- `hooks/*.md`
- `subagents/*.md`

If a Codex session expects a hook/subagent from this plugin and it is unavailable, report it as fallback.

## Recommended Codex Runtime Behavior

Use the plugin quietly:

- trigger `capability-routing` only for explicit container work, fallback/memory/close/audit/research, container-file work, or continuity-sensitive project work,
- treat hook/subagent files as spec-only unless a host adapter installed them,
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

After installation, start a new Codex thread to test that plugin skills are exposed in the
runtime skill list. Existing running threads may not pick up newly installed skills.
