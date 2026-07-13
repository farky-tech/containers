#!/usr/bin/env bash
# test_backbone_scripts.sh — unit tests for the container's scripted backbone.
# Zero-dep, hermetic: every test runs against a throwaway --memory-dir.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(cd "$script_dir/.." && pwd)"
scripts="$plugin_root/scripts"

work="$(mktemp -d "${TMPDIR:-/tmp}/hermes-backbone-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT

pass=0; fail=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

export HERMES_FAKE_TS="2026-06-24T10:00:00Z"

# ---------------------------------------------------------------- fallback_log
echo "test: fallback_log.sh"
hd="$work/h1"; mkdir -p "$hd"
"$scripts/fallback_log.sh" --memory-dir "$hd" --expected "tool runs" --actual "tool blocked" --mechanism "Bash" --signal rule >/dev/null 2>&1
check "writes a canonical block" '[ -f "$hd/fallbacks.md" ] && grep -q "hermes:entry kind=fallback" "$hd/fallbacks.md"'
check "block carries iso ts" 'grep -q "ts=2026-06-24T10:00:00Z" "$hd/fallbacks.md"'
check "block is closed" 'grep -q "<!-- /hermes:entry -->" "$hd/fallbacks.md"'

# idempotence: identical call must NOT duplicate (exit 2)
set +e
"$scripts/fallback_log.sh" --memory-dir "$hd" --expected "tool runs" --actual "tool blocked" --mechanism "Bash" --signal rule >/dev/null 2>&1
rc=$?
set -e
check "duplicate call exits 2" '[ "$rc" -eq 2 ]'
n="$(grep -c "hermes:entry kind=fallback" "$hd/fallbacks.md")"
check "duplicate not appended (count=1)" '[ "$n" -eq 1 ]'

# different content => new block
"$scripts/fallback_log.sh" --memory-dir "$hd" --expected "x" --actual "y" --mechanism "Z" >/dev/null 2>&1
n2="$(grep -c "hermes:entry kind=fallback" "$hd/fallbacks.md")"
check "distinct call appends (count=2)" '[ "$n2" -eq 2 ]'

# validation: missing required arg fails (exit 1)
set +e
"$scripts/fallback_log.sh" --memory-dir "$hd" --expected "only" >/dev/null 2>&1
rc=$?
set -e
check "missing required arg exits 1" '[ "$rc" -eq 1 ]'

# invalid signal fails
set +e
"$scripts/fallback_log.sh" --memory-dir "$hd" --expected a --actual b --mechanism c --signal bogus >/dev/null 2>&1
rc=$?
set -e
check "invalid --signal exits 1" '[ "$rc" -eq 1 ]'

# dry-run writes nothing
hd2="$work/h2"; mkdir -p "$hd2"
"$scripts/fallback_log.sh" --memory-dir "$hd2" --expected a --actual b --mechanism c --dry-run >/dev/null 2>&1
check "dry-run does not write" '[ ! -f "$hd2/fallbacks.md" ]'

