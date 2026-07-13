---
name: capability-routing
description: Use when a task may need existing skills, subagents, hooks, tools, or the container's project memory. Routes capabilities quietly, calibrates whether to stay silent or speak, classifies runtime availability, and reports only skipped or unavailable relevant capabilities. Do NOT use for every ordinary implementation task just because it is non-trivial.
license: MIT
metadata:
  hermes:
    tags: ["hermes", "routing", "capabilities"]
    related_skills: ["no-silent-fallback", "memory-routing", "session-close"]
---

# Capability Routing

This skill absorbs two former skills: trigger-calibration (the silent/speak/fallback
decision) and runtime-capability-map (the availability classes). They are sections
here, not separate files — one decision, one place.

## When To Use

Use when at least one is true:

- the user asks for review, audit, research, close, fallback handling, or memory/learning;
- the project has a `memory/` folder and the task needs continuity, ledger state, prior
  fallback, or capability memory;
- the prompt obviously matches a known skill/subagent/tool;
- a previous fallback suggests a capability should exist;
- current work touches container capability files.

Do not use this skill for every ordinary implementation task just because it is non-trivial.

## Step 1 — Calibrate (pick exactly one)

- `silent-route`: a fitting active capability exists and can run normally → use it, do not narrate.
- `speak-up`: risk, gate, contradiction, explicit user request, or close/handoff needs visible output.
- `fallback`: an expected capability cannot run or was replaced/weakened/skipped → go to `no-silent-fallback`.
- `do-nothing`: no container capability is relevant.

Do not call optional or spec-only assets a fallback. Do not narrate `silent-route`.

## Step 2 — Classify availability (only what's relevant)

- `active`: currently callable in this host runtime (skills here, and the backbone scripts in `scripts/`).
- `adapter-installed`: installed by a host adapter and expected for this project.
- `spec-only`: documented prompt/spec asset, not automatically callable (e.g. the non-wired hooks).
- `manual`: available only by explicit invocation (e.g. the project-template installer).
- `unavailable`: not present or blocked.

Only `active` and `adapter-installed` may be *expected* by default. `spec-only`/`manual`
become expected only when the user asks, the plan promised them, or `memory/` files require them.

## Step 3 — Route to the concrete capability

Match the task to a capability and run it. The backbone scripts make the action
deterministic — prefer them over doing the write/close/log by hand:

| Task | Capability | Concrete call |
|---|---|---|
| Persist a durable fact/lesson/decision | `memory-routing` | `scripts/memory_route.sh` |
| Carry open to-do items forward | (ledger) | `scripts/ledger_carry.sh` |
| Record a real fallback | `no-silent-fallback` | `scripts/fallback_log.sh` |
| Close / handoff a session | `session-close` | `scripts/session_close.sh` |
| Check declared-vs-actual drift | `capability-audit` | `scripts/capability_audit.sh` |

(In Claude Code the scripts live at `${CLAUDE_PLUGIN_ROOT}/scripts/`; pass the project's
`--memory-dir ./memory`.)

## Step 4 — Account for what you skipped

- If a fitting *expected* capability is not used, state why.
- If an expected active capability is unavailable, go to `no-silent-fallback`
  (which logs it via `scripts/fallback_log.sh`).

## Verification

- Relevant active capabilities were checked.
- Used capability is visible in the final close when continuity matters.
- A skipped/unavailable expected capability is reported as a fallback, not swallowed.
