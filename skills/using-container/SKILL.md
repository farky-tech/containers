---
name: using-container
description: Use when an agent is adopting, installing, tuning, upgrading, or modifying the capability container plugin, or is unsure where its own memory belongs relative to the plugin versus where to propose a change to the shared source. Explains the engine/memory split, how to use the backbone, where to write (own memory -> project memory/; proposals -> ADOPTION.md), and what not to do (don't overwrite the engine, don't trim it to the bone, don't hollow out the container by over-bridging). Do NOT use for authoring a brand-new standalone skill (see skill-authoring), for building a plugin from scratch (general plugin craft, not this container), or for choosing which memory TYPE a note is -- lesson vs. decision vs. profile (see memory-routing); this skill covers placement relative to the plugin, not memory-type routing.
license: MIT
metadata:
  hermes:
    tags: ["hermes", "onboarding", "engine-vs-memory", "contribution"]
    related_skills: ["capability-routing", "memory-routing", "no-silent-fallback", "session-close", "skill-authoring"]
---

# Using the container

This is a **quiet-by-default capability container**: the agent remembers it has
capabilities, uses them without ceremony, and never falls back silently. This skill is the map for
living with it correctly. Read it before you adopt, tune, upgrade, or change the plugin — so you
don't repeat mistakes earlier adopters already made.

## Understand it: engine vs. memory vs. constitution

Three layers. Mixing them up is the most common mistake here.

- **Engine** — generic machinery (`scripts/`, `skills/`, `agents/`, `hooks/`, `manifest.yaml`). Same
  for every project, versioned as one unit; an upgrade replaces it. **Never hand-edit the engine in
  your copy** — if you want it to behave differently, propose it (see *Where to write*). Editing it
  in place makes your copy drift and lose future upgrades.
- **Memory** — YOUR data: the project's live `memory/` folder (journal, lessons, decisions, capability
  index, carry-forward). It has **no other home**, and an upgrade never touches it. The engine writes
  here via `--memory-dir ./memory`.
- **Constitution** — your behavior rules live in your own `CLAUDE.md` / `AGENTS.md`, not in the plugin.
  Two reflexes (per-task brief, close retro) are main-head work — keep them in your constitution, not
  here (the `session-close` skill only does the mechanics).

## Use it

- Normal capability use is **silent** — check the capability index, use the fitting skills/scripts,
  keep moving. Speak up only for fallback, missing capability, risk/gate, contradiction, or close.
- Write to memory through the **backbone scripts**, not by hand: `session_note.sh` (journal),
  `memory_route.sh` (lessons/decisions, approval-gated), `ledger_carry.sh` (carry-forward + `--done`),
  `fallback_log.sh` (fallbacks + `--resolve`), `close_state.sh` (close-debt tracker + ledger gate + boot-recovery),
  `session_close.sh` (handoff compose). Always pass `--memory-dir ./memory`. They are deterministic, atomic,
  and idempotent — that is why they are scripts, not prose you run in your head. (2-occurrence candidates now
  live as tagged `CANDIDATE(type):` lines in `todo.md` — the kandidat/goqueue/loop_state scripts were retired.)
- **No silent fallback.** If a planned capability cannot run — replaced, weakened, skipped, refused —
  report it. A missed gap is the same as a silent fallback.

## Where to write

- **Your own memory** (what you did / learned / decided / left unfinished) -> the project `memory/`
  folder. It is the only place these belong.
- **A change, gap, or fix in the shared source** -> an entry in `ADOPTION.md` (what, why, how, which
  files). This is the designated place. Propose before large rewrites; small grounded patches can go
  straight in; append, never delete others' entries. The history of what broke is itself the value.

## What not to do (real failures earlier adopters hit)

- **Don't overwrite the engine.** Want different behavior? Propose it in `ADOPTION.md` — don't silently
  fork the source in your copy. A fork does not auto-update when the source improves; you inherit
  nothing and drift alone.
- **Don't trim it to the bone.** Tune = adapt and fill with your real capabilities, not cut. "I added
  a bridge instead" is not a license to omit content. Only plugin-infra (installer, tests, adapters)
  is safe to drop. (cc_pas once trimmed away prompts, templates, and the primitives concept.)
- **Don't hollow out the container by over-bridging.** The richer your existing memory, the more tempting it
  is to route every concept to "lives elsewhere." Bridge *project memory* and *constitution* only —
  never your journal, lessons, decisions, or carry-forward, which have no other home. An empty container
  is no memory of yourself. (cc_fenix, 2026-06-27.)
- **Don't write your capability index from memory.** Verify from real state (`ls`, settings, tool list)
  before writing what you "have." Onboarding from recall produces capabilities you do not actually
  have. (cc_pas once listed agents that did not exist.)

## Verify

- After changing the plugin, run `scripts/capability_audit.sh` — declared (manifest) vs. disk vs.
  runtime must be drift-free.
- `claude plugin validate .` is the first gate for manifest and structure.

## Related

- `README.md` -> full "Structure — engine vs. memory" map + "Installing on yourself (tune, don't
  trim)" + host-side reflexes.
- `ADOPTION.md` -> the adopter loop and field-feedback log.
- Skills: `capability-routing`, `memory-routing`, `no-silent-fallback`, `session-close`,
  `skill-authoring`.