# ---------------------------------------------------------------- ledger_carry
echo "test: ledger_carry.sh"
hl="$work/l1"; mkdir -p "$hl"
"$scripts/ledger_carry.sh" --memory-dir "$hl" --item "finish backbone" --item "wire verifier" >/dev/null 2>&1
check "carries items as todo blocks" '[ "$(grep -c "hermes:entry kind=todo" "$hl/todo.md")" -eq 2 ]'
# idempotent: same item not duplicated
"$scripts/ledger_carry.sh" --memory-dir "$hl" --item "finish backbone" >/dev/null 2>&1
check "duplicate item not re-carried (count=2)" '[ "$(grep -c "hermes:entry kind=todo" "$hl/todo.md")" -eq 2 ]'
# stdin items
printf 'from stdin\n' | "$scripts/ledger_carry.sh" --memory-dir "$hl" >/dev/null 2>&1
check "carries stdin item (count=3)" '[ "$(grep -c "hermes:entry kind=todo" "$hl/todo.md")" -eq 3 ]'
# non-tty stdin must NOT block (regression: cc_hlas 2026-07-12 — `--item` + an open
# idle stdin, as a non-interactive harness/CI leaves it, hung ~2 min). With --item
# stdin is skipped; the `< <(sleep 6)` open-idle pipe would take 6s if it regressed.
t0=$(date +%s)
"$scripts/ledger_carry.sh" --memory-dir "$hl" --item "no hang" --dry-run < <(sleep 6) >/dev/null 2>&1
elapsed=$(( $(date +%s) - t0 ))
check "--item + idle stdin returns fast, no hang" '[ "$elapsed" -lt 4 ]'
# nothing to carry exits 2
set +e
"$scripts/ledger_carry.sh" --memory-dir "$hl" </dev/null >/dev/null 2>&1
rc=$?
set -e
check "no items exits 2" '[ "$rc" -eq 2 ]'
# --done marks a carried item resolved (carry-forward loop hygiene)
hld="$work/ld"; mkdir -p "$hld"
"$scripts/ledger_carry.sh" --memory-dir "$hld" --item "finish loop" >/dev/null 2>&1
check "carried item starts open" 'grep -q -- "- \[ \] finish loop" "$hld/todo.md"'
"$scripts/ledger_carry.sh" --memory-dir "$hld" --done "finish loop" >/dev/null 2>&1
check "--done marks it [x]" 'grep -q -- "- \[x\] finish loop" "$hld/todo.md" && ! grep -q -- "- \[ \] finish loop" "$hld/todo.md"'
# --done fail-honest: no OPEN item matching -> exit 2, nothing changed (no silent no-op lie)
set +e; "$scripts/ledger_carry.sh" --memory-dir "$hld" --done "no such item ever" >/dev/null 2>&1; rc=$?; set -e
check "--done on non-existent item exits 2 (fail-honest)" '[ "$rc" -eq 2 ]'
# --done on an already-resolved [x] item -> no OPEN match -> exit 2 (idempotent honesty)
set +e; "$scripts/ledger_carry.sh" --memory-dir "$hld" --done "finish loop" >/dev/null 2>&1; rc=$?; set -e
check "--done on already-resolved item exits 2" '[ "$rc" -eq 2 ]'
# --done with no todo.md at all -> exit 2 (nothing resolved)
set +e; "$scripts/ledger_carry.sh" --memory-dir "$work/ld-empty" --done "x" >/dev/null 2>&1; rc=$?; set -e
check "--done with no todo.md exits 2" '[ "$rc" -eq 2 ]'

# --- A1 regression: --done must resolve EXACTLY one item, anchored (not substring/prefix) ---
# Bug repro: "fix login" + "fix logout" both share prefix "fix"; --done "fix"
# used to silently flip BOTH to [x] (unanchored substring match). Must now refuse (exit 2).
ha1="$work/a1"; mkdir -p "$ha1"
"$scripts/ledger_carry.sh" --memory-dir "$ha1" --item "fix login" >/dev/null 2>&1
"$scripts/ledger_carry.sh" --memory-dir "$ha1" --item "fix logout" >/dev/null 2>&1
set +e
"$scripts/ledger_carry.sh" --memory-dir "$ha1" --done "fix" >/dev/null 2>&1
rc=$?
set -e
check "prefix --done matches nothing, exits 2 (no false-positive substring match)" '[ "$rc" -eq 2 ]'
check "prefix collision: both items stay open" '[ "$(grep -c -- "- \[ \] fix" "$ha1/todo.md")" -eq 2 ]'
"$scripts/ledger_carry.sh" --memory-dir "$ha1" --done "fix login" >/dev/null 2>&1
check "exact --done resolves only the named item" 'grep -q -- "- \[x\] fix login" "$ha1/todo.md" && grep -q -- "- \[ \] fix logout" "$ha1/todo.md"'

# two items with IDENTICAL text -> genuinely ambiguous -> exit 2, nothing changed
ha1b="$work/a1b"; mkdir -p "$ha1b"
printf -- '- [ ] duplicate text\n- [ ] duplicate text\n' > "$ha1b/todo.md"
set +e
"$scripts/ledger_carry.sh" --memory-dir "$ha1b" --done "duplicate text" >/dev/null 2>&1
rc=$?
set -e
check "ambiguous multi-match --done exits 2" '[ "$rc" -eq 2 ]'
check "ambiguous multi-match changes nothing (both still open)" '[ "$(grep -c -- "- \[ \] duplicate text" "$ha1b/todo.md")" -eq 2 ]'

