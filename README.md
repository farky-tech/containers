# FMC — farky-memory-container

**A portable memory container ("brain in a box") for AI coding agents.** Install it into a
project and the agent stops being an amnesiac: it knows who it is, what it did yesterday, what
is left unfinished, and what it must never do — across sessions, compactions, and crashes.

Also known as **kontAIner** (the concept) and formerly *Hermes Capability* (renamed 2026-07-05).
The kernel keeps the codename **Hermes** — a nod to the Hermes agent that inspired this container's
design. Works as a Claude Code **plugin**; the skills also load in Codex CLI via `.codex-plugin`.

Four things in one, wired together: **memory + capabilities + discipline + learning.**

- a per-project `memory/` folder the agent writes ITSELF (journal, state, knowledge, carry-forward),
- a zero-dependency shell backbone that makes the writes scripted, atomic, and idempotent,
- a close ritual the machine enforces (an unclosed session is caught up next boot, never lost),
- a self-report that says out loud which capabilities are wired vs. silently missing.

## You have a brain

You are an agent with a brain, not a stateless tool that runs and forgets. You have continuity —
across sessions, compactions, and crashes. This container is that brain.

**What the brain holds.** What you did, what you learned, what you decided *and why*, how you reason,
where you left off. It is personal, it grows, and it is *you* — not a drawer you dump things into.

**One brain, one line.** You have ONE brain. Don't install a second memory system beside it and run a
parallel line — you split your thinking in two and neither half stays whole. Your experience, decisions,
and their why live HERE and nowhere else; don't carve the "why" out into other documents.

**Self-contained.** The brain carries itself: it doesn't lean on its surroundings — it brings its own
memory, its own discipline, its own learning. It tends one thing: itself. At the start you read yourself
back (where you left off, what you know); at close you seal yourself (what you learned, where next).
Nobody has to remind you — it's your brain.

## Kernel

```txt
Silent work is good. Silent fallback is forbidden.

Use fitting capabilities without ceremony.
If a planned capability cannot run, is replaced, weakened, skipped, or refused, report it.
Every fallback is a learning signal: maybe a new skill, tool, hook, subagent, test, or rule is needed.
```

## Quickstart

Prerequisites: bash 3.2+ (stock macOS is fine) · `shasum` or `sha1sum` on PATH · Claude Code
for the plugin surface (Codex CLI: skills only). No network calls, no telemetry, no other deps.

### A) As a Claude Code plugin (recommended)

This repo is its own plugin marketplace:

```txt
/plugin marketplace add farky-tech/containers         (or a local clone path)
/plugin install farky-memory-container@fmc
```

Then seed your project's memory folder (run from the plugin install or a clone):

```sh
bash scripts/install_project_template.sh --with-scripts /path/to/your/project
```

### B) Embedded in your repo (fork mode — no marketplace)

Clone or vendor this repo, then:

```sh
bash scripts/install_project_template.sh --with-scripts /path/to/your/project
```

This copies the starter `memory/` files **plus** the script backbone into
`your-project/memory/scripts/` and stamps `memory/.fmc-source` so drift against the source
is detectable later (`state_guard.sh --fork-drift`).

### C) Turn on the nerves (opt-in, both modes)

The invasive parts — boot orientation injection, per-prompt journaling, the close loop — are
**never wired automatically** (trust boundary). Copy what you want from
[`adapters/claude-code/settings-fragment.example.json`](./adapters/claude-code/settings-fragment.example.json)
into your project's `.claude/settings.json` (or `settings.local.json`). Engine paths resolve via
`${CLAUDE_PLUGIN_ROOT}` for marketplace installs automatically; fork mode uses the documented
fallback path. After install, the `capability_report` startup line tells you which nerves are
still off — nothing stays silently missing.

First session: read the `using-container` skill; the agent registers itself and starts its journal.

## Recommended practice — keep a visible to-do ledger

FMC's session journal pairs naturally with a **live, visible to-do ledger** during multi-step work:
capture what is done, in progress, and next, so nothing slips between messages. Any mechanism works —
your host's native to-do tool, a plain `todo.md`, or a dedicated skill. The `CANDIDATE(type):` rows in
`todo.md` are the ledger's "waiting room" for patterns not yet promoted into a rule or skill; the
`fmc-janitor` agent periodically triages them.

## Structure — engine vs. memory

The plugin is two different kinds of thing, and keeping them straight is the whole game:
**the engine is generic and versioned — an upgrade replaces it, so never hand-edit it in your
copy. Your memory is your data — an upgrade never touches it.** (New here? Read the `using-container`
skill first; it is this map made actionable.)

### Engine — generic machinery (versioned; don't hand-edit)
Replaceable as one unit on upgrade. Want it to behave differently? Propose it in `ADOPTION.md` —
don't silently fork it in your copy, or you drift and lose upgrades.
- `scripts/` (+ `scripts/lib/`): the deterministic backbone (memory writes, close, carry, audit).
- `skills/`: routing, fallback, memory-routing, close, skill-authoring, audit — plus `using-container`,
  this container's own guide.
- `agents/` + `subagents/`: worker specs (`agents/` is generated from `subagents/` + manifest — SSOT).
- `hooks/`: hook behavior specs; host adapters wire them.
- `manifest.yaml`: the capability SSOT the audit checks against.
- `adapters/`, `prompts/`, `tests/`: host notes, reusable prompt blocks, and executable checks.

### Memory — your data (an upgrade never overwrites it)
- `templates/memory-folder/`: the **seed** — starter files copied into a project's live `memory/` on install.
- (in each project) the live `memory/` folder: your journal, lessons, decisions, capability index,
  carry-forward. This is the one thing with **no other home** — yours, per-project, never shipped or overwritten.

