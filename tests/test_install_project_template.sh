#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(cd "$script_dir/.." && pwd)"
installer="$plugin_root/scripts/install_project_template.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  grep -F "$expected" "$file" >/dev/null || fail "Expected $file to contain: $expected"
}

assert_file_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -F "$unexpected" "$file" >/dev/null; then
    fail "Expected $file not to contain: $unexpected"
  fi
}

assert_not_exists() {
  local path="$1"
  [ ! -e "$path" ] || fail "Expected path to not exist: $path"
}

# Space in the root on purpose — adopters' paths have spaces (e.g. "Farky Stack"), and the
# installer must quote everything correctly end to end, not just in the happy-path tests.
tmp_root="$(mktemp -d "${TMPDIR:-/private/tmp}/farky memory container tests.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

echo "Running installer tests in $tmp_root"

echo "test: dry-run does not write"
project="$tmp_root/dry-run-project"
mkdir -p "$project"
"$installer" --dry-run "$project" >/tmp/hermes-dry-run.out
assert_not_exists "$project/memory"

echo "test: default merge does not overwrite existing files"
project="$tmp_root/merge-project"
mkdir -p "$project/memory"
printf 'EXISTING\n' > "$project/memory/MEMORY.md"
"$installer" "$project" >/tmp/hermes-merge.out
assert_file_contains "$project/memory/MEMORY.md" "EXISTING"
[ -f "$project/memory/fallbacks.md" ] || fail "Expected fallback template to be installed"
[ -f "$project/memory/todo.md" ] || fail "Expected todo template to be installed"

echo "test: force creates backup and overwrites"
project="$tmp_root/force-project"
backup="$tmp_root/backups"
mkdir -p "$project/memory"
printf 'EXISTING\n' > "$project/memory/MEMORY.md"
"$installer" --force --backup-dir "$backup" "$project" >/tmp/hermes-force.out
assert_file_contains "$project/memory/MEMORY.md" "contAIner"
backup_file_count="$(find "$backup" -path '*/memory/MEMORY.md' -type f | wc -l | tr -d ' ')"
[ "$backup_file_count" -eq 1 ] || fail "Expected exactly one MEMORY.md backup, got $backup_file_count"
assert_file_contains "$(find "$backup" -path '*/memory/MEMORY.md' -type f | head -n 1)" "EXISTING"

echo "test: multiple targets fail"
project_a="$tmp_root/project-a"
project_b="$tmp_root/project-b"
mkdir -p "$project_a" "$project_b"
if "$installer" "$project_a" "$project_b" >/tmp/hermes-multi.out 2>/tmp/hermes-multi.err; then
  fail "Expected multiple target arguments to fail"
fi

echo "test: missing target fails unless --create-target"
missing="$tmp_root/missing-project"
if "$installer" "$missing" >/tmp/hermes-missing.out 2>/tmp/hermes-missing.err; then
  fail "Expected missing target to fail"
fi
"$installer" --create-target "$missing" >/tmp/hermes-create.out
[ -f "$missing/memory/MEMORY.md" ] || fail "Expected --create-target to install template"

echo "test: symlink target file fails"
project="$tmp_root/symlink-project"
outside="$tmp_root/outside.txt"
mkdir -p "$project/memory"
printf 'OUTSIDE\n' > "$outside"
ln -s "$outside" "$project/memory/MEMORY.md"
if "$installer" --force "$project" >/tmp/hermes-symlink.out 2>/tmp/hermes-symlink.err; then
  fail "Expected symlink overwrite to fail"
fi
assert_file_contains "$outside" "OUTSIDE"

echo "test: existing directory in place of file fails"
project="$tmp_root/dir-conflict-project"
mkdir -p "$project/memory/MEMORY.md"
if "$installer" --force "$project" >/tmp/memory-dir.out 2>/tmp/memory-dir.err; then
  fail "Expected directory conflict to fail"
fi

