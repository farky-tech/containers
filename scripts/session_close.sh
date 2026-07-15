#!/usr/bin/env bash
# session_close.sh — compose a structured close/handoff summary from memory/ files.
#
# Backbone script (SCRIPTED). Read-only by default: reads memory/{todo,fallbacks,
# KNOWLEDGE,session}.md and prints a deterministic handoff block to stdout (open
# counts, recent entries). The fmc-close subagent calls this instead of
# free-forming a summary. With --carry it additionally persists open items passed
# on stdin via ledger_carry.sh (idempotent).
#
# Usage:
#   session_close.sh [--memory-dir <dir>]
#   printf 'open item\n' | session_close.sh --memory-dir ./memory --carry
#
# Exit codes:  0 ok | 1 error/usage

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hermes_blocks.sh
. "$script_dir/lib/hermes_blocks.sh"

usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

memory_dir="./memory" carry=0

while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir) memory_dir="${2:-}"; shift 2 ;;  # --hermes-dir = legacy alias (pre-rename adopters)
    --carry)      carry=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "session_close: unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [ ! -d "$memory_dir" ]; then
  echo "session_close: memory dir not found: $memory_dir" >&2
  exit 1
fi

todo="$memory_dir/todo.md"
fb="$memory_dir/fallbacks.md"
knowledge="$memory_dir/KNOWLEDGE.md"
legacy_les="$memory_dir/lessons.md"
legacy_dec="$memory_dir/decisions.md"
[ -f "$legacy_les" ] || legacy_les="$memory_dir/pouceni.md"
[ -f "$legacy_dec" ] || legacy_dec="$memory_dir/rozhodnuti.md"
sess="$memory_dir/session.md"

# Open to-do count — delegates to the shared, fenced/indent-aware definition in the
# lib so this handoff count and the close_state ledger gate never disagree.
count_open_todo() { hermes_count_open_todo "$1"; }

# KNOWLEDGE.md is the canonical shared store; kind distinguishes lessons and
# decisions. Fall back to one legacy genre file only when KNOWLEDGE.md does not
# exist, so an upgraded-but-not-canonicalized adopter stays readable without
# double-counting entries copied into both stores.
open_todo="$(count_open_todo "$todo")"
open_fb="$(hermes_count_open_fallbacks "$fb")"
fb_blocks="$(hermes_count_blocks "$fb" fallback)"
if [ -f "$knowledge" ]; then
  les_blocks="$(hermes_count_blocks "$knowledge" lesson)"
  dec_blocks="$(hermes_count_blocks "$knowledge" decision)"
else
  les_blocks="$(hermes_count_blocks "$legacy_les")"
  dec_blocks="$(hermes_count_blocks "$legacy_dec")"
fi

carry_status="n/a"
if [ "$carry" -eq 1 ] && [ ! -t 0 ]; then
  # Delegate persistence of stdin items to ledger_carry (idempotent). Do NOT
  # swallow failure — a silent carry failure is itself a silent fallback.
  set +e
  "$script_dir/ledger_carry.sh" --memory-dir "$memory_dir" >&2
  lrc=$?
  set -e
  case "$lrc" in
    0) carry_status="ok" ;;
    2) carry_status="empty (nothing to carry)" ;;
    *) carry_status="FAILED" ;;
  esac
fi

# Distil the session journal (raw black box) into a chronological recap. This is
# what lets a small-window model answer "what did we do this session" from the
# FILE, not from its drifted context.
sess_blocks="$(hermes_count_blocks "$sess" session)"
journal=""
if [ -f "$sess" ]; then
  journal="$(awk '
    /<!-- hermes:entry kind=session/ { inb=1; next }
    /<!-- \/hermes:entry -->/        { inb=0; next }
    inb { print "  - " $0 }
  ' "$sess")"
fi

# The actual open items (not just a count) so the next session can pull them
# straight back into the live lapac list (TodoWrite) as its first entries.
open_items=""
if [ -f "$todo" ]; then
  open_items="$(awk '
    /^```/ { fenced=!fenced; next }
    !fenced && /^- \[ \]/ { sub(/^[[:space:]]*/, "  "); print }
  ' "$todo" 2>/dev/null || true)"
fi

# Length-guard (audit finding: the SessionStart handoff injects this whole dump into context
# every boot; with per-turn journal auto-capture the journal grows fast, and a long todo backlog
# balloons open_items). Cap both dumps; the full content always stays in the source files.
_JMAX=10; _OMAX=8   # 0.1.24 boot diet: the handoff is orientation, not an archive — full content lives in the files
_jl="$(printf '%s\n' "$journal" | grep -c . 2>/dev/null || echo 0)"
if [ "${_jl:-0}" -gt "$_JMAX" ] 2>/dev/null; then
  journal="  (...older journal truncated — $((_jl - _JMAX)) lines hidden, full content in $sess)
$(printf '%s\n' "$journal" | tail -n "$_JMAX")"
fi
# tail (not head): keep the NEWEST items — ledger_carry appends new todos at the end, and the
# handoff instructs the next session to pull these into the lapac list, so newest = most relevant.
_ol="$(printf '%s\n' "$open_items" | grep -c '\[ \]' 2>/dev/null || echo 0)"
if [ "${_ol:-0}" -gt "$_OMAX" ] 2>/dev/null; then
  open_items="  (...and $((_ol - _OMAX)) more older items — see $todo)
$(printf '%s\n' "$open_items" | tail -n "$_OMAX")"
fi

cat <<EOF
## Session close — container handoff

- Open to-do items: $open_todo  (see $todo)
- Open fallbacks: $open_fb  (see $fb)
- Fallback blocks total: $fb_blocks
- Lesson blocks: $les_blocks
- Decision blocks: $dec_blocks
- Carry-forward: $carry_status
- Session journal entries: $sess_blocks  (see $sess)

### What happened this session (distilled from session.md → summarize into log.md)
${journal:-  (no session journal — session_note.sh --start was never run)}

### Open items (pull these into the lapac list first at next boot)
${open_items:-  (nothing unfinished — todo.md is clean)}
Next load: read memory/STATE.md (orientation, read-first), pull the open items above into the lapac list.
EOF

# Legacy compat hint (R10): warn if files still hold un-migrated entries.
for f in "$todo" "$fb" "$knowledge" "$legacy_les" "$legacy_dec"; do
  if hermes_has_legacy_entries "$f"; then
    echo "session_close: note — $f has legacy (## date) entries not in canonical blocks; see MIGRATION.md" >&2
  fi
done

# Surface a carry failure as a non-zero exit (no silent fallback in the close path).
if [ "$carry_status" = "FAILED" ]; then
  echo "session_close: carry-forward FAILED — open items were not persisted" >&2
  exit 1
fi

exit 0
