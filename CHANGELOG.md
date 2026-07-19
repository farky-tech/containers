# CHANGELOG — farky-memory-container

Engine version history. Version = single source of truth in `.claude-plugin/plugin.json`.
Newest first. Adopter-action detail → `MIGRATION.md`.

## 0.4.2 — a behavioral reflex nerve (both adapters, at parity)

Field use surfaced a gap of the same class on two hosts: the container ships skills for keeping a
running to-do ledger and for reaching for the right skill, but neither adapter fired anything at
`UserPromptSubmit` to actually trigger them each turn. An agent knew the rule at boot and then drifted
on the next prompt — most visibly by throwing away its accumulated to-do list on a pivot and starting a
fresh partial one. That is the "later = never" failure, now in the behavioral layer rather than delivery.

- Both adapters (`adapters/codex` → `update_plan`, `adapters/claude-code` → `TodoWrite`) now emit a
  short **behavioral reflex** on every `UserPromptSubmit`: keep ONE cumulative visible to-do ledger for
  the whole session (a pivot MERGES into the same list instead of replacing it; done items stay checked;
  a finished phase does not close the ledger), and check whether a skill covers each non-trivial step.
- The reflex **ships enabled and fires every prompt** — a deliberately overt nerve, a distinct category
  from the silent memory nerves (journal/recall): a nudge you cannot see does not nudge. It is not a
  "silent fallback" violation.
- **Parity is enforced.** The reflex lives in both host adapters in step (host-specific plan tool), not
  one — matching the delivery parity 0.4.0 established. Nerve count is unchanged (the reflex is an inline
  emit, not a script), so the capability self-report still sees the full set wired.

**Adopter action:** refresh the runtime plugin; for an in-repo backbone copy run
`install_project_template.sh --refresh-scripts <project>` (engine only — it never rewrites `memory/*.md`).
The reflex is part of the adapters, so it auto-wires — nothing to paste. A fresh top-level session
confirms it: after a pivot the agent keeps one visible to-do ledger, done items included.

## 0.4.1 — truthful session identity across hosts

FMC's SessionStart and close both ran through the adopter backbone, but a Codex host provides its
identity as `CODEX_THREAD_ID`, which the close-debt tracker did not know. Without it, a start or close
lacking an explicit id wrote into a shared `nosession` bucket — so several sessions could share one
state, and a conscious close might miss the session that start initialized.

- Identity now resolves in order: explicit `--session-id` → hook payload → `CODEX_THREAD_ID` →
  `CLAUDE_CODE_SESSION_ID`.
- `--init` and `--close-done` with no real identity now fail loudly (exit 1) instead of inventing a
  `nosession` bucket.
- Regression tests cover the source priority, both host adapters, and the fail-loud branch.

**Adopter action:** refresh the runtime plugin and, for an in-repo backbone copy, run
`install_project_template.sh --refresh-scripts <project>`. A fresh top-level session confirms the new
version is actually loaded.

## 0.4.0 — the Claude Code brain arrives switched ON (auto-wire parity with Codex)

Until now the Codex adapter dispatched all ten nerves automatically on install, while Claude Code
adopters got only a banner plus a self-report telling them to paste a settings fragment — the same
product delivering its "works on its own" promise on one host but not the other. 0.4.0 closes that:

- **Claude Code auto-wires the full nerve set** via the shipped `hooks/hooks.json`, which now calls a
  Claude lifecycle adapter (`adapters/claude-code/hook_dispatch.sh`) for SessionStart / UserPromptSubmit
  / SessionEnd / PreCompact — at parity with Codex. Paths resolve via `${CLAUDE_PLUGIN_ROOT}` inside the
  shipped hooks. The adapter is **inert outside projects that carry `memory/MEMORY.md`** — installing the
  plugin never seeds a brain into an unrelated repo; the brain wakes only where you set one up.
- **The settings fragment is retired as a required step** — it survives only as an override example
  (custom memory-dir, or an in-repo fork). The capability self-report now derives offered/wired state
  from the adapter dispatcher, so a fully auto-wired project reports all-on instead of nagging you.
