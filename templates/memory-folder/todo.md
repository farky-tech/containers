# Todo

This file stores carried-forward TodoWrite items that must survive long chat, compaction, or session handoff.

Use it only for items that remain open after close or must be visible to the next agent.

Format:

```txt
## YYYY-MM-DD — Session/topic
- [ ] Item:
  Context:
  Next step:
  Source:
  Status: open | in-progress | blocked | carried | done
```

Rules:
- Do not duplicate completed chat todo items here.
- Do not store vague "do later" thoughts without next step.
- If an item becomes a skill/tool/hook/test proposal, link it to `fallbacks.md` or `KNOWLEDGE.md`.
- Tagged rows carry waiting-room and human-GO items: `- [ ] CANDIDATE(type): <pattern> (occurrences: <date>)`
  (2 occurrences on distinct days → promote) · `- [ ] GO: <action> | risk: … | rollback: …` (never blocks).
