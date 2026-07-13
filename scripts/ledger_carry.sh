#!/usr/bin/env bash
# ledger_carry.sh — carry open to-do items forward into memory/todo.md.
#
# Backbone script (SCRIPTED): session-close / lapac call this to persist
# carry-forward items instead of trusting the agent to "remember to write them".
# Idempotent: the same item text is never carried twice.
#
# Usage:
#   ledger_carry.sh [--item <text>]... [--step <next step>] [--memory-dir <dir>] [--dry-run]
#   echo -e "item one\nitem two" | ledger_carry.sh --memory-dir ./memory
#
# Items come from repeated --item flags OR stdin (one item per line): stdin is read
# only when no --item is given. Non-interactive safe — with --item stdin is not
# touched, and without it an idle stdin is bounded by a read timeout (no hang).
#
# --step <next step>: OPTIONAL concrete next action, appended to every item in
# this call ("… — → next step: <step>"). When given it is enforced non-empty —
# a parked item without a concrete next step is a dead item ("do it someday" =
# never). Distilled loop_write mechanic (origin cc_hermy) without a second store.
# Batch/stdin carry stays unchanged for backward compat (adopters unaffected).
#
# Exit codes:  0 wrote >=1 / all duplicates / --done resolved a match
#              1 error/usage
#              2 nothing to carry, OR --done matched zero / more-than-one open item,
#                OR no todo.md (fail-honest — ambiguous match changes nothing)

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hermes_blocks.sh
. "$script_dir/lib/hermes_blocks.sh"

usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

memory_dir="./memory" dry_run=0 done_text="" krok=""
items=()

while [ $# -gt 0 ]; do
  case "$1" in
    --item)       items+=("${2:-}"); shift 2 ;;
    --step)       krok="${2:-}"; shift 2 ;;
    --done)       done_text="${2:-}"; shift 2 ;;
    --memory-dir|--hermes-dir) memory_dir="${2:-}"; shift 2 ;;  # --hermes-dir = legacy alias (pre-rename adopters)
    --dry-run)    dry_run=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "ledger_carry: unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

# --step, when given, is enforced non-empty and single-line, then appended to
# every carried item as a concrete next step. Absent --step = unchanged behaviour.
if [ -n "$krok" ]; then
  krok="$(printf '%s' "$krok" | tr '\n' ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$krok" ] || { echo "ledger_carry: --step must be non-empty (a concrete next step)" >&2; exit 1; }
fi

