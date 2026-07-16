# contAIner — Project Capability Container
<!-- sentinel: farky-memory-container loaded -->

## Kernel

- Silent work is good.
- Silent fallback is forbidden.
- Use fitting capabilities without ceremony.
- If a planned capability cannot run, is replaced, weakened, skipped, or refused, report it.
- Durable learning belongs in contAIner memory/skills/lessons, not product state by accident.
- This container is your BRAIN — what you did, learned, decided AND WHY, where you left off. It is YOU, not a drawer, and it is self-contained: it tends itself. One brain, one line — don't run a second memory system beside it, and don't carve your "why" out elsewhere; your experience/decisions/carry-forward live here and nowhere else. Keep it filled; don't bridge it away.

## Index

- `STATE.md`: **READ FIRST — where we are NOW, what we're solving, the next concrete step** (live thread; overwritten each close). Without it the next instance arrives lost even with a full log. Three roles, don't conflate: `STATE.md`=now · `log.md`=archive · `todo.md`=checklist.
- `CAN.md`: when to use capabilities.
- `BRIDGE.md`: what contAIner HOLDS (your memory) × what lives elsewhere (bridge). Don't over-bridge — your journal/lessons/decisions/carry-forward live ONLY here.
- `KNOWLEDGE.md`: ONE store of durable knowledge — lessons, decisions, procedures — as canonical
  blocks distinguished by `kind:` (0.1.24: merged the former lessons/decisions/procedures files;
  genre-split files proved write-only). A lesson that must CHANGE behavior gets promoted into
  CLAUDE.md or a skill (the actively-read layer); KNOWLEDGE is the raw store, not a graveyard.
- `fallbacks.md`: meaningful fallback events and learning signals.
- `todo.md`: carried-forward items for long continuity. Tagged rows replace former side-files:
  `- [ ] CANDIDATE(type): <pattern> (occurrences: <date>)` (2 occurrences on distinct days → promote)
  and `- [ ] GO: <risky action> | risk: … | rollback: …` (waits for the human; never blocks).
- `session.md`: live session journal (black box of what is happening now); distilled at close. **Backend file — NOT the user-visible to-do list; never let it substitute for showing the working ledger in the answer.**
- `sessions/`: rich per-session record (`YYYY-MM-DD-topic.md`) — the full story + **WHY** of each session (intent, decisions, dead-ends), compiled from the journal at close. The deep archive a future instance READS instead of re-deriving context from a dead chat (cheap to write, expensive to re-lose).
- `log.md`: one line per session = index that links to the matching `sessions/` record.

## How memory is written (SCRIPTED, not by hand)

This container's memory runs on a scripted backbone — write through the plugin's
scripts (with `--memory-dir ./memory`), not by hand-editing prose. Files are canonical
blocks: deterministic, idempotent, atomic, compaction-proof.

- Session journal: `session_note.sh --start "<goal>"` at the start, `--note "<milestone>"`
  as you go → `session.md`. So "what did we do this session" is read from the FILE, not
  from a drifted context window.
- Fallback: `fallback_log.sh …` → `fallbacks.md`; settle it later with `--resolve <id>`.
- Carry-forward: `ledger_carry.sh --item "<x>"` → `todo.md`; `--done "<x>"` resolves it.
  Waiting-room patterns and human-GO items are tagged todo rows (formats in Index above),
  carried with the same two commands — no separate stores or CLIs.
- Durable note: `memory_route.sh --text "<x>" --kind fact|lesson|decision|procedure`
  (approval-gated; `--commit` needs `--approved-by` + `--reason`). fact → `CAN.md`,
  everything else → `KNOWLEDGE.md`.
- Close/handoff: `session_close.sh` reads everything, distils the journal, lists open
  items to pull into the next session.
- Close-debt (opt-in hooks): `close_state.sh` (--init / --close-done / --session-end /
  --boot-recovery / --status) tracks whether a session that did real work got a conscious
  close; the close ends with `close_state.sh --close-done --ledger-ok` (after reconciling
  `todo.md`). A missed close is surfaced next boot by `--boot-recovery` and caught up from
  the journal (`/close --auto <SID>`) instead of nagging mid-work.

## Rule

Read the smallest relevant part. Do not load everything unless the task is about contAIner itself.