- **The prompt journal (`memory/session.md`) is gitignored by default** — a local-only black box of
  bounded prompt excerpts; gitignoring it keeps a prompt log from being pushed by accident. This
  reverses the earlier "your call" stance; the privacy default is now on.
- **Orphan close-debt markers age out.** An `UNCLOSED` marker older than 14 days
  (`HERMES_UNCLOSED_AGING_DAYS`) is moved aside (loudly) so boot-recovery stops nagging you to close a
  session that is effectively long gone.
- Folds in the intervening wiring/manifest fixes (0.3.10–0.3.12): Codex manifest hardening, generic
  journal identity, honest hook-spec docs.

**Adopter action (Claude Code, upgrading from a pasted fragment):** remove the FMC entries from your
`.claude/settings.json` / `settings.local.json` — the plugin now wires them itself, and keeping the
fragment would double-fire the nerves (duplicate journal entries, doubled context injection). If you
had `memory/session.md` tracked in git, untrack it: `git rm --cached memory/session.md`. Fresh installs
need no action.

## 0.3.9 — wiring hygiene from the field: gitignore on every install, honest hook paths, --memory-dir everywhere

An adopter wired 0.3.8 the documented way (docs-only templates + hooks fragment in project
settings) and hit three real gaps. All three verified against both the source and the live
installation, and fixed at the root:

- **Installer: the runtime gitignore-append now runs on EVERY install mode**, docs-only included.
  It used to be a `--with-scripts`/`--refresh-scripts` side effect — but the runtime artefacts
  under `memory/` are generated by the engine HOOKS regardless of whether the backbone scripts
  were copied locally, so a docs-only adopter ended up committing per-session state
  (`.close-state/*.env`, the generated `_rejstrik.md`). The entry list also grew
  (`.close-state/`, `.capability-snapshot`, `.watch-state`) and the warn/dry-run texts now derive
  from that one list — a hardcoded copy in the symlink warning had drifted (named 2 entries of 6).
  Deliberately NOT auto-ignored: `session.md`, `.session-archive/`, `INDEX.md` — those are
  data/curated hybrids and git policy for them is your call (new README section
  "What belongs in git": the durable layers are `sessions/` + `log.md`, not the live journal).
- **The hooks fragment's PATHS comment told a lie:** `${CLAUDE_PLUGIN_ROOT}` resolves ONLY inside
  hooks the plugin itself ships — in hooks pasted into your project settings it is EMPTY. The
  fallback segment is therefore mandatory, always, and must NEVER point at a versioned
  marketplace cache path (the version segment changes on every upgrade and the hooks go silently
  dead). Fragment `_comment` + the Claude adapter README now say so.
- **`capability_audit.sh` accepts `--memory-dir`** (and the legacy `--hermes-dir`) instead of
  failing with "Unknown argument" — it was the only backbone script with a different CLI
  convention. The flag is accepted and ignored with a stderr note (the audit targets the plugin
  checkout, not a memory dir); the CAN template documents the deviation.

**Adopter action:** refresh the engine. Docs-only adopters: re-run the installer in merge mode
(it never overwrites, it only tops up `.gitignore`) or add the entries by hand; already-tracked
runtime files need `git rm --cached <file>` (gitignore does not catch tracked files). Check the
fallback segment of your settings hooks — it must not point at a versioned cache path.

## 0.3.8 — the brain doctrine: a mental model, not just mechanics

