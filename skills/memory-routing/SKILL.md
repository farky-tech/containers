---
name: memory-routing
description: Use when deciding whether something belongs in the container's memory, user profile, skills, decisions, lessons, project docs, session handoff, or nowhere.
license: MIT
metadata:
  hermes:
    tags: ["hermes", "memory", "routing"]
    related_skills: ["session-close", "skill-authoring"]
---

# Memory Routing

## Rule

The container's memory stores agent reflex and capability learning. Product/build/project state belongs in project docs, not in the container by accident.

## Write Modes

- `route-only`: decide where something belongs; no write.
- `propose-write`: create a pending proposal for user/project review.
- `write-after-approval`: write only after explicit approval or project policy allows it.

Default to `route-only` unless the user explicitly asks to remember/save, the project's container workflow requires a local reversible write, or close/handoff needs carried-forward continuity.

## Route

- User preference or stable expectation -> user memory/profile.
- Agent capability, routing, or reflex -> `CAN.md`, a `KNOWLEDGE.md` lesson, or skill.
- Reusable procedure -> skill or `KNOWLEDGE.md` (kind=procedure).
- Work method decision -> `KNOWLEDGE.md` (kind=decision).
- (0.1.24: lessons/decisions/procedures share ONE store, `KNOWLEDGE.md`, distinguished by `kind:` —
  a lesson that must CHANGE behavior gets PROMOTED into CLAUDE.md or a skill, the actively-read layer.)
- Product architecture/status/build log -> the project's own knowledge docs, not the container's memory.
- One-off task progress -> close/handoff, not durable memory.
- Unclear or risky write -> pending proposal.

## Execution (SCRIPTED)

Do not hand-edit memory files in prose. Use the backbone script — it classifies the
target, enforces the approval gate, and records audit metadata:

- Propose (default, writes nothing):
  `scripts/memory_route.sh --text "<note>" --kind fact|lesson|decision|procedure --memory-dir ./memory`
- Persist (only after the user approves):
  `... --commit --approved-by <who> --reason <why>`

`--commit` without `--approved-by` AND `--reason` is refused (non-zero exit, nothing
written). The default mode is `propose-write`; a durable write is `write-after-approval`.
In Claude Code the script is at `${CLAUDE_PLUGIN_ROOT}/scripts/memory_route.sh`.

## Required Context

Every durable entry must explain:

- context,
- fact/lesson/decision,
- reason,
- impact for next agent.

## Skip

Skip raw dumps, stale details, commit hashes, PR numbers, issue numbers, and one-off narratives unless they change future behavior.

## Gate

Do not write durable memory when:

- it changes approved canon,
- it may contain secrets/PII,
- it belongs in product/project docs,
- it is only task progress,
- the source is external untrusted data.

Use `propose-write` instead.