# item carried with --step is resolvable by its base text (suffix-boundary match, not substring)
ha1c="$work/a1c"; mkdir -p "$ha1c"
"$scripts/ledger_carry.sh" --memory-dir "$ha1c" --item "loop A" --step "call the supplier" >/dev/null 2>&1
"$scripts/ledger_carry.sh" --memory-dir "$ha1c" --done "loop A" >/dev/null 2>&1
check "--done resolves item by its base text despite --step suffix" 'grep -q -- "- \[x\] loop A" "$ha1c/todo.md"'

# fenced code block example is illustrative meta-content, not a real item -> not matched
ha1d="$work/a1d"; mkdir -p "$ha1d"
printf '# Todo\n\n```txt\n- [ ] Item:\n```\n' > "$ha1d/todo.md"
set +e
"$scripts/ledger_carry.sh" --memory-dir "$ha1d" --done "Item:" >/dev/null 2>&1
rc=$?
set -e
check "--done ignores fenced-code-block example items" '[ "$rc" -eq 2 ]'
check "fenced example line untouched" 'grep -q -- "- \[ \] Item:" "$ha1d/todo.md"'

# resolved item no longer counts as open in session_close
out_d="$("$scripts/session_close.sh" --memory-dir "$hld" 2>/dev/null)"
check "resolved item drops from open count" 'printf "%s" "$out_d" | grep -q "Open to-do items: 0"'
# session_close lists the actual open items for pull-back
"$scripts/ledger_carry.sh" --memory-dir "$hld" --item "still pending thing" >/dev/null 2>&1
out_o="$("$scripts/session_close.sh" --memory-dir "$hld" 2>/dev/null)"
check "close lists concrete open item text" 'printf "%s" "$out_o" | grep -q "still pending thing"'
check "close has pull-back section" 'printf "%s" "$out_o" | grep -q "pull these into the lapac list"'

# --------------------------------------------------------------- memory_route
echo "test: memory_route.sh (approval gate)"
hm="$work/m1"; mkdir -p "$hm"
# default = propose, writes nothing
"$scripts/memory_route.sh" --memory-dir "$hm" --text "verify from real state" --kind lesson >/dev/null 2>&1
check "propose writes nothing" '[ ! -f "$hm/KNOWLEDGE.md" ]'
# CRITICAL gate: --commit without approval is refused (exit 2), nothing written
set +e
"$scripts/memory_route.sh" --memory-dir "$hm" --text "x" --kind lesson --commit >/dev/null 2>&1
rc=$?
set -e
check "commit without approval exits 2 (gate)" '[ "$rc" -eq 2 ]'
check "refused commit wrote nothing" '[ ! -f "$hm/KNOWLEDGE.md" ]'
# commit with approval writes + records metadata
"$scripts/memory_route.sh" --memory-dir "$hm" --text "verify from real state" --kind lesson \
  --commit --approved-by farky --reason "session learning" >/dev/null 2>&1
check "approved commit writes block" '[ -f "$hm/KNOWLEDGE.md" ] && grep -q "hermes:entry kind=lesson" "$hm/KNOWLEDGE.md"'
check "commit records approved_by" 'grep -q "approved_by: farky" "$hm/KNOWLEDGE.md"'
# 0.1.24: lesson/decision/procedure share ONE store (KNOWLEDGE.md), distinguished by kind:
"$scripts/memory_route.sh" --memory-dir "$hm" --text "use scripts" --kind decision \
  --commit --approved-by farky --reason "policy" >/dev/null 2>&1
check "decision lands in KNOWLEDGE.md (kind=decision)" 'grep -q "hermes:entry kind=decision" "$hm/KNOWLEDGE.md"'
# invalid kind fails
set +e
"$scripts/memory_route.sh" --memory-dir "$hm" --text x --kind bogus >/dev/null 2>&1
rc=$?
set -e
check "invalid --kind exits 1" '[ "$rc" -eq 1 ]'
# regression M1: whitespace-only approval must NOT pass the gate
set +e
"$scripts/memory_route.sh" --memory-dir "$hm" --text x --kind lesson --commit --approved-by " " --reason " " >/dev/null 2>&1
rc=$?
set -e
check "whitespace-only approval refused (exit 2)" '[ "$rc" -eq 2 ]'
# regression M1: sentinel in body must be refused (no boundary injection)
hm2="$work/m2"; mkdir -p "$hm2"
set +e
"$scripts/memory_route.sh" --memory-dir "$hm2" --text 'evil <!-- hermes:entry kind=memory id=x ts=x -->' --kind lesson --commit --approved-by farky --reason t >/dev/null 2>&1
rc=$?
set -e
check "sentinel in body refused (nonzero)" '[ "$rc" -ne 0 ]'
check "sentinel refusal wrote nothing" '[ ! -f "$hm2/KNOWLEDGE.md" ]'