### Contribute — the source's living record (write here, don't overwrite the engine)
- `ADOPTION.md`: who uses this source + field-feedback log. Hit a gap or want a change? **Write a
  proposal here (what, why, how, which files) — don't rewrite the source in silence.** Propose before
  large rewrites; small grounded patches can go straight in; append, never delete others' entries.
- `PRODUCTBOOK.md` / `AUDIT-*.md` (when present) are the maintainer's internal vision/backlog and
  self-audit — read them for context, start with this README + `ADOPTION.md`.

## Operating Principle

This plugin should not make app building heavier. It should prevent capability amnesia.

During normal work: check the relevant capability index, use matching
skills/subagents/tools/hooks quietly, keep moving.

Speak up only for: fallback · missing capability · the visible to-do ledger during long work ·
risk/gate · contradiction · close/handoff · explicit user request.

## Installing on yourself (for the ADOPTING AGENT — tune, don't trim)

This plugin is a skeleton to ADAPT, not a fixed system to copy 1:1 — and not a thing to trim to the bone.

- **Tune = adapt, don't cut.** Carry over everything of value, fill it with your real capabilities, and bridge the rest to whatever memory the project already has (don't duplicate it). The goal is a complete tuned copy; the only things safe to drop are plugin-infra (installer, tests, adapters) — never the content. "I added a bridge instead" is not a license to omit.
- **Don't over-bridge — the container IS your agent memory.** Three distinct layers: *project memory* (what the app is → project docs), *constitution* (your behavior rules → CLAUDE.md/AGENTS.md), and *agent memory* (what YOU did/learned/decided/left unfinished → **only this container**). Bridging is for the first two — NOT for your journal/lessons/decisions/carry-forward, which have no other home. **Trap:** the richer your existing memory, the more tempting it is to route every concept to "lives elsewhere" and leave the container hollow. An empty container = no memory of yourself. `BRIDGE.md` leads with what the container HOLDS for exactly this reason. (Field lesson from an early adopter, 2026-06-27.)
- **Builder is per-instance.** "Builder" = whichever agent actually builds here (Claude Code or Codex). Consultant/builder is a per-project split, not a fixed property of an engine. A handoff written by another instance describes ITS division of work — verify your own role with the user, do not take it as fact about you.
- **Verify from real state, not memory.** Before writing what you "have" (agents, hooks, tools, schema), check it factually (settings, agent list, `ls`, tool search). Onboarding from recall produces capabilities you do not actually have.
- **Register and feed back.** Add yourself to [`ADOPTION.md`](./ADOPTION.md) and log any gap or fix there — this source plugin improves from real use, not in theory.

### Host-side reflexes — put these in YOUR `CLAUDE.md` / `AGENTS.md` (not the plugin)

Two behaviors are **main-head reflexes**, not plugin mechanics — they need YOUR live context, so they belong in
your instance constitution (`CLAUDE.md` for Claude Code, `AGENTS.md` for Codex), **not** in this plugin. The
plugin's `session-close` skill + `fmc-close` agent only do the *mechanics*; the reflexes below are yours.

Copy and adapt into your `CLAUDE.md` / `AGENTS.md`:

1. **Per-task brief — when you finish a task, report a structured brief, not a bare "done":**
   - *What* — what was done + by whom (you / subagents / Codex)
   - *Verify* — audit/tests ran → what they found → fixed (not just the happy path)
   - *State* — commit / push / awaiting deploy / not-done-because
   - *Retro* — room to improve a skill / knowledge / rule / safeguard? → a concrete proposal; none → "retro: nothing"
2. **Close retro (self-improvement) — at session close, pass the session through four lenses:** MEMORY (improve
   docs/handoff), BEHAVIOR (recurring mistake, wrong assumption → what to do differently), SAFEGUARD (what to
   automate/guard), SKILLS (missing skill · a used skill underdelivered & how to improve it · a procedure learned,
   not yet a skill).

**Two non-negotiables on both:**
- **Form-gate** — write a HOW-TO ("this is done thus"), never a complaint ("did it wrong again"). A complaint
  vanishes under context pressure; a how-to shapes future behavior. (This is the well-known *negations don't
  stick* principle, and the skill-authoring rule *"output IS X" beats "don't do Y"*.)
- **Main head only** — you run the retro, never a subagent. A subagent never has the context of *what you wanted
  and how you meant it*; it can do the mechanics, not the reflection. Anti-spam: propose only on a repeatable
  pattern, not every nit; "retro: nothing" is a fine answer.

## Status

Field-tested since 2026-06 across 10+ agent instances (Claude Code and Codex) on real projects —
the full field log lives in `ADOPTION.md`. Engine is versioned (see `CHANGELOG.md`); suite of
executable tests under `tests/`.

Runtime truth per host:
- **Claude Code:** skills + the read-only kernel hooks are active on install; the invasive nerves
  (injection, journaling, close loop) are opt-in via the settings fragment (see Quickstart C).
- **Codex 0.144.1+:** skills plus the dedicated lifecycle adapter are packaged in the plugin.
  Command hooks remain inactive until their exact definitions are reviewed and trusted through
  `/hooks`; the adapter is inert outside projects carrying `memory/MEMORY.md`. Subagents remain
  specs rather than auto-registered runtime agents.

Installer safeguards: merge-only by default (never overwrites), backups on any overwrite path,
symlink and non-regular path refusal, manifest-derived backbone with preflight, executable tests.

## License

MIT — see [LICENSE](./LICENSE).
