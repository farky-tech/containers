#!/usr/bin/env bash
# state_guard.sh — guard state artifacts against drifting from reality (Farky's "state guard").
#
# The reflex "after a change, sync the state with reality" must NOT live in the agent's memory —
# it slips (proven: INDEX, STATE, todo, CHANGELOG, PRODUCTBOOK all drifted). This is
# the mechanical substrate: it CHECKS for drift and prints a targeted nudge; it never writes the fix
# itself (that needs judgment). Advisory only — never blocks a hook. Zero-dep (grep/sed).
#
# Modes (2026-07-06 / -07):
#   --release-drift --plugin-dir <dir>               plugin.json version vs the latest ## block in CHANGELOG.md.  (MAINTAINER)
#   --book-drift --plugin-dir <dir> --book <file>    "Plugin version: **X**" in a living book vs plugin.json. (MAINTAINER)
#   --adopter-drift --plugin-dir <dir> --cache-dir <d>  the adopter's ACTIVE version (plugin.json in <dir>) vs
#                                                    the newest version in the marketplace cache (<d>/<version>/).  (ADOPTER, cache install)
#   --fork-drift --marker <file>                     the version the fork was cut from (source_version in the .fmc-source
#                                                    marker stamped by the installer) vs the current plugin.json in the
#                                                    source repo (source_dir from the marker).  (ADOPTER, in-repo fork)
# release/book-drift = maintainer side. adopter-drift = cache-install consumer. fork-drift = in-repo tuned fork
# (a hash-diff would always cry drift on a tuned fork → version marker: "the source RELEASED something newer
# than what I forked from"). Advisory, never blocks.
# Full index/STATE/vision discovery follows the repo-order work (layer 1) — see the state-guard design note.
# Prints a warning line on drift, nothing when in sync. Exit 0 (advisory), 1 on usage error.
set -uo pipefail

mode="" plugin_dir="" book="" cache_dir="" marker=""
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --release-drift) mode="release-drift"; shift ;;
    --book-drift)    mode="book-drift"; shift ;;
    --adopter-drift) mode="adopter-drift"; shift ;;
    --fork-drift)    mode="fork-drift"; shift ;;
    --plugin-dir)    plugin_dir="${2:-}"; shift 2 ;;
    --book)          book="${2:-}"; shift 2 ;;
    --cache-dir)     cache_dir="${2:-}"; shift 2 ;;
    --marker)        marker="${2:-}"; shift 2 ;;
    -h|--help)       sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

# read a "version" string from a plugin.json (zero-dep)
_pv() { sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${1:-}" 2>/dev/null | head -n1; }

# plugin.json version vs newest ## block in CHANGELOG.md. A bump that forgot the CHANGELOG (exactly
# what happened: engine went ahead while CHANGELOG lagged) surfaces here. (Codex-side manifest is
# Farky's domain — he maintains it himself; the guard deliberately does not compare it.)
release_drift() { # $1 = plugin dir
  local dir="$1"
  local pj="$dir/.claude-plugin/plugin.json" cl="$dir/CHANGELOG.md"
  [ -f "$pj" ] && [ -f "$cl" ] || return 0   # not a plugin-with-changelog → silently skip
  local pv cv
  pv="$(_pv "$pj")"
  [ -n "$pv" ] || return 0                    # no version parsed → nothing to compare
  cv="$(grep -m1 '^## ' "$cl" 2>/dev/null | sed -n 's/^##[[:space:]]*\([0-9][0-9.]*\).*/\1/p')"
  if [ -n "$cv" ] && [ "$pv" != "$cv" ]; then
    printf '⚠️  RELEASE-DRIFT (%s): plugin.json version %s ≠ latest CHANGELOG block %s — write the CHANGELOG + ADOPTION entries (RELEASE CHECKLIST, mistr_pluginu §6g).\n' "$(basename "$dir")" "$pv" "$cv"
  fi
}

# Compare a "living book" declared version ("Plugin version: **X**") against plugin.json. Books drift
# silently because nobody reads them on boot / updates them on close (PRODUCTBOOK lagged 6 versions).
book_drift() { # $1 = plugin dir, $2 = book file
  local dir="$1" bk="$2"
  local pj="$dir/.claude-plugin/plugin.json"
  [ -f "$pj" ] && [ -f "$bk" ] || return 0
  local pv bv
  pv="$(_pv "$pj")"
  bv="$(grep -m1 -iE 'Plugin version:' "$bk" 2>/dev/null | sed -n 's/.*Plugin version:[^0-9]*\([0-9][0-9.]*\).*/\1/p')"
  [ -n "$pv" ] || return 0
  if [ -n "$bv" ] && [ "$pv" != "$bv" ]; then
    printf '⚠️  BOOK-DRIFT (%s): plugin.json version %s ≠ version %s declared in %s — update the living book (vision+backlog+Done) at close.\n' "$(basename "$dir")" "$pv" "$bv" "$(basename "$bk")"
  fi
}

# --- version compare (portable, zero-dep; dotted numeric like 0.1.17) -------
# _vlt A B → exit 0 (true) if A < B, else 1. Field-numeric sort (BSD+GNU safe).
_vlt() {
  [ "$1" = "$2" ] && return 1
  local lo
  lo="$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | head -n1)"
  [ "$lo" = "$1" ]
}
# Largest dotted-version among the immediate subdir names of a marketplace-cache
# plugin dir (…/<marketplace>/<plugin>/<version>/). Empty if the dir has none.
_cache_max() {
  local dir="$1"
  [ -d "$dir" ] || { printf ''; return 0; }
  ls -1 "$dir" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)+$' \
    | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -n1
}

