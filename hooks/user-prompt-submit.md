# UserPromptSubmit Hook Spec

Purpose: detect when a prompt likely needs a container capability.

When:
- user asks for review/audit,
- user asks to build/implement,
- user mentions prior work/session,
- user asks to remember/learn,
- user reports a failure or correction,
- user ends or pauses a workstream.

Action:
- suggest at most 1-2 matching capabilities.
- deduplicate repeated suggestions.
- be silent if no capability is relevant.

Important distinction:
- hook silence because nothing is relevant is normal quiet work.
- hook failure when it should have run is fallback and must be reported.

## Journal feed nerve (AUTO-WIRED, adapter-dispatched)

The engine ships two UserPromptSubmit nerves, run by `adapters/claude-code/hook_dispatch.sh
user-prompt-submit`: `scripts/journal_prompt.sh --memory-dir <dir>` (journal) then
`scripts/recall_inject.sh --memory-dir <dir>` (prompt-time pointers). The journal nerve silently
feeds the user's prompt into the session journal (`memory/session.md`) so the black box fills itself
**during** work instead of "when I remember" at close. Info-injection applied to the journal, not
context.

- **Write-only**: it emits NOTHING to stdout (zero context noise) and NEVER exits non-zero (a
  UserPromptSubmit hook with exit!=0 would BLOCK the prompt).
- Hardened: UTF-8-safe truncation (jq codepoints), secret redaction before write (the journal is a
  local black box; redaction is defense in depth so a key pasted into a prompt never lands in the
  journal, even though `session.md` is now git-ignored), timestamp-keyed to avoid dedup collisions
  on repeated short prompts.
- **Auto-wired** (Fáze A, 2026-07-18): both nerves fire via `hooks/hooks.json` → the dispatcher, at
  parity with the Codex dispatcher, inert without `memory/MEMORY.md`. The manifest's UserPromptSubmit
  entry is `status: active`; the advisory suggestion role above is delivered by the same event.
