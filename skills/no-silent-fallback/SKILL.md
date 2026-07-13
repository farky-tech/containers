---
name: no-silent-fallback
description: Use whenever an expected capability cannot run or is replaced by a weaker/manual path; do not treat optional spec-only capabilities as fallback.
license: MIT
metadata:
  hermes:
    tags: ["hermes", "fallback", "learning"]
    related_skills: ["capability-routing", "memory-routing"]
---

# No Silent Fallback

## Core Rule

Work quietly when the planned path works. When you switch to a weaker path, make
the switch visible: expected path, actual path, cause, and impact.

## Expected Capability

A capability is expected only when at least one is true:

- the user explicitly requested it,
- the agent plan promised it,
- the host runtime declares it active,
- project `memory/MEMORY.md` or `CAN.md` requires it for this task,
- a previous fallback/pending item explicitly made it part of the current work.

Spec-only assets are not expected unless installed by an adapter or explicitly requested.

## Fallback Means

- hook expected but unavailable,
- subagent expected but unavailable,
- tool expected but unavailable,
- expected skill not used,
- expected write/search/close/TodoWrite done manually instead of the expected mechanism,
- verification weakened or skipped,
- expected runtime capability absent.

## Not Fallback

- a hook stays silent because no capability is relevant,
- a skill is used quietly,
- a tool succeeds normally,
- a subagent is unnecessary for a small task.
- a spec-only hook/subagent is not installed and was never requested.

## Report Format

Report the fallback to the user. Persist meaningful or repeated fallbacks with
the backbone script so future sessions can learn from them:

```
scripts/fallback_log.sh --expected "<what should have run>" \
  --actual "<what ran instead>" --mechanism "<name>" \
  --cause "<why>" --impact "<impact>" --signal skill|tool|hook|subagent|test|rule|none \
  --memory-dir ./memory
```

The script is idempotent (same expected+actual+mechanism is never duplicated) and
writes a canonical block to `memory/fallbacks.md`. In Claude Code it lives at
`${CLAUDE_PLUGIN_ROOT}/scripts/fallback_log.sh`.

## Learning Signal

If repeated or meaningful, propose a new skill, tool, hook, subagent, test, or rule
(`--signal`). A recurring `--mechanism` is the trigger for `fmc-fallback-review`.
Do not turn small harmless adaptations into incident paperwork.
