#!/usr/bin/env bash
# close_state.sh — per-session close-debt tracker for the self-improvement loop.
#
# Backbone script. Tracks whether a session did real work and whether its conscious
# close happened. Hooks call it; the close skill clears it. It NEVER does the close
# itself (that is the main head's job) — it only records state so a forgotten close
# is caught by boot-recovery instead of relying on the agent remembering.
#
# Three-layer design: this is the AUTO/SCRIPTED substrate.
#   AUTO      — hooks (SessionStart→init + boot-recovery, SessionEnd→finalize) call this.
#   SCRIPTED  — this script: deterministic k=v state, atomic, locked, idempotent.
#   MAIN-HEAD — the close skill writes STAV/sessions/retro, then calls --close-done.
# (The Stop close-debt NAG was removed in F5 — it never enforced and misfired mid-work;
#  SessionEnd leaves an UNCLOSED marker → boot-recovery surfaces it → auto-recovery.)
#
# "Real work" = the session journal has >= WORK_THRESHOLD blocks WHOSE ts is at or
# after this session's --init ts. Using a ts baseline (not an absolute count) makes it
# per-session: a stale journal from a previous session (not yet archived by session_note
# --start) has older ts and is ignored; the new journal's blocks count. It decides
# whether SessionEnd leaves an UNCLOSED marker. Zero-dep (grep/sed/bash compare).
#
# State file: <memory-dir>/.close-state/<key>.env  (flat k=v, not JSON — zero-dep by
# design; the hook stdin IS json, we extract session_id from it). <key> = a safe
# form of session_id: sanitized if it round-trips, else a hash (no collisions).
#
# Usage:
#   close_state.sh --memory-dir <dir> --init [--session-id <id>]        # SessionStart + janitor sweep
#   close_state.sh --memory-dir <dir> --close-done [--ledger-ok] [--session-id <id>]  # close skill; LEDGER gate (open todo.md items need --ledger-ok)
#   close_state.sh --memory-dir <dir> --session-end [--session-id <id>] # SessionEnd: finalize
#   close_state.sh --memory-dir <dir> --boot-recovery                     # SessionStart: surface UNCLOSED queue (advisory recovery)
#   close_state.sh --memory-dir <dir> --status [--session-id <id>]      # print state (debug)
#   [--dry-run]
# If --session-id is omitted, it is extracted from a hook JSON payload on stdin.
#
# Exit codes: 0 ok | 1 error/usage | 2 close-done refused by ledger gate
# Env: HERMES_FAKE_TS (deterministic ts), HERMES_WORK_THRESHOLD (default 2 — journal blocks
#      with ts >= session start needed to count the session as "did work", for the UNCLOSED marker).
# (The Stop close-debt nag / --check mode was removed in F5; auto-recovery replaces it.)

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hermes_blocks.sh
. "$script_dir/lib/hermes_blocks.sh"

usage() { sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

memory_dir="./memory" mode="" sid="" dry_run=0 ledger_ok=0
while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir)  memory_dir="${2:-}"; shift 2 ;;  # --hermes-dir = legacy alias (pre-rename adopters)
    --session-id)  sid="${2:-}"; shift 2 ;;
    --init)        mode="init"; shift ;;
    --close-done)  mode="close-done"; shift ;;
    --ledger-ok)   ledger_ok=1; shift ;;   # assert the todo ledger was reconciled this close (see ledger gate)
    --session-end) mode="session-end"; shift ;;
    --boot-recovery) mode="boot-recovery"; shift ;;
    --status)      mode="status"; shift ;;
    --dry-run)     dry_run=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "close_state: unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

[ -n "$mode" ] || { echo "close_state: need a mode (--init/--close-done/--session-end/--boot-recovery/--status)" >&2; usage; exit 1; }

