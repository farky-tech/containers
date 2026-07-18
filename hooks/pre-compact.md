# PreCompact Hook Spec

Purpose: guard against context loss. Before Claude Code compacts the context,
make sure the live thread is on disk — so memory never hangs on the window.

When:
- before context compaction (trigger: auto | manual).

Action:
- emit a short reminder to flush any un-journaled live thread into
  `memory/session.md` / `STATE.md` before the window rolls (the journal is written
  as-you-go by session_note, so this is a safety net, not the primary path).
- non-blocking.

Must not:
- block compaction (return non-zero). Compaction is needed; we protect memory,
  we do not veto the compaction.

Auto-wired (Fáze A, 2026-07-18):
- advisory; wired via hooks/hooks.json → the Claude dispatcher, inert without memory/MEMORY.md.

Fallback:
- if no hook runtime, rely on the ongoing journal + main-head discipline.
