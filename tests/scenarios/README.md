# Container Capability Test Scenarios

These are behavior tests for human/model review. They verify the plugin stays quiet in normal work and loud only for fallback.

## Scenario 1: Normal Build Should Stay Quiet

Input:
- Project has `memory/`.
- User asks for a small implementation.
- Relevant skill is available and used.

Expected:
- No fallback report.
- No long container narration.
- Final answer may mention verification only.
- TodoWrite is used only if the task becomes multi-phase or follow-ups appear.

Fail if:
- Agent emits fallback despite no failed capability.
- Agent spends more text on the container than the task.

## Scenario 2: Expected Hook Unavailable

Input:
- Session expects SessionStart hook.
- Runtime has no hook support.
- Project continuity depends on `memory/MEMORY.md`.

Expected:
- Agent manually reads `memory/MEMORY.md`.
- Agent reports fallback: expected hook, manual read, impact, learning signal.

Fail if:
- Agent silently proceeds as if hook ran.

## Scenario 3: Repeated Manual Workaround

Input:
- Same fallback occurs twice: session search unavailable, manual text search used.

Expected:
- Second event triggers capability gap or skill-authoring proposal.
- Fallback goes to `memory/fallbacks.md` if project template exists.

Fail if:
- Repeated fallback remains chat-only.

## Scenario 4: Existing memory folder install

Input:
- Target project already has `memory/MEMORY.md`.
- Run installer without `--force`.

Expected:
- Existing file is skipped.
- Missing template files are installed.
- No existing content overwritten.

Fail if:
- Installer overwrites existing files.

## Scenario 5: Force Install Backup

Input:
- Target project has existing `memory/`.
- Run installer with `--force`.

Expected:
- Existing overwritten files are copied to `<target>/memory/.backups/hermes-template.<random>/memory/`
  (persistent default since 0.1.20; `--backup-dir` overrides the root).
- Output lists backup path.

Fail if:
- No backup exists.

## Scenario 6: Capability Audit

Input:
- `memory/CAN.md` declares a subagent that is absent.

Expected:
- `capability-audit` reports declared but missing.
- It proposes patch or adapter action.

Fail if:
- Missing runtime capability is ignored.

## Scenario 7: Long Chat TodoWrite Ledger

Input:
- User starts a multi-phase task in a long chat.
- During work, three follow-up ideas appear.
- One phase remains unfinished.

Expected:
- TodoWrite/update_plan is created early.
- Completed items are marked done as they complete.
- New follow-ups are added when they appear.
- Close shows either clean completed ledger or open items carried forward to `memory/todo.md`.

Fail if:
- Open work appears only in prose.
- Agent says "later" or "next" without visible todo.
- Close hides incomplete planned work.

## Scenario 8: Spec-Only Capability Is Not Fallback

Input:
- Codex runtime has only skills active.
- Hook specs exist in plugin but are not adapter-installed.
- User asks for a normal small code change.

Expected:
- No hook fallback report.
- Hook specs are treated as spec-only.

Fail if:
- Agent reports missing hook as fallback despite no expected hook.

## Scenario 9: Expected Capability Fallback

Input:
- User explicitly asks to use `fmc-close` subagent.
- Runtime has no callable subagent.

Expected:
- Agent reports fallback.
- Agent performs manual close or asks to install adapter.

Fail if:
- Agent silently performs manual close without naming fallback.
