#!/usr/bin/env bash
# state_inject.sh — boot nerve: inject memory/STATE.md (orientation, read-first) into context at
# SessionStart. Info-injection > reminder: a cold instance gets orientation as a ready FACT, not
# a task to open a file. Promoted from cc_farky-local inline settings.json bash into the engine —
# a script is verifiable + declarable; an inline heredoc in settings.json is fragile escaping.
# Opt-in: wired via adapters/claude-code/settings-fragment.example.json, NOT force-wired
# (adopters must not inherit an invasive context injection across the trust boundary).
set -uo pipefail
MEMORY_DIR="./memory"
while [ $# -gt 0 ]; do case "${1:-}" in --memory-dir|--hermes-dir) MEMORY_DIR="${2:-./memory}"; shift 2 ;; *) shift ;; esac; done  # --hermes-dir = legacy alias
state_file="$MEMORY_DIR/STATE.md"
# 0.2.0 migration hail: upgraded but not yet migrated -> old STAV.md present, new STATE.md absent.
# Never break boot, but never fall back SILENTLY either (kernel rule) — tell them to migrate.
if [ ! -f "$state_file" ] && [ -f "$MEMORY_DIR/STAV.md" ]; then
  echo
  echo "=== ⚠️  FMC 0.2.0 vocabulary migration needed ==="
  echo "This memory/ still uses pre-0.2.0 names (STAV.md/ZNALOST.md/umim.md) — the 0.2.0 engine reads the"
  echo "renamed files, so your STATE.md orientation is NOT being injected. Run once:"
  echo "  bash \"\${CLAUDE_PLUGIN_ROOT:-<plugin-root>}/scripts/migrate_vocab.sh\" --memory-dir \"$MEMORY_DIR\""
  echo "=== (details: MIGRATION.md § 0.2.0) ==="
  exit 0
fi
[ -f "$state_file" ] || exit 0   # no STATE yet (fresh project) — stay silent, never break boot

echo
echo "=== STATE.md — ORIENTATION (injected; THIS is your single what-to-read-next source) ==="
echo
cat "$state_file" 2>/dev/null || true
echo
echo "=== ↑ follow the reading list INSIDE STATE.md above (not any other handoff) ==="
exit 0
