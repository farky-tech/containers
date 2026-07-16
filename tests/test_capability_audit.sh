#!/usr/bin/env bash
# test_capability_audit.sh — reverse (bidirectional) drift detection: a skill/agent that
# is PHYSICALLY ON DISK but NOT declared in manifest.yaml must be flagged as drift.
# Exercises scripts/capability_audit.sh ~L366-382 ("on disk but not declared"), which
# until now was only ever verified by hand, not by an automated test.
#
# Also exercises FORWARD drift (declared in manifest.yaml but MISSING on disk) for
# backbone_scripts entries, and adapter hook->script wiring (settings-fragment.example.json
# references a script that no longer exists). An audit dogfooding itself found that
# backbone_scripts.{lib,scripts} entries and adapter-fragment script references had no
# forward check at all — a renamed/deleted script could silently vanish with drift_count
# staying 0 (skill/agent forward drift already worked via the `missing` status branch;
# these two did not). See scripts/capability_audit.sh comments at the backbone/adapter
# checks for the naostro-verified gap this closes.
#
# capability_audit.sh derives plugin_root from its own location (script_dir/..) and has
# no --root override, so this test builds a throwaway FIXTURE mini-plugin: a copy of the
# audit script placed inside fixture/scripts/, with its own manifest.yaml + skills/ +
# agents/. The fixture deliberately omits scripts/gen_agents.sh so the "agents/ byte-
# matches generated output" check (`if [ -x "$scripts_dir/gen_agents.sh" ]`, ~L423) never
# fires — that check is orthogonal to reverse-drift and would otherwise require a byte-
# identical subagents/<name>.md body just to keep the baseline at zero drift.
#
# Zero-dep, hermetic: everything runs against a throwaway mktemp -d fixture.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(cd "$here/.." && pwd)"
audit_src="$plugin_root/scripts/capability_audit.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/hermes-capaudit-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT

pass=0; fail=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# ---------------------------------------------------------------- fixture mini-plugin
fx="$work/fixture"
mkdir -p "$fx/scripts/lib" "$fx/skills/alpha" "$fx/agents" "$fx/adapters/claude-code" \
  "$fx/adapters/codex" "$fx/.codex-plugin"
cp "$audit_src" "$fx/scripts/capability_audit.sh"
chmod +x "$fx/scripts/capability_audit.sh"

# manifest declares exactly 1 skill (alpha), 1 agent (a1), 2 backbone_scripts entries
# (lib + 1 script) — baseline must match disk 1:1.
cat > "$fx/manifest.yaml" <<'EOF'
name: fixture-plugin
status: local-draft
capabilities:
  skills:
    - name: alpha
      trigger: "fixture skill for reverse-drift test"
      quiet: true
claude_binding:
  agents:
    - name: a1
      description: "fixture agent for reverse-drift test"
      tools: [Read]
      source: agents/a1.md
  verify:
    declared_skills_from: capabilities.skills
    declared_agents_from: claude_binding.agents
codex_binding:
  plugin:
    name: fixture-plugin
    hooks_json: adapters/codex/hooks.json
  hooks:
    - event: SessionStart
      status: active
backbone_scripts:
  lib: scripts/lib/fixture_lib.sh
  scripts:
    - scripts/fixture_backbone.sh
EOF

cat > "$fx/.codex-plugin/plugin.json" <<'EOF'
{
  "name": "fixture-plugin",
  "version": "0.0.1",
  "hooks": "./adapters/codex/hooks.json",
  "interface": {
    "capabilities": [
      "alpha"
    ]
  }
}
EOF

cat > "$fx/adapters/codex/hooks.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "bash adapters/codex/hook_dispatch.sh session-start"}]}
    ]
  }
}
EOF

cat > "$fx/adapters/codex/hook_dispatch.sh" <<'EOF'
#!/usr/bin/env bash
run_script "fixture_adapter_only.sh"
EOF

cat > "$fx/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: fixture skill (declared)
---

Fixture skill body.
EOF

cat > "$fx/agents/a1.md" <<'EOF'
---
name: a1
description: fixture agent (declared)
tools: [Read]
---

Fixture agent body.
EOF

# Backbone script + lib entries, both present at baseline (forward-drift check #1).
cat > "$fx/scripts/lib/fixture_lib.sh" <<'EOF'
#!/usr/bin/env bash
# fixture lib, declared under backbone_scripts.lib
EOF

cat > "$fx/scripts/fixture_backbone.sh" <<'EOF'
#!/usr/bin/env bash
# fixture backbone script, declared under backbone_scripts.scripts
EOF

# Adapter fragment referencing a script NOT declared under backbone_scripts, to prove the
# adapter check is independent of the backbone_scripts declaration (forward-drift check #2).
cat > "$fx/adapters/claude-code/settings-fragment.example.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR:-.}/scripts/fixture_adapter_only.sh\" --flag" }
        ]
      }
    ]
  }
}
EOF

cat > "$fx/scripts/fixture_adapter_only.sh" <<'EOF'
#!/usr/bin/env bash
# fixture script, referenced only by the adapter fragment above (not in backbone_scripts)
EOF

# ------------------------------------------------------------- 1. baseline (0 drift)
echo "test: baseline — declared manifest matches disk 1:1"
set +e
out_base="$("$fx/scripts/capability_audit.sh" 2>&1)"
rc_base=$?
set -e
check "baseline exits 0" '[ "$rc_base" -eq 0 ]'
check "baseline reports Drift count: 0" 'printf "%s" "$out_base" | grep -q "Drift count: 0"'
check "baseline shows backbone script active" 'printf "%s" "$out_base" | grep -q "backbone: scripts/fixture_backbone.sh -> active"'
check "baseline shows adapter script wired" 'printf "%s" "$out_base" | grep -q "adapter: scripts/fixture_adapter_only.sh -> wired"'
check "baseline shows Codex hook active" 'printf "%s" "$out_base" | grep -q "codex-hook: SessionStart -> active"'
check "baseline shows codex count-only honesty label" 'printf "%s" "$out_base" | grep -q "codex-plugin capability check: count-only"'

