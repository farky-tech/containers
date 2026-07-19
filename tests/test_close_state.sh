#!/usr/bin/env bash
# test_close_state.sh — fixture suite for the close-debt tracker (self-improvement loop).
# Zero-dep, deterministic (HERMES_FAKE_TS). Run: bash tests/test_close_state.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CS="$here/../scripts/close_state.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok()   { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# (F5: the Stop close-debt nag / --check mode was removed — tests 2–7, 10, 20 that exercised
#  the reminder/anti-spam/idle-gate/json-escape are gone. What survives: init, session_id
#  resolution, UNCLOSED marker, ledger gate, boot-recovery, concurrency, janitor.)

# helper: write a journal with N blocks all stamped ts
journal() { # dir ts n
  local d="$1" ts="$2" n="$3" i out
  out="# journal\n\n---\n"
  for i in $(seq 1 "$n"); do
    out="$out<!-- hermes:entry kind=session id=b$i ts=$ts -->\nx$i\n<!-- /hermes:entry -->\n"
  done
  printf "$out" > "$d/session.md"
}

SID="s1"
echo "== 1. init writes state =="
HERMES_FAKE_TS='2026-07-01T10:00:00Z' bash "$CS" --memory-dir "$T" --session-id "$SID" --init >/dev/null 2>&1
bash "$CS" --memory-dir "$T" --session-id "$SID" --status | grep -q 'started_at=2026-07-01T10:00:00Z' && ok "init records baseline" || bad "init"

echo "== 8. session_id from stdin JSON =="
echo '{"session_id":"json-9","hook_event_name":"SessionStart"}' | CODEX_THREAD_ID='codex-should-lose' CLAUDE_CODE_SESSION_ID='claude-should-lose' HERMES_FAKE_TS='2026-07-01T12:00:00Z' bash "$CS" --memory-dir "$T" --init >/dev/null 2>&1
[ -f "$T/.close-state/json-9.env" ] && [ ! -f "$T/.close-state/codex-should-lose.env" ] && [ ! -f "$T/.close-state/claude-should-lose.env" ] \
  && ok "hook session_id wins over host env" || bad "stdin priority: $(ls "$T/.close-state")"

echo "== 9. unsafe session_id -> hashed key, NO collision (a/b vs ab) =="
HERMES_FAKE_TS='2026-07-01T12:00:00Z' bash "$CS" --memory-dir "$T" --session-id 'a/b' --init >/dev/null 2>&1
HERMES_FAKE_TS='2026-07-01T12:00:01Z' bash "$CS" --memory-dir "$T" --session-id 'ab'  --init >/dev/null 2>&1
# 'ab' round-trips -> ab.env ; 'a/b' does not -> hashed h....env ; must be different files
c=$(ls "$T/.close-state" | grep -E '^(ab\.env|h[0-9a-f]+\.env)$' | wc -l | tr -d ' ')
[ "$c" -ge 2 ] && ok "unsafe id hashed, no collision with 'ab'" || bad "collision/hash: $(ls "$T/.close-state")"

echo "== 11. session-end with work + no close -> UNCLOSED marker =="
SID3="unclosed"
HERMES_FAKE_TS='2026-07-01T14:00:00Z' bash "$CS" --memory-dir "$T" --session-id "$SID3" --init >/dev/null 2>&1
journal "$T" '2026-07-01T14:01:00Z' 2
HERMES_FAKE_TS='2026-07-01T14:30:00Z' bash "$CS" --memory-dir "$T" --session-id "$SID3" --session-end >/dev/null 2>&1
[ -f "$T/.close-state/UNCLOSED-$SID3.env" ] && ok "unclosed marker left" || bad "no unclosed marker"

echo "== 12. concurrency: 8 parallel inits keep state valid (4 lines) =="
SID4="concur"
HERMES_FAKE_TS='2026-07-01T15:00:00Z' bash "$CS" --memory-dir "$T" --session-id "$SID4" --init >/dev/null 2>&1
for i in $(seq 1 8); do HERMES_FAKE_TS="2026-07-01T15:0$i:00Z" bash "$CS" --memory-dir "$T" --session-id "$SID4" --init >/dev/null 2>&1 & done
wait
lines=$(wc -l < "$T/.close-state/$SID4.env" | tr -d ' ')
[ "$lines" -eq 4 ] && ok "no corruption under concurrency" || bad "corrupted: $lines lines"

