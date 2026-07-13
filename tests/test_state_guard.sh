#!/usr/bin/env bash
# test_state_guard.sh — fixtures for the state guard. Zero-dep, deterministic.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SG="$here/../scripts/state_guard.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

mkplugin() { # dir pjver clver   (clver empty -> no CHANGELOG block)
  mkdir -p "$1/.claude-plugin"
  printf '{\n  "name": "x",\n  "version": "%s"\n}\n' "$2" > "$1/.claude-plugin/plugin.json"
  if [ -n "$3" ]; then
    printf '# CHANGELOG\n\n> intro\n\n## %s — 2026-07-06 — x\n- y\n\n## 0.1.0 — old\n- z\n' "$3" > "$1/CHANGELOG.md"
  fi
}

echo "== 1. versions match -> silent =="
mkplugin "$T/a" "0.1.14" "0.1.14"
o="$(bash "$SG" --release-drift --plugin-dir "$T/a")"
[ -z "$o" ] && ok "in sync -> silent" || bad "false drift: $o"

echo "== 2. version ahead of CHANGELOG -> warn (both versions shown) =="
mkplugin "$T/b" "0.1.15" "0.1.14"
o="$(bash "$SG" --release-drift --plugin-dir "$T/b")"
echo "$o" | grep -q 'RELEASE-DRIFT' && echo "$o" | grep -q '0.1.15' && echo "$o" | grep -q '0.1.14' \
  && ok "drift detected with both versions" || bad "no/partial drift warning: $o"

echo "== 3. newest block wins (older block below must not match) =="
# plugin 0.1.15, newest ## is 0.1.15, older is 0.1.0 -> silent (must read the TOP block, not any)
mkplugin "$T/d" "0.1.15" "0.1.15"
o="$(bash "$SG" --release-drift --plugin-dir "$T/d")"
[ -z "$o" ] && ok "reads newest block, ignores older" || bad "matched wrong block: $o"

echo "== 4. no CHANGELOG -> silent (not a plugin-with-changelog) =="
mkplugin "$T/c" "0.1.0" ""
o="$(bash "$SG" --release-drift --plugin-dir "$T/c")"
[ -z "$o" ] && ok "no changelog -> silent" || bad "warned without changelog: $o"

echo "== 5. missing --plugin-dir -> usage error (exit 1) =="
bash "$SG" --release-drift >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "usage error on missing dir" || bad "rc=$rc"

echo "== 6. living book in sync -> silent =="
mkplugin "$T/g" "0.1.16" ""
printf '> Plugin version: **0.1.16** · x\n' > "$T/g/PRODUCTBOOK.md"
o="$(bash "$SG" --book-drift --plugin-dir "$T/g" --book "$T/g/PRODUCTBOOK.md")"
[ -z "$o" ] && ok "book matches plugin -> silent" || bad "false book drift: $o"

echo "== 7. living book behind -> BOOK-DRIFT warn =="
mkplugin "$T/h" "0.1.16" ""
printf '> Plugin version: **0.1.10** · x\n' > "$T/h/PRODUCTBOOK.md"
o="$(bash "$SG" --book-drift --plugin-dir "$T/h" --book "$T/h/PRODUCTBOOK.md")"
echo "$o" | grep -q 'BOOK-DRIFT' && echo "$o" | grep -q '0.1.16' && echo "$o" | grep -q '0.1.10' \
  && ok "book drift detected" || bad "no/partial book drift: $o"

echo "== 8. book-drift missing --book -> usage error (exit 1) =="
bash "$SG" --book-drift --plugin-dir "$T/g" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "usage error on missing --book" || bad "rc=$rc"

echo "== 9. adopter in sync (active == cache max) -> silent =="
mkplugin "$T/i" "0.1.17" ""
mkdir -p "$T/cache_i/0.1.16" "$T/cache_i/0.1.17"
o="$(bash "$SG" --adopter-drift --plugin-dir "$T/i" --cache-dir "$T/cache_i")"
[ -z "$o" ] && ok "active == cache max -> silent" || bad "false adopter drift: $o"

echo "== 10. adopter behind cache -> ADOPTER-DRIFT warn (both versions) =="
mkplugin "$T/j" "0.1.13" ""
mkdir -p "$T/cache_j/0.1.13" "$T/cache_j/0.1.16" "$T/cache_j/0.1.17" "$T/cache_j/notaversion"
o="$(bash "$SG" --adopter-drift --plugin-dir "$T/j" --cache-dir "$T/cache_j")"
echo "$o" | grep -q 'ADOPTER-DRIFT' && echo "$o" | grep -q '0.1.13' && echo "$o" | grep -q '0.1.17' \
  && ok "adopter drift detected, ignores non-version subdir" || bad "no/partial adopter drift: $o"

echo "== 11. no plugin.json in active dir -> silent (not a versioned install) =="
mkdir -p "$T/k" "$T/cache_k/0.1.17"
o="$(bash "$SG" --adopter-drift --plugin-dir "$T/k" --cache-dir "$T/cache_k")"
[ -z "$o" ] && ok "no manifest -> silent skip" || bad "warned without manifest: $o"

echo "== 12. empty/absent cache -> silent (nothing available to compare) =="
mkplugin "$T/l" "0.1.13" ""
o="$(bash "$SG" --adopter-drift --plugin-dir "$T/l" --cache-dir "$T/cache_absent")"
[ -z "$o" ] && ok "absent cache -> silent" || bad "warned with no cache: $o"

echo "== 13. adopter-drift missing --cache-dir -> usage error (exit 1) =="
bash "$SG" --adopter-drift --plugin-dir "$T/l" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "usage error on missing --cache-dir" || bad "rc=$rc"

echo "== 14. fork in sync (marker version == source plugin.json) -> silent =="
mkplugin "$T/src1" "0.1.19" ""
printf 'source_version=0.1.19\nsource_dir=%s\ninstalled_at=2026-07-07T00:00:00Z\n' "$T/src1" > "$T/marker1"
o="$(bash "$SG" --fork-drift --marker "$T/marker1")"
[ -z "$o" ] && ok "fork == source -> silent" || bad "false fork drift: $o"

echo "== 15. fork behind source -> FORK-DRIFT warn (both versions) =="
mkplugin "$T/src2" "0.1.19" ""
printf 'source_version=0.1.13\nsource_dir=%s\ninstalled_at=2026-07-07T00:00:00Z\n' "$T/src2" > "$T/marker2"
o="$(bash "$SG" --fork-drift --marker "$T/marker2")"
echo "$o" | grep -q 'FORK-DRIFT' && echo "$o" | grep -q '0.1.13' && echo "$o" | grep -q '0.1.19' \
  && ok "fork drift detected with both versions" || bad "no/partial fork drift: $o"

echo "== 16. no marker file -> silent skip (pre-stamp fork) =="
o="$(bash "$SG" --fork-drift --marker "$T/nonexistent-marker")"
[ -z "$o" ] && ok "missing marker -> silent" || bad "warned without marker: $o"

echo "== 17. marker points at a gone/unreadable source -> silent skip =="
printf 'source_version=0.1.10\nsource_dir=%s/does-not-exist\ninstalled_at=x\n' "$T" > "$T/marker3"
o="$(bash "$SG" --fork-drift --marker "$T/marker3")"
[ -z "$o" ] && ok "gone source_dir -> silent" || bad "warned with dead source: $o"

echo "== 18. fork-drift missing --marker -> usage error (exit 1) =="
bash "$SG" --fork-drift >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "usage error on missing --marker" || bad "rc=$rc"

echo ""
echo "== state_guard: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
