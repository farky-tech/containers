#!/usr/bin/env bash
# test_boot_nerves.sh — the 8 "boot nerve" scripts that fire on EVERY SessionStart had
# ZERO tests before this file (audit finding: untested capability = unproven capability).
# Covers: capability_inject.sh · state_inject.sh · index_inject.sh · journal_prompt.sh ·
#         gen_index.sh · gen_agents.sh --check · sync_lapac.sh · watch.sh
#
# Zero-dep bash, hermetic (mktemp -d + trap cleanup), deterministic (HERMES_FAKE_TS where
# a script reads it). Style matches test_state_guard.sh / test_backbone_scripts.sh.
#
# SAFETY: several of these scripts default to $HOME or cwd/CLAUDE_PROJECT_DIR when a flag
# is absent. Every invocation below pins HOME / CLAUDE_PROJECT_DIR / script-copy-location
# explicitly into the temp sandbox so nothing here can ever write into the real
# ~/.claude, the real repo memory/, or the plugin's own tracked skills/agents files.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(cd "$here/.." && pwd)"
scripts="$plugin_root/scripts"

T="$(mktemp -d "${TMPDIR:-/tmp}/hermes-bootnerves.XXXXXX")"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

export HERMES_FAKE_TS="2026-07-07T10:00:00Z"

# ============================================================================
echo "== 1. capability_inject.sh — drift delta, anchored inbox dedup, atomic snapshot =="
CI="$scripts/capability_inject.sh"

# --- 1a. first run = baseline (no drift markers), snapshot created ---------
home_a="$T/ci_a/home"; mem_a="$T/ci_a/memory"
mkdir -p "$home_a/.claude/skills" "$home_a/.claude/agents" "$mem_a"
out1="$(HOME="$home_a" bash "$CI" --memory-dir "$mem_a")"
echo "$out1" | grep -q 'capability snapshot baseline initialized' \
  && ok "first run: baseline message, no crash" || bad "first run: missing baseline message"
echo "$out1" | grep -q '➕\|➖' \
  && bad "first run: falsely reports drift before any snapshot existed" \
  || ok "first run: no bogus drift on baseline"
[ -f "$mem_a/.capability-snapshot" ] && ok "snapshot file created" || bad "snapshot file missing"

# --- 1b. unchanged second run -> "no change" --------------------------------
out2="$(HOME="$home_a" bash "$CI" --memory-dir "$mem_a")"
echo "$out2" | grep -q 'no change since last boot' && ok "unchanged run: reports no drift" \
  || bad "unchanged run: missing 'no change': $out2"

# --- 1c. add a skill -> ➕ delta + auto-stub in inbox -----------------------
mkdir -p "$home_a/.claude/skills/newskill"
printf 'description: a brand new skill\n' > "$home_a/.claude/skills/newskill/SKILL.md"
out3="$(HOME="$home_a" bash "$CI" --memory-dir "$mem_a")"
echo "$out3" | grep -q '➕ NEW since last boot' && echo "$out3" | grep -q 'skill:newskill' \
  && ok "added skill: ➕ delta reported" || bad "added skill: no ➕ delta: $out3"
[ -f "$mem_a/.capability-inbox" ] && grep -qF -- '] skill:newskill —' "$mem_a/.capability-inbox" \
  && ok "added skill: auto-stubbed into .capability-inbox" || bad "added skill: no inbox stub"

# --- 1d. remove a skill -> ➖ delta ------------------------------------------
rm -rf "$home_a/.claude/skills/newskill"
out4="$(HOME="$home_a" bash "$CI" --memory-dir "$mem_a")"
echo "$out4" | grep -q '➖ GONE since last boot' && echo "$out4" | grep -q 'skill:newskill' \
  && ok "removed skill: ➖ delta reported" || bad "removed skill: no ➖ delta: $out4"

# --- 1e. atomic snapshot write: no .tmp/.XXXXXX residue after N runs -------
leftover="$(find "$mem_a" -maxdepth 1 -name '.capability-snapshot.??????' 2>/dev/null | wc -l | tr -d ' ')"
[ "$leftover" = "0" ] && ok "atomic write: no tmp residue after 4 runs" \
  || bad "atomic write: $leftover leftover tmp snapshot file(s)"

# --- 1e2. inbox lock lifecycle (0.1.35 re-audit): fresh lock defers stub WITHOUT
#          absorbing the delta; stale lock is reclaimed out loud ---------------------
mem_e="$T/ci_e"; home_e="$T/ci_e_home"; mkdir -p "$mem_e" "$home_e/.claude/skills/s1"
printf -- '---\ndescription: one\n---\n' > "$home_e/.claude/skills/s1/SKILL.md"
HOME="$home_e" bash "$CI" --memory-dir "$mem_e" >/dev/null    # baseline
mkdir -p "$home_e/.claude/skills/s2"; printf -- '---\ndescription: two\n---\n' > "$home_e/.claude/skills/s2/SKILL.md"
mkdir "$mem_e/.capability-inbox.lock"                          # FRESH lock (concurrent boot)
out5="$(HOME="$home_e" bash "$CI" --memory-dir "$mem_e")"
{ echo "$out5" | grep -q 'skill:s2' && ! grep -q 'skill:s2' "$mem_e/.capability-inbox" 2>/dev/null; } \
  && ok "fresh inbox lock: drift printed, stub deferred (not written)" \
  || bad "fresh-lock behavior wrong: $out5"
