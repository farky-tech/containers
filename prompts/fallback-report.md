# Fallback Report

Use whenever a planned, expected, or stronger mechanism did not run.

```txt
Fallback:
- What should have run:
- What ran instead:
- Why the original mechanism didn't run:
- Impact on quality/safety/continuity:
- What I did instead:
- Learning signal: new skill / tool / hook / subagent / test / rule / none
```

Rules:

- Do not report normal quiet work as fallback.
- Report capability failure, skipped capability, missing runtime support, manual replacement, weakened verification, or unavailable memory/search.
- If the same fallback repeats, propose a capability improvement.
