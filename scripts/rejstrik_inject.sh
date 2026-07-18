#!/usr/bin/env bash
# rejstrik_inject.sh — boot nerve: regenerate the atom registry from data, then inject it.
#
# Modeled on index_inject (regenerate-then-inject), NOT on a stored file: the registry is ALWAYS
# recomputed from the blocks before it is shown, so the boot map can never lie about what the
# instance knows. No "remember to regenerate on close" step — self-correcting by construction.
# Claude Code wires this through its opt-in fragment; Codex wires it by default from 0.3.11.
# Silent + harmless when there is no store yet.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
memory_dir="./memory"
while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir) memory_dir="${2:-./memory}"; shift 2 ;;
    *) shift ;;
  esac
done

have=0
for f in KNOWLEDGE.md CAN.md ZNALOST.md umim.md; do
  [ -f "$memory_dir/$f" ] && have=1
done
[ "$have" -eq 1 ] || exit 0   # no knowledge store yet — stay silent, never break boot

bash "$here/gen_rejstrik.sh" --memory-dir "$memory_dir" 2>/dev/null || true
reg="$memory_dir/_rejstrik.md"
[ -f "$reg" ] || exit 0

echo
echo "=== 🧭 REJSTŘÍK — co víš (atom registry; regenerováno z dat, nemůže lhát) ==="
echo
cat "$reg" 2>/dev/null || true
echo
echo "=== ↑ najdi relevantní atom → recall.sh --memory-dir $memory_dir <id> (NEČTI celý sklad) ==="
exit 0