out6="$(HOME="$home_e" bash "$CI" --memory-dir "$mem_e")"      # still locked -> delta must RE-SURFACE
echo "$out6" | grep -q 'skill:s2' \
  && ok "deferred stub: delta re-surfaces next boot (snapshot NOT absorbed)" \
  || bad "delta silently absorbed while stub was skipped: $out6"
rmdir "$mem_e/.capability-inbox.lock"
HOME="$home_e" bash "$CI" --memory-dir "$mem_e" >/dev/null
grep -q 'skill:s2' "$mem_e/.capability-inbox" \
  && ok "lock released: deferred stub finally written" \
  || bad "stub not written after lock release"
mkdir -p "$home_e/.claude/skills/s3"; printf -- '---\ndescription: three\n---\n' > "$home_e/.claude/skills/s3/SKILL.md"
mkdir "$mem_e/.capability-inbox.lock"; touch -t 202501010000 "$mem_e/.capability-inbox.lock"
out8="$(HOME="$home_e" bash "$CI" --memory-dir "$mem_e")"
{ echo "$out8" | grep -q 'reclaiming stale inbox lock' && grep -q 'skill:s3' "$mem_e/.capability-inbox"; } \
  && ok "stale (backdated) inbox lock reclaimed out loud, stub written" \
  || bad "stale inbox lock not reclaimed: $out8"

# --- 1f. anchored inbox dedup: skill:git must NOT collide with a pre-existing
#         skill:github stub (superstring). Natural drift sequence, own sandbox. --------
home_b="$T/ci_b/home"; mem_b="$T/ci_b/memory"
mkdir -p "$home_b/.claude/skills" "$home_b/.claude/agents" "$mem_b"
HOME="$home_b" bash "$CI" --memory-dir "$mem_b" >/dev/null            # run1: empty baseline
mkdir -p "$home_b/.claude/skills/github"
printf 'description: github skill\n' > "$home_b/.claude/skills/github/SKILL.md"
HOME="$home_b" bash "$CI" --memory-dir "$mem_b" >/dev/null            # run2: +skill:github -> stub
mkdir -p "$home_b/.claude/skills/git"
printf 'description: git skill\n' > "$home_b/.claude/skills/git/SKILL.md"
HOME="$home_b" bash "$CI" --memory-dir "$mem_b" >/dev/null            # run3: +skill:git -> must ALSO stub
# NB: `grep -c` prints "0" AND exits 1 on no-match — a trailing `|| echo 0` would double-print
# ("0\n0"). Capture raw, then default only if truly empty (e.g. file absent).
n_git="$(grep -c '^- \[ \] skill:git —' "$mem_b/.capability-inbox" 2>/dev/null)"; n_git="${n_git:-0}"
n_github="$(grep -c '^- \[ \] skill:github —' "$mem_b/.capability-inbox" 2>/dev/null)"; n_github="${n_github:-0}"
[ "$n_git" = "1" ] && [ "$n_github" = "1" ] \
  && ok "anchored dedup: skill:git stub NOT swallowed by skill:github (both present, 1 each)" \
  || bad "anchored dedup broken: skill:git=$n_git skill:github=$n_github"

# --- 1g. discrimination: mutate the dedup anchor into a naive substring check
#         (on a COPY, original untouched) and show the SAME scenario now loses
#         the skill:git stub — proving 1f actually exercises the anchor logic. ---
mkdir -p "$T/ci_mut"
cp "$CI" "$T/ci_mut/capability_inject.sh"
sed -i.bak 's/grep -qF -- "\] \$item —"/grep -qF -- "$item"/' "$T/ci_mut/capability_inject.sh"
rm -f "$T/ci_mut/capability_inject.sh.bak"
if ! diff -q "$CI" "$T/ci_mut/capability_inject.sh" >/dev/null 2>&1; then
  home_c="$T/ci_c/home"; mem_c="$T/ci_c/memory"
  mkdir -p "$home_c/.claude/skills" "$home_c/.claude/agents" "$mem_c"
  # NB: the copied script's PLUGIN_SKILLS (../skills relative to the copy) resolves to
  # nothing in the sandbox — seed one constant agent so `NOW` is non-empty on run1 and a
  # baseline actually gets persisted (else the script silently no-ops on an all-empty NOW).
  printf '# baseline agent\n' > "$home_c/.claude/agents/baseline-agent.md"
  HOME="$home_c" bash "$T/ci_mut/capability_inject.sh" --memory-dir "$mem_c" >/dev/null
  mkdir -p "$home_c/.claude/skills/github"
  printf 'description: github skill\n' > "$home_c/.claude/skills/github/SKILL.md"
  HOME="$home_c" bash "$T/ci_mut/capability_inject.sh" --memory-dir "$mem_c" >/dev/null
  mkdir -p "$home_c/.claude/skills/git"
  printf 'description: git skill\n' > "$home_c/.claude/skills/git/SKILL.md"
  HOME="$home_c" bash "$T/ci_mut/capability_inject.sh" --memory-dir "$mem_c" >/dev/null
  n_git_mut="$(grep -c '^- \[ \] skill:git —' "$mem_c/.capability-inbox" 2>/dev/null)"; n_git_mut="${n_git_mut:-0}"
  [ "$n_git_mut" = "0" ] \
    && ok "DISCRIMINATION: naive-substring mutant reproduces the swallow bug (test 1f would catch this regression)" \
    || bad "DISCRIMINATION: mutant did not reproduce the bug — test 1f may not actually be exercising the anchor"
else
  bad "mutation setup failed: sed did not change the script"
fi

# ============================================================================
echo "== 2. state_inject.sh — STATE.md missing must never break boot; present must inject =="
SI="$scripts/state_inject.sh"

