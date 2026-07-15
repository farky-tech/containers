#!/usr/bin/env bash
# test_recall_inject.sh — per-prompt recall nerve: golden matching fixture + failure matrix.
# Zero-dep, hermetic (mktemp -d). Run: bash tests/test_recall_inject.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RI="$here/../scripts/recall_inject.sh"
GR="$here/../scripts/gen_rejstrik.sh"
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

mkfix() { # golden store: 4 atoms incl. the live-incident case (public repo account = fact)
  local d="$1"; mkdir -p "$d"
  cat > "$d/KNOWLEDGE.md" <<'EOF'
# KNOWLEDGE

<!-- hermes:entry kind=fact id=aaaaaaaaaaa1 ts=2026-07-15T00:00:00Z -->
slug: git-ucet-verejne-repo
importance: 4
origin: user
Veřejné repo containers žije na GitHub účtu farky-tech (public export FMC; push dělá Farky).
<!-- /hermes:entry -->

<!-- hermes:entry kind=decision id=aaaaaaaaaaa2 ts=2026-07-13T00:00:00Z -->
slug: vocab-drift-stav-state
importance: 4
origin: user
Vocab drift STAV×STATE: oprav u zdroje migrací živých dat (migrate_vocab), ne trvalý back-compat shim.
<!-- /hermes:entry -->

<!-- hermes:entry kind=lesson id=aaaaaaaaaaa3 ts=2026-07-10T00:00:00Z -->
slug: orchestrace-subagentu
importance: 3
origin: ai-derived
Orchestrace subagentů: rozlož → deleguj → převezmi → slij; read-only research vždy paralelně.
<!-- /hermes:entry -->

<!-- hermes:entry kind=lesson id=aaaaaaaaaaa4 ts=2026-07-01T00:00:00Z -->
slug: kos-se-nemaze
importance: 2
origin: user
Uživatelský obsah se nemaže — přesouvá se do složky Koš; skutečné mazání dělá jen Farky.
<!-- /hermes:entry -->
EOF
}

json() { printf '{"session_id":"%s","prompt":"%s","hook_event_name":"UserPromptSubmit"}' "$1" "$2"; }

echo "== 1. golden positive: incident question finds the fact atom (match-only) =="
T="$(mktemp -d)"; mkfix "$T"
rows="$(bash "$GR" --memory-dir "$T" --tsv </dev/null)"
o="$(printf '%s\n' "$rows" | bash "$RI" --match-only "na jakém GitHub účtu žije veřejné repo containers?")"
printf '%s' "$o" | grep -q 'git-ucet-verejne-repo' && ok "public-repo question -> git-ucet atom" || bad "golden 1 missed: $o"

echo "== 2. golden positive: vocab question -> vocab atom, kos NOT matched =="
o="$(printf '%s\n' "$rows" | bash "$RI" --match-only "jak jsme řešili vocab drift STAV versus STATE?")"
if printf '%s' "$o" | grep -q 'vocab-drift-stav-state' && ! printf '%s' "$o" | grep -q 'kos-se-nemaze'; then
  ok "vocab question -> vocab atom only"
else bad "golden 2: $o"; fi

echo "== 3. golden negatives: unrelated prompts stay SILENT =="
n1="$(printf '%s\n' "$rows" | bash "$RI" --match-only "upeč mi bábovku podle babiččina receptu")"
n2="$(printf '%s\n' "$rows" | bash "$RI" --match-only "kolik stojí lístek na vlak do Brna a kdy jede")"
[ -z "$n1" ] && [ -z "$n2" ] && ok "both unrelated prompts silent" || bad "noise leaked: [$n1] [$n2]"

echo "== 4. hook mode: emits pointer block + telemetry + seen file =="
o="$(json sess-AAA "jak jsme řešili vocab drift STAV versus STATE?" | bash "$RI" --memory-dir "$T"; echo "rc=$?")"
if printf '%s' "$o" | grep -q '🧠 RECALL' && printf '%s' "$o" | grep -q 'vocab-drift-stav-state' \
   && printf '%s' "$o" | grep -q 'rc=0' && grep -q 'emitted' "$T/.recall-hits.log" \
   && ls "$T/.recall-state"/seen-* >/dev/null 2>&1; then
  ok "hook emits block, logs emitted, writes seen"
else bad "hook mode: $o / $(ls "$T/.recall-state" 2>/dev/null)"; fi

echo "== 5. dedupe: same session again -> silent; other session -> emits =="
o2="$(json sess-AAA "jak jsme řešili vocab drift STAV versus STATE?" | bash "$RI" --memory-dir "$T")"
o3="$(json sess-BBB "jak jsme řešili vocab drift STAV versus STATE?" | bash "$RI" --memory-dir "$T")"
[ -z "$o2" ] && printf '%s' "$o3" | grep -q 'vocab-drift-stav-state' && ok "per-session dedupe holds" || bad "dedupe: same=[$o2] other=[$o3]"

