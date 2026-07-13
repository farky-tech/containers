# SessionStart Hook Spec

Purpose: deliver the FMC kernel and local capability index at session start.

When:
- new project session starts,
- project root changes,
- user explicitly asks to activate FMC.

Action:
- insert a short sentinel: `FMC active (farky-memory-container)`.
- point to project `memory/MEMORY.md` if present.
- remind: silent work is OK; silent fallback is forbidden.
- (self-improvement loop, opt-in) run `close_state.sh --init` to start
  per-session close-debt tracking, so SessionEnd finalization and the boot
  recovery (`--boot-recovery`) have a baseline. (The per-turn Stop nag is
  retired — see hooks/stop.md.)

Must not:
- dump full plugin docs into context,
- force full memory read,
- block normal work if the container's project folder is absent.

Fallback:
- if no hook runtime exists, the agent performs this manually once and reports only if absence affects continuity.

## Boot nerves — info-injection (OPT-IN, adapter-wired)

Beyond the kernel sentinel above, the engine ships three SessionStart *injector* scripts that turn
orientation from "a reminder to open a file" into a **ready fact in context** (info-injection >
reminder). They are **opt-in**: enabled only by copying the SessionStart entries from
`adapters/claude-code/settings-fragment.example.json` into `.claude/settings.json`. They are
deliberately **NOT** wired into `hooks/hooks.json` — an adopter must not inherit invasive context
injection across the trust boundary (§6d). Each is silent + non-blocking if its source is absent.

- `scripts/state_inject.sh --memory-dir <dir>` — inject `memory/STATE.md` (orientation, read-first).
- `scripts/capability_inject.sh --memory-dir <dir>` — inject FMC backbone + the capability **drift**
  since last boot (newly gained / gone) + a reminder of unprocessed `.capability-inbox`. Adds only
  what the harness never tells you; no bare counts (irrelevant without value).
- `scripts/index_inject.sh --memory-dir <dir>` — inject the **sum of folder INDEX tables** (what I have
  where, in which folder). Injects only the manifest table, not the curated/kernel header (signal over fluff).

Guardrail: these inject context on every start, so keep their output lean — the cost is attention,
not tokens. If an injector grows into a doc dump, that violates the "must not dump full plugin docs"
rule above.
