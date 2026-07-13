# BRIDGE — what contAIner HOLDS (your memory) × what just points elsewhere

> **What contAIner IS for you:** your **agent memory** — the continuity of *you-as-builder*
> across sessions (journal, your own lessons, method decisions, carry-forward). This layer
> usually lives **NOWHERE ELSE**. Most projects already have *project memory* (docs,
> architecture) and a *constitution* (CLAUDE.md / AGENTS.md) — but **not a record of YOU**.
> contAIner is that record.
>
> **Three memory layers — keep them distinct:**
> - **Project memory** = what the app/product is (schema, architecture, plans) → project docs.
> - **Constitution** = your behavior rules → CLAUDE.md / AGENTS.md.
> - **Agent memory** = what YOU did / learned / decided / left unfinished → **ONLY in contAIner.**
>
> ⚠️ **Over-bridging trap:** the richer your existing memory, the MORE tempting it is to route
> every contAIner concept to "already lives elsewhere" and leave contAIner empty. Resist it. Project
> facts and behavior rules bridge OUT; your journal / lessons / decisions / carry-forward do
> NOT — they have no other home. An empty contAIner means you have no memory of yourself.

## (A) What contAIner HOLDS — your memory (single source; fill it, don't bridge it away)

| Layer | File | What it's for |
|---|---|---|
| Session journal (black box) | `session.md` | What's happening now — written as you go, survives context compaction. |
| Distilled history | `log.md` | One line per session — where you left off. **Read on session start.** |
| Durable knowledge | `KNOWLEDGE.md` | Lessons + method decisions + procedures in ONE store (blocks carry `kind:`). A lesson that must CHANGE behavior gets promoted into CLAUDE.md or a skill. **Read on session start** — an unread store = repeated mistakes. |
| Carry-forward | `todo.md` | What you didn't finish → survives into next session. **Read on session start.** Tagged rows `CANDIDATE:`/`GO:` replace separate waiting-room/GO-queue files. |
| Fallbacks | `fallbacks.md` | Where a capability failed = signal for a new skill/tool/rule. |

Written by SCRIPT, not by hand (canonical blocks): `session_note.sh`, `ledger_carry.sh`,
`memory_route.sh` (approval-gated), `session_close.sh` (distil journal→log at close).

## (B) What lives ELSEWHERE — bridge, don't copy (fill the right column for THIS instance)

Fill where each thing really lives so you don't read it twice. Delete rows that don't apply.

| Thing | Where it really lives for me | Why not in contAIner |
|---|---|---|
| Project knowledge (app, schema, plans) | <e.g. project docs / architecture set> | Project memory, not yours. |
| Behavior rules / reflexes | <e.g. global + project CLAUDE.md / AGENTS.md> | Constitution, not memory. |
| Capability routing | <e.g. CLAUDE.md reflex + subagent bank + skills> | Lives in host config. |
| Kernel "silent fallback forbidden" | <e.g. global CLAUDE.md reporting rule> | Constitution. |
| Operational state for the ecosystem | <e.g. shared hub> | Cross-project state, not your journal. |
| Feedback about the user / style | <e.g. global memory> | Different, cross-project layer. |

## Rule

When you want to write something from **(B)** → don't write it here, it belongs to its source
(add a row pointing at it). When it's from **(A)** — *what YOU did / learned / decided / left
unfinished* — it belongs here and **nowhere else**, because your agent continuity has no other home.
