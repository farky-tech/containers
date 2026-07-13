# sessions/ — rich per-session records

One file per session: `YYYY-MM-DD-topic.md`. Each holds the **full story + WHY** of that session — intent,
what happened, the reasoning behind each decision, dead-ends, what's done vs. open.

**Why this exists:** a future instance returning to a past session shouldn't have to re-derive *what we wanted
and how we meant it* from a dead chat (expensive, and it misleads). It reads the record (cheap). Writing rich
is cheap *while you still have the context*; re-losing it later is what costs.

- Written at close, **compiled from the `session.md` journal** (so feed the journal WITH the WHY as you go — a
  thin journal yields a thin record).
- The compilation is mechanical → **may be done by a subagent**. The retro (self-improvement) may NOT — that
  needs the main head's live context.
- `log.md` is the one-line index that links here. Roles: `STATE.md`=now · `sessions/`=per-session story ·
  `log.md`=index · `todo.md`=checklist · `session.md`=raw live journal.

(This `_README.md` is a placeholder so the folder ships in the template; real records sit beside it.)