echo "test: --with-scripts installs the full 21-script backbone from the manifest"
project="$tmp_root/full backbone project"
"$installer" --create-target --with-scripts "$project" >/tmp/hermes-full-backbone.out
backbone_count="$(find "$project/memory/scripts" -maxdepth 1 -name '*.sh' -type f | wc -l | tr -d ' ')"
[ "$backbone_count" -eq 21 ] || fail "Expected 21 backbone scripts installed, got $backbone_count"

echo "test: generated CAN routes capability audit to plugin source, not a missing adopter script"
assert_file_contains "$project/memory/CAN.md" 'installed `capability-audit` skill'
assert_file_contains "$project/memory/CAN.md" '`<plugin-root>/scripts/capability_audit.sh`'
assert_file_not_contains "$project/memory/CAN.md" '→ `scripts/capability_audit.sh`'
assert_not_exists "$project/memory/scripts/capability_audit.sh"

echo "test: --refresh-scripts refreshes a stale backbone script but never touches memory/*.md"
project="$tmp_root/refresh scripts project"
mkdir -p "$project/memory/scripts"
printf 'MY OWN NOTE\n' > "$project/memory/MEMORY.md"
printf '#!/usr/bin/env bash\necho STALE\n' > "$project/memory/scripts/session_note.sh"
chmod +x "$project/memory/scripts/session_note.sh"
"$installer" --refresh-scripts "$project" >/tmp/hermes-refresh.out
# Untouched, byte for byte — refresh-scripts must not even add missing templates.
assert_file_contains "$project/memory/MEMORY.md" "MY OWN NOTE"
assert_not_exists "$project/memory/fallbacks.md"
assert_not_exists "$project/memory/todo.md"
if grep -F "STALE" "$project/memory/scripts/session_note.sh" >/dev/null 2>&1; then
  fail "Expected --refresh-scripts to replace the stale session_note.sh stub"
fi
[ -x "$project/memory/scripts/session_note.sh" ] || fail "Expected refreshed script to remain executable"
refresh_backup="$(find "$project/memory/.backups" -name 'session_note.sh' -type f 2>/dev/null | head -n 1)"
[ -n "$refresh_backup" ] || fail "Expected --refresh-scripts to back up the previous script version"
assert_file_contains "$refresh_backup" "STALE"

echo "test: --refresh-scripts on a project with no memory/ yet creates no markdown templates"
project="$tmp_root/refresh scripts fresh project"
"$installer" --create-target --refresh-scripts "$project" >/tmp/hermes-refresh-fresh.out
assert_not_exists "$project/memory/MEMORY.md"
[ -f "$project/memory/scripts/session_note.sh" ] || fail "Expected --refresh-scripts to still deliver backbone scripts"

