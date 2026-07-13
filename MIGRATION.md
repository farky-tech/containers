# Migration — upgrading an existing fork across FMC versions

> **New here? Installing FMC for the first time? Ignore this file** — fresh installs get everything
> current; start at the README Quickstart. This file only concerns forks cut from older versions.

This guide is for an **adopter fork** (a project that installed a tuned copy of the engine) upgrading
across FMC's breaking changes. It is a **paced, opt-in** upgrade — nothing here is forced, and the engine
keeps working at each step. Per-version adopter actions also live in `ADOPTION.md`; this file is the
consolidated path.

> **Golden rule:** refresh the ENGINE (scripts/lib), never let it overwrite your DATA (`memory/*.md`).
> Use `install_project_template.sh --refresh-scripts .` — it force-overwrites backbone scripts + `lib/`,
> takes a timestamped backup, and **leaves `memory/*.md` untouched**. Do NOT use `--force` (deprecated —
> it also overwrites your memory tree).

## 0.2.0 — Vocabulary rename (breaking)

0.2.0 renames the engine's remaining non-English identifiers so the whole surface reads in English. If
you are upgrading a fork created **before 0.2.0**, your `memory/` folder still uses the old names and the
0.2.0 scripts read only the NEW ones — so you must rename once:

| Old | New |
|---|---|
| `memory/STAV.md`            | `memory/STATE.md`         |
| `memory/ZNALOST.md`         | `memory/KNOWLEDGE.md`     |
| `memory/umim.md`            | `memory/CAN.md`           |
| `memory/zdravi/`            | `memory/health/`          |
| `memory/.session-archiv/`   | `memory/.session-archive/`|

Plus internal renames you only notice if you script against them directly: SessionStart flag
`--boot-dojezd` → `--boot-recovery`; `fallback_log.sh --pozn` → `--note`; memory kind `kalibrace` →
`calibration` (and its required field `hranice:` → `boundary:`); the `state_inject.sh` script (was
`stav_inject.sh`).

**Run the one-shot migrator** — it renames the paths in place and never touches file contents:

```
bash <plugin>/scripts/migrate_vocab.sh --memory-dir <your-project>/memory
```

Or `git mv` the five paths by hand. After it, boot injection and `state_guard` find your `STATE.md`
again. Existing Czech `— → další krok:` carry markers keep working (read back-compat); new carried
items are written with the English `— → next step:` marker.

## 1. Refresh the engine (the older v2 "quiet brain" rework, F0–F5)

```
bash <plugin>/scripts/install_project_template.sh --refresh-scripts <your-project-root>
```

This brings your backbone scripts current (delivers new ones: `close_state.sh`, `brain_health.sh`;
removes retired ones from delivery). It writes `<memory>/.backups/` + `<memory>/.fmc-source` and
gitignores them. Verify: `git diff --stat` should match the CHANGELOG delta; drift should be 0.

## 2. Memory model changes — what your `memory/` becomes

- **`KNOWLEDGE.md` replaces the old `pouceni.md` + `rozhodnuti.md` + `postupy.md`.** `memory_route.sh`
  routes `--kind lesson|decision|procedure` into `KNOWLEDGE.md` (one store, blocks tagged `kind:`). Any
  old genre files stay **readable**; merge their content into `KNOWLEDGE.md` when convenient (not required).
- **`primitiva.md` is gone from the template** (engine knowledge belongs in plugin docs, not each copy).
- **Candidates / GO-queue are tagged todo lines**, not separate stores: `- [ ] CANDIDATE(type): …` /
  `- [ ] GO: … | risk | rollback` in `todo.md`. The old `kandidat.sh` / `goqueue_write.sh` scripts were retired.
- Net: live memory went from ~14 files to ~10. Day-1 payload ≈ 7 memory files + backbone scripts + `/close`.

## 3. Close flow — one command

- **Close is `/close`** (or the `session-close` skill): the `fmc-close` **drafter** subagent does the
  mechanics (writes `STATE.md`/sessions/log, reconciles the ledger) and hands you a DRAFT; you review + do
  the retro + approve. On a host without subagents (Codex), run the backbone scripts inline.
- **A forgotten close is auto-recovered:** SessionEnd leaves an `UNCLOSED-<sid>` marker → next boot
  `close_state.sh --boot-recovery` surfaces it → run `/close --auto <SID>` to reconstruct it (labeled
  "auto, unapproved"). Wire `--boot-recovery` into your SessionStart (see the settings fragment).

## 4. What to REMOVE from your hooks

- **Drop the Stop close-debt nag** if you wired it: remove the `Stop` hook calling `close_state.sh … --check`.
  The `--check` mode was removed — auto-recovery replaces it (it never enforced and misfired mid-work). The
  **LEDGER gate stays** (close still reconciles the todo).
- **If you opted into loops** (`.loop-state/enabled.env`): the LOOP gate was removed. Delete that file;
  maintenance is now the **weekly observer** — wire `brain_health.sh --due-check` into SessionStart and run
  the `fmc-janitor` observer when boot flags it. Observer, not gate: it measures + proposes.

## 5. Recommended new SessionStart wiring (opt-in, invasive)

See `adapters/claude-code/settings-fragment.example.json` for the full block. The additions to paste in
(after `close_state.sh --init`): `close_state.sh --boot-recovery` and `brain_health.sh --due-check`. These
cross the trust boundary (they write/read memory-state), so they are **never** force-wired into `hooks.json`.

---

## Appendix — legacy `## date` entries → canonical blocks

Old `memory/*.md` files may use a legacy heading format (`## YYYY-MM-DD — Title`). This is **safe and
supported** — the backbone scripts are append-only and never rewrite or delete legacy prose; counts, drift,
and carry-forward all work across mixed files. There is **no automatic rewriter** (the one-shot
`migrate_legacy.sh` was retired — blind conversion risked losing nuance). To canonicalize a file by hand:
re-enter each legacy entry through the matching script (`fallback_log.sh` / `memory_route.sh` / …), then
delete the old heading once the canonical block exists.
