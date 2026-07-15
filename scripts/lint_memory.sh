#!/usr/bin/env bash
# lint_memory.sh — hygiene check over the knowledge atoms. Keeps the brain honest.
#
# ADVISORY, not a gate (severka: mozek ne úředník). It MEASURES and REPORTS; it never blocks a
# write or a commit. Findings feed brain_health / the janitor, which propose — the head decides.
# Checks: duplicate ids · invalid importance/origin value · atom with no title · slug collision
#         (same slug on >1 atom -> ambiguous link) · dead [[id]] (a 12-hex-id wikilink to no atom).
#         NOTE: `kind` lives in the marker, so a missing body `kind:` is NOT flagged; and human
#         [[slug]] links are NOT dead-checked (an atom legitimately links out to knihovna/global
#         slugs that aren't atoms here — flagging those would be noise). Severka: no nagging.
#
# Usage: lint_memory.sh --memory-dir <dir> [--quiet]
# Exit:  0 always (advisory). Count of issues is printed; --quiet prints only the count line.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/hermes_blocks.sh"

memory_dir="./memory" quiet=0
while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir) memory_dir="${2:-./memory}"; shift 2 ;;
    --quiet) quiet=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "lint_memory: unknown arg: $1" >&2; exit 1 ;;
  esac
done

stores=()
for f in KNOWLEDGE.md CAN.md ZNALOST.md umim.md; do
  [ -f "$memory_dir/$f" ] && stores+=("$memory_dir/$f")
done
[ "${#stores[@]}" -gt 0 ] || { echo "lint_memory: 0 issues (no atom store)"; exit 0; }

# Per-block hygiene (title / importance-origin / duplicate id). frontmatter-scoped so a content
# line starting "importance:"/"origin:" cannot trip a false finding.
issues="$(awk '
  function flush() {
    if (id != "") {
      if (!has_title) print "  · blok id=" id " (" file "): bez titulku (## ani text)"
      if (bad_imp)    print "  · blok id=" id " (" file "): importance mimo 1..5"
      if (bad_org)    print "  · blok id=" id " (" file "): origin mimo user|ai-derived|doc|approved|untrusted"
      if (id in seen) print "  · DUPLICITNÍ id=" id " (" file ")"
      seen[id] = 1
    }
  }
  FNR==1 { file = FILENAME }
  /hermes:entry/ && $0 !~ /\/hermes:entry/ {
    flush()
    inblk=1; in_fm=1; id=""; has_title=0; bad_imp=0; bad_org=0
    for (i=1;i<=NF;i++) if ($i ~ /^id=/) id=substr($i,4)
    next
  }
  inblk && /\/hermes:entry/ { flush(); inblk=0; id=""; next }
  inblk {
    if (in_fm && $0 !~ /^[a-z_]+:[[:space:]]/ && $0 ~ /[^[:space:]]/) in_fm=0
    if ($0 ~ /^## / || ($0 ~ /[^[:space:]]/ && $0 !~ /^[a-z_]+:/)) has_title=1
    if (in_fm && $0 ~ /^importance:/ && $0 !~ /^importance:[[:space:]]*[1-5][[:space:]]*$/) bad_imp=1
    if (in_fm && $0 ~ /^origin:/ && $0 !~ /^origin:[[:space:]]*(user|ai-derived|doc|approved|untrusted)[[:space:]]*$/) bad_org=1
  }
  END { flush() }
' "${stores[@]}")"

# id<TAB>slug per block (slug = explicit `slug:` else derived from title — same rule as gen_rejstrik/recall).
idslug="$(
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
    ' "$s"
  done | while IFS="$(printf '\t')" read -r id eslug title; do
    sl="$eslug"; { [ "$sl" = "-" ] || [ -z "$sl" ]; } && sl="$(hermes_slug "$title")"
    printf '%s\t%s\n' "$id" "$sl"
  done
)"
targets="$(printf '%s\n' "$idslug" | awk -F'\t' '{print $1; if($2!="")print $2}' | sort -u)"
collisions="$(printf '%s\n' "$idslug" | awk -F'\t' '$2!=""{print $2}' | sort | uniq -d | while read -r sl; do
  [ -n "$sl" ] && echo "  · KOLIZE slugu [[$sl]]: nese ho víc atomů (link nejednoznačný)"
done)"
# dead [[id]]: only 12-hex-id links are UNAMBIGUOUS atom refs. Human [[slug]] links are NOT checked
# — an atom legitimately links out to knihovna pages / global memory slugs that aren't atoms here,
# and lint can't tell those from a typo, so flagging them would be pure noise (severka: no nagging).
deadlinks="$(grep -oE '\[\[[a-f0-9]{12}\]\]' "${stores[@]}" 2>/dev/null | grep -oE '[a-f0-9]{12}' | sort -u | while read -r l; do
  [ -n "$l" ] || continue
  printf '%s\n' "$targets" | grep -qx "$l" || echo "  · mrtvý [[$l]]: žádný atom s tím id"
done)"

all="$(printf '%s\n%s\n%s' "$issues" "$collisions" "$deadlinks" | grep -c '·' || true)"
echo "lint_memory: ${all:-0} issues"
if [ "${all:-0}" -gt 0 ] && [ "$quiet" -eq 0 ]; then
  [ -n "$issues" ]     && printf '%s\n' "$issues"
  [ -n "$collisions" ] && printf '%s\n' "$collisions"
  [ -n "$deadlinks" ]  && printf '%s\n' "$deadlinks"
fi
exit 0