mem2a="$T/si_a"; mkdir -p "$mem2a"
out="$(bash "$SI" --memory-dir "$mem2a")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && ok "no STATE.md: silent + exit 0" \
  || bad "no STATE.md: not silent/clean (rc=$rc): $out"

mem2b="$T/si_b"; mkdir -p "$mem2b"
printf 'MARKER-STATE-XYZ orientation text\n' > "$mem2b/STATE.md"
out="$(bash "$SI" --memory-dir "$mem2b")"; rc=$?
echo "$out" | grep -q 'MARKER-STATE-XYZ' && echo "$out" | grep -q 'ORIENTATION' && [ "$rc" -eq 0 ] \
  && ok "STATE.md present: injected verbatim" || bad "STATE.md present: not injected: $out"

# --- upgraded-but-not-migrated (0.2.3): only legacy STAV.md exists -> warn LOUD *and* still inject.
#     Regression: pre-0.2.3 this branch printed the migration hail and WITHHELD orientation entirely,
#     so the single most-important boot nerve fell silent over a vocab rename (found by cc_farky dog-food). ---
mem2c="$T/si_c"; mkdir -p "$mem2c"
printf 'MARKER-STAV-LEGACY orientation text\n' > "$mem2c/STAV.md"
out="$(bash "$SI" --memory-dir "$mem2c")"; rc=$?
{ echo "$out" | grep -q 'MARKER-STAV-LEGACY' && echo "$out" | grep -qi 'migration needed' && [ "$rc" -eq 0 ]; } \
  && ok "legacy STAV.md only: migration warned LOUD AND orientation still injected (0.2.3 back-compat)" \
  || bad "legacy STAV.md: withheld orientation or crashed (rc=$rc): $out"

# ============================================================================
echo "== 3. index_inject.sh — missing folders silent, existing folder injects table =="
II="$scripts/index_inject.sh"

root3a="$T/ii_a/root"; home3a="$T/ii_a/home"
mkdir -p "$root3a" "$home3a"
out="$(CLAUDE_PROJECT_DIR="$root3a" HOME="$home3a" bash "$II" --memory-dir "$root3a/memory")"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'memory manifest' \
  && ok "no subfolders exist: does not crash, still prints header" \
  || bad "no subfolders exist: crashed or missing header (rc=$rc): $out"

root3b="$T/ii_b/root"; home3b="$T/ii_b/home"
mkdir -p "$root3b/memory" "$home3b"
printf '# Testfile\nsome content\n' > "$root3b/memory/testfile.md"
out="$(CLAUDE_PROJECT_DIR="$root3b" HOME="$home3b" bash "$II" --memory-dir "$root3b/memory")"
echo "$out" | grep -q 'testfile.md' && ok "memory/ folder present: table lists testfile.md" \
  || bad "memory/ folder present: testfile.md missing from injected table: $out"
[ -f "$root3b/memory/INDEX.md" ] && ok "memory/INDEX.md regenerated on disk" \
  || bad "memory/INDEX.md not (re)generated"

# --- whole-repo scope (0.1.31): map of ALL top-level folders + root INDEX, opt-in --------
root3c="$T/ii_c/root"; home3c="$T/ii_c/home"
mkdir -p "$root3c/memory" "$root3c/knihovna" "$root3c/plainfolder" "$root3c/Koš" "$home3c"
printf '# Mem\nmemory note\n' > "$root3c/memory/m.md"
printf '# Kni\n> knihovna kontext\n<!-- gen_index:auto -->\n' > "$root3c/knihovna/INDEX.md"  # tracked (marker = real INDEX)
printf '# Plain\n> plain folder\n' > "$root3c/plainfolder/doc.md"    # untracked (no INDEX)
printf '# Trash\ntrash\n' > "$root3c/Koš/x.md"

# default scope = memory only: NO repo map (boot diet preserved)
outd="$(CLAUDE_PROJECT_DIR="$root3c" HOME="$home3c" bash "$II" --memory-dir "$root3c/memory")"
{ echo "$outd" | grep -q 'memory manifest' && ! echo "$outd" | grep -q 'REPO — folder map'; } \
  && ok "default scope stays memory-only (no repo map)" || bad "default scope leaked repo map: $outd"

# whole-repo: injects the repo map (all top-level folders) + memory detail
outw="$(CLAUDE_PROJECT_DIR="$root3c" HOME="$home3c" bash "$II" --memory-dir "$root3c/memory" --whole-repo)"; rc=$?
{ [ "$rc" -eq 0 ] && echo "$outw" | grep -q 'REPO — folder map' \
  && echo "$outw" | grep -q '`knihovna/`' && echo "$outw" | grep -q '`plainfolder/`' \
  && echo "$outw" | grep -q '`memory/`' && echo "$outw" | grep -q 'm.md'; } \
  && ok "whole-repo: root map lists ALL top-level folders + memory detail" \
  || bad "whole-repo: map incomplete (rc=$rc): $outw"
# Koš excluded from the deep per-folder refresh (no INDEX.md written into it)
[ ! -f "$root3c/Koš/INDEX.md" ] && ok "whole-repo: Koš excluded from per-folder refresh" \
  || bad "whole-repo: Koš got an INDEX.md (should be skipped)"
# root INDEX.md generated and must NOT list itself
{ [ -f "$root3c/INDEX.md" ] && ! grep -q '`INDEX.md`' "$root3c/INDEX.md"; } \
  && ok "whole-repo: root INDEX.md generated and does not self-list" \
  || bad "whole-repo: root INDEX.md missing or self-lists"
