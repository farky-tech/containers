---
name: session-close
description: Use at the end of larger work to capture outcomes, fallbacks, durable learning, pending proposals, and next-load context without turning task logs into memory. Runs close v2 — the drafter subagent does the mechanics, the head approves + does the retro.
license: MIT
metadata:
  hermes:
    tags: ["hermes", "close", "handoff"]
    related_skills: ["memory-routing", "no-silent-fallback", "capability-routing"]
---

# Session Close (v2 — quiet close)

## When To Use

Use full close when a workstream ends, pauses, changes direction, has multi-step work, produced
fallback/durable learning, has open TodoWrite items, or the user asks for close/handoff. For small
one-shot work without durable learning, a short normal final answer is enough.

## Principle (v2)

**The machine does the mandatory memory work; the head decides and approves.** A close is no longer a
10-step manual ritual — the `fmc-close` **drafter** subagent does the mechanics and hands you a finished
DRAFT; you only review it, do the **retro**, and approve. This is why every session actually gets a
close (and why the next instance keeps getting smarter): the burden that used to be skipped now lives
in a subagent, not in the head's memory.

## Flow

1. **Spawn the drafter** (`fmc-close`, NORMAL mode). It reads `session.md` + git + `todo.md` and produces
   the full draft: writes `STATE.md`, compiles `sessions/YYYY-MM-DD-topic.md` + the `log.md` index line,
   reconciles the ledger (strike done + carry open with `--step`), logs fallbacks, **proposes** durable
   lessons/decisions (approval-gated), and surfaces **2–3 retro candidates**. It does NOT do the retro.
2. **Review the draft — mainly `STATE.md`.** Would a cold next instance know what & why to do in 1 min?
   Edit if not. Roles never conflate: `STATE.md`=now (overwritten) · `log.md`=archive (append) ·
   `sessions/`=per-session story · `todo.md`=checklist.
3. **Do the RETRO — this is YOUR job, not the subagent's** (only the main head has the live context of
   *what was wanted and how it was meant*). Start from the drafter's candidates, pass the session through
   four lenses: **MEMORY** (docs/handoff structure), **BEHAVIOR** (recurring mistake / wrong assumption /
   workflow step to change), **SAFEGUARD** (what to automate with a script/hook/lint/test), **SKILLS** (a
   skill was missing · one underdelivered & how to improve it · a procedure learned, not yet a skill).
   **Learn from wins too:** a pattern that worked → add a tagged line to `memory/todo.md`:
   `- [ ] CANDIDATE(win): <pattern> (occurrences: <date>)`. The 2-occurrence rule still applies (one win is
   an anecdote) — when the same pattern recurs, promote it to a rule/skill. (The kandidat script was
   retired; candidates now live as tagged todo lines.)
   - **A lesson that should change behavior does NOT stay in KNOWLEDGE.md — promote it NOW** into
     CLAUDE.md / a skill (the actively-read layer). KNOWLEDGE is raw material, not a graveyard. Capturing a
     just-executed pattern is a NOW job, not a "next fresh session" job — the context does not survive.
   - **Form-gate:** each note is a HOW-TO ("this is done thus"), never a complaint. Don't self-edit
     governance — surface a proposal (type · target · reason · text/diff · awaiting approval), or say
     "retro: nothing" (anti-spam: propose only on a repeatable pattern).
4. **Persist approved durable learning:** `scripts/memory_route.sh --text "<note>" --kind lesson|decision
   --commit --approved-by <who> --reason <why>`.
5. **Settle the close-debt tracker:** `scripts/close_state.sh --memory-dir ./memory --close-done --ledger-ok`
   (`--ledger-ok` asserts step 1's reconcile happened; session id resolves from `$CLAUDE_CODE_SESSION_ID`).
   Without this SessionEnd leaves an UNCLOSED marker that boot-recovery surfaces next start.
6. **FMC self-report:** `scripts/capability_report.sh --close --project-dir .` shows which FMC nerves were
   WIRED this session vs. which are available but NOT turned on, and emits an `ADOPTION.md`-ready line if a
   gap exists. This lets an adopter **self-hail** a hole instead of running half a container silently (an
   un-wired nerve is invisible until found by accident). On a fully-wired setup it just says "All wired".

## Auto-recovery (advisory recovery) — an unclosed PRIOR session

If a boot surfaces `RECOVERY` (an UNCLOSED marker from a session that ended with work but no close),
recover it **before starting new work**: run the drafter in **AUTO `<SID>`** mode. It reconstructs that
dead session from the marker's ts-range over `session.md` + git, writes the draft **labeled
"AUTO-RECONSTRUCTION — auto, unapproved"**, and clears that marker (`--close-done --session-id <SID>`). You
have no live context for it, so you do NOT invent a retro — the banner is the receipt; the next head with
real context validates it. `/close --auto <SID>` (SID from the boot queue) is the command.

## Cross-platform honesty

The drafter is a **subagent** — active on Claude Code. On the **Codex** host subagents are spec-only, so
there `session-close` degrades to running the backbone scripts **inline** (`session_close.sh`,
`ledger_carry.sh`, `fallback_log.sh`, `memory_route.sh`) and writing STAV/sessions by hand — same
artifacts, no subagent. Do not claim a subagent close where the host has none.

(In Claude Code the scripts live at `${CLAUDE_PLUGIN_ROOT}/scripts/`.)

## Output

```txt
Container close (v2):
- Drafter: NORMAL | AUTO <SID>
- STATE.md reviewed/edited:
- Session record + log index:
- Ledger: struck / carried:
- Fallbacks / Durable learning committed:
- Retro (MEMORY/BEHAVIOR/SAFEGUARD/SKILLS — proposal awaiting approval, or "nothing"):
- Gate: close_state --close-done (0 ok):
```
