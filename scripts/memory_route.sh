#!/usr/bin/env bash
# memory_route.sh — route a durable note to the right memory/ memory file.
#
# Backbone script (SCRIPTED) with an ENFORCED approval gate (R1/CRITICAL).
# Default behaviour is PROPOSE ONLY: it classifies the target and prints the
# block it WOULD write, and writes nothing. A durable write happens only with
# --commit AND both --approved-by and --reason; otherwise the commit is refused
# with a non-zero exit. Approval metadata is recorded in the written block so
# the audit trail lives in git.
#
# Usage:
#   memory_route.sh --text <text> --kind fact|lesson|calibration|decision|procedure \
#                   [--memory-dir <dir>]
#   memory_route.sh --text <text> --kind decision \
#                   --commit --approved-by <who> --reason <why> [--memory-dir <dir>]
#
# Routing:  fact->CAN.md  lesson|calibration|decision|procedure->KNOWLEDGE.md
# (0.1.24, audit F1: the old pouceni/rozhodnuti/postupy genre files were merged into
#  KNOWLEDGE.md — one durable-knowledge store with blocks distinguished by a kind: field.
#  The genre files were provably write-only.)
#
# kind=calibration is a SCOPED behaviour correction and MUST carry a "boundary:" field
# (where the correction does NOT apply) — a hard gate rejects a calibration without
# it, so memory never fills with vague "be more careful" notes. (Origin: cc_hermy adopter.)
#
# Exit codes:  0 proposed or committed | 1 error/usage | 2 commit refused by gate
#              3 duplicate id (nothing written)

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hermes_blocks.sh
. "$script_dir/lib/hermes_blocks.sh"

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

text="" kind="" memory_dir="./memory" commit=0 approved_by="" reason="" importance="" origin="" slug=""

while [ $# -gt 0 ]; do
  case "$1" in
    --text)        text="${2:-}"; shift 2 ;;
    --kind)        kind="${2:-}"; shift 2 ;;
    --memory-dir|--hermes-dir)  memory_dir="${2:-}"; shift 2 ;;  # --hermes-dir = legacy alias (pre-rename adopters)
    --commit)      commit=1; shift ;;
    --approved-by) approved_by="${2:-}"; shift 2 ;;
    --reason)      reason="${2:-}"; shift 2 ;;
    --importance)  importance="${2:-}"; shift 2 ;;
    --origin)      origin="${2:-}"; shift 2 ;;
    --slug)        slug="${2:-}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "memory_route: unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

[ -n "$text" ] || { echo "memory_route: --text is required" >&2; exit 1; }
case "$kind" in
  fact)        target="CAN.md" ;;
  lesson)      target="KNOWLEDGE.md" ;;
  calibration) target="KNOWLEDGE.md" ;;
  decision)    target="KNOWLEDGE.md" ;;
  procedure)   target="KNOWLEDGE.md" ;;
  *) echo "memory_route: --kind must be fact|lesson|calibration|decision|procedure" >&2; exit 1 ;;
esac

# calibration hard gate: a scoped correction must state its boundary. Match "boundary:"
# only as a real field (line start or after whitespace) so a substring like
# "neco-boundary:" does not slip through. (Tightened over the adopter's plain grep.)
if [ "$kind" = "calibration" ] && ! printf '%s' "$text" | grep -qiE '(^|[[:space:]])boundary:'; then
  echo "memory_route: calibration without a 'boundary:' field refused — state where the correction does NOT apply" >&2
  exit 1
fi

# DNA fields (optional, first-class): importance 1..5 = primary ranking signal for the registry/hot;
# origin from a small vocabulary = defense against self-reinforcing error. Kept in the BODY
# frontmatter (never the marker) so the positional block parsers and idempotence stay untouched.
if [ -n "$importance" ] && ! printf '%s' "$importance" | grep -qE '^[1-5]$'; then
  echo "memory_route: --importance must be 1..5" >&2; exit 1
fi
if [ -n "$origin" ] && ! printf '%s' "$origin" | grep -qE '^(user|ai-derived|doc|approved|untrusted)$'; then
  echo "memory_route: --origin must be user|ai-derived|doc|approved|untrusted" >&2; exit 1
fi
if [ -n "$slug" ] && ! printf '%s' "$slug" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
  echo "memory_route: --slug must be kebab-case ([a-z0-9-], not starting with -)" >&2; exit 1
fi
dna=""
[ -n "$slug" ]       && dna="${dna}slug: ${slug}"$'\n'
[ -n "$importance" ] && dna="${dna}importance: ${importance}"$'\n'
[ -n "$origin" ]     && dna="${dna}origin: ${origin}"$'\n'

file="$memory_dir/$target"
ts="$(hermes_now_utc)"
id="$(hermes_block_id "memory:$kind" "$text")"

# ---- PROPOSE (default): classify + show, write nothing ----------------------
if [ "$commit" -eq 0 ]; then
  echo "memory_route: PROPOSAL (not written). Target: $file" >&2
  echo "memory_route: to persist, re-run with --commit --approved-by <who> --reason <why>" >&2
  printf '<!-- hermes:entry kind=%s id=%s ts=%s -->\nkind: %s\n%s%s\n<!-- /hermes:entry -->\n' \
    "$kind" "$id" "$ts" "$kind" "$dna" "$text"
  exit 0
fi

# ---- COMMIT: enforced approval gate -----------------------------------------
trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
ab="$(trim "$approved_by")"
rs="$(trim "$reason")"

# Reject empty-after-trim (blocks `--approved-by " "` slipping through the gate).
if [ -z "$ab" ] || [ -z "$rs" ]; then
  echo "memory_route: COMMIT REFUSED — --commit requires non-empty --approved-by AND --reason" >&2
  echo "memory_route: nothing written ($file)" >&2
  exit 2
fi
# Force single-line approval metadata (no newline injection into the audit fields).
case "$ab$rs" in
  *$'\n'*) echo "memory_route: COMMIT REFUSED — approval fields must be single-line" >&2; exit 2 ;;
esac

body="$(printf 'kind: %s\n%sapproved_by: %s\napproved_at: %s\nreason: %s\n\n%s' \
  "$kind" "$dna" "$ab" "$ts" "$rs" "$text")"

set +e
printf '%s' "$body" | hermes_append_block "$file" "$kind" "$id" "$ts"
rc=$?
set -e
case "$rc" in
  0) echo "memory_route: committed id=$id by=$approved_by -> $file" >&2; exit 0 ;;
  2) echo "memory_route: duplicate id=$id already present, skipped -> $file" >&2; exit 3 ;;
  *) echo "memory_route: write failed -> $file" >&2; exit 1 ;;
esac
