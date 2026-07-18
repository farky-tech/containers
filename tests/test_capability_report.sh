#!/usr/bin/env bash
# test_capability_report.sh — adopter self-report: WIRED vs OFFERED FMC nerves.
# Zero-dep, hermetic (mktemp -d + trap), deterministic (HERMES_FAKE_TS). Run: bash tests/test_capability_report.sh
#
# Contract since Fáze A (auto-wire, 2026-07-18): the Claude adapter ships the full nerve set in
# hooks/hooks.json → adapters/claude-code/hook_dispatch.sh. So capability_report derives BOTH
# offered and wired from the dispatch (like the Codex branch) — "running == wired". Two paths:
#   AUTO-WIRE  (dispatch present, hooks.json calls it): offered==wired by construction → all-on, silent.
#              "missing" is structurally impossible here; that is correct (gate = all-or-nothing).
#   FALLBACK   (no dispatch — trimmed/legacy install): offered from the fragment, wired from the
#              project settings.json → partial IS detectable (preserves meta-hub / legacy adopters).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(cd "$here/.." && pwd)"
CR="$plugin_root/scripts/capability_report.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/hermes-caprep.XXXXXX")"
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# A mock AUTO-WIRE plugin: hooks.json calls the dispatch for ALL FOUR lifecycle events (mirrors the
# real shipped hooks.json — a fixture wiring only SessionStart would encode a false positive, since
# is_wired treats "dispatch called + references the script" as wired), dispatch runs the given nerves.
mk_plugin_auto() { # dir  "space-separated nerve script basenames"
  local d="$1"; shift
  mkdir -p "$d/adapters/claude-code" "$d/hooks"
  local dp='bash \"${CLAUDE_PLUGIN_ROOT}/adapters/claude-code/hook_dispatch.sh\"'
  printf '{"hooks":{"SessionStart":[{"matcher":"*","hooks":[{"type":"command","command":"%s session-start"}]}],"UserPromptSubmit":[{"matcher":"*","hooks":[{"type":"command","command":"%s user-prompt-submit"}]}],"SessionEnd":[{"matcher":"*","hooks":[{"type":"command","command":"%s session-end"}]}],"PreCompact":[{"matcher":"*","hooks":[{"type":"command","command":"%s pre-compact"}]}]}}\n' "$dp" "$dp" "$dp" "$dp" > "$d/hooks/hooks.json"
  { echo '#!/usr/bin/env bash'; local s; for s in "$@"; do printf 'run_script "%s.sh" --memory-dir "$memory_dir"\n' "$s"; done; } > "$d/adapters/claude-code/hook_dispatch.sh"
}

# A mock FALLBACK plugin: NO dispatch; hooks.json does not call it; fragment declares OFFERED.
mk_plugin_legacy() { # dir  "space-separated offered nerve basenames"
  local d="$1"; shift
  mkdir -p "$d/adapters/claude-code" "$d/hooks"
  printf '{"hooks":{"SessionStart":[{"matcher":"*","hooks":[{"type":"command","command":"printf FMC"}]}]}}\n' > "$d/hooks/hooks.json"
  { printf '{"hooks":{"SessionStart":[{"hooks":['; local f=1 s; for s in "$@"; do [ $f -eq 1 ] || printf ','; printf '{"type":"command","command":"bash scripts/%s.sh --memory-dir ./memory"}' "$s"; f=0; done; printf ']}]}}\n'; } > "$d/adapters/claude-code/settings-fragment.example.json"
}

# A mock adopter project: settings.json wires only SOME nerves (used by the fallback path).
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

TEN="close_state brain_health state_inject capability_inject rejstrik_inject pending_inject index_inject state_guard journal_prompt recall_inject"

