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
#             Root marker `gen_index:tree` (0.3.4) upgrades this to recursive physical indexes and
#             a complete safe tree injection. `ostatni-v-repu/INDEX.md` with `gen_index:root-files`
#             owns files that conventionally remain directly in the repo root.
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

tree_dir_allowed() { # $1 = repo-relative directory, without leading ./
  local rel="${1:-}"
  case "/$rel/" in
    */.git/*|*/.venv/*|*/.tox/*|*/.cache/*|*/.pytest_cache/*|*/.mypy_cache/*|*/.ruff_cache/*|*/.next/*|*/.skill-build/*|*/__pycache__/*|*/node_modules/*|*/vendor/*|*/dist/*|*/build/*|*/Koš/*|*/Kos/*) return 1 ;;
    */memory/.backups/*|*/memory/.close-state/*|*/memory/.loop-state/*|*/memory/.session-archive/*|*/memory/.recall-state/*) return 1 ;;
  esac
  return 0
}

tree_dirs() {
  find "$ROOT" -type d 2>/dev/null | while IFS= read -r d; do
    [ "$d" = "$ROOT" ] && continue
    rel="${d#"$ROOT"/}"
    tree_dir_allowed "$rel" && printf '%s\n' "$d"
  done
}

refresh_tree_indexes() {
  # Pass 1 creates a physical INDEX.md in every included directory. Existing hand-written
  # or externally-generated INDEX files are authoritative for their folder and stay untouched.
  tree_dirs | while IFS= read -r d; do
    if [ -f "$d/INDEX.md" ] && grep -qF "gen_index:root-files" "$d/INDEX.md"; then
      continue
    fi
    [ -f "$d/INDEX.md" ] && continue
    bash "$GEN" "$d" --title "${d#"$ROOT"/}" --all-files --include-hidden \
      --merge-into "$d/INDEX.md" 2>/dev/null || true
  done

  # Pass 2 refreshes only FMC-managed indexes. Running after the seed pass means parent maps
  # already see the new child indexes on the first boot, not only on the second one.
  tree_dirs | while IFS= read -r d; do
    idx="$d/INDEX.md"
    grep -qF "gen_index:root-files" "$idx" 2>/dev/null && continue
    [ -f "$idx" ] && grep -qF "gen_index:auto" "$idx" || continue
    # Child mtimes catch content edits; the directory mtime catches add/remove/rename.
    # gen_index atomically replaces INDEX.md and therefore bumps the directory mtime too,
    # so touch INDEX.md after a successful refresh to make it the cache stamp again.
    if [ ! "$d" -nt "$idx" ] \
      && [ -z "$(find "$d" -mindepth 1 -maxdepth 1 ! -name INDEX.md -newer "$idx" -print -quit 2>/dev/null)" ]; then
      continue
    fi
    if bash "$GEN" "$d" --title "${d#"$ROOT"/}" --all-files --include-hidden \
      --merge-into "$idx" 2>/dev/null; then
      touch "$idx" 2>/dev/null || true
    fi
  done

  # A virtual folder owns the loose files that must stay in the repo root by convention.
  # Its INDEX is generated FROM the root, while the root INDEX itself stays a folder-only map.
  extras="$ROOT/ostatni-v-repu/INDEX.md"
  if [ -f "$extras" ] && grep -qF "gen_index:root-files" "$extras"; then
    bash "$GEN" "$ROOT" --title "ostatni-v-repu" --all-files --include-hidden --files-only \
      --merge-into "$extras" 2>/dev/null || true
  fi
}

emit_tree_map() {
  echo
  echo "=== 🌳 REPO TREE — compact complete path inventory ==="
  echo "(Open a folder's INDEX.md for descriptions; this startup view carries names only.)"
  echo
  echo './'
  tree_dirs | while IFS= read -r d; do
    rel="${d#"$ROOT"/}"
    printf '%s/: ' "$rel"
    if [ "$rel" = "ostatni-v-repu" ] && grep -qF "gen_index:root-files" "$d/INDEX.md" 2>/dev/null; then
      bash "$GEN" "$ROOT" --all-files --include-hidden --files-only --compact 2>/dev/null || true
    else
      bash "$GEN" "$d" --all-files --include-hidden --files-only --compact 2>/dev/null || true
    fi
  done
  echo
  echo "=== (secret files, VCS internals, caches, build/vendor and FMC runtime debris are intentionally excluded) ==="
}

if [ "$SCOPE" = "repo" ]; then
  echo
  echo "=== 🗂️ REPO — folder map (info-injection: you know what lives where) ==="
  # A second explicit marker upgrades the ordinary top-level map into a complete recursive tree.
  # Existing adopters with only gen_index:auto keep their prior behavior and do not receive a
  # surprise forest of generated files after an FMC upgrade.
  if [ -f "$ROOT/INDEX.md" ] && grep -qF "gen_index:tree" "$ROOT/INDEX.md"; then
    refresh_tree_indexes
    root_title="$(basename "$ROOT")"
    bash "$GEN" "$ROOT" --title "$root_title" --all-files --include-hidden --folders-only \
      --merge-into "$ROOT/INDEX.md" 2>/dev/null || true
    emit_tree_map
    exit 0
  fi

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
    # Child mtimes catch content edits; the directory mtime catches add/remove/rename.
    # gen_index atomically replaces INDEX.md and therefore bumps the directory mtime too,
    # so touch INDEX.md after a successful refresh to make it the cache stamp again.
    if [ ! "$sub" -nt "$sub/INDEX.md" ] \
      && [ -z "$(find "$sub" -mindepth 1 -maxdepth 1 ! -name INDEX.md -newer "$sub/INDEX.md" -print -quit 2>/dev/null)" ]; then
      continue
    fi
    if bash "$GEN" "$sub" --title "$b" --merge-into "$sub/INDEX.md" 2>/dev/null; then
      touch "$sub/INDEX.md" 2>/dev/null || true
    fi
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
