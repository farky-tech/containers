---
name: capability-audit
description: Use to compare declared container capabilities with actual skills, subagents, hooks, tools, and recent fallback reports.
license: MIT
metadata:
  hermes:
    tags: ["hermes", "audit", "capabilities"]
    related_skills: ["capability-routing", "skill-authoring"]
---

# Capability Audit

## When To Use

Use when capabilities feel forgotten, routing is noisy, fallback repeats, or the container's project files drift from actual runtime support.

## Procedure

1. Read `memory/CAN.md` if present.
2. Compare against available skills/subagents/hooks/tools — **verify availability from the real runtime** (settings, agent list, `ls`, tool search), not from memory or from what an index claims.
3. Review recent fallback reports.
4. Identify dead, missing, noisy, or un-routed capabilities.
5. Propose patches, not broad rewrites.

Rule: separate "not available" from "not checked" from "written from memory." A capability that is listed but was never verified against the real runtime is itself an audit finding.

## Output

```txt
Capability audit:
- Declared but missing:
- Available but not routed:
- Routed but too noisy:
- Repeated fallback:
- Patch candidates:
```

## Run

From the plugin root, run:

```bash
bash scripts/capability_audit.sh
```

This script is the executable enforcement of the declared-vs-actual rule described by this skill. It compares the declarations in `manifest.yaml` with the plugin files and supported runtime checks.

Exit codes:
- `0` = no drift.
- `1` = drift found, including missing declared capabilities.