# tracked folder INDEX.md refreshed, curated header kept
{ grep -q 'knihovna kontext' "$root3c/knihovna/INDEX.md" && grep -q 'gen_index:auto' "$root3c/knihovna/INDEX.md"; } \
  && ok "whole-repo: tracked folder INDEX.md refreshed, header preserved" \
  || bad "whole-repo: tracked folder INDEX.md broken"

# whole-repo skips symlinked folders (no write-through, no foreign content in map) — audit 2026-07-12
root3d="$T/ii_d/root"; home3d="$T/ii_d/home"; ext3d="$T/ii_d/external"
mkdir -p "$root3d/memory" "$ext3d" "$home3d"
printf '# m\nx\n' > "$root3d/memory/m.md"
printf '# ext\n<!-- gen_index:auto -->\nexternal secret notes\n' > "$ext3d/INDEX.md"
ln -s "$ext3d" "$root3d/linked"
outsl="$(CLAUDE_PROJECT_DIR="$root3d" HOME="$home3d" bash "$II" --memory-dir "$root3d/memory" --whole-repo 2>/dev/null)"
! echo "$outsl" | grep -q '`linked/`' && ok "whole-repo skips symlinked folder (not in map)" \
  || bad "whole-repo followed a symlink into the map: $outsl"

# whole-repo mtime skip: an unchanged folder is NOT regenerated on the 2nd boot — audit 2026-07-12
root3e="$T/ii_e/root"; home3e="$T/ii_e/home"
mkdir -p "$root3e/memory" "$root3e/stable" "$home3e"
printf '# m\nx\n' > "$root3e/memory/m.md"
printf '# S\n<!-- gen_index:auto -->\n' > "$root3e/stable/INDEX.md"
printf '# doc\ndesc\n' > "$root3e/stable/doc.md"
mstat() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }   # BSD | GNU
CLAUDE_PROJECT_DIR="$root3e" HOME="$home3e" bash "$II" --memory-dir "$root3e/memory" --whole-repo >/dev/null 2>&1
m1="$(mstat "$root3e/stable/INDEX.md")"; sleep 1
CLAUDE_PROJECT_DIR="$root3e" HOME="$home3e" bash "$II" --memory-dir "$root3e/memory" --whole-repo >/dev/null 2>&1
m2="$(mstat "$root3e/stable/INDEX.md")"
[ "$m1" = "$m2" ] && ok "whole-repo mtime skip: unchanged folder not regenerated" \
  || bad "whole-repo regenerated an unchanged folder ($m1 -> $m2)"

# ============================================================================
echo "== 4. journal_prompt.sh — write-only nerve: zero stdout noise, never blocks =="
JP="$scripts/journal_prompt.sh"

mem4a="$T/jp_a"; mkdir -p "$mem4a"
out="$(printf '{"prompt":"hello from the test"}' | bash "$JP" --memory-dir "$mem4a")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && ok "valid prompt: zero stdout, exit 0" \
  || bad "valid prompt: stdout noise or bad exit (rc=$rc): '$out'"
[ -f "$mem4a/session.md" ] && grep -q 'USER' "$mem4a/session.md" && grep -q 'hello from the test' "$mem4a/session.md" \
  && ok "valid prompt: actually written into session.md" || bad "valid prompt: not found in session.md"

mem4b="$T/jp_b"; mkdir -p "$mem4b"
out="$(printf '{"prompt":"   \\n\\t  "}' | bash "$JP" --memory-dir "$mem4b")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && [ ! -f "$mem4b/session.md" ] \
  && ok "whitespace-only prompt: silent no-op, no file created" \
  || bad "whitespace-only prompt: unexpected output/file (rc=$rc): '$out'"

mem4c="$T/jp_c"; mkdir -p "$mem4c"
secret='sk-ant-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
out="$(printf '{"prompt":"my key is %s ok"}' "$secret" | bash "$JP" --memory-dir "$mem4c")"; rc=$?
if [ -f "$mem4c/session.md" ] && grep -q '\[REDACTED\]' "$mem4c/session.md" && ! grep -qF "$secret" "$mem4c/session.md"; then
  ok "secret in prompt: redacted before it ever touches (git-tracked) session.md"
else
  bad "secret in prompt: leaked or not redacted"
fi

mem4d="$T/jp_d"; mkdir -p "$mem4d"
out="$(printf 'this is not json at all {' | bash "$JP" --memory-dir "$mem4d")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && ok "malformed JSON stdin: never blocks the prompt (exit 0, silent)" \
  || bad "malformed JSON stdin: broke the hard invariant (rc=$rc): '$out'"

# --- idle OPEN stdin must not hang the per-turn nerve (0.1.33; same hang family as
# close_state 0.1.30 / ledger_carry 0.1.29 — this was the last unbounded `cat` in backbone) ---
mem4e="$T/jp_e"; mkdir -p "$mem4e"
start_e="$(date +%s)"
bash "$JP" --memory-dir "$mem4e" < <(sleep 8) >/dev/null 2>&1; rc=$?
end_e="$(date +%s)"; el=$((end_e - start_e))
[ "$rc" -eq 0 ] && [ "$el" -le 5 ] && ok "idle open stdin: bounded read returns fast (${el}s), exit 0" \
  || bad "idle open stdin: hung for ${el}s or rc=$rc"

