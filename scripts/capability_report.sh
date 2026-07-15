#!/usr/bin/env bash
# capability_report.sh — adopter-facing self-report: which FMC capabilities are WIRED on this
# project vs. which are OFFERED but never turned on. This closes FMC's OWN silent-fallback gap:
# a boot nerve is opt-in (trust boundary — never force-wired), so an adopter who never wired it
# runs half a container and nobody says so — the hole is found by accident. This makes the
# container SAY it. Read-only; never writes; never blocks a session; quiet when everything is on.
#
# "OFFERED" is derived from the selected host adapter — never from a hardcoded parallel list.
# Claude Code reads settings-fragment.example.json; Codex reads the scripts actually dispatched by
# adapters/codex/hook_dispatch.sh. "WIRED" means the host adapter references the nerve. For Codex,
# this report itself runs only after hook trust, so a running startup report is also execution proof.
# Honest boundary (0.1.33 audit): "wired" is a settings-TEXT check, not an execution proof —
# a hook whose path does not resolve still counts as wired here. The root fix for that trap is
# the fragment defaulting to ${CLAUDE_PLUGIN_ROOT} (resolves wherever the plugin lives); this
# report deliberately stays a cheap read-only signal, not a runtime prober.
#
# Modes:
#   --startup   SessionStart advisory: "N of M wired; missing: <human names>". SILENT if all wired.
#               Safe to force-wire into the kernel (read-only, never writes, never blocks).
#   --close     close report: what was available this session + what is still not wired + an
#               ADOPTION-ready line to report a gap upstream (self-hail instead of silent gap).
#   --status    raw wired/offered/missing breakdown (debug/tests).
#   [--plugin-dir <dir>]   default: this script's ../  (works from cache-install OR in-repo)
#   [--project-dir <dir>]  default: $CLAUDE_PROJECT_DIR or .
#   [--memory-dir <dir>]   default: <project-dir>/memory  (reserved; close usage evidence)
#   [--instance <name>]    label for the ADOPTION line (default: from dir name)
#   [--host claude|codex]  adapter to inspect (default: codex when PLUGIN_ROOT is set, else claude)
# Env: HERMES_FAKE_TS (deterministic date in the ADOPTION line, for tests).
set -uo pipefail

mode="" plugin_dir="" project_dir="" memory_dir="" instance="" host=""
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --startup) mode="startup"; shift ;;
    --close)   mode="close"; shift ;;
    --status)  mode="status"; shift ;;
    --plugin-dir)  plugin_dir="${2:-}"; shift 2 ;;
    --project-dir) project_dir="${2:-}"; shift 2 ;;
    --memory-dir)  memory_dir="${2:-}"; shift 2 ;;
    --instance)    instance="${2:-}"; shift 2 ;;
    --host)        host="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$mode" ] || { echo "capability_report: need --startup / --close / --status" >&2; exit 1; }

if [ -z "$host" ]; then
  if [ -n "${PLUGIN_ROOT:-}" ]; then host="codex"; else host="claude"; fi
fi
case "$host" in
  claude|codex) ;;
  *) echo "capability_report: --host must be claude or codex" >&2; exit 2 ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "$plugin_dir" ]  || plugin_dir="$(cd "$script_dir/.." && pwd)"
[ -n "$project_dir" ] || project_dir="${CLAUDE_PROJECT_DIR:-.}"
[ -n "$memory_dir" ]  || memory_dir="$project_dir/memory"
[ -n "$instance" ]    || instance="$(basename "$project_dir" 2>/dev/null || echo '<your-instance>')"

settings="$project_dir/.claude/settings.json"
settings_local="$project_dir/.claude/settings.local.json"
codex_dispatch="$plugin_dir/adapters/codex/hook_dispatch.sh"
codex_hooks="$plugin_dir/adapters/codex/hooks.json"
codex_manifest="$plugin_dir/.codex-plugin/plugin.json"

