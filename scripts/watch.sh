#!/usr/bin/env bash
# watch.sh — drift "tap": reports when a watched file changed since the last run.
#
# MAINTAINER-ONLY tool (0.1.33; same pattern as state_guard.sh maintainer modes):
# it is NOT part of the adopter opt-in fragment and never will be force-wired.
# The source curator wires it into their OWN SessionStart to triage inbound edits
# (typically: an adopter appended to ADOPTION.md). Adopters lose nothing without it.
#
# File-watcher primitive for the cross-session case: Claude Code has no live push
# into a non-running session, so we fingerprint the watched files and report the
# diff at session start.
#
# Usage:
#   watch.sh --memory-dir <dir> [--paths "p1 p2 ..."] [--label "<text>"]
# Default watched files (no --paths): ADOPTION.md + manifest.yaml at the plugin
#   root (derived from this script's location; space-safe). NOTE: --paths itself
#   is a space-separated list — paths given through it must not contain spaces
#   (the space-safe path is the default set).
# State: <memory-dir>/.watch-state (lines: "<sha>\t<path>"). Always exit 0
#   (delivery/report primitive — must never block a session start).

set -u

MEMORY_DIR=""
PATHS=""
LABEL="FMC WATCH"

while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir) MEMORY_DIR="${2:-}"; shift 2 ;;  # --hermes-dir = legacy alias (pre-rename adopters)
    --paths)      PATHS="${2:-}"; shift 2 ;;
    --label)      LABEL="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

[ -z "$MEMORY_DIR" ] && { echo "watch: missing --memory-dir" >&2; exit 0; }
[ -d "$MEMORY_DIR" ] || { echo "watch: --memory-dir does not exist: $MEMORY_DIR" >&2; exit 0; }

# Plugin root = the script's parent dir (scripts/..)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Watched paths as a bash-3.2 array (0.1.33): the old space-joined string
# word-split the DEFAULT paths too — a plugin root containing a space (iCloud,
# "My Drive", …) silently watched two nonexistent fragments and reported nothing.
PATHS_ARR=()
if [ -z "$PATHS" ]; then
  PATHS_ARR=("$PLUGIN_ROOT/ADOPTION.md" "$PLUGIN_ROOT/manifest.yaml")
else
  for _p in $PATHS; do PATHS_ARR+=("$_p"); done   # --paths stays space-separated by contract
fi

STATE="$MEMORY_DIR/.watch-state"

# sha256 helper (macOS shasum vs linux sha256sum)
sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  else echo "nohash"; fi
}

prev_sha() { [ -f "$STATE" ] && grep -F "	$1" "$STATE" 2>/dev/null | head -1 | cut -f1; }

CHANGED=""
# tmp beside the destination (0.1.33): a global-TMPDIR tmp made the final mv
# potentially cross-filesystem, i.e. non-atomic — a killed run could leave a
# truncated baseline.
NEWSTATE="$(mktemp "$MEMORY_DIR/.watch-state.XXXXXX" 2>/dev/null)" || exit 0
FIRST_RUN=0
[ -f "$STATE" ] || FIRST_RUN=1

for p in "${PATHS_ARR[@]}"; do
  [ -f "$p" ] || continue
  cur="$(sha "$p")"
  old="$(prev_sha "$p")"
  printf '%s\t%s\n' "$cur" "$p" >> "$NEWSTATE"
  if [ "$FIRST_RUN" -eq 0 ] && [ -n "$old" ] && [ "$cur" != "$old" ]; then
    CHANGED="$CHANGED $p"
  elif [ "$FIRST_RUN" -eq 0 ] && [ -z "$old" ]; then
    CHANGED="$CHANGED $p"   # newly watched file
  fi
done

mv "$NEWSTATE" "$STATE"

if [ "$FIRST_RUN" -eq 1 ]; then
  echo "⚙️  $LABEL: baseline initialized (${#PATHS_ARR[@]} watched paths). Changes reported from the next run."
elif [ -n "$CHANGED" ]; then
  echo "🔔 $LABEL: changed since last run →$CHANGED"
  echo "   → READ and triage (typically: an adopter appended to ADOPTION.md). Curator duty, not optional."
fi
exit 0
