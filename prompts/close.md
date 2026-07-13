# Close Prompt

> **v2 (0.1.25):** the close is now one command — `/close` runs the `fmc-close` drafter, which
> produces the DRAFT below mechanically; the head only reviews + does the retro + approves. This
> template is what the drafter fills in (and the inline fallback on a host without subagents). See
> the `session-close` skill for the full v2 flow.

Use at the end of a larger task/session.

```txt
Close:
- Done:
- Changed:
- Verified:
- Unverified:
- TodoWrite state:
- Capabilities used:
- Fallbacks:
- Durable learning:
- Pending proposals:
- Risks:
- Load next:
- Next step:
- Retro (improve skill/knowledge/safeguard — proposal awaiting approval, or "nothing"):
```

**Always overwrite `memory/STATE.md`** (live thread · next concrete step · what to read · open
decisions) — the chat block above dies with the session; STATE.md is what the next boot reads first.
**Also write a rich `memory/sessions/YYYY-MM-DD-topic.md`** — the full story of this session (intent, what
happened, WHY each decision, dead-ends), compiled from the `session.md` journal. This is the deep archive a
future instance returns to when STATE.md's short orientation isn't enough; `log.md` is the one-line index that
links to it. Roles: STATE.md=now (overwritten) · sessions/=per-session story (append) · log.md=index · todo.md=checklist.
This **session record may be compiled by a subagent** (it's mechanical assembly from the journal); the **retro
below may NOT** — that needs the main head's live context.
Write the journal/log/STATE **WITH CONTEXT — the WHY, not just the WHAT** (why we solved or chose NOT
to solve things, the reasoning, dead-ends) so a future instance (even the 56th, or one recovering
after a crash) reconstructs the thinking, not a checklist. A bare what-list = broken handoff.

**Retro (mandatory) — done by the MAIN HEAD, not a subagent.** Only the main head holds the context of
*what you wanted and how you meant it*; a subagent never has it. Pass the session through four lenses —
**MEMORY** (improve docs/handoff), **BEHAVIOR** (recurring mistake, wrong assumption — what to do differently),
**SAFEGUARD** (what to automate/guard), **SKILLS** (missing skill · used a skill that underdelivered & how to
improve it · learned a procedure not yet a skill). **Form-gate:** write a HOW-TO ("this is done thus"), never a
complaint ("did it wrong again") — complaints vanish under pressure, how-tos shape behavior. Don't self-edit
governance (CLAUDE.md/skills) — surface a proposal awaiting approval, or say "retro: nothing" (that's fine).

Close is quiet when nothing durable happened. Use the full block when continuity matters.

Before close, reconcile TodoWrite:
- all items completed, or
- remaining items carried forward to `memory/todo.md`, issue, doc, or pending proposal.
