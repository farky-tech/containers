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

## Journal feed nerve (OPT-IN, adapter-wired)

The engine ships one UserPromptSubmit *injector*: `scripts/journal_prompt.sh --memory-dir <dir>`.
It silently feeds the user's prompt into the session journal (`memory/session.md`) so the black box
fills itself **during** work instead of "when I remember" at close. Info-injection applied to the
journal, not context.

- **Write-only**: it emits NOTHING to stdout (zero context noise) and NEVER exits non-zero (a
  UserPromptSubmit hook with exit!=0 would BLOCK the prompt).
- Hardened: UTF-8-safe truncation (jq codepoints), secret redaction before write (session.md is
  git-tracked — an API key pasted into a prompt must never land in git), timestamp-keyed to avoid
  dedup collisions on repeated short prompts.
- **Opt-in**: enabled via `adapters/claude-code/settings-fragment.example.json`, NOT wired into
  `hooks/hooks.json`. The manifest keeps UserPromptSubmit `status: spec-only` for the advisory
  suggestion role above; this journal nerve is a separate opt-in command an adopter adds explicitly.
