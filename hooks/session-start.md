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
- (self-improvement loop, auto-wired) run `close_state.sh --init` to start
  per-session close-debt tracking, so SessionEnd finalization and the boot
  recovery (`--boot-recovery`) have a baseline. (The per-turn Stop nag is
  retired — see hooks/stop.md.)

Must not:
- dump full plugin docs into context,
- force full memory read,
- block normal work if the container's project folder is absent.

Fallback:
- if no hook runtime exists, the agent performs this manually once and reports only if absence affects continuity.

## Boot nerves — info-injection (AUTO-WIRED, adapter-dispatched)

Beyond the kernel sentinel above, the engine ships SessionStart *injector* scripts that turn
orientation from "a reminder to open a file" into a **ready fact in context** (info-injection >
reminder). They are **auto-wired** (Fáze A, 2026-07-18): `hooks/hooks.json` calls
`adapters/claude-code/hook_dispatch.sh session-start`, which runs the whole nerve chain in a
deterministic order (parity with the Codex dispatcher). The dispatcher is **inert** unless the
project carries `memory/MEMORY.md` — installing the plugin does not seed a brain into every repo, so
there is no invasive injection across the trust boundary (§6d). Each nerve is silent + non-blocking
if its source is absent. (`adapters/claude-code/settings-fragment.example.json` is retired as a
required step — it survives only as a hand-wire override example for a custom memory-dir or an
in-repo fork.)

The dispatched SessionStart chain (see `hook_dispatch.sh`), in order:

- `scripts/close_state.sh --boot-recovery` / `--init` — recover any prior close debt, then baseline
  the current session's close-debt tracking.
- `scripts/brain_health.sh --due-check` — weekly brain-health cadence advisory.
- `scripts/state_inject.sh --memory-dir <dir>` — inject `memory/STATE.md` (orientation, read-first).
- `scripts/capability_inject.sh --memory-dir <dir>` — inject FMC backbone + the capability **drift**
  since last boot (newly gained / gone) + a reminder of unprocessed `.capability-inbox`. Adds only
  what the harness never tells you; no bare counts (irrelevant without value).
- `scripts/rejstrik_inject.sh --memory-dir <dir>` — regenerate + inject the atom registry (what I know).
- `scripts/pending_inject.sh --memory-dir <dir>` — announce open `PENDING(<owner>):` ledger items loudly until resolved.
- `scripts/index_inject.sh --memory-dir <dir>` — inject the **sum of folder INDEX tables** (what I have
  where, in which folder). Injects only the manifest table, not the curated/kernel header (signal over fluff).
- `scripts/state_guard.sh --fork-drift` / `--adopter-drift` — advisory drift warnings (never blocks).
- `scripts/capability_report.sh --startup` — "what you're missing" advisory; silent when all wired.

Guardrail: these inject context on every start, so keep their output lean — the cost is attention,
not tokens. If an injector grows into a doc dump, that violates the "must not dump full plugin docs"
rule above.
