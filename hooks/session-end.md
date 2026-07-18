# SessionEnd Hook Spec

Purpose: finalize the session's close-debt state when the session terminates.
Runs ONCE, on real session end (not per turn like Stop).

When:
- session terminates (reason: clear | resume | logout | prompt_input_exit | other).

Action:
- run `close_state.sh --memory-dir <dir> --session-end` (session_id from stdin JSON):
  - if the session did work but no conscious close happened -> leave an UNCLOSED
    marker for the next boot to surface (so a lost close is visible, not silent),
  - else clear the close-state.
- side-effects only (SessionEnd cannot block).

Must not:
- attempt the close itself. The conscious close (STATE / sessions/ / retro) is the
  MAIN HEAD's job and cannot happen after the session has ended — the head is gone.

Auto-wired (Fáze A, 2026-07-18):
- invasive (writes memory-state), but auto-wired via hooks/hooks.json → the Claude
  dispatcher, inert without memory/MEMORY.md (installing a brain = consent to write
  under memory/). SessionEnd runs through the dispatcher.

Fallback:
- if no hook runtime, the marker isn't left; boot still reads STATE.md.
