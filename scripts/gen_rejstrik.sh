#!/usr/bin/env bash
# gen_rejstrik.sh — regenerate the atom registry (_rejstrik.md) from the knowledge store.
#
# The "read index -> drill" navigation layer of the brain: one row per atom (importance, slug,
# kind, title) so an instance sees WHAT it knows at a glance AND the human slug to link/recall it
# by. ALWAYS recomputed from the blocks themselves -> it can never drift from reality (the exact
# disease the whole rebuild fixes). No hand-maintenance, no "remember to regenerate".
#
# Usage: gen_rejstrik.sh --memory-dir <dir> [--stdout]
# Exit:  0 always (empty store -> header-only registry, never breaks)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/hermes_blocks.sh"

memory_dir="./memory" to_stdout=0
while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir) memory_dir="${2:-./memory}"; shift 2 ;;
    --stdout)                  to_stdout=1; shift ;;
    -h|--help)                 grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "gen_rejstrik: unknown arg: $1" >&2; exit 1 ;;
  esac
done

stores=()
for f in KNOWLEDGE.md CAN.md ZNALOST.md umim.md; do
  [ -f "$memory_dir/$f" ] && stores+=("$memory_dir/$f")
done

# One TSV row per block: importance <TAB> kind <TAB> id <TAB> explicit-slug <TAB> title.
# importance/slug read ONLY from the frontmatter (a content line starting "importance:"/"slug:"
# must not override the DNA). title: first `## ` heading, else first content line, else placeholder.
rows=""
if [ "${#stores[@]}" -gt 0 ]; then
  rows="$(awk '
    /hermes:entry/ && $0 !~ /\/hermes:entry/ {
      inblk=1; in_fm=1; kind="?"; id="?"; title=""; slug=""
      for (i=1;i<=NF;i++){ if($i ~ /^kind=/){kind=substr($i,6)} if($i ~ /^id=/){id=substr($i,4)} }
      imp = (kind=="decision"||kind=="procedure"||kind=="calibration") ? 4 : (kind=="fact") ? 2 : 3
      next
    }
    inblk && /\/hermes:entry/ {
      if (title=="") title="(bez titulku)"
      printf "%s\t%s\t%s\t%s\t%s\n", imp, kind, id, (slug==""?"-":slug), title
      inblk=0; next
    }
    inblk {
      if (in_fm && $0 !~ /^[a-z_]+:[[:space:]]/ && $0 ~ /[^[:space:]]/) in_fm=0
      if (in_fm && $0 ~ /^importance:[[:space:]]*[1-5]/) { t=$0; sub(/^importance:[[:space:]]*/,"",t); imp=substr(t,1,1) }
      if (in_fm && $0 ~ /^slug:[[:space:]]*[a-z0-9-]/) { s=$0; sub(/^slug:[[:space:]]*/,"",s); slug=s }
      if (title=="" && $0 ~ /^## /) { title=$0; sub(/^## /,"",title) }
      if (title=="" && $0 !~ /^[a-z_]+:/ && $0 ~ /[^[:space:]]/) { title=$0 }
    }
  ' "${stores[@]}" | sort -t"$(printf '\t')" -k1,1nr -s)"
fi

n="$(printf '%s' "$rows" | grep -c . || true)"

emit() {
  printf '# _rejstrik — atom registry (auto, gen_rejstrik.sh; needituj ručně, přegeneruje se)\n\n'
  printf '> Co instance VÍ, na jeden pohled. Řádek = 1 atom (importance · slug · kind · titulek), řazeno dle importance.\n'
  printf '> Drill: `recall.sh --memory-dir %s <slug|id>` nebo `--query "slova"`. Odkaz na atom v těle: `[[slug]]`. Zdroj pravdy jsou bloky, ne tenhle soubor.\n\n' "$memory_dir"
  printf '%s atomů.\n\n' "${n:-0}"
  if [ -n "$rows" ]; then
    printf '| imp | slug | kind | atom |\n|---|---|---|---|\n'
    printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r imp kind id slug title; do
      [ -n "$id" ] || continue
      sl="$slug"; { [ "$sl" = "-" ] || [ -z "$sl" ]; } && sl="$(hermes_slug "$title")"   # explicit slug wins, else derive ("-" = none, TAB-collapse guard)
      t="$title"; [ "${#t}" -gt 80 ] && t="${t:0:80}…"           # terse navigation row (attention = scarce RAM)
      t="${t//|/\\|}"                                            # escape pipe so a title can't break the table
      printf '| %s | `%s` | %s | %s |\n' "$imp" "$sl" "$kind" "$t"
    done
  fi
}

if [ "$to_stdout" -eq 1 ]; then
  emit
else
  out="$memory_dir/_rejstrik.md"
  tmp="$(mktemp "${out}.XXXXXX")" || { echo "gen_rejstrik: mktemp failed" >&2; exit 1; }
  emit > "$tmp" && mv "$tmp" "$out" || { rm -f "$tmp"; echo "gen_rejstrik: write failed" >&2; exit 1; }
fi
exit 0