# Resolve session id, in priority order:
#   1. explicit --session-id (wins — tests, manual runs).
#   2. hook JSON on stdin (hooks pipe it; only read when stdin is NOT a tty).
#   3. $CLAUDE_CODE_SESSION_ID env var (set for interactive Bash calls — this is how
#      --close-done resolves: the close skill runs interactively with a tty on stdin,
#      so path 2 is skipped and there is no payload. WITHOUT this the id stayed empty
#      → key="nosession" → the close wrote close_done_at to nosession.env while the
#      real session's Stop/SessionEnd hooks kept their own <sid>.env → the reminder
#      never went silent and UNCLOSED-<sid> markers piled up forever. Verified real
#      env name is CLAUDE_CODE_SESSION_ID, not CLAUDE_SESSION_ID.)
# The hook JSON on stdin is delivered ONLY by the SessionStart/SessionEnd hooks — i.e.
# only --init and --session-end ever legitimately receive it. Every other mode resolves
# its id elsewhere: --close-done (close skill / fmc-close subagent) takes --session-id or
# $CLAUDE_CODE_SESSION_ID; --boot-recovery/--status use no id at all. So only the two
# hook-driven modes may touch stdin — WHITELIST them (not blacklist the rest): safe-by-
# default, a future mode won't silently start reading stdin. Blacklisting missed exactly
# this: --close-done was not excluded, so a headless close (subagent / no tty, no
# </dev/null) fell into `cat` and hung the close gate forever (0.1.30 fix).
# And even for the two allowed modes the read is TIME-BOUNDED: `read -d '' -t 2` slurps
# the whole payload on EOF, or gives up after 2s of idle stdin — never an unbounded `cat`
# that hangs when a hook is killed or the script is run by hand. (Same two-layer fix as
# ledger_carry 0.1.29: semantic skip + integer read timeout; bash-3.2 safe.)
if [ -z "$sid" ] && [ ! -t 0 ] && { [ "$mode" = "init" ] || [ "$mode" = "session-end" ]; }; then
  payload=""; IFS= read -r -d '' -t 2 payload 2>/dev/null || true
  sid="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
# Build a safe, collision-free state key from the raw session id:
#  - if the id round-trips through the safe-char filter unchanged, use it (readable);
#  - else hash the RAW id (no lossy collisions like a/b -> ab);
#  - empty id -> a fixed bucket (last resort; a hook payload should always carry one).
raw_sid="$sid"
safe_sid="$(printf '%s' "$raw_sid" | tr -cd 'A-Za-z0-9._-')"
if [ -z "$raw_sid" ]; then
  key="nosession"
elif [ "$safe_sid" = "$raw_sid" ]; then
  key="$safe_sid"
else
  key="h$(printf '%s' "$raw_sid" | hermes_sha1 | cut -c1-16)"
fi

state_dir="$memory_dir/.close-state"
state_file="$state_dir/${key}.env"
journal="$memory_dir/session.md"
ts="$(hermes_now_utc)"
work_threshold="${HERMES_WORK_THRESHOLD:-2}"

# --- helpers ---------------------------------------------------------------

cs_get() { # read one key from the flat state file (empty if absent). args: key
  [ -f "$state_file" ] || { printf ''; return 0; }
  sed -n "s/^$1=\(.*\)$/\1/p" "$state_file" | head -n1
}


# Emit the flat state file atomically. Caller MUST already hold the lock.
# args: key=value ...  (merges over existing file)
cs_emit_state() {
  local started_at close_done
  started_at="$(cs_get started_at)"; [ -n "$started_at" ] || started_at="$ts"
  close_done="$(cs_get close_done_at)"
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      started_at) started_at="$v" ;;
      close_done_at) close_done="$v" ;;
    esac
  done
  {
    printf 'session_id=%s\n' "$raw_sid"
    printf 'started_at=%s\n' "$started_at"
    printf 'close_done_at=%s\n' "$close_done"
    printf 'updated_at=%s\n' "$ts"
  } | hermes_atomic_write "$state_file"
}

cs_write() { # take the lock, emit state, release. args: key=value ...
  local lockdir="${state_file}.lock"
  hermes_lock "$lockdir" || return 1
  local rc=0; cs_emit_state "$@" || rc=1
  hermes_unlock "$lockdir"; return "$rc"
}

# Did this session do real work? journal blocks with ts >= baseline >= threshold.
# args: baseline_ts
cs_work_done() {
  local base="$1" n=0 t
  [ -f "$journal" ] || return 1
  [ -n "$base" ] || base="0000"
  while IFS= read -r t; do
    # string compare on ISO-8601 == chronological compare
    if [ -n "$t" ] && { [ "$t" = "$base" ] || [ "$t" \> "$base" ]; }; then
      n=$((n + 1))
    fi
  done < <(grep -o 'hermes:entry kind=session [^>]*ts=[^ ]*' "$journal" 2>/dev/null | sed 's/.*ts=//')
  [ "$n" -ge "$work_threshold" ]
}

# --- modes -----------------------------------------------------------------