# ------------------------------------------------- 1b. --memory-dir CLI-consistency no-op
# Every other backbone script takes --memory-dir; adopters reach for it here too and used to
# hit "Unknown argument" (field report cc_chobotnice 2026-07-16). Accepted + ignored + noted.
echo "test: --memory-dir accepted (ignored, noted) instead of failing as unknown argument"
set +e
out_memdir="$("$fx/scripts/capability_audit.sh" --memory-dir "$work/whatever mem" 2>&1)"
rc_memdir=$?
set -e
check "--memory-dir exits 0 on a clean fixture" '[ "$rc_memdir" -eq 0 ]'
check "--memory-dir prints the ignored note" 'printf "%s" "$out_memdir" | grep -q "accepted for backbone CLI consistency"'
check "legacy --hermes-dir alias also accepted" '"$fx/scripts/capability_audit.sh" --hermes-dir=/tmp/x >/dev/null 2>&1'

# ------------------------------------------------------------- 2. reverse skill drift
echo "test: reverse drift — undeclared skill physically on disk"
mkdir -p "$fx/skills/beta"
cat > "$fx/skills/beta/SKILL.md" <<'EOF'
---
name: beta
description: undeclared fixture skill
---

Undeclared skill body — never listed under capabilities.skills.
EOF
set +e
out_skill="$("$fx/scripts/capability_audit.sh" 2>&1)"
rc_skill=$?
set -e
check "undeclared skill on disk fails the audit (exit 1)" '[ "$rc_skill" -eq 1 ]'
check "undeclared skill flagged as drift" 'printf "%s" "$out_skill" | grep -q "on disk but not declared"'
check "undeclared skill names beta" 'printf "%s" "$out_skill" | grep -q "skill: beta -> DRIFT: on disk but not declared"'

# ------------------------------------------------------------- 3. reverse agent drift
echo "test: reverse drift — undeclared agent physically on disk"
cat > "$fx/agents/a2.md" <<'EOF'
---
name: a2
description: undeclared fixture agent
---

Undeclared agent body — never listed under claude_binding.agents.
EOF
set +e
out_agent="$("$fx/scripts/capability_audit.sh" 2>&1)"
rc_agent=$?
set -e
check "undeclared agent on disk fails the audit (exit 1)" '[ "$rc_agent" -eq 1 ]'
check "undeclared agent flagged as drift" 'printf "%s" "$out_agent" | grep -q "on disk but not declared"'
check "undeclared agent names a2" 'printf "%s" "$out_agent" | grep -q "agent: a2 -> DRIFT: on disk but not declared"'

# ------------------------------------------------------- 4. forward drift — backbone script
# Declared under backbone_scripts.scripts (and passed at baseline in test 1) but the file
# is deleted from disk. Mutation-proves discrimination: same declaration, only the disk
# state changed, from "active" (test 1) to "DRIFT: declared but missing on disk" here.
echo "test: forward drift — backbone_scripts entry declared but missing on disk"
rm -f "$fx/scripts/fixture_backbone.sh"
set +e
out_backbone="$("$fx/scripts/capability_audit.sh" 2>&1)"
rc_backbone=$?
set -e
check "missing backbone script fails the audit (exit 1)" '[ "$rc_backbone" -eq 1 ]'
check "missing backbone script flagged as drift" 'printf "%s" "$out_backbone" | grep -q "declared but missing on disk"'
check "missing backbone script names fixture_backbone.sh" 'printf "%s" "$out_backbone" | grep -q "backbone: scripts/fixture_backbone.sh -> DRIFT: declared but missing on disk"'

# --------------------------------------------------- 5. forward drift — adapter hook script
# The adapter fragment (settings-fragment.example.json) references fixture_adapter_only.sh,
# which is NOT declared under backbone_scripts.scripts at all — this isolates the adapter
# check from the backbone check above. Deleting the script it wires must still be caught.
echo "test: forward drift — adapter fragment references a missing script"
rm -f "$fx/scripts/fixture_adapter_only.sh"
set +e
out_adapter="$("$fx/scripts/capability_audit.sh" 2>&1)"
rc_adapter=$?
set -e
check "missing adapter script fails the audit (exit 1)" '[ "$rc_adapter" -eq 1 ]'
check "missing adapter script flagged as drift" 'printf "%s" "$out_adapter" | grep -q "adapter references missing script"'
check "missing adapter script names fixture_adapter_only.sh" 'printf "%s" "$out_adapter" | grep -q "adapter: scripts/fixture_adapter_only.sh -> DRIFT: adapter references missing script"'

# --------------------------------------------------- 6. Codex declared-vs-wired drift
echo "test: Codex hook declared active but removed from its host-specific hooks file"
printf '{"hooks":{}}\n' > "$fx/adapters/codex/hooks.json"
set +e
out_codex="$($fx/scripts/capability_audit.sh 2>&1)"
rc_codex=$?
set -e
check "missing declared Codex hook fails the audit (exit 1)" '[ "$rc_codex" -eq 1 ]'
check "missing Codex SessionStart is host-labelled drift" \
  'printf "%s" "$out_codex" | grep -q "codex-hook: SessionStart -> DRIFT: declared active but not wired"'

echo
echo "capability_audit tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
