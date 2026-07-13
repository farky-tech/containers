#!/usr/bin/env bash
set -euo pipefail

# Audit declared container capabilities against the Claude Code plugin files.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
layout_override=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --layout)
      shift
      if [ "$#" -eq 0 ]; then
        echo "Missing value for --layout (plugin|repo)" >&2
        exit 2
      fi
      layout_override="$1"
      ;;
    --layout=*)
      layout_override="${1#--layout=}"
      ;;
    -h|--help)
      echo "Usage: bash scripts/capability_audit.sh [--layout plugin|repo]" >&2
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

case "$layout_override" in
  ""|plugin|repo) ;;
  *)
    echo "Invalid --layout value: $layout_override (expected plugin|repo)" >&2
    exit 2
    ;;
esac

plugin_root="$(cd "$script_dir/.." && pwd)"
repo_candidate="$(cd "$script_dir/../.." 2>/dev/null && pwd || printf '%s' "$plugin_root")"

if [ "$layout_override" = "repo" ]; then
  if [ -f "$repo_candidate/manifest.yaml" ]; then
    plugin_root="$repo_candidate"
  fi
elif [ -z "$layout_override" ] && [ ! -f "$plugin_root/manifest.yaml" ] && [ -f "$repo_candidate/manifest.yaml" ]; then
  plugin_root="$repo_candidate"
fi

manifest="$plugin_root/manifest.yaml"

if [ ! -f "$manifest" ]; then
  echo "Manifest not found: $manifest" >&2
  exit 1
fi

manifest_val() {
  key="$1"
  awk -v key="$key" '
    $0 ~ "^" key ":" {
      line = $0
      sub("^" key ":[[:space:]]*", "", line)
      sub("[[:space:]]*#.*$", "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      gsub(/^["\047]/, "", line)
      gsub(/["\047]$/, "", line)
      print line
      exit
    }
  ' "$manifest"
}

resolve_path() {
  p="$1"
  case "$p" in
    /*) printf '%s' "$p" ;;
    *) printf '%s/%s' "$plugin_root" "$p" ;;
  esac
}

layout="${layout_override:-plugin}"
if [ -z "$layout_override" ]; then
  if [ ! -d "$plugin_root/skills" ] && [ -d "$plugin_root/.claude/skills" ]; then
    layout="repo"
  fi
fi

if [ "$layout" = "repo" ]; then
  default_skills_dir=".claude/skills"
  default_agents_dir=".claude/agents"
  default_scripts_dir="scripts/hermes"
  default_hook_config=".claude/settings.json"
else
  default_skills_dir="skills"
  default_agents_dir="agents"
  default_scripts_dir="scripts"
  default_hook_config="hooks/hooks.json"
fi

skills_dir_rel="$(manifest_val skills_dir)"
agents_dir_rel="$(manifest_val agents_dir)"
scripts_dir_rel="$(manifest_val scripts_dir)"
hooks_json_rel="$(manifest_val hooks_json)"
settings_json_rel="$(manifest_val settings_json)"

skills_dir_rel="${skills_dir_rel:-$default_skills_dir}"
agents_dir_rel="${agents_dir_rel:-$default_agents_dir}"
scripts_dir_rel="${scripts_dir_rel:-$default_scripts_dir}"
if [ -n "$hooks_json_rel" ]; then
  hook_config_rel="$hooks_json_rel"
elif [ -n "$settings_json_rel" ]; then
  hook_config_rel="$settings_json_rel"
else
  hook_config_rel="$default_hook_config"
fi

skills_dir="$(resolve_path "$skills_dir_rel")"
agents_dir="$(resolve_path "$agents_dir_rel")"
scripts_dir="$(resolve_path "$scripts_dir_rel")"
hooks_json="$(resolve_path "$hook_config_rel")"

scripts_ref="$scripts_dir_rel"
case "$scripts_ref" in
  ./*) scripts_ref="${scripts_ref#./}" ;;
esac

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_string_array() {
  file="$1"
  first=1
  printf '['
  if [ -s "$file" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '"%s"' "$(json_escape "$line")"
    done < "$file"
  fi
  printf ']'
}

json_status_array() {
  file="$1"
  key="$2"
  first=1
  printf '['
  if [ -s "$file" ]; then
    while IFS='|' read -r name status; do
      [ -n "$name" ] || continue
      if [ "$first" -eq 0 ]; then
        printf ','
      fi
      first=0
      printf '{"%s":"%s","status":"%s"}' "$key" "$(json_escape "$name")" "$(json_escape "$status")"
    done < "$file"
  fi
  printf ']'
}

wired_hook_events() {
  if [ ! -f "$hooks_json" ]; then
    return
  fi
  awk '
    /^    "[^"]+"[[:space:]]*:/ {
      line = $0
      sub(/^    "/, "", line)
      sub(/".*/, "", line)
      print line
    }
  ' "$hooks_json"
}