case "$mode" in
  init)
    if [ "$dry_run" -eq 1 ]; then echo "close_state: dry-run init ($key)" >&2; exit 0; fi
    mkdir -p "$state_dir"
    # Janitor pass (every boot) — the state dir must not accumulate forever:
    #  - settled states (close_done_at set) older than 7 days have no consumer;
    #  - orphan states (no close recorded — e.g. a killed session that never got
    #    SessionEnd) older than 7 days are removed OUT LOUD, not silently;
    #  - stale .lock dirs (crash mid-write) older than 60 min would make every
    #    later call silently skip, muting the whole loop forever.
    #  UNCLOSED-* markers are debt, not litter: only --close-done clears them.
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if ! grep -q '^close_done_at=.' "$f" 2>/dev/null; then
        echo "close_state: janitor removed stale orphan state (no close recorded): $(basename "$f")" >&2
      fi
      rm -f "$f" 2>/dev/null || true
    done < <(find "$state_dir" -maxdepth 1 -name '*.env' ! -name 'UNCLOSED-*' -mtime +7 2>/dev/null)
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      rmdir "$d" 2>/dev/null && echo "close_state: janitor removed stale lock: $(basename "$d")" >&2
    done < <(find "$state_dir" -maxdepth 1 -name '*.lock' -type d -mmin +60 2>/dev/null)
    cs_write started_at="$ts" || { echo "close_state: init write failed" >&2; exit 1; }
    echo "close_state: init $key" >&2
    ;;

  close-done)
    if [ "$dry_run" -eq 1 ]; then echo "close_state: dry-run close-done ($key)" >&2; exit 0; fi
    # LEDGER RECONCILE GATE (always on, 0.1.19): a conscious close MUST reconcile the
    # ledger — mark resolved items done, carry the rest — not leave it to memory. todo.md
    # notoriously accretes done-but-unmarked items (proven: 40 open, several long resolved),
    # because "tick off what's done" is a memory reflex and memory slips. A script can't
    # judge WHICH are done, so it forces the head to LOOK: open items + no --ledger-ok =
    # close refused, items printed. Escape is trivial once reviewed (mark done, then
    # --close-done --ledger-ok). This is the "mandatory step", mechanical not remembered.
    todo_file="$memory_dir/todo.md"
    if [ "$ledger_ok" -eq 0 ] && [ -f "$todo_file" ]; then
      # Count via the SHARED fenced/indent-aware definition (hermes_count_open_todo)
      # so the gate agrees with session_close's handoff count — a raw grep here
      # false-blocked on a fenced example and missed indented sub-items (audit 2026-07-07).
      open_n="$(hermes_count_open_todo "$todo_file")"
      if [ "$open_n" -gt 0 ]; then
        echo "close_state: LEDGER not reconciled — $open_n open item(s) in todo.md. Review them, mark the finished ones done (ledger_carry.sh --done \"<text>\"), keep the rest; then rerun --close-done --ledger-ok." >&2
        # List them (same fenced/indent-aware rule) with line numbers for review.
        awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f;next} !f && /^[[:space:]]*- \[ \]/{printf "    %d:%s\n", NR, $0}' "$todo_file" >&2
        exit 2
      fi
    fi
    # (LOOP GATE removed in F3 — the maintenance-loop machinery it guarded, loop_state.sh, is
    # retired; its role moves to the F4 weekly observer. The LEDGER gate above stays. plan-review 2026-07-11.)
    mkdir -p "$state_dir"
    cs_write close_done_at="$ts" || { echo "close_state: close-done write failed" >&2; exit 1; }
    # A done close settles the debt: clear this session's UNCLOSED marker too,
    # else every future boot keeps surfacing an already-paid debt forever.
    rm -f "$state_dir/UNCLOSED-${key}.env" 2>/dev/null || true
    echo "close_state: close-done $key" >&2
    ;;

  session-end)
    # Finalize. If work happened but no close, leave an UNCLOSED marker for the
    # next boot to surface; otherwise clear the state.
    if [ "$dry_run" -eq 1 ]; then echo "close_state: dry-run session-end ($key)" >&2; exit 0; fi
    # Transactional (0.1.33, pre-publication audit): --close-done writes under the
    # state lock (cs_write), but this branch used to read-decide-write-delete WITHOUT
    # it — a close finishing concurrently could be overruled by a stale decision
    # (false UNCLOSED debt, or a lost close). Hold the same lock across the whole
    # read/decision/marker/delete transaction.
    se_lock="${state_file}.lock"
    hermes_lock "$se_lock" || { echo "close_state: session-end could not acquire state lock — state retained, nothing changed (fail loud)" >&2; exit 1; }
    baseline="$(cs_get started_at)"
    if [ -f "$state_file" ] && [ -z "$(cs_get close_done_at)" ] && cs_work_done "$baseline"; then
      mkdir -p "$state_dir"
      # Fail-honest (audit 2026-07-07): the OLD code did `| hermes_atomic_write … || true`
      # then deleted the live state UNCONDITIONALLY and reported "marker left" + exit 0.
      # If the marker write failed (disk full / unwritable dir / mv race) the close-debt
      # was SILENTLY LOST while the script claimed success — the plugin breaking its own
      # "silent fallback is forbidden" law, in the self-improvement nerve itself.
      # Marker MUST be self-sufficient for the boot-recovery pass: carry the immutable ts-range
      # (started_at..unclosed_at) so the drafter can isolate THIS dead session's journal
      # blocks by ts, independent of the live state file (deleted below) or whether the
      # journal was later archived by a session_note --start. (Audit/plan-review 2026-07-11:
      # a marker with only session_id could not be resolved to a journal range.)
      if printf 'session_id=%s\nstarted_at=%s\nunclosed_at=%s\njournal=%s\nnote=session ended with work but no conscious close\n' "$raw_sid" "$baseline" "$ts" "$journal" \
           | hermes_atomic_write "$state_dir/UNCLOSED-${key}.env"; then
        # Marker safely carries the debt now; the live state has no consumer after
        # session end — remove it so a zombie .env doesn't accumulate.
        rm -f "$state_file" 2>/dev/null || true
        echo "close_state: session-end UNCLOSED marker left ($key)" >&2
      else
        # Write FAILED — do NOT delete the live state; it still holds the unclosed
        # debt (recoverable). Fail loud instead of pretending the marker was written.
        echo "close_state: session-end UNCLOSED marker write FAILED — debt RETAINED in $state_file (not lost). Fix the memory dir; the debt is not gone. (fail loud)" >&2
        hermes_unlock "$se_lock"
        exit 1
      fi
    else
      rm -f "$state_file" 2>/dev/null || true
      echo "close_state: session-end clean ($key)" >&2
    fi
    hermes_unlock "$se_lock"
    ;;

  boot-recovery)
    # SessionStart surfacer — ADVISORY RECOVERY (not autonomous close). A hook cannot spawn
    # the drafter subagent, so this turns each UNCLOSED marker into a must-do-first advisory:
    # the head runs `/close --auto <SID>` as its first action. The marker persists until
    # `--close-done --session-id <deadSID>` clears it, so an ignored advisory RE-SURFACES next
    # boot — the debt is never silently lost (fail-persistent, not fail-silent). Read-only.
    [ -d "$state_dir" ] || exit 0
    # Sort the queue by started_at (FIFO — oldest debt first). Empty glob -> [ -e ] skips.
    queue="$(
      for mf in "$state_dir"/UNCLOSED-*.env; do
        [ -e "$mf" ] || continue
        s="$(sed -n 's/^started_at=\(.*\)$/\1/p' "$mf" | head -n1)"
        printf '%s\t%s\n' "${s:-0000}" "$mf"
      done | sort
    )"
    [ -n "$queue" ] || exit 0
    printf '=== FMC RECOVERY — unclosed prior session (advisory) ===\n'
    printf 'A previous session ended with real work but no conscious close. BEFORE starting new work, catch it up:\n'
    printf 'run  /close --auto <SID>  — the drafter reconstructs STAV/sessions/log from the journal\n'
    printf '(session.md) by ts-range and marks them "auto, unapproved". Queue (oldest first):\n'
    printf '%s\n' "$queue" | while IFS="$(printf '\t')" read -r s mf; do
      [ -n "$mf" ] || continue
      msid="$(sed -n 's/^session_id=\(.*\)$/\1/p' "$mf" | head -n1)"
      mend="$(sed -n 's/^unclosed_at=\(.*\)$/\1/p' "$mf" | head -n1)"
      printf '  - SID=%s  journal-range %s .. %s\n' "${msid:-?}" "${s:-?}" "${mend:-?}"
    done
    printf '=== (the marker persists until /close --auto runs — otherwise this re-surfaces next boot) ===\n'
    exit 0
    ;;

  status)
    if [ -f "$state_file" ]; then cat "$state_file"; else echo "(no close-state for $key)"; fi
    ;;
esac