# --- no-jq fallback: journaling must survive without jq (zero-dep promise, 0.1.33) ---
mem4f="$T/jp_f"; mkdir -p "$mem4f"
out="$(printf '{"prompt":"fallback path test with \\"quotes\\" inside"}' | HERMES_NO_JQ=1 bash "$JP" --memory-dir "$mem4f")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && [ -f "$mem4f/session.md" ] && grep -q 'fallback path test' "$mem4f/session.md" \
  && ok "no-jq fallback: prompt still journaled via sed/awk path" \
  || bad "no-jq fallback: rc=$rc content='$(cat "$mem4f/session.md" 2>/dev/null || echo MISSING)'"

mem4g="$T/jp_g"; mkdir -p "$mem4g"
printf '{"prompt":"my key is %s ok"}' "$secret" | HERMES_NO_JQ=1 bash "$JP" --memory-dir "$mem4g" >/dev/null 2>&1
{ [ -f "$mem4g/session.md" ] && grep -q '\[REDACTED\]' "$mem4g/session.md" && ! grep -qF "$secret" "$mem4g/session.md"; } \
  && ok "no-jq fallback: secret still redacted downstream of extraction" \
  || bad "no-jq fallback: secret leaked or nothing written"

# --- backslash adjacency (0.1.35 re-audit): "C:\new" must NOT corrupt to "C:\ ew" ---
mem4h="$T/jp_h"; mkdir -p "$mem4h"
printf '%s' '{"prompt":"path C:\\new and C:\\top done"}' | HERMES_NO_JQ=1 bash "$JP" --memory-dir "$mem4h" >/dev/null 2>&1
grep -qF 'path C:\new and C:\top done' "$mem4h/session.md" 2>/dev/null \
  && ok "no-jq fallback: backslash before n/t survives (single-pass unescape)" \
  || bad "no-jq fallback corrupted backslash text: $(grep 'USER' "$mem4h/session.md" 2>/dev/null || echo MISSING)"
if command -v jq >/dev/null 2>&1; then
  mem4i="$T/jp_i"; mkdir -p "$mem4i"
  printf '%s' '{"prompt":"path C:\\new and C:\\top done"}' | bash "$JP" --memory-dir "$mem4i" >/dev/null 2>&1
  grep -qF 'path C:\new and C:\top done' "$mem4i/session.md" 2>/dev/null \
    && ok "jq path parity: identical text preserved" || bad "jq/fallback parity broken"
fi

# ============================================================================
echo "== 5. gen_index.sh — table output, space-in-filename, description precedence, merge =="
GI="$scripts/gen_index.sh"

d5="$T/gi_dir"; mkdir -p "$d5/subskill"
printf -- '---\ndescription: "Desc from frontmatter"\n---\n# Should Not Win\nbody\n' > "$d5/a-frontmatter.md"
printf '> Desc from blockquote\n# Should not win either\n' > "$d5/b-blockquote.md"
printf '# Desc from H1\nbody text\n' > "$d5/c-h1.md"
printf 'plain first line wins here\nmore text\n' > "$d5/d-plain.md"
printf '# Title With Space Name\nbody\n' > "$d5/note one.md"
printf -- '---\ndescription: "Sub skill desc"\n---\nbody\n' > "$d5/subskill/SKILL.md"

out="$(bash "$GI" "$d5" --title "GiTest" --table-only)"
echo "$out" | grep -qF '| File | What it is |' && ok "table: header row present" || bad "table: header row missing"
echo "$out" | grep -qF '`a-frontmatter.md`' && echo "$out" | grep -qF 'Desc from frontmatter' \
  && ok "desc precedence: frontmatter wins over H1 in same file" || bad "desc precedence: frontmatter not used"
echo "$out" | grep -qF '`b-blockquote.md`' && echo "$out" | grep -qF 'Desc from blockquote' \
  && ok "desc precedence: blockquote wins over H1 in same file" || bad "desc precedence: blockquote not used"
echo "$out" | grep -qF '`c-h1.md`' && echo "$out" | grep -qF 'Desc from H1' \
  && ok "desc precedence: H1 used when no frontmatter/blockquote" || bad "desc precedence: H1 not used"
echo "$out" | grep -qF '`d-plain.md`' && echo "$out" | grep -qF 'plain first line wins here' \
  && ok "desc precedence: first line fallback used" || bad "desc precedence: first-line fallback not used"
echo "$out" | grep -qF '`note one.md`' \
  && ok "filename with a SPACE handled correctly" || bad "filename with a space broke the table row"
echo "$out" | grep -qF '`subskill/`' && echo "$out" | grep -qF 'Sub skill desc' \
  && ok "subfolder row derives desc from SKILL.md" || bad "subfolder row missing/wrong desc"

# --- nested-only folder (0.2.3): a folder whose content lives in SUB-folders (e.g. domeny/<d>/*.md)
#     has no top-level lead file. Regression: pre-0.2.3 the count used maxdepth-1 -> "(folder, 0 files)",
#     so the injected map LIED that a rich folder was empty. Must count .md recursively. ---
d5n="$T/gi_nested"; mkdir -p "$d5n/topfolder/sub1" "$d5n/topfolder/sub2"
printf '# a\nx\n' > "$d5n/topfolder/sub1/a.md"
printf '# b\ny\n' > "$d5n/topfolder/sub2/b.md"
outn="$(bash "$GI" "$d5n" --table-only)"
rown="$(printf '%s\n' "$outn" | grep -F '`topfolder/`')"
{ [ -n "$rown" ] && printf '%s' "$rown" | grep -qE '2 \.md files'; } \
  && ok "nested-only folder counts .md recursively, not '(folder, 0 files)' (0.2.3 domeny-lie fix)" \
  || bad "nested folder .md count wrong (regression of domeny=0 lie): $rown"

