# CAN — Capability Routing

## Always

- Use relevant skills quietly.
- Use subagents for bounded independent work when available and useful.
- Use tools for actions they can validate better than prose.
- Use TodoWrite as the visible session ledger for long-running chat work.
- Report fallback, missing capability, risk, contradiction, or close.

## Capabilities

- `capability-routing`: explicit contAIner work, review/audit/close/memory/fallback, or continuity-sensitive project work. Absorbs the former trigger-calibration (silent/speak/fallback decision) and runtime-capability-map (availability classes) as sections.
- `no-silent-fallback`: when an expected active capability cannot run or is replaced → logs via `scripts/fallback_log.sh`.
- `session-close`: handoff, multi-step work, fallback, durable learning, direction change, explicit close → composes via `scripts/session_close.sh`.
- `memory-routing`: when something may be durable learning → proposes/commits via `scripts/memory_route.sh` (approval-gated).
- `skill-authoring`: when a repeated workflow/fallback should become a skill.
- `capability-audit`: when routing drifts or capabilities are forgotten → use the installed `capability-audit` skill and run `<plugin-root>/scripts/capability_audit.sh`. This maintainer/source verifier is not shipped in the adopter `memory/scripts/` backbone.
- `lapac`: long-running/multi-step work, discovered follow-ups, handoff continuity → carry forward via `scripts/ledger_carry.sh`. Also keeps the **session journal** (`session.md`) via `scripts/session_note.sh` — see MEMORY.md "How memory is written".