echo "== 1. AUTO-WIRE: offered==wired from the dispatch (all-on) =="
pa="$T/plugin_auto"; mk_plugin_auto "$pa" $TEN
proj="$T/proj"; mkdir -p "$proj/memory"
out="$(bash "$CR" --status --plugin-dir "$pa" --project-dir "$proj")"
echo "$out" | grep -q "offered=10 wired=10" && ok "auto-wire status offered=10 wired=10" || bad "status wrong: $out"

echo "== 2. AUTO-WIRE startup: SILENT (nothing missing) =="
out="$(bash "$CR" --startup --plugin-dir "$pa" --project-dir "$proj")"; rc=$?
{ [ -z "$out" ] && [ "$rc" -eq 0 ]; } && ok "auto-wire startup silent" || bad "startup not silent: rc=$rc out='$out'"

echo "== 3. FALLBACK (no dispatch): lists missing when settings wire only some =="
pl="$T/plugin_legacy"; mk_plugin_legacy "$pl" $TEN
p_half="$T/p_half"; mk_project "$p_half" index_inject state_inject
out="$(bash "$CR" --startup --plugin-dir "$pl" --project-dir "$p_half")"
{ echo "$out" | grep -q '2 of 10' && echo "$out" | grep -q 'NOT wired'; } \
  && ok "fallback surfaces missing nerves (2 of 10)" || bad "fallback missing content: $out"

echo "== 4. FALLBACK close: report + ADOPTION-ready line with instance + count =="
out="$(HERMES_FAKE_TS='2026-07-12T10:00:00Z' bash "$CR" --close --plugin-dir "$pl" --project-dir "$p_half" --instance cc_test)"
{ echo "$out" | grep -q 'self-report' && echo "$out" | grep -q '2026-07-12' && echo "$out" | grep -q '`cc_test`' \
  && echo "$out" | grep -q "2/10"; } \
  && ok "fallback close emits ADOPTION line (date, instance, N/M)" || bad "close line wrong: $out"

echo "== 5. AUTO-WIRE close: says all-on, NO ADOPTION line =="
out="$(bash "$CR" --close --plugin-dir "$pa" --project-dir "$proj")"
{ echo "$out" | grep -q 'Everything wired' && ! echo "$out" | grep -q 'ADOPTION'; } \
  && ok "auto-wire close: all-on, no gap line" || bad "close full wrong: $out"

echo "== 6. trimmed install (no dispatch, no fragment): silent, exit 0 =="
out="$(bash "$CR" --startup --plugin-dir "$T/nonexistent" --project-dir "$p_half")"; rc=$?
{ [ -z "$out" ] && [ "$rc" -eq 0 ]; } && ok "trimmed -> silent exit 0" || bad "trimmed not silent: rc=$rc out='$out'"

echo "== 7. FALLBACK settings.local.json also counts as wired (adopter split) =="
p7="$T/p_local"; mkdir -p "$p7/.claude" "$p7/memory"
printf '{"hooks":{}}\n' > "$p7/.claude/settings.json"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash scripts/index_inject.sh --memory-dir ./memory"}]}]}}\n' > "$p7/.claude/settings.local.json"
out="$(bash "$CR" --status --plugin-dir "$pl" --project-dir "$p7")"
echo "$out" | grep -qE 'wired=1( |$)' && ok "settings.local.json counted as wired" || bad "local not counted: $out"

echo "== 8. AUTO-WIRE trumps partial settings (dispatch wins, no false 'missing') =="
# Regression for the Fáze A trap: an adopter mid-migration with a partial fragment in settings must
# still report all-on via the dispatch, never nag "0 wired -> paste the fragment" (double-wire trap).
p_mig="$T/p_mig"; mk_project "$p_mig" index_inject
out="$(bash "$CR" --startup --plugin-dir "$pa" --project-dir "$p_mig")"; rc=$?
{ [ -z "$out" ] && [ "$rc" -eq 0 ]; } && ok "auto-wire silent even with partial settings" || bad "auto-wire nagged wrongly: rc=$rc out='$out'"

echo ""
echo "== capability_report: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