# --------------------------------------------------------------- write failure
echo "test: write-failure propagation (H1)"
hro="$work/ro"; mkdir -p "$hro"; chmod 555 "$hro"
set +e
"$scripts/fallback_log.sh" --memory-dir "$hro" --expected a --actual b --mechanism c >/dev/null 2>&1
rc=$?
set -e
chmod 755 "$hro"
check "write to read-only dir fails (exit 1, no silent success)" '[ "$rc" -eq 1 ]'

# --------------------------------------------------------------- session_close
echo "test: session_close.sh"
hc="$work/c1"; mkdir -p "$hc"
"$scripts/ledger_carry.sh" --memory-dir "$hc" --item "open one" >/dev/null 2>&1
out="$("$scripts/session_close.sh" --memory-dir "$hc" 2>/dev/null)"
check "close prints handoff header" 'printf "%s" "$out" | grep -q "Session close — container handoff"'
check "close reports open todo count" 'printf "%s" "$out" | grep -q "Open to-do items: 1"'
hc_doc="$work/c-doc"; mkdir -p "$hc_doc"
printf '# Todo\n\n```txt\n- [ ] Item:\n```\n' > "$hc_doc/todo.md"
printf '# Fallbacks\n\n```txt\nStatus: open | closed\n```\n' > "$hc_doc/fallbacks.md"
out_doc="$("$scripts/session_close.sh" --memory-dir "$hc_doc" 2>/dev/null)"
check "close ignores checklist examples in fenced code" 'printf "%s" "$out_doc" | grep -q "Open to-do items: 0"'
check "close ignores fallback status examples in fenced code" 'printf "%s" "$out_doc" | grep -q "Open fallbacks: 0"'
set +e
"$scripts/session_close.sh" --memory-dir "$work/does-not-exist" >/dev/null 2>&1
rc=$?
set -e
check "missing hermes dir exits 1" '[ "$rc" -eq 1 ]'

# length-guard: open_items capped at _OMAX=8 (0.1.24 boot dieta), keeps the NEWEST (tail), shows overflow count
hg="$work/guard"; mkdir -p "$hg"
for i in $(seq -w 1 15); do "$scripts/ledger_carry.sh" --memory-dir "$hg" --item "guard item $i" >/dev/null 2>&1 || true; done
out_g="$("$scripts/session_close.sh" --memory-dir "$hg" 2>/dev/null)"
check "length-guard caps open_items (overflow note, 15-8=7)" 'printf "%s" "$out_g" | grep -q "and 7 more older items"'
check "length-guard keeps NEWEST item (tail, not head)" 'printf "%s" "$out_g" | grep -q "guard item 15"'
check "length-guard drops oldest item" '! printf "%s" "$out_g" | grep -q "guard item 01"'

# (migrate_legacy tests removed in F3 — script retired.)

# count bugfix: empty hermes => clean single 0 (no "0\n0")
hempty="$work/empty"; mkdir -p "$hempty"
out_e="$("$scripts/session_close.sh" --memory-dir "$hempty" 2>/dev/null)"
check "empty fallback count is clean '0'" 'printf "%s" "$out_e" | grep -q "Fallback blocks total: 0$"'
check "no doubled-zero line" '[ "$(printf "%s" "$out_e" | grep -c "^0$")" -eq 0 ]'

