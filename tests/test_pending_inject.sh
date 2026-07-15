#!/usr/bin/env bash
# test_pending_inject.sh — PENDING forcing-function nerve: loud, bounded, fence-aware, read-only.
# Zero-dep, hermetic (mktemp -d). Run: bash tests/test_pending_inject.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI="$here/../scripts/pending_inject.sh"
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== 1. no todo / no PENDING -> silent rc=0 =="
T="$(mktemp -d)"
o="$(bash "$PI" --memory-dir "$T"; echo "rc=$?")"
printf '# t\n- [ ] normal work item\n' > "$T/todo.md"
o2="$(bash "$PI" --memory-dir "$T"; echo "rc=$?")"
[ "$o" = "rc=0" ] && [ "$o2" = "rc=0" ] && ok "silent without PENDING" || bad "not silent: [$o] [$o2]"

echo "== 2. two PENDING, fenced example + checked-off excluded, count + oldest date =="
cat > "$T/todo.md" <<'EOF'
# Todo
- [ ] PENDING(farky): Schválit severku v globálu / jde o kánon / dopad: rychlé čtení bez misparse (proposed 2026-07-15)
- [ ] běžná položka
- [x] PENDING(farky): už rozhodnuté
```
- [ ] PENDING(farky): příklad formátu (nesmí se počítat)
```
  - [ ] PENDING(farky): Vybrat směr u zaměstnanců / jen ty znáš záměr / dopad: odblokuje kontejner (proposed 2026-07-12)
EOF
o="$(bash "$PI" --memory-dir "$T")"
if printf '%s' "$o" | grep -q 'PENDING DECISIONS (2; oldest 2026-07-12)' \
   && printf '%s' "$o" | grep -q 'Schválit severku' && printf '%s' "$o" | grep -q 'Vybrat směr' \
   && ! printf '%s' "$o" | grep -q 'příklad formátu' && ! printf '%s' "$o" | grep -q 'už rozhodnuté'; then
  ok "count=2, oldest date, fence + done excluded, indented counted"
else bad "block wrong: $o"; fi

echo "== 3. resolve hint present =="
printf '%s' "$o" | grep -q -- "--done '<full item text from todo.md>'" && ok "resolve hint" || bad "hint missing"

echo "== 4. inflation bounded: 200 items -> block capped + 'and K more' =="
{ echo '# Todo'; i=0; while [ $i -lt 200 ]; do
  printf -- '- [ ] PENDING(farky): Rozhodnutí číslo %s s dostatečně dlouhým textem aby se počítal rozpočet bloku správně (proposed 2026-07-01)\n' "$i"
  i=$((i+1)); done; } > "$T/todo.md"
o="$(bash "$PI" --memory-dir "$T")"
blen=${#o}
if printf '%s' "$o" | grep -q 'PENDING DECISIONS (200' && printf '%s' "$o" | grep -q 'and .* more' \
   && [ "$blen" -lt 10000 ]; then
  ok "200 items -> bounded block (${blen} chars) + overflow row"
else bad "inflation: len=$blen"; fi

echo "== 5. kill switch + read-only (todo untouched) =="
sum1="$(cksum "$T/todo.md")"
o="$(HERMES_PENDING_OFF=1 bash "$PI" --memory-dir "$T"; echo "rc=$?")"
sum2="$(cksum "$T/todo.md")"
[ "$o" = "rc=0" ] && [ "$sum1" = "$sum2" ] && ok "kill switch silent, file untouched" || bad "kill/RO: $o"

rm -rf "$T" 2>/dev/null
echo "== pending_inject: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