# --- pipe in derived desc must not break the 2-column table (cc_fos field report 2026-07-12) ---
printf '# Pipe Cell\n> Vytvoreno 2026 | Celkem 42 | verze 3\n' > "$d5/pipe-cell.md"
outp="$(bash "$GI" "$d5" --table-only)"
rowp="$(printf '%s\n' "$outp" | grep -F '`pipe-cell.md`')"
# neutralize escaped \| then count remaining |: exactly 3 cell delimiters = row stayed 2-column
delim="$(printf '%s' "$rowp" | sed 's/\\|/X/g' | tr -cd '|' | wc -c | tr -d ' ')"
{ [ -n "$rowp" ] && [ "$delim" -eq 3 ] && printf '%s' "$rowp" | grep -qF '\|'; } \
  && ok "pipe in derived desc escaped -> table row stays 2-column (3 delimiters)" \
  || bad "pipe in desc broke table: delimiters=$delim row='$rowp'"

# --- merge REFUSES to overwrite an INDEX.md without a marker (BLOCKER fix, audit 2026-07-12) ---
d5m="$T/gi_nomark"; mkdir -p "$d5m"
printf 'HAND-WRITTEN CONTEXT, no marker, must survive\n' > "$d5m/INDEX.md"
bash "$GI" "$d5m" --merge-into "$d5m/INDEX.md" >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 3 ] && grep -q 'HAND-WRITTEN CONTEXT' "$d5m/INDEX.md" && ! grep -q 'gen_index:auto' "$d5m/INDEX.md"; } \
  && ok "merge refuses to overwrite marker-less INDEX.md (content preserved, exit 3)" \
  || bad "merge clobbered marker-less INDEX.md (rc=$rc): $(cat "$d5m/INDEX.md")"

# --- desc_line redacts secrets before they reach the git-tracked INDEX (audit 2026-07-12) ---
d5s="$T/gi_secret"; mkdir -p "$d5s"
printf 'sk-ant-api03-FAKEFAKEFAKEFAKEFAKE123456 key pasted here\n' > "$d5s/rawdump.md"
outs="$(bash "$GI" "$d5s" --table-only)"
{ echo "$outs" | grep -q 'REDACTED' && ! echo "$outs" | grep -q 'sk-ant-api03-FAKE'; } \
  && ok "desc_line redacts a secret-looking first line" \
  || bad "secret leaked into table: $outs"

# --- merge mode: curated header above the marker survives regeneration -----
idx5="$d5/INDEX.md"
bash "$GI" "$d5" --merge-into "$idx5" >/dev/null
sed -i.bak '/gen_index:auto/i\
CURATED-HEADER-MARKER-123
' "$idx5"
rm -f "$idx5.bak"
printf 'new file added after curation\n' > "$d5/e-new.md"
bash "$GI" "$d5" --merge-into "$idx5" >/dev/null
grep -q 'CURATED-HEADER-MARKER-123' "$idx5" && grep -qF '`e-new.md`' "$idx5" \
  && ok "merge mode: curated header preserved AND table refreshed with new file" \
  || bad "merge mode: lost curated header or table not refreshed"

# ============================================================================
echo "== 6. gen_agents.sh --check — in-sync on real repo; DRIFT detected on mutated copy =="
GA="$scripts/gen_agents.sh"

if bash "$GA" --check >/tmp/ga-real-check.$$ 2>&1; then
  grep -q 'in sync' /tmp/ga-real-check.$$ && ok "real repo: --check reports in sync (exit 0)" \
    || bad "real repo: exit 0 but no 'in sync' message"
else
  bad "real repo: --check reports DRIFT (repo not clean / agents/ stale — investigate before trusting this test)"
fi
rm -f /tmp/ga-real-check.$$

cp -R "$plugin_root" "$T/ga_copy"
printf '\nSTRAY MUTATION LINE — not regenerated from subagents/\n' >> "$T/ga_copy/agents/fmc-close.md"
if bash "$T/ga_copy/scripts/gen_agents.sh" --check >/tmp/ga-mut-check.$$ 2>&1; then
  bad "DISCRIMINATION: mutated agents/fmc-close.md was NOT detected as drift"
else
  grep -q 'DRIFT' /tmp/ga-mut-check.$$ && grep -q 'fmc-close' /tmp/ga-mut-check.$$ \
    && ok "DISCRIMINATION: mutated agents/fmc-close.md correctly reported as DRIFT (exit 1)" \
    || bad "DISCRIMINATION: exit 1 but message doesn't name the drifted agent"
fi
rm -f /tmp/ga-mut-check.$$

# ============================================================================
echo "== 7. sync_lapac.sh — maintainer-only sync, isolated so it can never touch the real plugin =="
SL="$scripts/sync_lapac.sh"
if [ ! -f "$SL" ]; then
  echo "  SKIP: sync_lapac.sh not shipped in this copy (maintainer-only) — §7 skipped"
else

mkdir -p "$T/sl/scripts"
cp "$SL" "$T/sl/scripts/sync_lapac.sh"   # copy so \$script_dir/../skills/lapac resolves INTO the sandbox

out="$(LAPAC_CANON="$T/sl/no-such-canon" bash "$T/sl/scripts/sync_lapac.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ ! -f "$T/sl/skills/lapac/SKILL.md" ] \
  && ok "no canon at LAPAC_CANON: no-op success, nothing written" \
  || bad "no canon: unexpected write or non-zero exit (rc=$rc): $out"