# --------------------------------------------------------------- session_note
echo "test: session_note.sh (session journal)"
hsn="$work/sn"; mkdir -p "$hsn"
"$scripts/session_note.sh" --memory-dir "$hsn" --start "rebuild lapac journal" >/dev/null 2>&1
check "start creates session.md with goal block" '[ -f "$hsn/session.md" ] && grep -q "SESSION GOAL: rebuild lapac journal" "$hsn/session.md"'
check "goal is a canonical session block" '[ "$(grep -c "hermes:entry kind=session" "$hsn/session.md")" -eq 1 ]'
"$scripts/session_note.sh" --memory-dir "$hsn" --note "decided: session.md is raw, log.md is distilled" >/dev/null 2>&1
"$scripts/session_note.sh" --memory-dir "$hsn" --note "built session_note.sh" >/dev/null 2>&1
check "notes append as session blocks (3 total)" '[ "$(grep -c "hermes:entry kind=session" "$hsn/session.md")" -eq 3 ]'
# idempotent note
"$scripts/session_note.sh" --memory-dir "$hsn" --note "built session_note.sh" >/dev/null 2>&1
check "duplicate note not appended (still 3)" '[ "$(grep -c "hermes:entry kind=session" "$hsn/session.md")" -eq 3 ]'
# re-start archives previous journal
"$scripts/session_note.sh" --memory-dir "$hsn" --start "next session" >/dev/null 2>&1
check "re-start archives previous journal" '[ -d "$hsn/.session-archive" ] && [ "$(ls "$hsn/.session-archive" | wc -l | tr -d " ")" -ge 1 ]'
check "fresh journal has only the new goal" '[ "$(grep -c "hermes:entry kind=session" "$hsn/session.md")" -eq 1 ] && grep -q "next session" "$hsn/session.md"'
# --note auto-creates journal if missing
hsn2="$work/sn2"; mkdir -p "$hsn2"
"$scripts/session_note.sh" --memory-dir "$hsn2" --note "first note no start" >/dev/null 2>&1
check "note auto-creates session.md" '[ -f "$hsn2/session.md" ] && grep -q "first note no start" "$hsn2/session.md"'

# (kandidat tests removed in F3 — script retired; 2-occurrence candidates now live as tagged
#  CANDIDATE(type): lines in todo.md.)

# --------------------------------------------------------------- fallback --resolve (state flip)
echo "test: fallback_log.sh --resolve (exactly-one-match state flip)"
hfr="$work/fbres"
"$scripts/fallback_log.sh" --memory-dir "$hfr" --expected "A" --actual "B" --mechanism "mech1" >/dev/null 2>&1
"$scripts/fallback_log.sh" --memory-dir "$hfr" --expected "C" --actual "D" --mechanism "mech2" >/dev/null 2>&1
fid="$(grep -oE "id=[a-f0-9]+" "$hfr/fallbacks.md" | head -1 | cut -d= -f2)"
"$scripts/fallback_log.sh" --memory-dir "$hfr" --resolve "$fid" --status closed --note "resolved by test" >/dev/null 2>&1
check "resolve flips Status inside the block" 'grep -q "Status: closed (" "$hfr/fallbacks.md"'
check "other block stays open" 'grep -q "Status: open" "$hfr/fallbacks.md"'
set +e; "$scripts/fallback_log.sh" --memory-dir "$hfr" --resolve "zzzz" --status closed >/dev/null 2>&1; rc=$?; set -e
check "no match exits 2" '[ "$rc" -eq 2 ]'
set +e; "$scripts/fallback_log.sh" --memory-dir "$hfr" --resolve "" --status closed >/dev/null 2>&1; rc=$?; set -e
check "empty prefix (matches all = ambiguous) refused" '[ "$rc" -ne 0 ]'
set +e; "$scripts/fallback_log.sh" --memory-dir "$hfr" --resolve "$fid" --status nonsense >/dev/null 2>&1; rc=$?; set -e
check "unknown status exits 1" '[ "$rc" -eq 1 ]'

# (goqueue tests removed in F3 — script retired; GO queue never materialized in use.)

# --------------------------------------------------------------- ledger_carry --step (opt-in gate)
echo "test: ledger_carry.sh --step (distilled loop_write)"
hlk="$work/lk"; mkdir -p "$hlk"
"$scripts/ledger_carry.sh" --memory-dir "$hlk" --item "loop X" --step "call the supplier" >/dev/null 2>&1
check "--step appended as next step" 'grep -q "next step: call the supplier" "$hlk/todo.md"'
# marker back-compat: an OLD item carried with the CZ marker must still resolve via --done
printf -- '- [ ] old item — → další krok: finish\n' >> "$hlk/todo.md"
"$scripts/ledger_carry.sh" --memory-dir "$hlk" --done "old item" >/dev/null 2>&1
check "--done still resolves an item with the legacy CZ marker" 'grep -q -- "- \[x\] old item" "$hlk/todo.md"'
set +e; "$scripts/ledger_carry.sh" --memory-dir "$hlk" --item "Y" --step "   " >/dev/null 2>&1; rc=$?; set -e
check "whitespace-only --step rejected (exit 1)" '[ "$rc" -eq 1 ]'
# backward compat: --item without --step still works
"$scripts/ledger_carry.sh" --memory-dir "$hlk" --item "item without a step" >/dev/null 2>&1
check "--item without --step still works (backward compat)" 'grep -q "item without a step" "$hlk/todo.md"'