# OFFERED = scripts named by the selected host adapter (its real execution source of truth).
if [ "$host" = "codex" ]; then
  offered="$(grep -oE 'run_script[[:space:]]+"[a-z_]+\.sh"' "$codex_dispatch" 2>/dev/null \
    | sed -E 's/.*"([a-z_]+)\.sh"/\1/' | grep -v '^capability_report$' | sort -u)"
else
  fragment="$plugin_dir/adapters/claude-code/settings-fragment.example.json"
  offered="$(grep -oE 'scripts/[a-z_]+\.sh' "$fragment" 2>/dev/null \
    | sed 's#scripts/##; s#\.sh##' | sort -u)"
fi
# No fragment / nothing declared → stay silent, never break the boot. (Also true on a source
# checkout without adapters/, or a trimmed install.)
[ -n "$offered" ] || exit 0

is_wired() { # script-basename → 0 if referenced by the selected active host adapter
  if [ "$host" = "codex" ]; then
    grep -qF '"hooks": "./adapters/codex/hooks.json"' "$codex_manifest" 2>/dev/null \
      && grep -qF 'hook_dispatch.sh' "$codex_hooks" 2>/dev/null \
      && grep -qE "run_script[[:space:]]+\"$1\.sh\"" "$codex_dispatch" 2>/dev/null
    return
  fi
  grep -q "scripts/$1\.sh" "$settings" 2>/dev/null && return 0
  grep -q "scripts/$1\.sh" "$settings_local" 2>/dev/null && return 0
  return 1
}

# Human label so the report reads for a person, not as a filename.
human() {
  case "$1" in
    state_inject)      echo "memory orientation at boot (STATE)" ;;
    capability_inject) echo "capability overview + drift" ;;
    index_inject)      echo "folder map at boot" ;;
    journal_prompt)    echo "session journal capture" ;;
    close_state)       echo "close recovery (unfinished session)" ;;
    brain_health)      echo "weekly brain health" ;;
    state_guard)       echo "version drift guard" ;;
    *)                 echo "$1" ;;
  esac
}

# Partition offered into wired / missing (preserve order, count).
wired_list="" missing_list="" n_off=0 n_wired=0
while IFS= read -r s; do
  [ -n "$s" ] || continue
  n_off=$((n_off + 1))
  if is_wired "$s"; then n_wired=$((n_wired + 1)); wired_list="$wired_list $s"
  else missing_list="$missing_list $s"; fi
done <<EOF
$offered
EOF

case "$mode" in
  startup)
    # Silent on a healthy (fully wired) setup — no noise when nothing is missing.
    [ -z "$missing_list" ] && exit 0
    echo "=== FMC — capabilities: $n_wired of $n_off wired ==="
    echo "Available but NOT wired (nobody reports these for you — now you see them):"
    for s in $missing_list; do printf '  · %s\n' "$(human "$s")"; done
    if [ "$host" = "codex" ]; then
      echo "→ update the FMC Codex adapter, then review/trust its exact hook definitions via /hooks"
    else
      echo "→ wire them via the /using-container skill or adapters/claude-code/settings-fragment.example.json"
    fi
    ;;
  close)
    echo "=== FMC self-report — what was available this session ==="
    if [ -n "$wired_list" ]; then
      printf 'Wired:'; for s in $wired_list; do printf ' %s ·' "$(human "$s")"; done; echo
    fi
    if [ -n "$missing_list" ]; then
      printf 'NOT wired (available):'; for s in $missing_list; do printf ' %s ·' "$(human "$s")"; done; echo
      d="${HERMES_FAKE_TS%%T*}"; [ -n "$d" ] || d="$(date +%Y-%m-%d 2>/dev/null || echo '<date>')"
      echo "→ was anything from FMC missing or broken? report it to the source ADOPTION.md. Ready-made line:"
      echo "    ### $d — \`$instance\`: FMC self-report — $n_wired/$n_off nerves wired; not wired:$missing_list"
    else
      echo "Everything wired — full FMC."
    fi
    ;;
  status)
    echo "offered=$n_off wired=$n_wired"
    echo "wired:$wired_list"
    echo "missing:$missing_list"
    ;;
esac
exit 0
