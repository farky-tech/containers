#!/usr/bin/env bash
# test_capability_report.sh — adopter self-report: WIRED vs OFFERED FMC nerves.
# Zero-dep, hermetic (mktemp -d + trap), deterministic (HERMES_FAKE_TS). Run: bash tests/test_capability_report.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(cd "$here/.." && pwd)"
CR="$plugin_root/scripts/capability_report.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/hermes-caprep.XXXXXX")"
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# A minimal adopter project: settings.json wires only SOME of the offered nerves.
mk_project() { # dir  "space-separated wired script basenames"
  local d="$1"; shift
  mkdir -p "$d/.claude" "$d/memory"
  {
    printf '{"hooks":{"SessionStart":[{"hooks":['
    local first=1 s
    for s in "$@"; do
      [ $first -eq 1 ] || printf ','
      printf '{"type":"command","command":"bash scripts/%s.sh --memory-dir ./memory"}' "$s"
      first=0
    done
    printf ']}]}}\n'
  } > "$d/.claude/settings.json"
}

# The OFFERED set is whatever the real adapter fragment declares — derive it the same way the
# script does, so the test tracks the SSOT instead of hardcoding a count that drifts.
offered_n="$(grep -oE 'scripts/[a-z_]+\.sh' "$plugin_root/adapters/claude-code/settings-fragment.example.json" | sed 's#scripts/##;s#\.sh##' | sort -u | wc -l | tr -d ' ')"

echo "== 1. status: offered derived from fragment; wired counted from settings =="
p1="$T/p_half"; mk_project "$p1" index_inject state_inject
out="$(bash "$CR" --status --plugin-dir "$plugin_root" --project-dir "$p1")"
echo "$out" | grep -q "offered=$offered_n wired=2" && ok "status counts offered($offered_n)/wired(2)" \
  || bad "status wrong: $out"

echo "== 2. startup: SILENT when everything offered is wired =="
p2="$T/p_full"
# wire ALL offered nerves
all="$(grep -oE 'scripts/[a-z_]+\.sh' "$plugin_root/adapters/claude-code/settings-fragment.example.json" | sed 's#scripts/##;s#\.sh##' | sort -u | tr '\n' ' ')"
mk_project "$p2" $all
out="$(bash "$CR" --startup --plugin-dir "$plugin_root" --project-dir "$p2")"; rc=$?
{ [ -z "$out" ] && [ "$rc" -eq 0 ]; } && ok "startup silent on fully-wired setup" || bad "startup not silent: rc=$rc out='$out'"

echo "== 3. startup: lists what's missing when only some wired =="
out="$(bash "$CR" --startup --plugin-dir "$plugin_root" --project-dir "$p1")"
{ echo "$out" | grep -q '2 of' && echo "$out" | grep -q 'NOT wired' && echo "$out" | grep -q 'using-container'; } \
  && ok "startup surfaces missing nerves + how to enable" || bad "startup missing content: $out"

echo "== 4. close: report + ADOPTION-ready line with instance + count =="
out="$(HERMES_FAKE_TS='2026-07-12T10:00:00Z' bash "$CR" --close --plugin-dir "$plugin_root" --project-dir "$p1" --instance cc_test)"
{ echo "$out" | grep -q 'self-report' && echo "$out" | grep -q '2026-07-12' && echo "$out" | grep -q '`cc_test`' \
  && echo "$out" | grep -q "2/$offered_n"; } \
  && ok "close emits ADOPTION line (date, instance, N/M)" || bad "close line wrong: $out"

echo "== 5. close on fully-wired: says all-on, NO ADOPTION line =="
out="$(bash "$CR" --close --plugin-dir "$plugin_root" --project-dir "$p2")"
{ echo "$out" | grep -q 'Everything wired' && ! echo "$out" | grep -q 'ADOPTION'; } \
  && ok "close on full setup: all-on, no gap line" || bad "close full wrong: $out"

echo "== 6. no fragment (trimmed install): silent, never breaks boot (exit 0) =="
out="$(bash "$CR" --startup --plugin-dir "$T/nonexistent" --project-dir "$p1")"; rc=$?
{ [ -z "$out" ] && [ "$rc" -eq 0 ]; } && ok "no fragment -> silent exit 0" || bad "no-fragment not silent: rc=$rc out='$out'"

echo "== 7. settings.local.json also counts as wired (adopter split) =="
p7="$T/p_local"; mkdir -p "$p7/.claude" "$p7/memory"
printf '{"hooks":{}}\n' > "$p7/.claude/settings.json"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash scripts/index_inject.sh --memory-dir ./memory"}]}]}}\n' > "$p7/.claude/settings.local.json"
out="$(bash "$CR" --status --plugin-dir "$plugin_root" --project-dir "$p7")"
echo "$out" | grep -q 'wired=1' && ok "settings.local.json counted as wired" || bad "local not counted: $out"

echo ""
echo "== capability_report: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
