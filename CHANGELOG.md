# CHANGELOG — farky-memory-container

Engine version history. Version = single source of truth in `.claude-plugin/plugin.json`.
Newest first. Adopter-action detail → `MIGRATION.md`.

## 0.2.0 — first public release

The first public release of **farky-memory-container** (also known as *kontAIner*): a portable,
quiet-by-default **memory + capability container** for AI coding agents. It gives an agent a
per-project `memory/` folder it writes ITSELF (journal, state, knowledge, carry-forward), a
zero-dependency shell backbone that makes those writes scripted, atomic, and idempotent, a
machine-enforced close ritual (an unclosed session is caught up on the next boot, never lost), and
a self-report that says out loud which capabilities are wired vs. silently missing.

Works as a Claude Code **plugin**; the skills also load in Codex CLI via `.codex-plugin`. See the
README for the full picture and Quickstart.

Field-hardened across 10+ internal agent instances (Claude Code and Codex) on real projects before
going public; the detailed internal iteration history stays in the maintainer's workspace.
