# Session journal (cc) — black box of the live session

Raw material for the close distillation. Written via the **script** `session_note.sh` (not by hand):

- `session_note.sh --memory-dir ./memory --start "<session goal>"` — at the start (archives the previous journal)
- `session_note.sh --memory-dir ./memory --note "<milestone>"` — as you go (decision / finding / built / hit a wall)

At close, `session_close.sh` reads this file and prints "what happened this session" →
distil into `log.md` (one line) + optionally `KNOWLEDGE.md` (kind lesson/decision) via `memory_route.sh`.
After distillation the journal is archived into `.session-archive/` on the next `--start`.

Why: session memory must not hang on the context-window size — it is read from a file,
not from drifted context.

---