mkdir -p "$T/sl/canon"
printf -- '---\nname: lapac\n---\nCANON MARKER CONTENT\n' > "$T/sl/canon/SKILL.md"
out="$(LAPAC_CANON="$T/sl/canon" bash "$T/sl/scripts/sync_lapac.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$T/sl/skills/lapac/SKILL.md" ] && grep -q 'CANON MARKER CONTENT' "$T/sl/skills/lapac/SKILL.md" \
  && ok "canon present: synced into the (sandboxed) plugin copy dir" \
  || bad "canon present: sync failed (rc=$rc): $out"
fi

# ============================================================================
echo "== 8. watch.sh — fingerprint baseline, silent when unchanged, alert on change =="
W="$scripts/watch.sh"

mem8="$T/watch_mem"; mkdir -p "$mem8"
f8="$T/watched.md"; printf 'version 1\n' > "$f8"

out="$(bash "$W" --memory-dir "$mem8" --paths "$f8" --label "TESTWATCH" 2>&1)"
echo "$out" | grep -q 'baseline initialized' && ok "watch: first run initializes baseline" \
  || bad "watch: first run did not report baseline init: $out"
[ -f "$mem8/.watch-state" ] && ok "watch: .watch-state written" || bad "watch: .watch-state missing"

out="$(bash "$W" --memory-dir "$mem8" --paths "$f8" --label "TESTWATCH" 2>&1)"
[ -z "$out" ] && ok "watch: unchanged file -> silent" || bad "watch: unchanged file was noisy: $out"

printf 'version 2 — changed\n' > "$f8"
out="$(bash "$W" --memory-dir "$mem8" --paths "$f8" --label "TESTWATCH" 2>&1)"
echo "$out" | grep -q '🔔' && echo "$out" | grep -q 'TESTWATCH' && echo "$out" | grep -qF "$f8" \
  && ok "watch: changed file -> alert with label + path" || bad "watch: changed file not detected: $out"

# ============================================================================
echo "== 9. retrieval core (F1) — gen_rejstrik.sh + recall.sh + hermes_get_block =="
GR="$scripts/gen_rejstrik.sh"; RC="$scripts/recall.sh"

mem9="$T/mem9"; mkdir -p "$mem9"
{
  printf '<!-- hermes:entry kind=lesson id=aaaaaaaaaaaa ts=2026-07-15T00:00:00Z -->\nkind: lesson\nimportance: 5\n## 2026-07-15 — Alpha lesson about widgets\nbody alpha widgets\n<!-- /hermes:entry -->\n'
  printf '<!-- hermes:entry kind=decision id=bbbbbbbbbbbb ts=2026-07-15T00:00:01Z -->\nkind: decision\n## 2026-07-15 — Beta decision about gadgets\nbody beta gadgets\n<!-- /hermes:entry -->\n'
} > "$mem9/KNOWLEDGE.md"

bash "$GR" --memory-dir "$mem9" >/dev/null
{ [ -f "$mem9/_rejstrik.md" ] && grep -q 'alpha-lesson-about-widgets' "$mem9/_rejstrik.md" \
  && grep -q 'beta-decision-about-gadgets' "$mem9/_rejstrik.md" && grep -q 'Alpha lesson' "$mem9/_rejstrik.md"; } \
  && ok "gen_rejstrik: registry lists both atoms by derived slug + title" || bad "gen_rejstrik: registry incomplete"

# importance 5 must rank above the default-3 atom: first data row's importance is 5
first_imp="$(grep -oE '^\| [0-9] ' "$mem9/_rejstrik.md" | head -1 | grep -oE '[0-9]')"
[ "$first_imp" = "5" ] && ok "gen_rejstrik: importance 5 ranks above default 3" || bad "gen_rejstrik: importance sort wrong (first imp=$first_imp)"

# recall by human slug (0.3.x) resolves to the atom, same as by id
slug_a="$(grep -oE '`[a-z0-9-]*alpha-lesson-about-widgets`' "$mem9/_rejstrik.md" | head -1 | tr -d '`')"
out="$(bash "$RC" --memory-dir "$mem9" "$slug_a")"; rc=$?
{ [ "$rc" -eq 0 ] && echo "$out" | grep -q 'Alpha lesson' && ! echo "$out" | grep -q 'Beta'; } \
  && ok "recall by slug: derived slug -> right block" || bad "recall by slug wrong (rc=$rc slug=$slug_a): $out"

# recall by id -> exactly that block, nothing else
out="$(bash "$RC" --memory-dir "$mem9" bbbbbbbbbbbb)"; rc=$?
{ [ "$rc" -eq 0 ] && echo "$out" | grep -q 'Beta decision' && echo "$out" | grep -q 'id=bbbbbbbbbbbb' \
  && ! echo "$out" | grep -q 'Alpha lesson'; } \
  && ok "recall by id: returns only that block" || bad "recall by id: wrong/empty (rc=$rc): $out"

# recall --query -> ALL words must match; returns only the matching block
out="$(bash "$RC" --memory-dir "$mem9" --query "beta gadgets")"; rc=$?
{ [ "$rc" -eq 0 ] && echo "$out" | grep -q 'Beta decision' && ! echo "$out" | grep -q 'Alpha'; } \
  && ok "recall --query: ALL-words match returns only the right block" || bad "recall --query wrong (rc=$rc): $out"

# recall no-match -> exit 2, silent (never a false hit)
out="$(bash "$RC" --memory-dir "$mem9" --query "nonexistentword" 2>/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && [ -z "$out" ] && ok "recall --query: no match -> exit 2, silent" || bad "recall no-match wrong (rc=$rc): $out"
bash "$RC" --memory-dir "$mem9" ffffffffffff >/dev/null 2>&1; [ "$?" -eq 2 ] \
  && ok "recall unknown id -> exit 2" || bad "recall unknown id: wrong exit"

