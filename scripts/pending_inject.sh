#!/usr/bin/env bash
# pending_inject.sh — boot nerve: surface decisions waiting on a HUMAN, loudly, every boot.
#
# The forcing function against "awaiting approval" items dying as passive carry lines:
# a proposal parked in todo.md as `- [ ] PENDING(<owner>): ...` is announced at EVERY session
# start until the human resolves it (ledger_carry --done with the item's full text). This is
# a VOICE, not a gate — human-owned debt must never hard-block work (the loop-gate lesson:
# blocking the unresolvable breeds defer theater). Inflation (10+ pending) is a signal the
# owner isn't deciding — exactly what should be visible, not hidden.
#
# Convention (write side, via existing ledger_carry --item — no new store):
#   - [ ] PENDING(farky): WHAT I want / WHY you / impact of yes-no (proposed YYYY-MM-DD)
#
# Read side here: fence-aware single-pass over ONE snapshot (mirrors hermes_count_open_todo —
# a documentation example inside a ``` fence is NOT a real pending decision), bounded output
# (block cap ~8 KB, per-item display cap 200 chars — the ITEM is never truncated in todo.md,
# only its display row), secret redaction on the way out.
#
# Invariants: read-only · exit 0 always · silent when there is nothing pending.
# Kill switch: HERMES_PENDING_OFF=1 -> immediate silent exit.
set -uo pipefail

[ "${HERMES_PENDING_OFF:-0}" = "1" ] && exit 0

memory_dir="./memory"
while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir) memory_dir="${2:-./memory}"; shift 2 ;;
    -h|--help)                 grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

todo="$memory_dir/todo.md"
[ -f "$todo" ] || exit 0

# One snapshot, one fence-aware pass: open PENDING items only (checked-off ones are resolved).
items="$(awk '
  /^[[:space:]]*```/ { fenced = !fenced; next }
  !fenced && /^[[:space:]]*- \[ \] PENDING\(/ {
    line = $0; sub(/^[[:space:]]*- \[ \] /, "", line)
    print line
  }
' "$todo" 2>/dev/null)" || items=""
[ -n "$items" ] || exit 0

n="$(printf '%s\n' "$items" | grep -c . || true)"

# Oldest proposed date, when items carry the "(proposed YYYY-MM-DD)" convention.
oldest="$(printf '%s\n' "$items" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | head -n1 || true)"
hdr="=== ⏳ PENDING DECISIONS ($n"
[ -n "$oldest" ] && hdr="$hdr; oldest $oldest"
hdr="$hdr) — waiting on a human call; surfaced EVERY boot until resolved ==="

echo
echo "$hdr"
budget=8192 used=0 shown=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  disp="$line"; [ "${#disp}" -gt 200 ] && disp="${disp:0:200}…"
  disp="$(printf '%s' "$disp" | sed -E \
    -e 's/(sk-|sk-ant-|AIza|ghp_|gho_|ghs_|ghu_|ghr_|glpat-|xox[baprs]-)[A-Za-z0-9_-]{16,}/[REDACTED]/g' \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g')"
  used=$((used + ${#disp} + 4))
  if [ "$used" -gt "$budget" ]; then
    echo "> …and $((n - shown)) more — see $todo"
    break
  fi
  printf '> %s\n' "$disp"
  shown=$((shown+1))
done <<EOF_ITEMS
$items
EOF_ITEMS
echo "=== resolve: decide, then: ledger_carry.sh --memory-dir $memory_dir --done '<full item text from todo.md>' ==="
exit 0