echo "== 13. close-done settles the debt: UNCLOSED marker cleared =="
SID5="paydebt"
HERMES_FAKE_TS='2026-07-01T16:00:00Z' bash "$CS" --memory-dir "$T" --session-id "$SID5" --init >/dev/null 2>&1
journal "$T" '2026-07-01T16:01:00Z' 2
HERMES_FAKE_TS='2026-07-01T16:30:00Z' bash "$CS" --memory-dir "$T" --session-id "$SID5" --session-end >/dev/null 2>&1
[ -f "$T/.close-state/UNCLOSED-$SID5.env" ] || bad "precondition: no marker to settle"
HERMES_FAKE_TS='2026-07-01T17:00:00Z' bash "$CS" --memory-dir "$T" --session-id "$SID5" --close-done >/dev/null 2>&1
[ ! -f "$T/.close-state/UNCLOSED-$SID5.env" ] && ok "close-done cleared UNCLOSED marker" || bad "marker survived close-done"

echo "== 14. session-end leaving a marker also clears the live state (no zombie .env) =="
[ ! -f "$T/.close-state/$SID3.env" ] && ok "no zombie state after unclosed session-end" || bad "zombie state file left"

echo "== 15. init janitor: old settled+orphan removed; ANCIENT UNCLOSED aged to .aged/; RECENT UNCLOSED + fresh kept =="
old="$T/.close-state/olddone.env"
printf 'session_id=olddone\nstarted_at=2026-06-01T00:00:00Z\nclose_done_at=2026-06-01T01:00:00Z\nlast_reminded_at=\nupdated_at=2026-06-01T01:00:00Z\n' > "$old"
touch -t 202606010100 "$old"
orph="$T/.close-state/oldorphan.env"
printf 'session_id=oldorphan\nstarted_at=2026-06-01T00:00:00Z\nclose_done_at=\nlast_reminded_at=\nupdated_at=2026-06-01T00:00:00Z\n' > "$orph"
touch -t 202606010000 "$orph"
# ANCIENT UNCLOSED marker (mtime way past the aging window) -> aged to .aged/, LOUDLY (fail-aged).
unc="$T/.close-state/UNCLOSED-oldunc.env"
printf 'session_id=oldunc\nunclosed_at=2026-06-01T00:00:00Z\nnote=x\n' > "$unc"
touch -t 202606010000 "$unc"
# RECENT UNCLOSED marker (mtime = now) -> real debt, must be KEPT in place (boot-recovery surfaces it).
recentunc="$T/.close-state/UNCLOSED-recent.env"
printf 'session_id=recent\nunclosed_at=2026-07-18T00:00:00Z\nnote=x\n' > "$recentunc"
fresh="$T/.close-state/s1.env"   # from test 1, mtime = now
HERMES_FAKE_TS='2026-07-01T18:00:00Z' bash "$CS" --memory-dir "$T" --session-id "janitor1" --init >/dev/null 2>&1
[ ! -f "$old" ] && [ ! -f "$orph" ] \
  && [ ! -f "$unc" ] && [ -f "$T/.close-state/.aged/UNCLOSED-oldunc.env" ] \
  && [ -f "$recentunc" ] && [ -f "$fresh" ] \
  && ok "janitor: settled+orphan removed, ancient UNCLOSED aged to .aged/, recent UNCLOSED+fresh kept" \
  || bad "janitor: old=$([ -f "$old" ] && echo LIVE) orph=$([ -f "$orph" ] && echo LIVE) aged=$([ ! -f "$T/.close-state/.aged/UNCLOSED-oldunc.env" ] && echo NOTAGED) recent=$([ ! -f "$recentunc" ] && echo GONE) fresh=$([ ! -f "$fresh" ] && echo GONE)"

