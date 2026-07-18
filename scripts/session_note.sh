#!/usr/bin/env bash
# session_note.sh — the session journal (black box of "what is happening now").
#
# Backbone script. The lapac skill calls this to record the live session as it
# unfolds, into memory/session.md, so the narrative survives compaction/drift and
# can be distilled at close — independent of the model's context window.
#
# session.md is RAW (many notes during one session); log.md is the DISTILLED one
# line per session. They do not duplicate: session_close reads session.md to
# produce the log line, then the journal is archived on the next --start.
#
# Usage:
#   session_note.sh --memory-dir <dir> --start "<session goal>"   # begin a session
#   session_note.sh --memory-dir <dir> --note  "<milestone>"      # record an event
#   [--dry-run]
#
# A milestone = decision made, thing learned, thing built, wall hit. NOT every step.
#
# Exit codes:  0 ok (or idempotent skip) | 1 error/usage

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hermes_blocks.sh
. "$script_dir/lib/hermes_blocks.sh"

usage() { sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

memory_dir="./memory" mode="" text="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir) memory_dir="${2:-}"; shift 2 ;;  # --hermes-dir = legacy alias (pre-rename adopters)
    --start)      mode="start"; text="${2:-}"; shift 2 ;;
    --note)       mode="note"; text="${2:-}"; shift 2 ;;
    --dry-run)    dry_run=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "session_note: unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

[ -n "$mode" ] || { echo "session_note: need --start or --note" >&2; usage; exit 1; }
[ -n "$text" ] || { echo "session_note: text is required" >&2; exit 1; }

file="$memory_dir/session.md"
ts="$(hermes_now_utc)"

instance_name="${FMC_INSTANCE_NAME:-}"
if [ -z "$instance_name" ] && [ -f "$memory_dir/MEMORY.md" ]; then
  instance_name="$(awk '
    /^(Instance|Owner|Vlastnik|Vlastník):[[:space:]]*/ {
      line=$0
      sub(/^[^:]*:[[:space:]]*/, "", line)
      print line
      exit
    }
  ' "$memory_dir/MEMORY.md")"
fi
instance_name="$(printf '%s' "$instance_name" | tr '\r\n\t' '   ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | cut -c1-80)"
[ -n "$instance_name" ] || instance_name="current instance"

if [ "$mode" = "start" ]; then
  if [ "$dry_run" -eq 1 ]; then
    echo "session_note: dry-run — would start new session.md (goal: $text)" >&2
    exit 0
  fi
  mkdir -p "$memory_dir"
  # Archive a previous, non-empty journal so nothing is lost, then start fresh.
  if [ -f "$file" ] && hermes_count_blocks "$file" session | grep -qv '^0$'; then
    archive_dir="$memory_dir/.session-archive"
    mkdir -p "$archive_dir"
    stamp="$(printf '%s' "$ts" | tr ':' '-')"
    mv "$file" "$archive_dir/session-$stamp.md"
    echo "session_note: archived previous journal -> $archive_dir/session-$stamp.md" >&2
  fi
  {
    printf '# Session journal — %s — black box of the live session\n\n' "$instance_name"
    printf 'Raw material for the close distillation (session_close → log.md / KNOWLEDGE).\n'
    printf 'Written via session_note.sh; survives compaction. Archived on the next --start after distillation.\n'
    printf 'WRITE WITH CONTEXT — WHY, not just WHAT: why we did/skipped it, what we decided and WHY,\n'
    printf 'what we ran into. Goal: the next %s after a crash must understand the\n' "$instance_name"
    printf 'THINKING, not just a list of done things. A bare list without why = a broken handoff.\n\n'
    printf -- '---\n'
  } | hermes_atomic_write "$file"
  # First entry = the goal.
  id="$(hermes_block_id "session" "start|$text|$ts")"
  printf 'SESSION GOAL: %s' "$text" | hermes_append_block "$file" "session" "$id" "$ts" >/dev/null
  echo "session_note: started session.md (goal: $text)" >&2
  exit 0
fi

# mode = note
if [ "$dry_run" -eq 1 ]; then
  printf '<!-- hermes:entry kind=session id=… ts=%s -->\n%s\n<!-- /hermes:entry -->\n' "$ts" "$text"
  echo "session_note: dry-run, nothing written ($file)" >&2
  exit 0
fi
# Auto-create a minimal journal if --note is the first call of the session.
if [ ! -f "$file" ]; then
  mkdir -p "$memory_dir"
  printf '# Session journal — %s\n\n---\n' "$instance_name" | hermes_atomic_write "$file"
fi
id="$(hermes_block_id "session" "$text")"
set +e
printf '%s' "$text" | hermes_append_block "$file" "session" "$id" "$ts"
rc=$?
set -e
case "$rc" in
  0) echo "session_note: noted -> $file" >&2; exit 0 ;;
  2) echo "session_note: duplicate note, skipped -> $file" >&2; exit 0 ;;
  *) echo "session_note: write failed -> $file" >&2; exit 1 ;;
esac
