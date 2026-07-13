#!/usr/bin/env bash
# brain_health.sh — weekly "brain health" observer (F4). MEASURES and REPORTS; never gates,
# never silently writes governance. Replaces the retired LOOP GATE with observation + a report
# Farky reads. The judgment work (dedup/promote/triage PROPOSALS) is the fmc-janitor subagent's;
# this script is the deterministic measurement substrate it (and the boot cadence) run on.
#
# Modes:
#   brain_health.sh --memory-dir <dir> [--plugin-dir <dir>] --report [--out <file>]
#       compute metrics -> write a markdown health report (default: <memory>/health/<UTCdate>.md).
#   brain_health.sh --memory-dir <dir> --due-check
#       SessionStart cadence surfacer: print an advisory iff the last report is >7 days old
#       (or none exists) — else silent. Read-only.
#   [--dry-run]  (report mode: print to stdout, do not write the file)
#
# Env: HERMES_FAKE_TS (deterministic now), HERMES_HEALTH_DUE_DAYS (default 7).
# Zero-dep (grep/sed/date/bash). Non-blocking by design — an observer must never crash a session.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hermes_blocks.sh
. "$script_dir/lib/hermes_blocks.sh"

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

memory_dir="./memory" plugin_dir="" mode="" out="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir) memory_dir="${2:-}"; shift 2 ;;
    --plugin-dir)  plugin_dir="${2:-}"; shift 2 ;;
    --report)      mode="report"; shift ;;
    --due-check)   mode="due-check"; shift ;;
    --out)         out="${2:-}"; shift 2 ;;
    --dry-run)     dry_run=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "brain_health: unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done
[ -n "$mode" ] || { echo "brain_health: need --report or --due-check" >&2; usage; exit 1; }

due_days="${HERMES_HEALTH_DUE_DAYS:-7}"
health_dir="$memory_dir/health"
now_iso="$(hermes_now_utc)"
now_date="${now_iso%%T*}"

# ISO-8601 -> epoch (GNU then BSD), empty on failure.
bh_epoch() { local iso="$1"; [ -n "$iso" ] || { printf ''; return 0; }
  date -u -d "$iso" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null || printf ''; }
bh_now_epoch() { if [ -n "${HERMES_FAKE_TS:-}" ]; then bh_epoch "$HERMES_FAKE_TS"; else date -u +%s; fi; }

# Newest report date (YYYY-MM-DD) from filenames in health/, empty if none.
bh_last_report_date() {
  [ -d "$health_dir" ] || { printf ''; return 0; }
  ls "$health_dir" 2>/dev/null | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)\.md$/\1/p' | sort | tail -n1
}

# --- due-check: advisory iff last report older than due_days -----------------
if [ "$mode" = "due-check" ]; then
  last="$(bh_last_report_date)"
  if [ -n "$last" ]; then
    le="$(bh_epoch "${last}T00:00:00Z")"; ne="$(bh_now_epoch)"
    if [ -n "$le" ] && [ -n "$ne" ]; then
      age_days=$(( (ne - le) / 86400 ))
      [ "$age_days" -lt "$due_days" ] && exit 0   # recent -> silent
    fi
  fi
  printf '=== FMC MAINTENANCE — weekly brain health is due ===\n'
  if [ -n "$last" ]; then printf 'Last report: %s (>%s days). ' "$last" "$due_days"; else printf 'No health report yet. '; fi
  printf 'Invoke the fmc-janitor agent (or /uklid if your host defines that alias) — it measures the state and PROPOSES consolidation (dedup/triage/lesson promotion).\n'
  printf '=== (observer, not a gate — blocks nothing; you approve the proposals) ===\n'
  exit 0
fi

