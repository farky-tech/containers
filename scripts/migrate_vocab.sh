#!/usr/bin/env bash
# migrate_vocab.sh — one-shot 0.2.0 vocabulary migration for an existing memory/ folder.
#
# 0.2.0 renamed the engine's remaining non-English identifiers. Fresh installs get the new
# names from the template; an EXISTING fork's memory/ still has the old names, and the 0.2.0
# scripts read only the new ones. This renames the paths in place — it NEVER touches contents.
#
# Renames (idempotent, safe to re-run):
#   STAV.md          -> STATE.md
#   ZNALOST.md       -> KNOWLEDGE.md
#   umim.md          -> CAN.md
#   zdravi/          -> health/
#   .session-archiv/ -> .session-archive/
#
# Usage:   migrate_vocab.sh --memory-dir <dir> [--dry-run]
# Exit:    0 = done (or nothing to do) | 1 = usage/error

set -euo pipefail

memory_dir="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir) memory_dir="${2:-}"; shift 2 ;;
    --dry-run)    dry_run=1; shift ;;
    -h|--help)    grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "migrate_vocab: unknown arg: $1" >&2; exit 1 ;;
  esac
done
[ -n "$memory_dir" ] || { echo "migrate_vocab: --memory-dir <dir> is required" >&2; exit 1; }
[ -d "$memory_dir" ] || { echo "migrate_vocab: not a directory: $memory_dir" >&2; exit 1; }

# rename OLD -> NEW under memory_dir. Skip if OLD absent; refuse if NEW already exists (don't clobber).
renamed=0 skipped=0
do_rename() {
  old="$memory_dir/$1"; new="$memory_dir/$2"
  if [ ! -e "$old" ]; then skipped=$((skipped+1)); return 0; fi
  if [ -e "$new" ]; then
    echo "migrate_vocab: SKIP $1 -> $2 (target already exists — resolve by hand)" >&2
    skipped=$((skipped+1)); return 0
  fi
  if [ "$dry_run" -eq 1 ]; then echo "migrate_vocab: would rename $1 -> $2"; renamed=$((renamed+1)); return 0; fi
  # prefer git mv when the path is tracked, so history follows; else plain mv.
  if git -C "$memory_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
     && git -C "$memory_dir" ls-files --error-unmatch "$1" >/dev/null 2>&1; then
    git -C "$memory_dir" mv "$1" "$2"
  else
    mv "$old" "$new"
  fi
  echo "migrate_vocab: renamed $1 -> $2"
  renamed=$((renamed+1))
}

do_rename "STAV.md"          "STATE.md"
do_rename "ZNALOST.md"       "KNOWLEDGE.md"
do_rename "umim.md"          "CAN.md"
do_rename "zdravi"           "health"
do_rename ".session-archiv"  ".session-archive"

echo "migrate_vocab: done — $renamed renamed, $skipped already-current/absent.$([ "$dry_run" -eq 1 ] && echo ' (dry-run)')"
[ "$renamed" -gt 0 ] || echo "migrate_vocab: nothing to migrate (already on 0.2.0 vocabulary)."
exit 0