echo "== 16. init janitor: stale lock removed (crashed session must not mute the loop) =="
stale="$T/.close-state/stuck.env.lock"
mkdir -p "$stale"; touch -t 202606010000 "$stale"
HERMES_FAKE_TS='2026-07-01T18:10:00Z' bash "$CS" --memory-dir "$T" --session-id "janitor2" --init >/dev/null 2>&1
[ ! -d "$stale" ] && ok "stale lock removed" || bad "stale lock survived"

# (Tests 17–19 removed in F3: the LOOP GATE was retired with loop_state.sh. The LEDGER gate —
#  tests 23–28 below — stays and is the close's reconcile enforcement.)

echo "== 21. session-id from CLAUDE_CODE_SESSION_ID env (interactive --close-done fix) =="
# The close skill runs --close-done interactively: no --session-id, tty stdin, no
# hook payload. Before the fix sid stayed empty -> key=nosession -> the real
# session's marker never cleared. Now it falls back to the env var.
TE="$(mktemp -d)"
env -u CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID="env-sid-42" HERMES_FAKE_TS='2026-07-01T21:00:00Z' bash "$CS" --memory-dir "$TE" --init </dev/null >/dev/null 2>&1
journal "$TE" '2026-07-01T21:01:00Z' 2
env -u CODEX_THREAD_ID CLAUDE_CODE_SESSION_ID="env-sid-42" HERMES_FAKE_TS='2026-07-01T21:30:00Z' bash "$CS" --memory-dir "$TE" --close-done </dev/null >/dev/null 2>&1
if [ -f "$TE/.close-state/env-sid-42.env" ] && [ ! -f "$TE/.close-state/nosession.env" ] \
   && grep -q 'close_done_at=2026-07-01T21:30:00Z' "$TE/.close-state/env-sid-42.env"; then
  ok "env-var session id resolves close-done to the real session (not nosession)"
else
  bad "env fallback: files=[$(ls "$TE/.close-state" 2>/dev/null | tr '\n' ' ')]"
fi
rm -rf "$TE"

echo "== 21a. session-id from CODEX_THREAD_ID env (Codex init + close-done) =="
TCX="$(mktemp -d)"
env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID="codex-thread-42" HERMES_FAKE_TS='2026-07-01T22:00:00Z' bash "$CS" --memory-dir "$TCX" --init </dev/null >/dev/null 2>&1
journal "$TCX" '2026-07-01T22:01:00Z' 2
env -u CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID="codex-thread-42" HERMES_FAKE_TS='2026-07-01T22:30:00Z' bash "$CS" --memory-dir "$TCX" --close-done </dev/null >/dev/null 2>&1
if [ -f "$TCX/.close-state/codex-thread-42.env" ] && [ ! -f "$TCX/.close-state/nosession.env" ] \
   && grep -q 'close_done_at=2026-07-01T22:30:00Z' "$TCX/.close-state/codex-thread-42.env"; then
  ok "CODEX_THREAD_ID resolves init and close-done to the real thread"
else
  bad "Codex env fallback: files=[$(ls "$TCX/.close-state" 2>/dev/null | tr '\n' ' ')]"
fi
rm -rf "$TCX"

echo "== 21b. CODEX_THREAD_ID wins over CLAUDE_CODE_SESSION_ID when both exist =="
THOST="$(mktemp -d)"
CODEX_THREAD_ID="codex-wins" CLAUDE_CODE_SESSION_ID="claude-loses" HERMES_FAKE_TS='2026-07-01T22:45:00Z' bash "$CS" --memory-dir "$THOST" --init </dev/null >/dev/null 2>&1
[ -f "$THOST/.close-state/codex-wins.env" ] && [ ! -f "$THOST/.close-state/claude-loses.env" ] \
  && ok "Codex host identity wins over Claude host identity" || bad "host priority: $(ls "$THOST/.close-state" 2>/dev/null | tr '\n' ' ')"
rm -rf "$THOST"

