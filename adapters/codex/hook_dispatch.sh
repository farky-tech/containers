#!/usr/bin/env bash
# Codex lifecycle adapter for FMC.
#
# Codex launches matching command hooks concurrently. Keep the SessionStart nerves behind
# one dispatcher so recovery, initialization and context injection run in a deterministic
# order. The adapter is inert outside projects that explicitly carry memory/MEMORY.md.
set -uo pipefail

event="${1:-}"
plugin_root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
if [ -z "$plugin_root" ]; then
  plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd || true)"
fi

# Hook stdin is a single JSON object. Keep a bounded copy so it can be forwarded to scripts
# that need session_id or prompt text. A malformed/missing payload must never block Codex.
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

# Commands run with the session cwd. Walk upwards to support Codex launched from a repo
# subdirectory; the nearest memory/MEMORY.md is the explicit FMC adoption boundary.
project_dir="$(pwd -P 2>/dev/null || pwd)"
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
    printf 'FMC FALLBACK: Codex hook expected %s but it is missing under %s. Continuity is partial.\n' \
      "$script_name" "$plugin_root"
    return 0
  fi
  if ! bash "$script_path" "$@"; then
    printf 'FMC FALLBACK: Codex hook script %s failed. Continuity is partial.\n' "$script_name"
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

    # A managed root INDEX is the project's explicit opt-in to the whole-repo map.
    if [ -f "$project_dir/INDEX.md" ] && grep -qF "gen_index:auto" "$project_dir/INDEX.md"; then
      (cd "$project_dir" && run_script "index_inject.sh" --memory-dir "$memory_dir" --whole-repo)
    else
      (cd "$project_dir" && run_script "index_inject.sh" --memory-dir "$memory_dir")
    fi

    run_script "state_guard.sh" --fork-drift --marker "$memory_dir/.fmc-source"
    run_script "state_guard.sh" --adopter-drift --plugin-dir "$plugin_root" \
      --cache-dir "$(dirname "$plugin_root")"
    run_script "capability_report.sh" --startup --host codex --plugin-dir "$plugin_root" \
      --project-dir "$project_dir" --memory-dir "$memory_dir"
    ;;

  user-prompt-submit)
    # journal_prompt owns bounded parsing and secret redaction. Forward the original JSON.
    printf '%s' "$payload" | run_script "journal_prompt.sh" --memory-dir "$memory_dir"
    ;;

  pre-compact)
    printf '%s\n' \
      'FMC PreCompact: flush the live thread to memory/session.md and key orientation to memory/STATE.md before compaction.'
    ;;

  *)
    printf 'FMC FALLBACK: unknown Codex hook event "%s"; nothing ran.\n' "$event"
    ;;
esac

# Lifecycle advisory hooks must never block the Codex turn.
exit 0
