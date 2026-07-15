# CHANGELOG — farky-memory-container

Engine version history. Version = single source of truth in `.claude-plugin/plugin.json`.
Newest first. Adopter-action detail → `MIGRATION.md`.

## 0.3.2 — recall fires by itself; PENDING decisions surface every boot

Two new **opt-in** nerves close the "the memory system lets things slip" gap:

- **`recall_inject.sh` (UserPromptSubmit, Claude Code host):** every prompt is matched against a
  FRESH atom registry (`gen_rejstrik --tsv`, fail-closed on generation failure) — BM25 with Czech
  diacritics folding + light stemming (Dolamic/Savoy), strict anti-noise gates (silence is the
  default; precision over recall) — and matching atoms are injected as POINTERS (slug + one line +
  "pull the atom BEFORE answering"). Per-session dedupe, both funnel sides logged to
  `.recall-hits.log`, kill switch `HERMES_RECALL_OFF=1`. Deliberately NOT dispatched on the Codex
  host (trust boundary — ask if you want it there).
- **`pending_inject.sh` (SessionStart):** todo items written as `- [ ] PENDING(<owner>): what /
  why-you / impact (proposed YYYY-MM-DD)` are announced EVERY boot until the human resolves them
  (`ledger_carry --done` with the full item text). Fence-aware, bounded output (8 KB + overflow
  row), read-only — a voice, not a gate (human-owned debt never blocks). Kill switch
  `HERMES_PENDING_OFF=1`.
- Supporting: `gen_rejstrik --tsv` machine contract (+ optional `tags:` frontmatter passthrough);
  `recall.sh` logs the consumed side of the funnel (success only); `brain_health` reports the
  recall funnel with honest labels (emitted / all recall runs / 7-day slug overlap);
  `close_state --init` janitor expires per-session recall state (7 d) and rotates the telemetry
  log (64 KB); the installer gitignores the new runtime files (`.recall-state/`,
  `.recall-hits.log`). `session-close` skill + `fmc-close` drafter: proposals waiting on a human
  become PENDING items, and durable FACTS (accounts, URLs) get atomized too — a fact that lives
  only in chat is unrecallable next session.
- Wiring: two new opt-in lines in `adapters/claude-code/settings-fragment.example.json`. Tests:
  +19 (matcher golden fixture, concurrency, hostile session-id, C-locale, no-hang, 500-atom perf).

## 0.3.1 — slug + [[link]] layer; recall by human name

Atoms are now addressable and linkable by a human **slug**, not just a hash id. `recall.sh <slug|id>`
drills an atom by its slug (or exact 12-hex id); the registry shows each atom's slug as its address;
`memory_route --slug` sets an explicit one (otherwise it is derived from the title). `lint_memory` gains
slug-collision detection; dead-link checking stays on `[[hexid]]` links only (a human `[[slug]]` may point
to an external note, so flagging it would be noise).

## 0.3.0 — retrieval-first: the container now RECALLS, not just stores

A retrieval layer so an instance sees WHAT it knows at boot and can pull the one atom it needs, instead of
reading the whole store:
- `gen_rejstrik.sh` + `rejstrik_inject.sh` — a boot-injected **atom registry** (one ranked row per atom),
  always recomputed from the blocks so it cannot drift.
- `recall.sh <id> | --query "words"` — drill a single atom out of the cold store.
- `memory_route --importance 1..5 --origin <src>` — first-class ranking + provenance DNA in the block body
  frontmatter (the block marker stays frozen, so idempotence is untouched).
- `lint_memory.sh` — advisory atom hygiene (duplicate id / bad DNA / missing title / dead link), also a
  metric in the health report. It measures and proposes; it never blocks a write.

## 0.2.3 — boot orientation survives an un-migrated memory

Three boot-nerve fixes: `state_inject` now injects the legacy orientation file (with a loud migrate
reminder) instead of withholding it; the folder index counts nested `.md` recursively instead of lying
"(folder, 0 files)"; and the close handoff points at the real orientation file.

## 0.2.2 — accurate fallback metrics + honest audit routing

`brain_health` and `session_close` now share one fence-aware definition of an open fallback, so a fenced
documentation example is never counted as real debt; a fresh install no longer routes the capability audit
at a script that is not part of the adopter backbone.

## 0.2.1 — Codex lifecycle adapter

The Codex adapter wires real plugin-bundled lifecycle hooks (SessionStart / UserPromptSubmit / PreCompact)
through one sequential dispatcher, with hash-bound trust via `/hooks`; the self-report distinguishes the
Claude and Codex hosts.

## 0.2.0 — first public release

The first public release of **farky-memory-container** (also known as *kontAIner*): a portable,
quiet-by-default **memory + capability container** for AI coding agents. It gives an agent a
per-project `memory/` folder it writes ITSELF (journal, state, knowledge, carry-forward), a
zero-dependency shell backbone that makes those writes scripted, atomic, and idempotent, a
machine-enforced close ritual (an unclosed session is caught up on the next boot, never lost), and
a self-report that says out loud which capabilities are wired vs. silently missing.

Works as a Claude Code **plugin**; the skills also load in Codex CLI via `.codex-plugin`. See the
README for the full picture and Quickstart.

Field-hardened across 10+ internal agent instances (Claude Code and Codex) on real projects before
going public; the detailed internal iteration history stays in the maintainer's workspace.