echo "== 22. explicit --session-id still wins over env var =="
TE2="$(mktemp -d)"
echo '{"session_id":"payload-should-lose"}' | CODEX_THREAD_ID="codex-should-lose" CLAUDE_CODE_SESSION_ID="claude-should-lose" HERMES_FAKE_TS='2026-07-01T23:00:00Z' bash "$CS" --memory-dir "$TE2" --session-id "explicit-wins" --init >/dev/null 2>&1
[ -f "$TE2/.close-state/explicit-wins.env" ] && [ ! -f "$TE2/.close-state/codex-should-lose.env" ] && [ ! -f "$TE2/.close-state/claude-should-lose.env" ] \
  && [ ! -f "$TE2/.close-state/payload-should-lose.env" ] \
  && ok "explicit --session-id wins over payload and env" || bad "priority: $(ls "$TE2/.close-state" 2>/dev/null | tr '\n' ' ')"
rm -rf "$TE2"

echo "== 23. LEDGER GATE: open todo.md items + no --ledger-ok -> close-done refused (exit 2) =="
TL="$(mktemp -d)"
HERMES_FAKE_TS='2026-07-02T09:00:00Z' bash "$CS" --memory-dir "$TL" --session-id "ledg" --init >/dev/null 2>&1
printf '# todo\n\n- [ ] something open\n- [x] already done\n' > "$TL/todo.md"
HERMES_FAKE_TS='2026-07-02T09:30:00Z' bash "$CS" --memory-dir "$TL" --session-id "ledg" --close-done >/dev/null 2>&1; rc=$?
st="$(bash "$CS" --memory-dir "$TL" --session-id "ledg" --status)"
if [ "$rc" -eq 2 ] && echo "$st" | grep -q 'close_done_at=$'; then
  ok "open ledger blocks close-done, close_done_at unset"
else
  bad "ledger gate rc=$rc st=$st"
fi

echo "== 24. LEDGER GATE: --ledger-ok lets close-done through =="
HERMES_FAKE_TS='2026-07-02T10:00:00Z' bash "$CS" --memory-dir "$TL" --session-id "ledg" --close-done --ledger-ok >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && bash "$CS" --memory-dir "$TL" --session-id "ledg" --status | grep -q 'close_done_at=2026-07-02T10:00:00Z' \
  && ok "--ledger-ok passes the gate" || bad "ledger-ok rc=$rc"
rm -rf "$TL"

echo "== 25. LEDGER GATE: no open items (only [x]) -> close-done passes without flag =="
TL2="$(mktemp -d)"
HERMES_FAKE_TS='2026-07-02T11:00:00Z' bash "$CS" --memory-dir "$TL2" --session-id "clean" --init >/dev/null 2>&1
printf '# todo\n\n- [x] all done here\n' > "$TL2/todo.md"
HERMES_FAKE_TS='2026-07-02T11:30:00Z' bash "$CS" --memory-dir "$TL2" --session-id "clean" --close-done >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "clean ledger needs no flag" || bad "clean ledger rc=$rc"
rm -rf "$TL2"

echo "== 26. LEDGER GATE: no todo.md at all -> close-done passes (nothing to reconcile) =="
TL3="$(mktemp -d)"
HERMES_FAKE_TS='2026-07-02T12:00:00Z' bash "$CS" --memory-dir "$TL3" --session-id "notodo" --init >/dev/null 2>&1
HERMES_FAKE_TS='2026-07-02T12:30:00Z' bash "$CS" --memory-dir "$TL3" --session-id "notodo" --close-done >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "no todo.md -> no gate" || bad "no-todo rc=$rc"
rm -rf "$TL3"

echo "== 27. LEDGER GATE fenced-aware: a '- [ ]' inside a code fence does NOT block =="
TLF="$(mktemp -d)"
HERMES_FAKE_TS='2026-07-02T13:00:00Z' bash "$CS" --memory-dir "$TLF" --session-id "fenced" --init >/dev/null 2>&1
printf '# todo\n\n```\n- [ ] this is just an example inside a fence, not a real item\n```\n\n- [x] done\n' > "$TLF/todo.md"
HERMES_FAKE_TS='2026-07-02T13:30:00Z' bash "$CS" --memory-dir "$TLF" --session-id "fenced" --close-done >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "fenced '- [ ]' ignored (gate agrees with session_close)" || bad "fenced blocked close rc=$rc"
rm -rf "$TLF"