# Adopter side: my ACTIVE installed version (plugin.json in --plugin-dir) vs the
# newest version sitting in the marketplace cache (--cache-dir). A `/plugin
# marketplace update` drops a newer version dir into the cache but does NOT flip
# the active install — so the adopter runs behind until `/plugin update`, silently.
# This surfaces that gap the way --release-drift surfaces the maintainer's.
adopter_drift() { # $1 = active install dir, $2 = cache dir (<marketplace>/<plugin>)
  local dir="$1" cache="$2"
  local pj="$dir/.claude-plugin/plugin.json"
  [ -f "$pj" ] || return 0                      # no manifest → not a versioned install, silent skip
  local av mv
  av="$(_pv "$pj")"
  [ -n "$av" ] || return 0                       # no version parsed → nothing to compare
  mv="$(_cache_max "$cache")"
  [ -n "$mv" ] || return 0                        # cache absent / no version dirs → silent skip
  if _vlt "$av" "$mv"; then
    printf '⚠️  ADOPTER-DRIFT (%s): you run %s, the marketplace cache has %s — consider syncing (/plugin update, then the ADOPTION sync loop). Advisory, never blocks.\n' "$(basename "$dir")" "$av" "$mv"
  fi
}

# In-repo fork side: the ONLY topology every real adopter uses (tuned copy via
# install_project_template.sh --with-scripts; no plugin.json, no marketplace cache).
# The installer stamps <memory>/.fmc-source with the source version + source dir at
# install time; here we compare that stamped version against the source repo's CURRENT
# plugin.json. A tuned fork can't be hash-diffed (its tuning always "differs"), so the
# honest signal is "did the source RELEASE a newer version than I forked from".
fork_drift() { # $1 = marker file (<memory-dir>/.fmc-source)
  local marker="$1"
  [ -f "$marker" ] || return 0                    # pre-stamp fork / no marker → silent skip
  local fv sd sv
  fv="$(sed -n 's/^source_version=//p' "$marker" 2>/dev/null | head -n1)"
  sd="$(sed -n 's/^source_dir=//p'     "$marker" 2>/dev/null | head -n1)"
  [ -n "$fv" ] && [ -n "$sd" ] || return 0        # marker missing keys → silent skip
  local pj="$sd/.claude-plugin/plugin.json"
  [ -f "$pj" ] || return 0                          # source repo moved/unreadable → silent skip
  sv="$(_pv "$pj")"
  [ -n "$sv" ] || return 0
  if _vlt "$fv" "$sv"; then
    printf '⚠️  FORK-DRIFT: your fork was cut from version %s, but the source (%s) is at %s — refresh: install_project_template.sh --refresh-scripts. Advisory, never blocks.\n' "$fv" "$(basename "$sd")" "$sv"
  fi
}

case "$mode" in
  release-drift)
    [ -n "$plugin_dir" ] || { echo "state_guard: --release-drift needs --plugin-dir" >&2; exit 1; }
    release_drift "$plugin_dir"
    ;;
  book-drift)
    [ -n "$plugin_dir" ] && [ -n "$book" ] || { echo "state_guard: --book-drift needs --plugin-dir and --book" >&2; exit 1; }
    book_drift "$plugin_dir" "$book"
    ;;
  adopter-drift)
    [ -n "$plugin_dir" ] && [ -n "$cache_dir" ] || { echo "state_guard: --adopter-drift needs --plugin-dir and --cache-dir" >&2; exit 1; }
    adopter_drift "$plugin_dir" "$cache_dir"
    ;;
  fork-drift)
    [ -n "$marker" ] || { echo "state_guard: --fork-drift needs --marker" >&2; exit 1; }
    fork_drift "$marker"
    ;;
  *) echo "state_guard: need a mode (--release-drift | --book-drift | --adopter-drift | --fork-drift)" >&2; exit 1 ;;
esac
exit 0
