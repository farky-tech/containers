#!/usr/bin/env bash
# recall.sh — pull a knowledge atom (full canonical block) from the cold store.
#
# The retrieval half of the brain. Replaces "open the whole 45KB KNOWLEDGE.md and read it all":
# an instance drills the one atom it needs, by human slug, by id, or by query — as the registry points.
# A capability, not a gate — it does not write, lock, or guard anything.
#
# Usage:
#   recall.sh --memory-dir <dir> <slug|id> [<slug|id> ...]   # a 12-char hex id is exact; anything else = slug
#   recall.sh --memory-dir <dir> --query "two words"         # blocks whose CONTENT matches ALL words
# Exit: 0 = something printed | 1 = usage/store error | 2 = nothing matched
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/hermes_blocks.sh"

memory_dir="./memory" query=""
keys=()
while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir) memory_dir="${2:-./memory}"; shift 2 ;;
    --query)                   query="${2:-}"; shift 2 ;;
    -h|--help)                 grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                         keys+=("$1"); shift ;;
  esac
done

# Atom stores, new vocab first then legacy fallback (an un-migrated fork still recalls).
stores=()
for f in KNOWLEDGE.md CAN.md ZNALOST.md umim.md; do
  [ -f "$memory_dir/$f" ] && stores+=("$memory_dir/$f")
done
[ "${#stores[@]}" -gt 0 ] || { echo "recall: no atom store under $memory_dir" >&2; exit 1; }

# Resolve a human slug to its block(s): scan, compute each block's slug (explicit `slug:` else derived
# from title), print matches. Same derivation as gen_rejstrik so registry ↔ recall stay consistent.
resolve_slug() {
  local target="$1" s
  for s in "${stores[@]}"; do
    awk '
      /hermes:entry/ && $0 !~ /\/hermes:entry/ { inblk=1; in_fm=1; id="?"; slug=""; title="";
        for(i=1;i<=NF;i++) if($i ~ /^id=/) id=substr($i,4); next }
      inblk && /\/hermes:entry/ { printf "%s\t%s\t%s\n", id, (slug==""?"-":slug), title; inblk=0; next }
      inblk {
        if (in_fm && $0 !~ /^[a-z_]+:[[:space:]]/ && $0 ~ /[^[:space:]]/) in_fm=0
        if (in_fm && $0 ~ /^slug:[[:space:]]*[a-z0-9-]/){ x=$0; sub(/^slug:[[:space:]]*/,"",x); slug=x }
        if (title=="" && $0 ~ /^## /){ title=$0; sub(/^## /,"",title) }
        if (title=="" && $0 !~ /^[a-z_]+:/ && $0 ~ /[^[:space:]]/) title=$0
      }
    ' "$s" | while IFS="$(printf '\t')" read -r id eslug title; do
      sl="$eslug"; { [ "$sl" = "-" ] || [ -z "$sl" ]; } && sl="$(hermes_slug "$title")"
      [ "$sl" = "$target" ] && { hermes_get_block "$s" "$id"; echo; }
    done
  done
}

printed=0

if [ -n "$query" ]; then
  for s in "${stores[@]}"; do
    out="$(awk -v q="$query" '
      BEGIN { n = split(tolower(q), w, " ") }
      /hermes:entry/ && $0 !~ /\/hermes:entry/ { buf = $0 "\n"; mt = ""; cap = 1; next }
      cap && /\/hermes:entry/ {
        buf = buf $0 "\n"; lc = tolower(mt); ok = 1          # match CONTENT only, not marker/frontmatter
        for (i = 1; i <= n; i++) if (index(lc, w[i]) == 0) { ok = 0; break }
        if (ok) printf "%s\n", buf
        cap = 0; buf = ""; mt = ""; next
      }
      cap {
        buf = buf $0 "\n"
        if ($0 !~ /^[a-z_]+:[[:space:]]/) mt = mt $0 "\n"    # skip frontmatter fields (kind:/importance:/...)
      }
    ' "$s")"
    if [ -n "$out" ]; then printf '%s\n' "$out"; printed=1; fi
  done
elif [ "${#keys[@]}" -gt 0 ]; then
  for k in "${keys[@]}"; do
    hit=0
    if printf '%s' "$k" | grep -qE '^[a-f0-9]{12}$'; then      # exact 12-hex id
      for s in "${stores[@]}"; do hermes_get_block "$s" "$k" && { hit=1; echo; break; }; done
    fi
    if [ "$hit" -eq 0 ]; then                                  # otherwise treat as a human slug
      out="$(resolve_slug "$k")"
      [ -n "$out" ] && { printf '%s' "$out"; hit=1; }
    fi
    [ "$hit" -eq 1 ] && printed=1
  done
else
  echo "recall: give a slug/id or --query \"words\"" >&2; exit 1
fi

[ "$printed" -eq 1 ] || { echo "recall: nothing matched" >&2; exit 2; }
exit 0