echo "== 6. malformed / empty stdin -> silent rc=0 =="
o="$(printf 'this is not json {{{' | bash "$RI" --memory-dir "$T"; echo "rc=$?")"
o2="$(printf '' | bash "$RI" --memory-dir "$T"; echo "rc=$?")"
[ "$o" = "rc=0" ] && [ "$o2" = "rc=0" ] && ok "malformed+empty silent rc=0" || bad "malformed: [$o] [$o2]"

echo "== 7. no-jq parity: fallback parser produces the same match =="
o="$(json sess-CCC "jak jsme řešili vocab drift STAV versus STATE?" | HERMES_NO_JQ=1 bash "$RI" --memory-dir "$T")"
printf '%s' "$o" | grep -q 'vocab-drift-stav-state' && ok "no-jq fallback matches too" || bad "no-jq: $o"

echo "== 8. hostile session_id -> hashed state name, no traversal =="
o="$(json '../evil/../../x y' "orchestrace subagentů rozlož deleguj" | bash "$RI" --memory-dir "$T"; echo rc=$?)"
if printf '%s' "$o" | grep -q 'rc=0' && ! find "$T/.recall-state" -name '*evil*' 2>/dev/null | grep -q . \
   && [ ! -e "$T/../evil" ]; then
  ok "hostile SID neutralized (hash only)"
else bad "hostile SID: $o"; fi

echo "== 9. kill switch =="
o="$(json sess-DDD "vocab drift STAV STATE" | HERMES_RECALL_OFF=1 bash "$RI" --memory-dir "$T"; echo "rc=$?")"
[ "$o" = "rc=0" ] && ok "HERMES_RECALL_OFF=1 -> silent" || bad "kill switch: $o"

echo "== 10. no store -> silent, no log =="
T2="$(mktemp -d)"
o="$(json sess-E "vocab drift" | bash "$RI" --memory-dir "$T2"; echo "rc=$?")"
[ "$o" = "rc=0" ] && [ ! -f "$T2/.recall-hits.log" ] && ok "no store silent" || bad "no store: $o"

echo "== 11. C locale: matching still works (fold is byte-literal) =="
o="$(json sess-F "jak jsme řešili vocab drift STAV versus STATE?" | LC_ALL=C bash "$RI" --memory-dir "$T" 2>/dev/null)"
printf '%s' "$o" | grep -q 'vocab-drift-stav-state' && ok "LC_ALL=C still matches" || bad "C locale: $o"

echo "== 12. non-tty open-but-empty stdin does NOT hang (5s alarm) =="
if perl -e 'alarm 8; exec @ARGV' bash -c "mkfifo /tmp/ri_fifo.$$; (sleep 6 > /tmp/ri_fifo.$$ &) ; bash '$RI' --memory-dir '$T' < /tmp/ri_fifo.$$ >/dev/null 2>&1; rm -f /tmp/ri_fifo.$$" 2>/dev/null; then
  ok "open-empty stdin bounded (no hang)"
else bad "stdin hang (alarm fired)"; fi

echo "== 13. concurrency smoke: two parallel hook calls, state intact =="
( json sess-P1 "orchestrace subagentů deleguj rozlož" | bash "$RI" --memory-dir "$T" >/dev/null 2>&1 ) &
( json sess-P2 "orchestrace subagentů deleguj rozlož" | bash "$RI" --memory-dir "$T" >/dev/null 2>&1 ) &
wait
if awk -F'\t' 'NF && NF<3 {bad=1} END{exit bad?1:0}' "$T/.recall-hits.log" 2>/dev/null; then
  ok "parallel calls: log lines intact"
else bad "concurrency corrupted log"; fi

echo "== 14. 500-atom synthetic registry: bounded runtime, no crash =="
T3="$(mktemp -d)"; mkdir -p "$T3"
{ echo "# K"; i=0; while [ $i -lt 500 ]; do
  printf '<!-- hermes:entry kind=lesson id=%012x ts=2026-01-01T00:00:00Z -->\nslug: syn-atom-%s\nAtom číslo %s o tématu synteticky generovaném pro výkonový test.\n<!-- /hermes:entry -->\n' "$i" "$i" "$i"
  i=$((i+1)); done; } > "$T3/KNOWLEDGE.md"
t0=$SECONDS
o="$(json sess-PERF "atom číslo tématu synteticky generovaném" | bash "$RI" --memory-dir "$T3"; echo "rc=$?")"
dt=$((SECONDS - t0))
printf '%s' "$o" | grep -q 'rc=0' && [ "$dt" -le 5 ] && ok "500 atoms in ${dt}s, rc=0" || bad "perf: ${dt}s $o"

rm -rf "$T" "$T2" "$T3" 2>/dev/null
echo "== recall_inject: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
