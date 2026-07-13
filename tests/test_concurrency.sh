#!/usr/bin/env bash
# test_concurrency.sh — proves the mutual-exclusion lock in hermes_blocks.sh
# (hermes_lock/hermes_unlock) actually serializes concurrent appends.
#
# hermes_blocks.sh's own header claims: "Two parallel sessions cannot lose an
# append ... last-write-wins is forbidden." Nothing in the existing suite checks
# that claim directly — test_close_state.sh's "concurrency" case only asserts a
# fixed line count after 8 parallel *reads* of an unchanged journal, which the
# atomic mktemp+mv write alone already guarantees, with or without a lock.
#
# This test drives real concurrent *appends* (via the real backbone caller
# ledger_carry.sh -> hermes_append_block) at the same file, and separately
# proves the test is discriminating: with hermes_lock neutered on a throwaway
# COPY of the lib, the identical scenario loses appends. If it didn't, this
# suite would be exactly as toothless as the one it's meant to backstop.
#
# Zero-dep bash. Run: bash tests/test_concurrency.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SCRIPTS="$here/../scripts"
LEDGER="$REPO_SCRIPTS/ledger_carry.sh"
LIB="$REPO_SCRIPTS/lib/hermes_blocks.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

N=30

# helper: fire N parallel `ledger_carry.sh --item <unique>` calls at the same
# todo.md under $1, using ledger binary $2. Each item text is unique so no
# id-based dedup (hermes_has_block) masks a lost append as "already there".
fire_parallel() { # mem_dir ledger_bin label
  local dir="$1" ledger="$2" label="$3" i
  mkdir -p "$dir"
  for i in $(seq 1 "$N"); do
    ( bash "$ledger" --memory-dir "$dir" --item "concurrency-${label}-item-${i}" </dev/null >/dev/null 2>&1 ) &
  done
  wait
}

echo "== 1. real lock: $N parallel appends -> all $N blocks present (no lost update) =="
REAL="$T/real"
fire_parallel "$REAL" "$LEDGER" "real"
. "$LIB"   # for hermes_count_blocks, on the untouched original lib
real_count="$(hermes_count_blocks "$REAL/todo.md" todo)"
[ "$real_count" -eq "$N" ] && ok "all $N appends survived concurrency ($real_count/$N)" \
  || bad "lost update under real lock: only $real_count/$N blocks present"

echo "== 2. real lock: no stale lock dirs or tmp files left behind =="
stale_locks="$(find "$REAL" -iname '*.lock' 2>/dev/null | wc -l | tr -d ' ')"
stale_tmps="$(find "$REAL" -iname '.hermes-aw.*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$stale_locks" -eq 0 ] && [ "$stale_tmps" -eq 0 ] \
  && ok "no stale .lock dirs or .hermes-aw.* tmp files" \
  || bad "leftovers: $stale_locks lock dir(s), $stale_tmps tmp file(s)"

echo "== 3. discrimination check: neuter hermes_lock on a COPY of the lib -> same scenario loses appends =="
# Copy the backbone (script + lib) into a throwaway dir, preserving the
# relative scripts/lib/ layout ledger_carry.sh sources by BASH_SOURCE. The
# REAL repo lib is never touched.
LOCKOFF="$T/lockoff"
mkdir -p "$LOCKOFF/scripts/lib"
cp "$LEDGER" "$LOCKOFF/scripts/ledger_carry.sh"
cp "$LIB" "$LOCKOFF/scripts/lib/hermes_blocks.sh"
# A later function definition in the same sourced file wins at call time in
# bash, so appending a no-op override is a clean, surgical neutering — no
# line-editing of the original function body required.
printf '\nhermes_lock() { return 0; }\n' >> "$LOCKOFF/scripts/lib/hermes_blocks.sh"

LOCKOFF_MEM="$T/lockoff-mem"
fire_parallel "$LOCKOFF_MEM" "$LOCKOFF/scripts/ledger_carry.sh" "lockoff"
lockoff_count="$(hermes_count_blocks "$LOCKOFF_MEM/todo.md" todo)"
if [ "$lockoff_count" -lt "$N" ]; then
  ok "lock-disabled copy LOST appends ($lockoff_count/$N survived) -> this suite is discriminating, not a rubber stamp"
else
  bad "lock-disabled copy kept all $N appends -> race did not manifest, test would NOT catch a broken lock (re-run or raise N)"
fi

echo ""
echo "== test_concurrency: $pass passed, $fail failed =="
echo "   (real lock: $real_count/$N blocks · lock-disabled control: $lockoff_count/$N blocks)"
[ "$fail" -eq 0 ]