# --done: mark a carried item resolved ("- [ ]" -> "- [x]") so it stops being
# pulled forward into new sessions. Idempotent; atomic; under the file lock.
# Fail-honest: if no OPEN item matches the text, this is a silent no-op that lies
# to the caller ("marked done") while nothing changed — the gate then trusts a
# debt was cleared when it wasn't. Refuse loudly (exit 2) instead. (no-silent-fallback.)
#
# Match must be EXACT and ANCHORED to a whole top-level item, not a substring/prefix:
# a bare "- [ ] " line's text must equal $done_text verbatim, or equal $done_text
# followed by the " — → next step:" suffix marker (items carried with --step).
# A prefix match (e.g. --done "fix" hitting both "fix login" and "fix logout") is
# exactly the bug this guards against — it silently flips every item sharing that
# prefix. Fenced ``` code blocks are skipped: todo.md's own format template shows
# "- [ ] Item:" as illustrative text, not a real open item.
if [ -n "$done_text" ]; then
  file="$memory_dir/todo.md"
  [ -f "$file" ] || { echo "ledger_carry: no todo.md to resolve" >&2; exit 2; }

  lockdir="${file}.lock"
  hermes_lock "$lockdir" || exit 1

  tmp_out="$(mktemp)"
  tmp_status="$(mktemp)"
  awk -v t="$done_text" '
    # Indent- and fence-semantics MUST mirror hermes_count_open_todo (lib): the close
    # gate counts indented "- [ ]" rows too, so --done must be able to resolve them —
    # otherwise a nested todo can block close while the prescribed fix command cannot
    # touch it (0.1.33; found in the pre-publication audit).
    BEGIN { in_fence = 0; n = 0 }
    {
      lines[NR] = $0
      if ($0 ~ /^[[:space:]]*```/) { in_fence = !in_fence; next }
      if (in_fence) next
      if (match($0, /^[[:space:]]*- \[ \] /)) {
        remainder = substr($0, RLENGTH + 1)
        # Marker back-compat (0.1.34): --step now writes the EN marker, but adopters
        # have years of items carrying the old CZ one — match BOTH forever.
        marker_en = t " — → next step:"
        marker_cz = t " — → další krok:"
        if (remainder == t \
            || substr(remainder, 1, length(marker_en)) == marker_en \
            || substr(remainder, 1, length(marker_cz)) == marker_cz) {
          n++
          matchline = NR
        }
      }
    }
    END {
      if (n == 1) {
        line = lines[matchline]
        match(line, /^[[:space:]]*/)
        ind = substr(line, 1, RLENGTH)
        rest = substr(line, RLENGTH + 1)
        lines[matchline] = ind "- [x] " substr(rest, 7)
        for (i = 1; i <= NR; i++) print lines[i]
        print "OK" > "/dev/stderr"
      } else {
        print n > "/dev/stderr"
      }
    }
  ' "$file" >"$tmp_out" 2>"$tmp_status"

  status_line="$(cat "$tmp_status")"
  rm -f "$tmp_status"

  if [ "$status_line" = "OK" ]; then
    # Guard the write like fallback_log.sh --resolve does: under `set -e` a failed
    # hermes_atomic_write (disk full / perms) would abort the script HERE and skip
    # hermes_unlock — leaving todo.md.lock held forever (0.1.33 audit fix).
    set +e
    hermes_atomic_write "$file" < "$tmp_out"
    write_rc=$?
    set -e
    rm -f "$tmp_out"
    hermes_unlock "$lockdir"
    if [ "$write_rc" -ne 0 ]; then
      echo "ledger_carry: write to $file FAILED (rc=$write_rc) — todo.md unchanged, lock released" >&2
      exit 1
    fi
    echo "ledger_carry: marked done -> $done_text" >&2
    exit 0
  fi

  rm -f "$tmp_out"
  hermes_unlock "$lockdir"
  n="${status_line:-0}"
  if [ "$n" = "0" ]; then
    echo "ledger_carry: --done found no OPEN item matching: $done_text (nothing changed — already done? typo?)" >&2
  else
    echo "ledger_carry: --done ambiguous: $n items match '$done_text' (nothing changed — give more of the text)" >&2
  fi
  exit 2
fi

# Read items from stdin only when NO --item was given — stdin is the ALTERNATIVE
# input path, not additive. A non-interactive caller (harness/CI, e.g. session_close
# --carry) can leave an open-but-empty stdin, and an untimed `read` blocks on it
# forever — that hung this script for ~2 min (bug: cc_hlas 2026-07-12). bash 3.2 has
# no working `read -t 0` probe, so we (a) skip stdin entirely when --item is present
# and (b) bound each read with an integer timeout, turning a possible infinite hang
# into a ~2s worst case. `echo … | ledger_carry.sh` (no --item) and `< /dev/null`
# both still work.
if [ "${#items[@]}" -eq 0 ] && [ ! -t 0 ]; then
  while IFS= read -t 2 -r line; do
    [ -n "$line" ] || continue
    items+=("$line")
  done
fi

if [ "${#items[@]}" -eq 0 ]; then
  echo "ledger_carry: no items to carry (use --item or stdin)" >&2
  exit 2
fi

file="$memory_dir/todo.md"
ts="$(hermes_now_utc)"
wrote=0 skipped=0

for item in "${items[@]}"; do
  [ -n "$item" ] || continue
  [ -n "$krok" ] && item="$item — → next step: $krok"
  id="$(hermes_block_id "todo" "$item")"
  body="$(printf -- '- [ ] %s' "$item")"
  if [ "$dry_run" -eq 1 ]; then
    printf '<!-- hermes:entry kind=todo id=%s ts=%s -->\n%s\n<!-- /hermes:entry -->\n' "$id" "$ts" "$body"
    continue
  fi
  set +e
  printf '%s' "$body" | hermes_append_block "$file" "todo" "$id" "$ts"
  rc=$?
  set -e
  case "$rc" in
    0) wrote=$((wrote+1)) ;;
    2) skipped=$((skipped+1)) ;;
    *) echo "ledger_carry: write failed for item: $item" >&2; exit 1 ;;
  esac
done

if [ "$dry_run" -eq 1 ]; then
  echo "ledger_carry: dry-run, nothing written ($file)" >&2
  exit 0
fi

echo "ledger_carry: carried $wrote, skipped $skipped duplicates -> $file" >&2
exit 0