echo "== 28. LEDGER GATE indent-aware: a nested '  - [ ]' sub-item DOES block =="
TLN="$(mktemp -d)"
HERMES_FAKE_TS='2026-07-02T14:00:00Z' bash "$CS" --memory-dir "$TLN" --session-id "nested" --init >/dev/null 2>&1
printf '# todo\n\n- [x] parent done\n  - [ ] but this sub-item is still open\n' > "$TLN/todo.md"
HERMES_FAKE_TS='2026-07-02T14:30:00Z' bash "$CS" --memory-dir "$TLN" --session-id "nested" --close-done >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "nested sub-item counted, close blocked (raw ^grep would have missed it)" || bad "nested slipped gate rc=$rc"
rm -rf "$TLN"

echo "== 29. B1 fail-honest: session-end marker write fails -> exit 1, state RETAINED (not silently lost) =="
TBE="$(mktemp -d)"
HERMES_FAKE_TS='2026-07-02T15:00:00Z' bash "$CS" --memory-dir "$TBE" --session-id "bwrite" --init >/dev/null 2>&1
journal "$TBE" '2026-07-02T15:01:00Z' 2
chmod 555 "$TBE/.close-state"   # make the state dir unwritable -> marker write must fail
HERMES_FAKE_TS='2026-07-02T15:30:00Z' bash "$CS" --memory-dir "$TBE" --session-id "bwrite" --session-end >/dev/null 2>&1; rc=$?
chmod 755 "$TBE/.close-state"   # restore so we can inspect + cleanup
if [ "$rc" -eq 1 ] && [ -f "$TBE/.close-state/bwrite.env" ] && [ ! -f "$TBE/.close-state/UNCLOSED-bwrite.env" ]; then
  ok "marker write failed -> exit 1, live state retained, no false marker"
else
  bad "B1 rc=$rc state=$([ -f "$TBE/.close-state/bwrite.env" ] && echo kept || echo GONE) marker=$([ -f "$TBE/.close-state/UNCLOSED-bwrite.env" ] && echo FALSE-PRESENT || echo none)"
fi
rm -rf "$TBE"

echo "== 30. empty session id fails loud for init and close-done =="
TNS="$(mktemp -d)"
init_err="$(env -u CODEX_THREAD_ID -u CLAUDE_CODE_SESSION_ID HERMES_FAKE_TS='2026-07-03T09:00:00Z' bash "$CS" --memory-dir "$TNS" --init </dev/null 2>&1)"; init_rc=$?
close_err="$(env -u CODEX_THREAD_ID -u CLAUDE_CODE_SESSION_ID HERMES_FAKE_TS='2026-07-03T09:01:00Z' bash "$CS" --memory-dir "$TNS" --close-done </dev/null 2>&1)"; close_rc=$?
[ "$init_rc" -eq 1 ] && [ "$close_rc" -eq 1 ] && [ ! -e "$TNS/.close-state/nosession.env" ] \
  && printf '%s' "$init_err" | grep -q 'requires a session id' \
  && printf '%s' "$close_err" | grep -q 'requires a session id' \
  && ok "missing identity refuses init and close-done without nosession state" \
  || bad "missing-id contract: init=$init_rc close=$close_rc files=[$(ls "$TNS/.close-state" 2>/dev/null | tr '\n' ' ')]"
rm -rf "$TNS"

echo "== 31. boot-recovery: 2 dead markers + 1 live -> surface exactly the 2 dead, FIFO by started_at =="
TBD="$(mktemp -d)"; mkdir -p "$TBD/.close-state"
# a live session (state present, NO UNCLOSED marker) must NOT be surfaced
printf 'session_id=live1\nstarted_at=2026-07-12T09:00:00Z\nclose_done_at=\n' > "$TBD/.close-state/live1.env"
printf 'session_id=deadNEW\nstarted_at=2026-07-11T10:00:00Z\nunclosed_at=2026-07-11T12:00:00Z\njournal=%s/session.md\nnote=x\n' "$TBD" > "$TBD/.close-state/UNCLOSED-deadNEW.env"
printf 'session_id=deadOLD\nstarted_at=2026-07-10T08:00:00Z\nunclosed_at=2026-07-10T09:00:00Z\njournal=%s/session.md\nnote=x\n' "$TBD" > "$TBD/.close-state/UNCLOSED-deadOLD.env"
o="$(bash "$CS" --memory-dir "$TBD" --boot-recovery)"
n_sid="$(printf '%s\n' "$o" | grep -c 'SID=dead')"
first="$(printf '%s\n' "$o" | grep 'SID=dead' | head -n1)"
if [ "$n_sid" -eq 2 ] && printf '%s' "$first" | grep -q 'SID=deadOLD' && ! printf '%s\n' "$o" | grep -q 'live1'; then
  ok "surfaced exactly 2 dead, oldest-first (FIFO), live session not surfaced"
