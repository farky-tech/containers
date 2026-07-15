#!/usr/bin/env bash
# test_brain_health.sh — fixtures for the F4 weekly brain-health observer.
# Zero-dep, deterministic (HERMES_FAKE_TS). Run: bash tests/test_brain_health.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BH="$here/../scripts/brain_health.sh"
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== 1. --report writes memory/health/<date>.md with the metric table =="
T="$(mktemp -d)"; mkdir -p "$T"
printf '# todo\n\n- [ ] a\n- [ ] b\n- [x] done\n' > "$T/todo.md"
out="$(HERMES_FAKE_TS='2026-07-11T10:00:00Z' bash "$BH" --memory-dir "$T" --report 2>/dev/null; echo)"
if [ -f "$T/health/2026-07-11.md" ] && grep -q 'Brain health — 2026-07-11' "$T/health/2026-07-11.md" \
   && grep -q 'Open todo items | 2' "$T/health/2026-07-11.md"; then
  ok "report written with correct date + open-todo count (2)"
else
  bad "report missing/incorrect: $(ls "$T/health" 2>/dev/null)"
fi

echo "== 2. --report --dry-run prints, writes nothing =="
out="$(HERMES_FAKE_TS='2026-07-11T10:00:00Z' bash "$BH" --memory-dir "$T" --report --dry-run 2>/dev/null)"
printf '%s' "$out" | grep -q 'Brain health' && [ ! -f "$T/health/dry.md" ] && ok "dry-run prints, no extra file" || bad "dry-run"

echo "== 3. --due-check: no report -> advisory =="
T2="$(mktemp -d)"
o="$(bash "$BH" --memory-dir "$T2" --due-check)"
printf '%s' "$o" | grep -q 'FMC MAINTENANCE' && ok "no report -> advisory" || bad "no-report due-check: $o"

echo "== 4. --due-check: fresh report today -> silent =="
mkdir -p "$T2/health"; : > "$T2/health/2026-07-11.md"
o="$(HERMES_FAKE_TS='2026-07-11T12:00:00Z' bash "$BH" --memory-dir "$T2" --due-check)"
[ -z "$o" ] && ok "fresh report -> silent" || bad "fresh not silent: $o"

echo "== 5. --due-check: report 10 days old -> advisory =="
rm -f "$T2/health/2026-07-11.md"; : > "$T2/health/2026-07-01.md"
o="$(HERMES_FAKE_TS='2026-07-11T12:00:00Z' bash "$BH" --memory-dir "$T2" --due-check)"
printf '%s' "$o" | grep -q 'FMC MAINTENANCE' && ok "stale report -> advisory" || bad "stale not advised: $o"

echo "== 6. --due-check: report 6 days old (< 7) -> silent =="
rm -f "$T2/health/2026-07-01.md"; : > "$T2/health/2026-07-05.md"
o="$(HERMES_FAKE_TS='2026-07-11T12:00:00Z' bash "$BH" --memory-dir "$T2" --due-check)"
[ -z "$o" ] && ok "6-day-old report -> silent" || bad "6-day not silent: $o"

echo "== 7. UNCLOSED markers counted in report =="
T3="$(mktemp -d)"; mkdir -p "$T3/.close-state"
printf 'session_id=x\n' > "$T3/.close-state/UNCLOSED-x.env"
printf 'session_id=y\n' > "$T3/.close-state/UNCLOSED-y.env"
HERMES_FAKE_TS='2026-07-11T10:00:00Z' bash "$BH" --memory-dir "$T3" --report >/dev/null 2>&1
grep -q 'Unclosed sessions (UNCLOSED markers) | 2' "$T3/health/2026-07-11.md" && ok "2 UNCLOSED markers counted" || bad "unclosed count"

echo "== 8. template fallback example is not counted as open debt =="
T4="$(mktemp -d)"
cp "$here/../templates/memory-folder/fallbacks.md" "$T4/fallbacks.md"
o="$(HERMES_FAKE_TS='2026-07-11T10:00:00Z' bash "$BH" --memory-dir "$T4" --report --dry-run 2>/dev/null)"
printf '%s' "$o" | grep -qF '| Open fallbacks | 0 |' \
  && ok "fenced template example -> 0 open fallbacks" \
  || bad "fenced template example counted as fallback: $o"

echo "== 9. one canonical open fallback is counted exactly once =="
printf '\n<!-- hermes:entry kind=fallback id=fixture-open ts=2026-07-11T10:00:00Z -->\n## Fixture fallback\nStatus: open\n<!-- /hermes:entry -->\n' >> "$T4/fallbacks.md"
o="$(HERMES_FAKE_TS='2026-07-11T10:00:00Z' bash "$BH" --memory-dir "$T4" --report --dry-run 2>/dev/null)"
printf '%s' "$o" | grep -qF '| Open fallbacks | 1 |' \
  && ok "one canonical open fallback -> 1" \
  || bad "canonical open fallback count incorrect: $o"

rm -rf "$T" "$T2" "$T3" "$T4"
echo ""
echo "== brain_health: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
