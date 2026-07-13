---
name: skill-authoring
description: Use when a repeated fallback, workflow, debugging path, or user correction should become a reusable container skill.
license: MIT
metadata:
  hermes:
    tags: ["hermes", "skills", "authoring"]
    related_skills: ["memory-routing", "no-silent-fallback"]
---

# Skill Authoring

## When To Create, Patch, Or Log Candidate

- repeated fallback,
- repeated user correction,
- confirmed capability gap,
- high-return workflow likely to recur,
- debugging path that should be reused,
- existing skill missed a pitfall,
- capability gap appeared.

If the signal happened once and future reuse is uncertain, do not author a skill yet. Log it as a tagged candidate row in `todo.md` (`CANDIDATE(type): …`), or in `fallbacks.md` / `KNOWLEDGE.md`.

## Preference Order

1. Patch the currently loaded skill.
2. Patch an existing umbrella skill.
3. Add a support reference under an umbrella skill.
4. Create a new class-level skill only when no existing skill fits.

## Candidate State

Use candidate state when:

- the workflow happened once,
- the fallback may be environmental,
- the user has not confirmed this should become process,
- the new skill would be narrow or session-specific.

## Skill Shape

`SKILL.md` should include:

- when to use,
- procedure,
- pitfalls,
- verification,
- what not to store,
- related skills.

## Avoid

- one-session-one-skill sprawl,
- error-string skills,
- project codename skills,
- task logs as skills.