Adopters were handed the MECHANICS (engine vs. memory, where to write) but never the MENTAL MODEL —
why this container IS their brain and how to think about it. The seed ("the container is your agent
memory") sat buried under "Installing on yourself", framed as memory, not identity. Real failure
mode: an adopter installs a second memory system beside the container, or runs a parallel line,
because nobody told them this IS their mind.

- New **`You have a brain`** doctrine — the first section after the intro in README (you have a
  brain, this container IS it, one brain / one line, self-contained).
- Boot injects carry it condensed: `prompts/start.md` (Claude) + the Codex lifecycle adapter, above
  the behavior kernel. The `memory/` seed promotes its old one-line note to the full wording.

No data or interface change — pure mental model + docs.
**Adopter action:** refresh the engine; the doctrine shows up at boot and in README.

## 0.3.7 — the whole-repo INDEX cache sees clean deletes and moves

The whole-repo INDEX cache compared only existing children against `INDEX.md`'s mtime, so a clean
delete or move left no newer child and the physical index could keep a stale row until something
else changed in the same folder.

- Top-level and tree mode also use the directory's own mtime as an add/remove/rename signal.
- After a successful atomic merge the index is touched as the fresh cache stamp, so an unchanged
  folder still skips regeneration on the next boot.
- Regressions cover deletion, rename, nested-tree deletion, and the original unchanged-skip.

**Adopter action:** refresh the engine; physical indexes self-correct on the next tree run.

## 0.3.6 — the full map fits inside SessionStart

A fresh-session nonce smoke test showed a 38 KB descriptive rollup of 84 indexes was dropped whole
by the Codex hook output — the indexes themselves were correct, but the agent never saw them at boot.

- The recursive SessionStart map is now a compact names-only path inventory.
- Physical `INDEX.md` files still carry the full tables and derived descriptions.
- Atomic `.gen_index.*` temp files are never catalogued.
- Regressions guard completeness of hidden/non-Markdown entries and the compact-output ceiling.

**Adopter action:** refresh the engine and runtime; verify in a new session.

## 0.3.5 — INDEX filters runtime debris from the parent map too

The first live 0.3.4 generation correctly refused to descend into the container's runtime
directories, but `memory/INDEX.md` still listed them as direct rows — same for runtime markers and
the log.

- The shared generator skips `.backups`, `.close-state`, `.loop-state`, `.session-archive`,
  `.recall-state`, `.fmc-source`, `.capability-snapshot`, and `.recall-hits.log`.
- The regression checks both that no index is created inside runtime dirs and that they are absent
  from the injected parent map.

**Adopter action:** refresh the engine and runtime; indexes self-clean on the next tree run.

## 0.3.4 — recursive whole-repo INDEX tree

Live use in a Codex instance showed the whole-repo map was not the whole tree: it injected only
top-level non-hidden folders and the generator emitted Markdown only, so the agent never saw
`.agents/`, `.codex/`, scripts, tests, JSON/YAML, or deeper directories at boot.

- A new explicit root marker `gen_index:tree` turns on recursive mode; existing adopters with a
  plain `gen_index:auto` keep their behavior.
- Every safe folder gets a physical `INDEX.md`; FMC-managed indexes are refreshed, hand-authored or
  foreign-owned ones are never overwritten.
- Boot injects the rollup of all included folders, including project dot-directories and every safe
  file type; the root `INDEX.md` stays a folder map and loose root files land in a virtual
  `ostatni-v-repu/INDEX.md`.
- Non-Markdown file contents are never read; the map derives only the safe type.

**Adopter action:** opt in with the `gen_index:tree` root marker; `gen_index:auto` is unchanged.

## 0.3.3 — session close reads the canonical KNOWLEDGE store

Found during a real adopter migration off legacy genre files: `memory_route.sh` had been writing
lessons and decisions into the canonical `KNOWLEDGE.md`, but `session_close.sh` still counted the
removed `lessons.md`/`decisions.md` — a brain holding 56 atoms reported zero at close.
`session_close.sh` now counts `kind=lesson` / `kind=decision` blocks from `KNOWLEDGE.md`, with a
fail-honest fallback to a single legacy genre file for un-migrated forks. New regression test
creates both kinds through the approved `memory_route.sh` path and asserts exact close counts.
**Adopter action:** refresh the engine (`install_project_template.sh --refresh-scripts <project>`).

## 0.3.2 — recall fires by itself; PENDING decisions surface every boot

Two new **opt-in** nerves close the "the memory system lets things slip" gap:

- **`recall_inject.sh` (UserPromptSubmit, Claude Code host):** every prompt is matched against a
  FRESH atom registry (`gen_rejstrik --tsv`, fail-closed on generation failure) — BM25 with Czech
  diacritics folding + light stemming (Dolamic/Savoy), strict anti-noise gates (silence is the
  default; precision over recall) — and matching atoms are injected as POINTERS (slug + one line +
  "pull the atom BEFORE answering"). Per-session dedupe, both funnel sides logged to
  `.recall-hits.log`, kill switch `HERMES_RECALL_OFF=1`. Deliberately NOT dispatched on the Codex
  host (trust boundary — ask if you want it there).
- **`pending_inject.sh` (SessionStart):** todo items written as `- [ ] PENDING(<owner>): what /
  why-you / impact (proposed YYYY-MM-DD)` are announced EVERY boot until the human resolves them
  (`ledger_carry --done` with the full item text). Fence-aware, bounded output (8 KB + overflow
  row), read-only — a voice, not a gate (human-owned debt never blocks). Kill switch
  `HERMES_PENDING_OFF=1`.
- Supporting: `gen_rejstrik --tsv` machine contract (+ optional `tags:` frontmatter passthrough);
  `recall.sh` logs the consumed side of the funnel (success only); `brain_health` reports the
  recall funnel with honest labels (emitted / all recall runs / 7-day slug overlap);
  `close_state --init` janitor expires per-session recall state (7 d) and rotates the telemetry
  log (64 KB); the installer gitignores the new runtime files (`.recall-state/`,
  `.recall-hits.log`). `session-close` skill + `fmc-close` drafter: proposals waiting on a human
  become PENDING items, and durable FACTS (accounts, URLs) get atomized too — a fact that lives
  only in chat is unrecallable next session.
- Wiring: two new opt-in lines in `adapters/claude-code/settings-fragment.example.json`. Tests:
  +19 (matcher golden fixture, concurrency, hostile session-id, C-locale, no-hang, 500-atom perf).

## 0.3.1 — slug + [[link]] layer; recall by human name

Atoms are now addressable and linkable by a human **slug**, not just a hash id. `recall.sh <slug|id>`
drills an atom by its slug (or exact 12-hex id); the registry shows each atom's slug as its address;
`memory_route --slug` sets an explicit one (otherwise it is derived from the title). `lint_memory` gains
slug-collision detection; dead-link checking stays on `[[hexid]]` links only (a human `[[slug]]` may point
to an external note, so flagging it would be noise).

## 0.3.0 — retrieval-first: the container now RECALLS, not just stores

A retrieval layer so an instance sees WHAT it knows at boot and can pull the one atom it needs, instead of
reading the whole store:
- `gen_rejstrik.sh` + `rejstrik_inject.sh` — a boot-injected **atom registry** (one ranked row per atom),
  always recomputed from the blocks so it cannot drift.
- `recall.sh <id> | --query "words"` — drill a single atom out of the cold store.
- `memory_route --importance 1..5 --origin <src>` — first-class ranking + provenance DNA in the block body
  frontmatter (the block marker stays frozen, so idempotence is untouched).
- `lint_memory.sh` — advisory atom hygiene (duplicate id / bad DNA / missing title / dead link), also a
  metric in the health report. It measures and proposes; it never blocks a write.

## 0.2.3 — boot orientation survives an un-migrated memory

Three boot-nerve fixes: `state_inject` now injects the legacy orientation file (with a loud migrate
reminder) instead of withholding it; the folder index counts nested `.md` recursively instead of lying
"(folder, 0 files)"; and the close handoff points at the real orientation file.

## 0.2.2 — accurate fallback metrics + honest audit routing

`brain_health` and `session_close` now share one fence-aware definition of an open fallback, so a fenced
documentation example is never counted as real debt; a fresh install no longer routes the capability audit
at a script that is not part of the adopter backbone.

## 0.2.1 — Codex lifecycle adapter

The Codex adapter wires real plugin-bundled lifecycle hooks (SessionStart / UserPromptSubmit / PreCompact)
through one sequential dispatcher, with hash-bound trust via `/hooks`; the self-report distinguishes the
Claude and Codex hosts.

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