# --- report: measure -> markdown --------------------------------------------
# Close hygiene
unclosed=0
[ -d "$memory_dir/.close-state" ] && unclosed="$(find "$memory_dir/.close-state" -maxdepth 1 -name 'UNCLOSED-*.env' 2>/dev/null | wc -l | tr -d ' ')"
stav="$memory_dir/STATE.md"; stav_age="?"
if [ -f "$stav" ]; then
  me="$(date -u -r "$stav" +%s 2>/dev/null || echo '')"; ne="$(bh_now_epoch)"
  [ -n "$me" ] && [ -n "$ne" ] && stav_age=$(( (ne - me) / 86400 ))
fi
# Ledger / fallback / knowledge
open_todo="$(hermes_count_open_todo "$memory_dir/todo.md" 2>/dev/null || echo 0)"
open_fb=0; [ -f "$memory_dir/fallbacks.md" ] && open_fb="$(grep -c '^Status: open' "$memory_dir/fallbacks.md" 2>/dev/null || echo 0)"
znalost_blocks=0; [ -f "$memory_dir/KNOWLEDGE.md" ] && znalost_blocks="$(hermes_count_blocks "$memory_dir/KNOWLEDGE.md" 2>/dev/null || echo 0)"
sess_entries=0; [ -f "$memory_dir/session.md" ] && sess_entries="$(hermes_count_blocks "$memory_dir/session.md" 2>/dev/null || echo 0)"
# Drift (optional — needs plugin-dir; MAINTAINER-side)
drift="n/a"
if [ -n "$plugin_dir" ] && [ -f "$plugin_dir/scripts/capability_audit.sh" ]; then
  drift="$(bash "$plugin_dir/scripts/capability_audit.sh" 2>/dev/null | sed -n 's/^Drift count: \([0-9]*\).*/\1/p' | head -n1 || echo '?')"
fi

flag() { # value threshold -> emoji; args: value amber red  (>=amber -> 🟠, >=red -> 🔴, else 🟢)
  local v="$1" a="$2" r="$3"; [ "$v" = "?" ] && { printf '⚪'; return; }
  if [ "$v" -ge "$r" ] 2>/dev/null; then printf '🔴'; elif [ "$v" -ge "$a" ] 2>/dev/null; then printf '🟠'; else printf '🟢'; fi
}
stav_flag='⚪'; [ "$stav_age" != "?" ] && stav_flag="$(flag "$stav_age" 3 7)"
drift_flag='⚪'; [ "$drift" != "n/a" ] && [ "$drift" != "?" ] && drift_flag="$(flag "$drift" 1 1)"

report="$(cat <<EOF
# Brain health — $now_date

> Automatic snapshot (brain_health.sh). Observer, not a gate — numbers + flags; proposals come
> from fmc-janitor and YOU approve them. 🟢 ok · 🟠 watch · 🔴 act · ⚪ not measured.

| Metric | Value | Status |
|---|---|---|
| Unclosed sessions (UNCLOSED markers) | $unclosed | $(flag "$unclosed" 1 3) |
| STATE.md age (days) | $stav_age | $stav_flag |
| Open todo items | $open_todo | $(flag "$open_todo" 25 45) |
| Open fallbacks | $open_fb | $(flag "$open_fb" 3 6) |
| KNOWLEDGE blocks | $znalost_blocks | $(flag "$znalost_blocks" 45 70) |
| Session journal (blocks) | $sess_entries | $(flag "$sess_entries" 60 120) |
| Engine drift (capability_audit) | $drift | $drift_flag |

## What to look at (fmc-janitor adds the proposals)
- 🔴/🟠 rows above = action candidates (catch up sessions · rewrite STATE · triage todo · resolve
  fallbacks · dedup + promote KNOWLEDGE lessons into CLAUDE.md/skills · rotate the journal).
- Lesson promotion and todo cuts = **PROPOSALS for the head**, never silent writes.
EOF
)"

if [ "$dry_run" -eq 1 ]; then printf '%s\n' "$report"; exit 0; fi
mkdir -p "$health_dir"
out="${out:-$health_dir/${now_date}.md}"
printf '%s\n' "$report" | hermes_atomic_write "$out"
echo "brain_health: report -> $out" >&2
exit 0