else
  bad "boot-recovery n=$n_sid first='$first' (expected 2, deadOLD first, no live1)"
fi

echo "== 32. boot-recovery: no markers -> silent, exit 0 =="
rm -f "$TBD"/.close-state/UNCLOSED-*.env
o="$(bash "$CS" --memory-dir "$TBD" --boot-recovery)"; rc=$?
{ [ -z "$o" ] && [ "$rc" -eq 0 ]; } && ok "no markers -> silent exit 0" || bad "boot-recovery not silent: rc=$rc o='$o'"

echo "== 33. dojezd close: --close-done --session-id <deadSID> clears ONLY that marker =="
printf 'session_id=deadNEW\nstarted_at=2026-07-11T10:00:00Z\nunclosed_at=2026-07-11T12:00:00Z\njournal=%s/session.md\nnote=x\n' "$TBD" > "$TBD/.close-state/UNCLOSED-deadNEW.env"
printf 'session_id=deadOLD\nstarted_at=2026-07-10T08:00:00Z\nunclosed_at=2026-07-10T09:00:00Z\njournal=%s/session.md\nnote=x\n' "$TBD" > "$TBD/.close-state/UNCLOSED-deadOLD.env"
HERMES_FAKE_TS='2026-07-12T10:00:00Z' bash "$CS" --memory-dir "$TBD" --session-id "deadOLD" --close-done >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$TBD/.close-state/UNCLOSED-deadOLD.env" ] && [ -f "$TBD/.close-state/UNCLOSED-deadNEW.env" ]; then
  ok "close-done cleared deadOLD marker only; deadNEW still queued (per-SID receipt)"
else
  bad "dojezd rc=$rc deadOLD=$([ -f "$TBD/.close-state/UNCLOSED-deadOLD.env" ] && echo PRESENT || echo cleared) deadNEW=$([ -f "$TBD/.close-state/UNCLOSED-deadNEW.env" ] && echo present || echo GONE)"
fi
rm -rf "$TBD"

echo "== 34. non-tty idle stdin must NOT hang (0.1.30 regression: --close-done fell into cat) =="
# Before 0.1.30 the stdin guard blacklisted only boot-recovery/status, so --close-done (and a
# hook-driven --init/--session-end run by hand) fell into `cat` and hung forever when stdin
# was open-but-empty (headless subagent close, no </dev/null). Guard now whitelists the two
# hook modes + bounds the read. This test runs each headless with a stdin that never EOFs and
# asserts it terminates. Zero-dep timeout: background + kill-poll (no `timeout`/perl dep).
TH="$(mktemp -d)"
printf '<!-- hermes:entry kind=session id=x ts=2000-01-01T00:00:00Z -->\n' > "$TH/session.md"
printf '# todo\n' > "$TH/todo.md"
hung=""
for m in close-done init session-end; do
  bash "$CS" --memory-dir "$TH" "--$m" < <(sleep 6) >/dev/null 2>&1 &
  hp=$!
  i=0
  while kill -0 "$hp" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -ge 8 ] && break   # ~4s cap (8 * 0.5s); fix returns in <2s
    sleep 0.5
  done
  if kill -0 "$hp" 2>/dev/null; then kill "$hp" 2>/dev/null; hung="$hung --$m"; fi
  wait "$hp" 2>/dev/null || true
done
[ -z "$hung" ] && ok "non-tty idle stdin terminates (close-done/init/session-end)" || bad "non-tty stdin HUNG on:$hung"
rm -rf "$TH"

echo ""
echo "== close_state: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
