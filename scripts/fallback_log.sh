#!/usr/bin/env bash
# fallback_log.sh — append a structured fallback entry to memory/fallbacks.md.
#
# Backbone script (SCRIPTED capability): a skill/agent calls this instead of
# narrating "write a fallback" in prose. Deterministic, idempotent, atomic.
#
# Usage:
#   fallback_log.sh --expected <text> --actual <text> --mechanism <name> \
#                   [--cause <text>] [--impact <text>] [--signal <kind>] \
#                   [--name <short>] [--memory-dir <dir>] [--dry-run]
#   fallback_log.sh --resolve <id-prefix> --status accepted-once|converted|closed|blocked \
#                   [--note "<text>"] [--memory-dir <dir>]
#
# --signal: skill|tool|hook|subagent|test|rule|none   (default: none)
# --resolve: flip Status of exactly ONE matching open block (ambiguous prefix = error).
#            blocked = waiting on a human/external decision (listed, not gate-blocking).
# --memory-dir: project memory/ folder (default: ./memory)
# --dry-run: print the block, write nothing.
#
# Exit codes:  0 written | 1 error/usage/ambiguous | 2 gate/skip (duplicate or no match)

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hermes_blocks.sh
. "$script_dir/lib/hermes_blocks.sh"

usage() { sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

expected="" actual="" mechanism="" cause="" impact="" signal="none"
name="" memory_dir="./memory" dry_run=0 resolve_id="" new_status="" pozn=""

while [ $# -gt 0 ]; do
  case "$1" in
    --expected)   expected="${2:-}"; shift 2 ;;
    --actual)     actual="${2:-}"; shift 2 ;;
    --mechanism)  mechanism="${2:-}"; shift 2 ;;
    --cause)      cause="${2:-}"; shift 2 ;;
    --impact)     impact="${2:-}"; shift 2 ;;
    --signal)     signal="${2:-}"; shift 2 ;;
    --name)       name="${2:-}"; shift 2 ;;
    --resolve)    resolve_id="${2:-}"; shift 2 ;;
    --status)     new_status="${2:-}"; shift 2 ;;
    --note)       pozn="${2:-}"; shift 2 ;;
    --memory-dir|--hermes-dir) memory_dir="${2:-}"; shift 2 ;;  # --hermes-dir = legacy alias (pre-rename adopters)
    --dry-run)    dry_run=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "fallback_log: unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

# --- resolve mode: state flip of exactly one existing block --------------------
if [ -n "$resolve_id" ]; then
  file="$memory_dir/fallbacks.md"
  case "$new_status" in
    accepted-once|converted|closed|blocked) ;;
    *) echo "fallback_log: --resolve requires --status accepted-once|converted|closed|blocked" >&2; exit 1 ;;
  esac
  [ -f "$file" ] || { echo "fallback_log: $file does not exist" >&2; exit 2; }
  ts="$(hermes_now_utc)"
  lockdir="${file}.lock"
  # Select under the lock (0.1.33, pre-publication audit): choosing the block BEFORE
  # locking left a window where a concurrent resolve rewrote the file between the
  # selection and the rewrite. Match and rewrite are now one locked transaction.
  hermes_lock "$lockdir" || exit 1
  # Exactly-one-match guard: an ambiguous prefix must not flip a random block.
  matches="$(grep -o '<!-- hermes:entry kind=fallback id=[a-f0-9]*' "$file" 2>/dev/null \
    | sed 's/.*id=//' | grep "^$resolve_id" || true)"
  n="$(printf '%s' "$matches" | grep -c . || true)"
  if [ "${n:-0}" -eq 0 ]; then
    hermes_unlock "$lockdir"
    echo "fallback_log: no fallback id starts with '$resolve_id'" >&2; exit 2
  fi
  if [ "$n" -gt 1 ]; then
    hermes_unlock "$lockdir"
    echo "fallback_log: prefix '$resolve_id' is ambiguous ($n blocks):" >&2
    printf '%s\n' "$matches" >&2; exit 1
  fi
  full_id="$matches"
  set +e
  awk -v id="$full_id" -v st="$new_status" -v ts="$ts" -v pozn="$pozn" '
    /<!-- hermes:entry / { inb = (index($0, "id=" id " ") > 0) }
    inb && /^Status: / { $0 = "Status: " st " (" ts (pozn=="" ? "" : "; " pozn) ")" }
    { print }
  ' "$file" | hermes_atomic_write "$file"
  rc=$?
  set -e
  hermes_unlock "$lockdir"
  [ "$rc" -eq 0 ] || { echo "fallback_log: resolve write failed" >&2; exit 1; }
  echo "fallback_log: $full_id -> Status: $new_status" >&2
  exit 0
fi

if [ -z "$expected" ] || [ -z "$actual" ] || [ -z "$mechanism" ]; then
  echo "fallback_log: --expected, --actual and --mechanism are required" >&2
  exit 1
fi
case "$signal" in
  skill|tool|hook|subagent|test|rule|none) ;;
  *) echo "fallback_log: invalid --signal: $signal" >&2; exit 1 ;;
esac

[ -n "$name" ] || name="$mechanism"
ts="$(hermes_now_utc)"
# Idempotence key: same expected+actual+mechanism = same entry, never duplicated.
id="$(hermes_block_id "fallback" "${expected}|${actual}|${mechanism}")"
file="$memory_dir/fallbacks.md"

body="$(printf '## %s\nExpected mechanism: %s\nActual mechanism: %s\nCause: %s\nImpact: %s\nLearning signal: %s\nStatus: open' \
  "$name" "$expected" "$actual" "$cause" "$impact" "$signal")"

if [ "$dry_run" -eq 1 ]; then
  printf '<!-- hermes:entry kind=fallback id=%s ts=%s -->\n%s\n<!-- /hermes:entry -->\n' "$id" "$ts" "$body"
  echo "fallback_log: dry-run, nothing written ($file)" >&2
  exit 0
fi

set +e
printf '%s' "$body" | hermes_append_block "$file" "fallback" "$id" "$ts"
rc=$?
set -e
case "$rc" in
  0) echo "fallback_log: wrote fallback id=$id -> $file" >&2; exit 0 ;;
  2) echo "fallback_log: duplicate id=$id already present, skipped -> $file" >&2; exit 2 ;;
  *) echo "fallback_log: write failed -> $file" >&2; exit 1 ;;
esac
