# Stop Hook Spec — RETIRED (0.1.27; `--check` mode removed in 0.1.28)

Status: NOT wired, and there is nothing left to wire. The per-turn close-debt
nag this spec originally described (`close_state.sh --check`) was retired in
0.1.27 (F4) and the `--check` mode was fully REMOVED from `close_state.sh` in
0.1.28 (F5). Calling it today returns `unknown arg`.

How close-debt is covered instead (no per-turn nag):

- SessionEnd (`close_state.sh --session-end`) leaves an `UNCLOSED-<sid>` marker
  when a session did real work without a conscious close;
- the next boot (`close_state.sh --boot-recovery`) surfaces the marker as a
  must-do-first advisory (`/close --auto <SID>`);
- the marker persists until `--close-done` clears it — an ignored advisory
  re-surfaces every boot. Fail-persistent, never fail-silent.

Why the close was never here:

- a close needs the MAIN HEAD (retro = "what was wanted and how it was meant");
  a per-turn shell hook cannot do that. The nag also misfired mid-work: the
  journal logs user prompts, so a long working turn read as idle.

This file remains as the historical spec anchor for `manifest.yaml`'s Stop
entry (status: retired). Do not wire a Stop hook from this plugin.
