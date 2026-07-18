#!/usr/bin/env bash
# Claude Code lifecycle adapter for FMC.
#
# Mirror of adapters/codex/hook_dispatch.sh for the Claude Code host. Keeps the SessionStart
# nerves behind one dispatcher so recovery, initialization and context injection run in a
# deterministic order (Claude may launch matching command hooks concurrently). The adapter is
# INERT outside projects that explicitly carry memory/MEMORY.md — installing the plugin does not
# seed a brain into every repo; the brain wakes only where a brain was set up. This is the SHIP
# default (hooks/hooks.json calls it), so a Claude adopter gets a working brain on install, at
# parity with the Codex adapter — no manual settings-fragment paste ("later = never").
#
# The nerve CHAIN below is the adopter set and MUST stay in step with the Codex dispatcher's
# session-start chain (SSOT by convention — the two hosts differ only in lifecycle events, not in
# which nerves fire). Maintainer-only nerves (release-drift / book-drift / novinky) are NOT here —
# they live in the meta-hub's own settings.json, never shipped to adopters.
set -uo pipefail

event="${1:-}"
plugin_root="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}"
if [ -z "$plugin_root" ]; then
  plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd || true)"
fi

# Hook stdin is a single JSON object. Keep a bounded copy so it can be forwarded to scripts that
# need session_id or prompt text. A malformed/missing payload must never block the turn.
payload=""
while [ "${#payload}" -lt 262144 ]; do
  line=""
  if IFS= read -r -t 2 line; then
    payload="${payload}${line}"$'\n'
  else
    [ -n "$line" ] && payload="${payload}${line}"
    break
  fi
done

# The gate: nearest memory/MEMORY.md walking up from the session cwd is the explicit FMC adoption
# boundary. No marker → this project never adopted a brain → do nothing (exit 0, silent).
# Canonicalize to a PHYSICAL ABSOLUTE path first (Codex adapter does the same via pwd -P): a
# relative CLAUDE_PROJECT_DIR (".", a subdir) would make the walk-up loop forever (dirname "." == "."),
# and a symlinked path would walk lexical parents instead of the real ones and miss the marker.
project_dir="$(cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null && pwd -P || pwd -P)"
probe="$project_dir"
while [ "$probe" != "/" ] && [ ! -f "$probe/memory/MEMORY.md" ]; do
  probe="$(dirname "$probe")"
done
if [ ! -f "$probe/memory/MEMORY.md" ]; then
  exit 0
fi
project_dir="$probe"
memory_dir="$project_dir/memory"

run_script() {
  local script_name="$1"
  shift
  local script_path="$plugin_root/scripts/$script_name"
  if [ ! -f "$script_path" ]; then
    printf 'FMC FALLBACK: Claude hook expected %s but it is missing under %s. Continuity is partial.\n' \
      "$script_name" "$plugin_root"
    return 0
  fi
  if ! bash "$script_path" "$@"; then
    printf 'FMC FALLBACK: Claude hook script %s failed. Continuity is partial.\n' "$script_name"
  fi
  return 0
}

case "$event" in
  session-start)
    printf '%s\n' \
      'FMC active (farky-memory-container).' \
      'You have a brain — this container: what you did, learned, decided AND WHY, where you left off. It is you, not a drawer.' \
      'One brain, one line: no second memory system beside it; your experience and decisions live here and nowhere else.' \
      'Self-contained: it tends itself — read yourself back at start, seal yourself at close.' \
      'Silent work is good. Silent fallback is forbidden.'

    # Recover prior close debt before marking the current session active.
    run_script "close_state.sh" --memory-dir "$memory_dir" --boot-recovery
    printf '%s' "$payload" | run_script "close_state.sh" --memory-dir "$memory_dir" --init

    run_script "brain_health.sh" --memory-dir "$memory_dir" --due-check
    run_script "state_inject.sh" --memory-dir "$memory_dir"
    run_script "capability_inject.sh" --memory-dir "$memory_dir"
    run_script "rejstrik_inject.sh" --memory-dir "$memory_dir"
    run_script "pending_inject.sh" --memory-dir "$memory_dir"

    # A managed root INDEX is the project's explicit opt-in to the whole-repo map.
    if [ -f "$project_dir/INDEX.md" ] && grep -qF "gen_index:auto" "$project_dir/INDEX.md"; then
      (cd "$project_dir" && run_script "index_inject.sh" --memory-dir "$memory_dir" --whole-repo)
    else
      (cd "$project_dir" && run_script "index_inject.sh" --memory-dir "$memory_dir")
    fi

    run_script "state_guard.sh" --fork-drift --marker "$memory_dir/.fmc-source"
    run_script "state_guard.sh" --adopter-drift --plugin-dir "$plugin_root" \
      --cache-dir "$(dirname "$plugin_root")"
    run_script "capability_report.sh" --startup --host claude --plugin-dir "$plugin_root" \
      --project-dir "$project_dir" --memory-dir "$memory_dir"
    ;;

  user-prompt-submit)
    # Both nerves own bounded parsing. Journal first so the black box is durable even when recall
    # stays silent; then recall may emit task-relevant pointers into model context.
    printf '%s' "$payload" | run_script "journal_prompt.sh" --memory-dir "$memory_dir"
    printf '%s' "$payload" | run_script "recall_inject.sh" --memory-dir "$memory_dir"
    ;;

  session-end)
    # Finalize the close-debt tracker: work + no conscious close leaves an UNCLOSED marker for the
    # next boot's --boot-recovery to surface. (Claude-only lifecycle event; Codex has no analogue.)
    printf '%s' "$payload" | run_script "close_state.sh" --memory-dir "$memory_dir" --session-end
    ;;

  pre-compact)
    printf '%s\n' \
      'FMC PreCompact: flush the live thread to memory/session.md and key orientation to memory/STATE.md before compaction.'
    ;;

  *)
    printf 'FMC FALLBACK: unknown Claude hook event "%s"; nothing ran.\n' "$event"
    ;;
esac

# Lifecycle advisory hooks must never block the Claude turn.
exit 0