declared_skills() {
  awk '
    /^capabilities:/ { in_capabilities = 1; next }
    /^claude_binding:/ { in_capabilities = 0; in_skills = 0 }
    in_capabilities && /^  skills:/ { in_skills = 1; next }
    in_skills && /^  [a-zA-Z_]+:/ { in_skills = 0 }
    in_skills && /^    - name:/ {
      line = $0
      sub(/^    - name:[[:space:]]*/, "", line)
      gsub(/"/, "", line)
      print line
    }
  ' "$manifest"
}

declared_agents() {
  awk '
    /^claude_binding:/ { in_binding = 1; next }
    in_binding && /^  agents:/ { in_agents = 1; next }
    in_agents && /^  verify:/ { in_agents = 0 }
    in_agents && /^    - name:/ {
      line = $0
      sub(/^    - name:[[:space:]]*/, "", line)
      gsub(/"/, "", line)
      print line
    }
  ' "$manifest"
}

declared_hooks() {
  awk '
    /^claude_binding:/ { in_binding = 1; next }
    in_binding && /^  hooks:/ { in_hooks = 1; next }
    in_hooks && /^  agents:/ { in_hooks = 0 }
    in_hooks && /^    - event:/ {
      event = $0
      sub(/^    - event:[[:space:]]*/, "", event)
      gsub(/"/, "", event)
    }
    in_hooks && /^[[:space:]]+status:/ {
      status = $0
      sub(/^[[:space:]]+status:[[:space:]]*/, "", status)
      gsub(/"/, "", status)
      if (event != "") {
        print event "|" status
        event = ""
      }
    }
  ' "$manifest"
}

declared_backbone_scripts() {
  awk '
    /^backbone_scripts:/ { inb = 1; next }
    inb && /^[a-zA-Z]/ { inb = 0 }
    inb && /^  lib:/ {
      line = $0
      sub(/^  lib:[[:space:]]*/, "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      gsub(/^[[:space:]]+/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      if (line != "") print line
      next
    }
    inb && /^  scripts:/ { insc = 1; next }
    inb && insc && /^  [a-zA-Z_]+:/ { insc = 0 }
    inb && insc && /^    - / {
      line = $0
      sub(/^    - /, "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      gsub(/^[[:space:]]+/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      if (line != "") print line
    }
  ' "$manifest"
}

declared_edges() {
  awk '
    /^edges:/ { ine = 1; next }
    ine && /^[a-zA-Z]/ { ine = 0 }
    ine && /from:/ {
      f = $0; sub(/.*from:[[:space:]]*/, "", f); sub(/[,}].*/, "", f); gsub(/[ ]/, "", f)
      t = $0; sub(/.*to:[[:space:]]*/, "", t); sub(/[}].*/, "", t); gsub(/[ ]/, "", t)
      if (f != "" && t != "") print f "\t" t
    }
  ' "$manifest"
}

# Classify one edge: SCRIPTED (source references target script) / PROSE (declared,
# not referenced) / BROKEN (target or source file absent).
classify_edge() {
  local from="$1" to="$2" ff="" tf scriptname
  case "$from" in
    skill/*)  ff="$skills_dir/${from#skill/}/SKILL.md" ;;
    agent/*)  ff="$agents_dir/${from#agent/}.md" ;;
    script/*) ff="$scripts_dir/${from#script/}" ;;
  esac
  tf="$scripts_dir/${to#script/}"
  scriptname="${to#script/}"
  if [ ! -f "$tf" ]; then printf 'BROKEN'; return; fi
  if [ -z "$ff" ] || [ ! -f "$ff" ]; then printf 'BROKEN'; return; fi
  # script->script edges: a script calls its sibling via "$script_dir/<name>", so a
  # path-qualified literal never appears — accept the bare filename here (it is code,
  # not prose; a false positive from a comment inside our own script is acceptable
  # and covered by tests). Plan-review 2026-07-05.
  if [ "${from%%/*}" = "script" ]; then
    if grep -qF "$scriptname" "$ff" 2>/dev/null; then printf 'SCRIPTED'; else printf 'PROSE'; fi
    return
  fi
  # Require a path-qualified reference (scripts/<name>), not a bare filename in prose,
  # so a comment or changelog mention cannot satisfy a declared edge as SCRIPTED.
  # Accept both the layout-configured path ("$scripts_ref/<name>", e.g. scripts/memory/X
  # in repo layout) AND the canonical logical form ("scripts/<name>") so a repo-layout
  # adopter whose SKILL.md keeps the plugin-style "scripts/X" reference still classifies
  # as SCRIPTED. (Plugin layout: scripts_ref == "scripts", so both checks coincide.)
  if grep -qF "$scripts_ref/$scriptname" "$ff" 2>/dev/null \
     || grep -qF "scripts/$scriptname" "$ff" 2>/dev/null; then printf 'SCRIPTED'; else printf 'PROSE'; fi
}

status_lines="$(mktemp "${TMPDIR:-/tmp}/hermes-audit-status.XXXXXX")"
skills_json="$(mktemp "${TMPDIR:-/tmp}/hermes-audit-skills.XXXXXX")"
agents_json="$(mktemp "${TMPDIR:-/tmp}/hermes-audit-agents.XXXXXX")"
hooks_json_lines="$(mktemp "${TMPDIR:-/tmp}/hermes-audit-hooks.XXXXXX")"
global_json="$(mktemp "${TMPDIR:-/tmp}/hermes-audit-global.XXXXXX")"
declared_hook_events_file="$(mktemp "${TMPDIR:-/tmp}/hermes-audit-declared-hooks.XXXXXX")"
declared_skills_file="$(mktemp "${TMPDIR:-/tmp}/hermes-audit-declared-skills.XXXXXX")"
declared_agents_file="$(mktemp "${TMPDIR:-/tmp}/hermes-audit-declared-agents.XXXXXX")"
trap 'rm -f "$status_lines" "$skills_json" "$agents_json" "$hooks_json_lines" "$global_json" "$declared_hook_events_file" "$declared_skills_file" "$declared_agents_file"' EXIT

drift_count=0

record_status() {
  kind="$1"
  name="$2"
  status="$3"
  line="$kind: $name -> $status"
  echo "$line" >> "$status_lines"
  case "$kind" in
    skill) echo "$name|$status" >> "$skills_json" ;;
    agent) echo "$name|$status" >> "$agents_json" ;;
    hook) echo "$name|$status" >> "$hooks_json_lines" ;;
  esac
  case "$status" in
    missing|DRIFT|DRIFT:*) drift_count=$((drift_count + 1)) ;;
  esac
}

while IFS= read -r skill; do
  [ -n "$skill" ] || continue
  echo "$skill" >> "$declared_skills_file"
  if [ -f "$skills_dir/$skill/SKILL.md" ]; then
    record_status "skill" "$skill" "active"
  else
    record_status "skill" "$skill" "missing"
  fi
done <<EOF_SKILLS
$(declared_skills)
EOF_SKILLS

while IFS= read -r agent; do
  [ -n "$agent" ] || continue
  echo "$agent" >> "$declared_agents_file"
  if [ -f "$agents_dir/$agent.md" ]; then
    record_status "agent" "$agent" "active"
  else
    record_status "agent" "$agent" "missing"
  fi
done <<EOF_AGENTS
$(declared_agents)
EOF_AGENTS

while IFS='|' read -r event status; do
  [ -n "$event" ] || continue
  echo "$event" >> "$declared_hook_events_file"
  wired=0
  if [ -f "$hooks_json" ] && grep -q "\"$event\"" "$hooks_json"; then
    wired=1
  fi

  if [ "$status" = "active" ]; then
    if [ "$wired" -eq 1 ]; then
      record_status "hook" "$event" "active"
    else
      record_status "hook" "$event" "DRIFT: declared active but not wired"
    fi
  elif [ "$status" = "spec-only" ]; then
    if [ "$wired" -eq 1 ]; then
      record_status "hook" "$event" "DRIFT: spec-only but wired"
    else
      record_status "hook" "$event" "spec-only"
    fi
  elif [ "$status" = "retired" ]; then
    # retired = deliberately decommissioned (0.1.33: Stop nag). Being wired anyway IS drift.
    if [ "$wired" -eq 1 ]; then
      record_status "hook" "$event" "DRIFT: retired but wired"
    else
      record_status "hook" "$event" "retired"
    fi
  else
    record_status "hook" "$event" "DRIFT: unknown status $status"
  fi
done <<EOF_HOOKS
$(declared_hooks)
EOF_HOOKS

while IFS= read -r wired_event; do
  [ -n "$wired_event" ] || continue
  if ! grep -qx "$wired_event" "$declared_hook_events_file"; then
    record_status "hook" "$wired_event" "DRIFT: wired but not declared"
  fi
done <<EOF_WIRED_HOOKS
$(wired_hook_events)
EOF_WIRED_HOOKS

# Reverse (bidirectional) check for skills/agents: a file ON DISK not declared in the manifest
# is drift — mirrors the "wired but not declared" hook check above. Plugin-internal scope only
# (skills_dir/agents_dir resolved from manifest); host ~/.claude stays OUT OF SCOPE (note below).
if [ -d "$skills_dir" ]; then
  for _sd in "$skills_dir"/*/; do
    [ -f "${_sd}SKILL.md" ] || continue
    _sn="$(basename "$_sd")"
    grep -qx "$_sn" "$declared_skills_file" 2>/dev/null || record_status "skill" "$_sn" "DRIFT: on disk but not declared"
  done
fi
if [ -d "$agents_dir" ]; then
  for _ad in "$agents_dir"/*.md; do
    [ -f "$_ad" ] || continue
    _an="$(basename "$_ad" .md)"
    grep -qx "$_an" "$declared_agents_file" 2>/dev/null || record_status "agent" "$_an" "DRIFT: on disk but not declared"
  done
fi

# Forward drift for backbone_scripts (lib + scripts list): declared skills/agents already
# flag "declared but missing on disk" via the `missing` branch above (record_status counts
# it into drift_count) — that path already worked. backbone_scripts.{lib,scripts} entries
# did NOT: they were only ever checked incidentally, as a side effect of appearing as an
# edges: target (classify_edge -> BROKEN). Several backbone scripts have no edge at all
# (session_note.sh, state_guard.sh, state_inject.sh,
# capability_inject.sh, index_inject.sh, gen_index.sh, journal_prompt.sh) — deleting or
# renaming one of those left drift_count at 0. Verified naostro before this fix (fixture
# with a `- scripts/ghost_script.sh` entry produced zero signal). Closes that gap directly
# against the manifest's own backbone_scripts declaration, independent of edges:.
while IFS= read -r bscript; do
  [ -n "$bscript" ] || continue
  bpath="$(resolve_path "$bscript")"
  if [ -f "$bpath" ]; then
    record_status "backbone" "$bscript" "active"
  else
    record_status "backbone" "$bscript" "DRIFT: declared but missing on disk"
  fi
done <<EOF_BACKBONE
$(declared_backbone_scripts)
EOF_BACKBONE

# Adapter hook->script edges (settings-fragment.example.json is NOT modeled in manifest
# edges: — a separate hand-maintained edge list would itself be a second copy that can
# drift from the fragment, so instead parse the fragment directly: it is the single real
# source of which scripts Claude Code hook commands actually invoke). Extract every
# path-qualified "scripts/<name>.sh" reference (path-qualified = must contain the
# "scripts/" segment, so a bare filename mention in prose cannot satisfy this) and check
# the target exists under scripts_dir. A renamed/deleted script still referenced by a hook
# command now shows up as drift instead of staying silent. Missing fragment file (e.g. a
# repo-layout host that never copied adapters/) is not itself drift — this check degrades
# quietly, matching the gen_agents.sh / lapac-sync pattern elsewhere in this script.
adapter_fragment="$(resolve_path "adapters/claude-code/settings-fragment.example.json")"
if [ -f "$adapter_fragment" ]; then
  while IFS= read -r aref; do
    [ -n "$aref" ] || continue
    asname="${aref#scripts/}"
    if [ -f "$scripts_dir/$asname" ]; then
      record_status "adapter" "$aref" "wired"
    else
      record_status "adapter" "$aref" "DRIFT: adapter references missing script"
    fi
  done <<EOF_ADAPTER
$(grep -oE 'scripts/[A-Za-z0-9_]+\.sh' "$adapter_fragment" | sort -u)
EOF_ADAPTER
fi

# Global host-config drift (e.g. a global SessionStart hook naming agents that do
# not exist in ~/.claude/agents/) is intentionally OUT OF SCOPE for this plugin
# verifier. It cannot reliably parse arbitrary agent names from free-form hook
# command text, and auditing the user's global config is a separate concern from
# verifying THIS plugin's declared-vs-actual consistency. global_drift stays empty;
# host-config drift is handled explicitly outside the plugin.

# ---- Interop graph (R6): classify declared edges, score wiring ----------------
auto_count=0; scripted_count=0; prose_count=0; broken_count=0
edge_json_lines="$(mktemp "${TMPDIR:-/tmp}/hermes-audit-edges.XXXXXX")"
# Single cumulative trap: a second `trap … EXIT` OVERRIDES the first (audit 2026-07-11 —
# the original override silently leaked declared_skills_file + declared_agents_file on every run).
trap 'rm -f "$status_lines" "$skills_json" "$agents_json" "$hooks_json_lines" "$global_json" "$declared_hook_events_file" "$declared_skills_file" "$declared_agents_file" "$edge_json_lines"' EXIT

# AUTO = hooks actually wired into hooks.json (real runtime triggers).
while IFS= read -r wired_event; do
  [ -n "$wired_event" ] || continue
  auto_count=$((auto_count + 1))
done <<EOF_AUTO
$(wired_hook_events)
EOF_AUTO

efirst=1
while IFS=$'\t' read -r efrom eto; do
  [ -n "$efrom" ] || continue
  cls="$(classify_edge "$efrom" "$eto")"
  case "$cls" in
    SCRIPTED) scripted_count=$((scripted_count + 1)) ;;
    PROSE)    prose_count=$((prose_count + 1)); drift_count=$((drift_count + 1)) ;;
    BROKEN)   broken_count=$((broken_count + 1)); drift_count=$((drift_count + 1)) ;;
  esac
  [ "$efirst" -eq 0 ] && printf ',' >> "$edge_json_lines"
  efirst=0
  printf '{"from":"%s","to":"%s","class":"%s"}' \
    "$(json_escape "$efrom")" "$(json_escape "$eto")" "$cls" >> "$edge_json_lines"
done <<EOF_EDGES
$(declared_edges)
EOF_EDGES

# Generated agents/ must match scripts/gen_agents.sh output (no hand-drift).
gen_status="ok"
if [ -x "$scripts_dir/gen_agents.sh" ]; then
  if ! "$scripts_dir/gen_agents.sh" --check >/dev/null 2>&1; then
    gen_status="DRIFT"
    drift_count=$((drift_count + 1))
  fi
fi

# lapac sync status: canonical lives in ~/.claude/skills/lapac (maintainer-only).
# Plugin carries its own copy; report sync state without failing on a clean host.
lapac_sync="maintainer-skip"
lapac_canon="${HOME:-/nonexistent}/.claude/skills/lapac/SKILL.md"
lapac_copy="$skills_dir/lapac/SKILL.md"
if [ -f "$lapac_canon" ] && [ -f "$lapac_copy" ]; then
  if diff -q "$lapac_canon" "$lapac_copy" >/dev/null 2>&1; then
    lapac_sync="synced"
  else
    lapac_sync="drift"
  fi
fi

# ---- Stale capability references (closes the M4 gap the sweep found) ----------
# (a) related_skills frontmatter must point to skills that still exist on disk.
for sk in "$skills_dir"/*/SKILL.md; do
  [ -f "$sk" ] || continue
  rel="$(awk -F'[][]' '/related_skills:/{print $2}' "$sk" | tr ',' '\n' | tr -d '" ')"
  for r in $rel; do
    [ -n "$r" ] || continue
    if [ ! -d "$skills_dir/$r" ]; then
      record_status "ref" "related_skills:$r ($(basename "$(dirname "$sk")"))" "DRIFT: points to missing skill"
    fi
  done
done
# (b) .codex-plugin capability list count must match skills on disk (catches the
# Codex-facing drift a Claude-only check used to miss).
# HONESTY NOTE: this is COUNT-ONLY. It compares list LENGTH, not per-capability identity
# or VERSION — two lists of equal size that name different skills, or a Codex manifest
# that is 5 versions behind (same headcount, stale content), both read as "in sync" here.
# Codex-side plugin distribution/version sync is Farky's maintainer domain (out of scope
# for this verifier) — do not read "drift 0" from this check as "Codex is up to date",
# only as "same number of entries." Echoed explicitly below so the report cannot imply more
# than it checks.
skills_n=0
if [ -d "$skills_dir" ]; then
  skills_n="$(find "$skills_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
fi
codex_caps_n=""
if [ -f "$plugin_root/.codex-plugin/plugin.json" ]; then
  codex_caps_n="$(awk '/"capabilities":/{f=1;next} f&&/\]/{f=0} f&&/"/{c++} END{print c+0}' "$plugin_root/.codex-plugin/plugin.json" 2>/dev/null)"
fi
if [ -n "$codex_caps_n" ] && [ "$codex_caps_n" != "$skills_n" ]; then
  record_status "ref" ".codex-plugin capabilities=$codex_caps_n vs skills=$skills_n" "DRIFT: codex capability list out of sync"
fi

echo "Container capability audit"
echo "Plugin root: $plugin_root"
echo
echo "Declared capability status:"
if [ -s "$status_lines" ]; then
  sed 's/^/- /' "$status_lines"
else
  echo "- none"
fi
echo
echo "Interop score (declared edges):"
echo "- AUTO (wired hooks): $auto_count"
echo "- SCRIPTED (source calls script): $scripted_count"
echo "- PROSE (declared, not wired): $prose_count"
echo "- BROKEN (target/source missing): $broken_count"
echo "- agents/ generation: $gen_status"
echo "- lapac sync: $lapac_sync"
echo "- codex-plugin capability check: count-only (version not compared — maintainer domain), skills=$skills_n codex=${codex_caps_n:-n/a}"
echo
echo "Drift count: $drift_count"
echo
echo '```json'
printf '{\n'
printf '  "skills": '
json_status_array "$skills_json" "name"
printf ',\n'
printf '  "agents": '
json_status_array "$agents_json" "name"
printf ',\n'
printf '  "hooks": '
json_status_array "$hooks_json_lines" "event"
printf ',\n'
printf '  "global_drift": '
json_string_array "$global_json"
printf ',\n'
printf '  "interop": {"auto":%s,"scripted":%s,"prose":%s,"broken":%s,"agents_gen":"%s","lapac_sync":"%s"},\n' \
  "$auto_count" "$scripted_count" "$prose_count" "$broken_count" "$gen_status" "$lapac_sync"
printf '  "edges": ['
cat "$edge_json_lines"
printf '],\n'
printf '  "drift_count": %s\n' "$drift_count"
printf '}\n'
echo '```'

if [ "$drift_count" -eq 0 ]; then
  exit 0
fi

exit 1
