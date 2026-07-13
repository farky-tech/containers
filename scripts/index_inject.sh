#!/usr/bin/env bash
# index_inject.sh — inject a folder-INDEX map at session start (Farky's model: "you get the
# sum of the indexes = you know at once what lives where and in which folder"). One start-time map.
#
# Promoted into the plugin engine (was cc_farky-local .claude/scripts). Opt-in boot nerve:
# adopters wire it via adapters/claude-code/settings-fragment.example.json, it is NOT force-wired.
#
# Repo folders carry a physical INDEX.md (curated header + generated manifest); this hook
# REGENERATES that file (merge — keeps the header, refreshes the table so it matches reality)
# but INJECTS only the TABLE (what lives where), not the kernel header — signal over fluff (1M window
# means size is a non-issue; the point is attention: don't dilute today's news with kernel).
# Host ~/.claude folders are live-only (shared, not written into).
#
# TWO SCOPES (--scope, default memory):
#   memory  — inject ONLY the memory/ manifest (0.1.24 boot diet; the safe default for adopters).
#   repo    — WHOLE-REPO rollup (Farkyho original vision, restored 0.1.31): refresh every tracked
#             folder's INDEX.md + (re)generate the ROOT INDEX.md as a rollup of all top-level
#             folders & root docs, and inject that map + the memory/ detail. A folder is "tracked"
#             = it already carries an INDEX.md (curator opt-in: give a folder an INDEX.md once and
#             it stays fresh + shows in the map). `--whole-repo` is shorthand for `--scope repo`.
# (0.1.24 narrowed inject to memory/ "boot diet"; that quietly dropped Farky's whole-repo intent —
#  the header kept promising "the sum of all indexes" while the body did one folder. repo scope fixes
#  that drift; memory stays the default so no adopter's boot cost changes without opting in.)
set -uo pipefail
MEMORY_DIR="./memory"
SCOPE="memory"
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --memory-dir|--hermes-dir) MEMORY_DIR="${2:-./memory}"; shift 2 ;;  # --hermes-dir = legacy alias
    --scope)       SCOPE="${2:-memory}"; shift 2 ;;
    --whole-repo)  SCOPE="repo"; shift ;;
    *) shift ;;
  esac
done
ROOT="${CLAUDE_PROJECT_DIR:-.}"
GEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gen_index.sh"   # sibling in the engine
[ -f "$GEN" ] || exit 0

# refresh a folder's INDEX.md (keep curated header) and inject only its table
emit_repo() { # $1 = rel dir, $2 = title
  local d="$ROOT/$1"
  [ -d "$d" ] || return 0
  bash "$GEN" "$d" --title "$2" --merge-into "$d/INDEX.md" 2>/dev/null || true
  echo; printf '## %s\n' "$2"; bash "$GEN" "$d" --title "$2" --table-only 2>/dev/null || true
}

if [ "$SCOPE" = "repo" ]; then
  echo
  echo "=== 🗂️ REPO — folder map (info-injection: you know what lives where) ==="
  # 1. Keep every TRACKED folder's INDEX.md fresh (tracked = already has an INDEX.md).
  for sub in "$ROOT"/*/; do
    b="$(basename "$sub")"
    # Skip trash, dot/underscore folders, and common build/vendor dirs (noise on adopter repos).
    case "$b" in Koš|Kos|_*|.*|node_modules|vendor|dist|build) continue ;; esac
    # Never write through a symlink OUT of the repo (trust boundary; audit 2026-07-12).
    [ -L "${sub%/}" ] && continue
    # "Tracked" = the folder already carries an INDEX.md (curator opt-in for the deep refresh).
    [ -f "$sub/INDEX.md" ] || continue
    # memory/ is refreshed in step 3 (detailed) — don't regenerate it twice per boot.
    [ "$b" = "memory" ] && continue
    # mtime skip (audit 2026-07-12): only regenerate when something inside is NEWER than the
    # INDEX.md — its own mtime is the cache stamp. Keeps a many-folder repo's SessionStart from
    # re-generating every INDEX from scratch on every boot when nothing changed.
    # -mindepth 1 excludes the dir itself: `mv`-ing INDEX.md bumps the dir mtime, so including
    # the dir would make it look "newer than INDEX.md" every time and never skip.
    if [ -z "$(find "$sub" -mindepth 1 -maxdepth 1 ! -name INDEX.md -newer "$sub/INDEX.md" 2>/dev/null)" ]; then
      continue
    fi
    bash "$GEN" "$sub" --title "$b" --merge-into "$sub/INDEX.md" 2>/dev/null || true
  done
  # 2. (re)generate the ROOT INDEX.md — the rollup of all top-level folders + root docs — keeping
  #    any curated header, and inject that map. This is "kde co je" for the whole repo on one screen.
  root_title="$(basename "$ROOT")"
  bash "$GEN" "$ROOT" --title "$root_title" --merge-into "$ROOT/INDEX.md" 2>/dev/null || true
  echo; printf '## repo — what lives where (top-level)\n'
  bash "$GEN" "$ROOT" --title "$root_title" --table-only 2>/dev/null || true
  # 3. memory/ stays DETAILED — it is boot-critical (the map above shows it only as one row).
  emit_repo "memory" "memory/ — the brain's memory"
  echo
  echo "=== (folder detail → open its INDEX.md; only the map + memory get injected) ==="
  exit 0
fi

# default scope=memory (0.1.24 boot diet): inject only the memory/ manifest.
echo
echo "=== 🗂️ memory/ — memory manifest (info-injection: you KNOW it) ==="
emit_repo "memory" "memory/ — the brain's memory"
echo
echo "=== (the full curated header lives in the folder's INDEX.md; only the manifest table is injected) ==="
exit 0