echo "test: --force backup defaults to a persistent location under the target, not TMPDIR"
# Note: this whole test sandbox lives under TMPDIR (tmp_root, above), so a plain substring
# check against TMPDIR would false-fail here regardless of the installer's behavior. The real
# invariant is structural: the backup must land under the TARGET's own memory/.backups/ (which
# survives independently of TMPDIR housekeeping), not under the old bare
# "$TMPDIR/farky-memory-container-backups" default.
project="$tmp_root/force default backup project"
mkdir -p "$project/memory"
printf 'EXISTING\n' > "$project/memory/MEMORY.md"
"$installer" --force "$project" >/tmp/hermes-force-default.out
default_backup="$(find "$project/memory/.backups" -path '*/memory/MEMORY.md' -type f 2>/dev/null | head -n 1)"
[ -n "$default_backup" ] || fail "Expected a default --force backup under $project/memory/.backups"
case "$default_backup" in
  */farky-memory-container-backups/*)
    fail "Expected default backup away from the old bare TMPDIR location, got: $default_backup"
    ;;
esac

echo "test: --with-scripts stamps memory/.fmc-source with source_version/source_dir/installed_at"
project="$tmp_root/marker project"
"$installer" --create-target --with-scripts "$project" >/tmp/hermes-marker.out
marker="$project/memory/.fmc-source"
[ -f "$marker" ] || fail "Expected memory/.fmc-source to be written"
grep -qE '^source_version=.+$' "$marker" || fail "Expected source_version=<value> in $marker"
grep -qF "source_dir=$plugin_root" "$marker" || fail "Expected source_dir=$plugin_root in $marker"
grep -qE '^installed_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$marker" \
  || fail "Expected installed_at=<UTC timestamp> in $marker"

echo "test: HERMES_FAKE_TS overrides installed_at in the .fmc-source marker"
project="$tmp_root/marker fake ts project"
HERMES_FAKE_TS="2026-01-02T03:04:05Z" "$installer" --create-target --refresh-scripts "$project" >/tmp/hermes-marker-fake.out
assert_file_contains "$project/memory/.fmc-source" "installed_at=2026-01-02T03:04:05Z"

echo "test: scripts delivery ensures runtime artefacts in .gitignore next to memory dir (idempotent)"
project="$tmp_root/gitignore ensure project"
"$installer" --create-target --with-scripts "$project" >/tmp/hermes-gitignore.out
gi="$project/.gitignore"
[ -f "$gi" ] || fail "Expected $gi to be created by scripts delivery"
grep -qxF "memory/.backups/" "$gi" || fail "Expected memory/.backups/ line in $gi"
grep -qxF "memory/.fmc-source" "$gi" || fail "Expected memory/.fmc-source line in $gi"
grep -qxF "memory/.close-state/" "$gi" || fail "Expected memory/.close-state/ line in $gi"
"$installer" --refresh-scripts "$project" >/tmp/hermes-gitignore2.out
n_backups="$(grep -cxF "memory/.backups/" "$gi")"
n_marker="$(grep -cxF "memory/.fmc-source" "$gi")"
[ "$n_backups" = "1" ] || fail "Expected exactly 1 memory/.backups/ line after re-run, got $n_backups"
[ "$n_marker" = "1" ] || fail "Expected exactly 1 memory/.fmc-source line after re-run, got $n_marker"

echo "test: docs-only install (no --with-scripts) ALSO ensures the runtime gitignore entries (0.3.9, cc_chobotnice field report)"
project="$tmp_root/gitignore docs-only project"
"$installer" --create-target "$project" >/tmp/hermes-gitignore3.out
gi="$project/.gitignore"
[ -f "$gi" ] || fail "Expected $gi to be created by a docs-only install (engine hooks generate runtime state regardless of --with-scripts)"
for entry in "memory/.close-state/" "memory/.capability-snapshot" "memory/.watch-state" "memory/_rejstrik.md" "memory/.recall-state/"; do
  grep -qxF "$entry" "$gi" || fail "Expected $entry line in $gi after docs-only install"
done
# Fáze A (2026-07-18): the prompt journal is a LOCAL-ONLY black box (bounded prompt excerpts) and
# MUST be gitignored by default so a prompt log can't be pushed by accident — the one real privacy
# default of auto-wire. Curated continuity stays tracked (INDEX.md et al.).
for entry in "memory/session.md" "memory/.session-archive/" "memory/.capability-inbox"; do
  grep -qxF "$entry" "$gi" || fail "Expected $entry (journal privacy default) in $gi after docs-only install"
done
if grep -qxF "memory/INDEX.md" "$gi"; then
  fail "memory/INDEX.md must NOT be auto-ignored (curated continuity — README What belongs in git)"
fi

echo "test: missing manifest.yaml fails hard instead of installing a silent partial backbone"
plugin_copy="$tmp_root/plugin copy no manifest"
mkdir -p "$plugin_copy"
cp -R "$plugin_root/." "$plugin_copy/"
rm -f "$plugin_copy/manifest.yaml"
project="$tmp_root/no manifest project"
if "$plugin_copy/scripts/install_project_template.sh" --create-target --with-scripts "$project" \
  >/tmp/hermes-no-manifest.out 2>/tmp/hermes-no-manifest.err; then
  fail "Expected install to fail hard when manifest.yaml is missing"
fi
grep -qi "manifest" /tmp/hermes-no-manifest.err || fail "Expected the failure to mention the manifest"

echo "All installer tests passed"