# hermes_get_block: extract exactly one block; unknown id -> non-zero
( . "$scripts/lib/hermes_blocks.sh"
  blk="$(hermes_get_block "$mem9/KNOWLEDGE.md" aaaaaaaaaaaa)"
  printf '%s' "$blk" | grep -q 'Alpha lesson' && ! printf '%s' "$blk" | grep -q 'Beta' \
    && ! hermes_get_block "$mem9/KNOWLEDGE.md" zzzzzzzzzzzz >/dev/null 2>&1 ) \
  && ok "hermes_get_block: extracts one block, unknown id -> non-zero" || bad "hermes_get_block wrong"

# rejstrik_inject: empty store silent; populated store regenerates + injects
mem9e="$T/mem9e"; mkdir -p "$mem9e"
oute="$(bash "$scripts/rejstrik_inject.sh" --memory-dir "$mem9e" 2>&1)"; rce=$?
{ [ -z "$oute" ] && [ "$rce" -eq 0 ]; } && ok "rejstrik_inject: empty store -> silent, exit 0" || bad "rejstrik_inject empty: noisy (rc=$rce)"
outp="$(bash "$scripts/rejstrik_inject.sh" --memory-dir "$mem9" 2>&1)"
{ echo "$outp" | grep -q 'REJSTŘÍK' && echo "$outp" | grep -q 'Alpha lesson'; } \
  && ok "rejstrik_inject: populated store -> regenerates + injects" || bad "rejstrik_inject populated: missing content"

# ============================================================================
echo "== 10. lint_memory.sh (F3) — atom hygiene, advisory not a gate =="
LM="$scripts/lint_memory.sh"
mem10="$T/mem10"; mkdir -p "$mem10"

printf '<!-- hermes:entry kind=lesson id=cccccccccccc ts=2026-07-15T00:00:00Z -->\nkind: lesson\nimportance: 3\n## Clean atom\nbody\n<!-- /hermes:entry -->\n' > "$mem10/KNOWLEDGE.md"
out="$(bash "$LM" --memory-dir "$mem10")"; rc=$?
{ [ "$rc" -eq 0 ] && echo "$out" | grep -q '0 issues'; } && ok "lint: clean store -> 0 issues, exit 0" || bad "lint clean wrong (rc=$rc): $out"

{
  printf '<!-- hermes:entry kind=lesson id=dddddddddddd ts=2026-07-15T00:00:00Z -->\nkind: lesson\n## A\nsee [[beefbeefbeef]]\n<!-- /hermes:entry -->\n'
  printf '<!-- hermes:entry kind=lesson id=dddddddddddd ts=2026-07-15T00:00:01Z -->\nkind: lesson\nimportance: 8\n## B\nx\n<!-- /hermes:entry -->\n'
} > "$mem10/KNOWLEDGE.md"
out="$(bash "$LM" --memory-dir "$mem10")"; rc=$?
{ [ "$rc" -eq 0 ] && echo "$out" | grep -q 'DUPLICITNÍ' && echo "$out" | grep -qi 'importance mimo' && echo "$out" | grep -q 'mrtvý'; } \
  && ok "lint: catches dup id + bad importance + dead link, exit 0 (advisory)" || bad "lint broken-detect wrong (rc=$rc): $out"

# anti-nag (severka): a body WITHOUT the redundant `kind:` line must NOT be flagged — the marker carries kind.
printf '<!-- hermes:entry kind=lesson id=eeeeeeeeeeee ts=2026-07-15T00:00:00Z -->\n## No body kind line\nbody\n<!-- /hermes:entry -->\n' > "$mem10/KNOWLEDGE.md"
out="$(bash "$LM" --memory-dir "$mem10")"
echo "$out" | grep -q '0 issues' && ok "lint: missing redundant body kind: NOT flagged (anti-nag)" || bad "lint over-flags missing body kind: $out"

# --- slug link layer (0.3.x): [[slug]] resolution + collision (extends the [[id]] dead-link check) ---
mem10s="$T/mem10s"; mkdir -p "$mem10s"
{
  printf '<!-- hermes:entry kind=lesson id=1111aaaa1111 ts=2026-07-15T00:00:00Z -->\nkind: lesson\n## Widget alpha\nsee [[deadbeef9999]] and [[some-external-page]]\n<!-- /hermes:entry -->\n'
  printf '<!-- hermes:entry kind=lesson id=3333cccc3333 ts=2026-07-15T00:00:02Z -->\nkind: lesson\nslug: dup-slug\n## One\nx\n<!-- /hermes:entry -->\n'
  printf '<!-- hermes:entry kind=lesson id=4444dddd4444 ts=2026-07-15T00:00:03Z -->\nkind: lesson\nslug: dup-slug\n## Two\nx\n<!-- /hermes:entry -->\n'
} > "$mem10s/KNOWLEDGE.md"
out="$(bash "$LM" --memory-dir "$mem10s")"
{ echo "$out" | grep -q 'deadbeef9999' && echo "$out" | grep -qi 'KOLIZE.*dup-slug' \
  && ! echo "$out" | grep -q 'some-external-page'; } \
  && ok "lint: dead [[hexid]] flagged + slug collision caught + external [[slug]] NOT nagged" \
  || bad "lint slug/id layer wrong: $out"

# ============================================================================
echo ""
echo "== test_boot_nerves: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