# ------------------------------------------- legacy alias --hermes-dir (pre-rename adopters, drop-in marketplace update)
echo "test: --hermes-dir legacy alias (backward compat)"
hla="$work/la"; mkdir -p "$hla"
"$scripts/session_note.sh" --hermes-dir "$hla" --start "alias test" >/dev/null 2>&1
check "session_note accepts --hermes-dir" 'grep -q "alias test" "$hla/session.md"'
"$scripts/ledger_carry.sh" --hermes-dir "$hla" --item "alias item" >/dev/null 2>&1
check "ledger_carry accepts --hermes-dir" 'grep -q "alias item" "$hla/todo.md"'
"$scripts/fallback_log.sh" --hermes-dir "$hla" --expected "e" --actual "a" --mechanism "m" --signal rule >/dev/null 2>&1
check "fallback_log accepts --hermes-dir" '[ -f "$hla/fallbacks.md" ] && grep -q "hermes:entry kind=fallback" "$hla/fallbacks.md"'

# ------------------------------------------------- 0.1.33 pre-publication audit fixes
echo "test: ledger_carry.sh --done indent-aware (gate counts indented items; --done must resolve them)"
hin="$work/indent"; mkdir -p "$hin"
printf '# Todo\n\n- [ ] parent item\n  - [ ] nested subtask\n' > "$hin/todo.md"
"$scripts/ledger_carry.sh" --memory-dir "$hin" --done "nested subtask" >/dev/null 2>&1
check "indented '- [ ]' resolved, indentation preserved" 'grep -q -- "^  - \[x\] nested subtask" "$hin/todo.md"'
check "sibling top-level item untouched" 'grep -q -- "^- \[ \] parent item" "$hin/todo.md"'

echo "test: hermes_lock stale-lock janitor (killed writer must not brick the file forever)"
hjl="$work/jl"; mkdir -p "$hjl/todo.md.lock"
touch -t 202501010000 "$hjl/todo.md.lock"
"$scripts/ledger_carry.sh" --memory-dir "$hjl" --item "after stale lock" >/dev/null 2>"$work/jl.err"
check "write succeeds after reclaiming a stale (backdated) lock" 'grep -q "after stale lock" "$hjl/todo.md"'
check "reclaim announced out loud (no silent steal)" 'grep -q "stale lock" "$work/jl.err"'
hjf="$work/jf"; mkdir -p "$hjf/todo.md.lock"   # FRESH lock = live writer; must NOT be stolen
set +e; HERMES_LOCK_TRIES=3 "$scripts/ledger_carry.sh" --memory-dir "$hjf" --item "x" >/dev/null 2>&1; rc=$?; set -e
check "fresh (live) lock not stolen — bounded retry then loud fail" '[ "$rc" -ne 0 ] && [ ! -f "$hjf/todo.md" ]'

echo "test: hermes_sha1 sha1sum fallback (minimal Linux without perl shasum)"
shim="$work/shim"; mkdir -p "$shim"
printf '#!/bin/sh\nexec shasum -a 1 "$@"\n' > "$shim/sha1sum"; chmod +x "$shim/sha1sum"
id_norm="$(bash -c '. "'"$scripts"'/lib/hermes_blocks.sh"; hermes_block_id kind key')"
id_fb="$(PATH="$shim:$PATH" bash -c 'command() { if [ "${1:-}" = "-v" ] && [ "${2:-}" = "shasum" ]; then return 1; fi; builtin command "$@"; }; . "'"$scripts"'/lib/hermes_blocks.sh"; hermes_block_id kind key')"
check "sha1sum branch yields the identical block id" '[ -n "$id_norm" ] && [ "$id_norm" = "$id_fb" ]'

echo
echo "backbone tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
