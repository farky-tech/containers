#!/usr/bin/env bash
# hermes_blocks.sh — shared library for the container's backbone scripts.
#
# Zero-dep: bash, awk, sed, shasum-or-sha1sum, mktemp, mkdir. No $HOME, no
# network, no interactive prompts. Sourced (not executed) by the backbone scripts:
#   fallback_log.sh, ledger_carry.sh, memory_route.sh, session_close.sh
#
# Canonical block schema (the contract every script reads and writes):
#
#   <!-- hermes:entry kind=<kind> id=<id> ts=<iso8601> -->
#   <markdown body>
#   <!-- /hermes:entry -->
#
# - kind: fallback | todo | lesson | decision | memory (stable vocabulary)
# - id:   deterministic 12-char hash of (kind + stable key) → idempotence anchor.
#         Same logical entry = same id = never duplicated.
# - ts:   ISO-8601 UTC timestamp.
#
# Concurrency: every mutating write takes a per-file mkdir lock (atomic) and
# rewrites via tmp + mv (atomic on same filesystem). Two parallel sessions
# cannot lose an append or shred a section. last-write-wins is forbidden.

# Note: callers set their own `set -euo pipefail`; this lib avoids relying on it.

# ISO-8601 UTC timestamp. Override via HERMES_FAKE_TS for deterministic tests.
hermes_now_utc() {
  if [ -n "${HERMES_FAKE_TS:-}" ]; then
    printf '%s' "$HERMES_FAKE_TS"
    return 0
  fi
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# sha1 stream helper: prefer shasum (ships with macOS), fall back to sha1sum
# (minimal Linux images often lack perl's shasum). Fail loud if neither exists —
# every scripted write depends on this (0.1.33, pre-publication audit).
hermes_sha1() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 1
  elif command -v sha1sum >/dev/null 2>&1; then sha1sum
  else echo "hermes_blocks: need shasum or sha1sum on PATH" >&2; return 127; fi
}

# Deterministic short id from (kind, stable key). Idempotence anchor.
# args: kind key
hermes_block_id() {
  printf '%s\037%s' "$1" "$2" | hermes_sha1 | cut -c1-12
}

# Atomic full-file write: stdin -> tmp -> mv over target (same dir for atomicity).
# Returns non-zero (and leaves target untouched) if any step fails.
# args: target_file
hermes_atomic_write() {
  local target="$1" dir tmp
  dir="$(dirname "$target")"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "${dir}/.hermes-aw.XXXXXX")" || return 1
  if ! cat > "$tmp"; then rm -f "$tmp"; return 1; fi
  if ! mv "$tmp" "$target"; then rm -f "$tmp"; return 1; fi
  return 0
}

# Acquire a lock via mkdir (atomic create). Bounded retry, then fail loud.
# args: lockdir
hermes_lock() {
  local lockdir="$1" tries=0 max="${HERMES_LOCK_TRIES:-50}" stale_min="${HERMES_LOCK_STALE_MIN:-30}"
  # Ensure the lock's parent dir exists so a fresh --memory-dir does not fail the
  # lock before hermes_atomic_write gets to create it. The lock itself stays a
  # plain (non -p) mkdir so it keeps its atomic "fail if already held" semantics.
  mkdir -p "$(dirname "$lockdir")" 2>/dev/null || true
  # Stale-lock janitor (0.1.33, pre-publication audit): a writer killed between
  # mkdir and rmdir (force-quit, hook timeout, OOM) would otherwise block this
  # file's writes FOREVER — close_state has had its own janitor since 0.1.8; this
  # generalizes the proven pattern to every hermes_lock caller (todo / fallbacks /
  # KNOWLEDGE / session). A live writer holds a lock for milliseconds, so reclaiming
  # only locks older than stale_min minutes cannot steal an active one.
  if [ -d "$lockdir" ] && [ -n "$(find "$lockdir" -maxdepth 0 -mmin "+$stale_min" 2>/dev/null)" ]; then
    echo "hermes_blocks: removing stale lock (older than ${stale_min}m): $lockdir" >&2
    rmdir "$lockdir" 2>/dev/null || true
  fi
  while ! mkdir "$lockdir" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge "$max" ]; then
      echo "hermes_blocks: could not acquire lock: $lockdir (another writer running? if none is, remove it: rmdir '$lockdir')" >&2
      return 1
    fi
    sleep 0.1
  done
  return 0
}

# args: lockdir
hermes_unlock() {
  rmdir "$1" 2>/dev/null || true
}

# True (0) if file already contains a block with this id.
# args: file id
hermes_has_block() {
  [ -f "$1" ] || return 1
  grep -q "hermes:entry kind=[^ ]* id=$2 " "$1" 2>/dev/null
}

# Derive a stable human slug from a title: lowercase, non-alnum runs -> single dash, trimmed, capped.
# Deterministic + zero-dep (LC_ALL=C byte view). Diacritics collapse to dashes — a slug is an
# address/link target, exactness + stability matter more than prettiness; lint catches collisions.
# args: title text -> slug on stdout.
hermes_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed 's/[^a-z0-9]\{1,\}/-/g; s/^-*//; s/-*$//' \
    | cut -c1-50 | LC_ALL=C sed 's/-*$//'
}

# Print the full canonical block (opening+body+closing markers) whose id matches.
# The retrieval primitive: drill one atom out of the cold store instead of reading the whole file.
# args: file id   -> block on stdout; exit 0 if found, 1 if not.
hermes_get_block() {
  [ -f "$1" ] || return 1
  awk -v id="$2" '
    index($0, "id=" id " ") && /hermes:entry/ && $0 !~ /\/hermes:entry/ { inblk=1 }
    inblk { print; found=1 }
    inblk && /\/hermes:entry/ { inblk=0 }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

# Append one canonical block, idempotently and atomically, under a file lock.
# args: file kind id ts   (body read from stdin)
# return: 0 written | 2 skipped (id already present) | 1 error
hermes_append_block() {
  local file="$1" kind="$2" id="$3" ts="$4"
  local lockdir="${file}.lock"
  local body; body="$(cat)"

  # Reject bodies carrying a block sentinel — prevents an entry from forging or
  # breaking canonical block boundaries via injected <!-- hermes:entry --> lines.
  if printf '%s' "$body" | grep -q 'hermes:entry'; then
    echo "hermes_blocks: body contains a block sentinel, refused" >&2
    return 3
  fi

  hermes_lock "$lockdir" || return 1

  if hermes_has_block "$file" "$id"; then
    hermes_unlock "$lockdir"
    return 2
  fi

  local rc=0
  if {
       if [ -f "$file" ]; then
         cat "$file"
         printf '\n'
       fi
       printf '<!-- hermes:entry kind=%s id=%s ts=%s -->\n' "$kind" "$id" "$ts"
       printf '%s\n' "$body"
       printf '<!-- /hermes:entry -->\n'
     } | hermes_atomic_write "$file"; then
    rc=0
  else
    rc=1
  fi

  hermes_unlock "$lockdir"
  return "$rc"
}

# Count canonical blocks of a given kind (or all kinds if kind omitted/"*").
# args: file [kind]
hermes_count_blocks() {
  local file="$1" kind="${2:-*}" c
  [ -f "$file" ] || { printf '0'; return 0; }
  if [ "$kind" = "*" ]; then
    c="$(grep -c "hermes:entry kind=" "$file" 2>/dev/null || true)"
  else
    c="$(grep -c "hermes:entry kind=$kind " "$file" 2>/dev/null || true)"
  fi
  printf '%s' "${c:-0}"
}

# True (0) if file contains at least one legacy "## YYYY-MM-DD" entry that is
# NOT wrapped in a canonical block (used by migration/compat warnings). A date
# heading sitting inside a block body is migrated already and does not count.
# args: file
hermes_has_legacy_entries() {
  [ -f "$1" ] || return 1
  awk '
    /<!-- hermes:entry/        { inb=1; next }
    /<!-- \/hermes:entry -->/  { inb=0; next }
    !inb && /^## [0-9]{4}-[0-9]{2}-[0-9]{2}/ { found=1 }
    END { exit found ? 0 : 1 }
  ' "$1"
}

# Count OPEN todo items ("- [ ]") in a file. Prints an integer (0 if absent).
# The SINGLE definition of "open" — shared by session_close (handoff count) and
# close_state (ledger reconcile gate) so they can never disagree. Two invariants
# the raw `grep -c '^- \[ \]'` got wrong (audit 2026-07-07):
#   - fenced-aware: a "- [ ]" inside a ``` code fence is meta-content (a todo about
#     todo formatting), NOT a real open item — must not count / must not block close;
#   - indentation-aware: nested "  - [ ] subtask" IS a real open item — must count
#     (the anchored ^ regex silently skipped it, letting sub-items slip the gate).
hermes_count_open_todo() { # $1 = todo file -> integer on stdout
  local c
  [ -f "$1" ] || { printf '0'; return 0; }
  c="$(awk '
    /^[[:space:]]*```/            { fenced = !fenced; next }
    !fenced && /^[[:space:]]*- \[ \]/ { c++ }
    END { print c+0 }
  ' "$1" 2>/dev/null || true)"
  printf '%s' "${c:-0}"
}

# Count open fallback status lines outside fenced documentation examples. This
# deliberately accepts both canonical blocks and legacy unfenced entries: old
# adopter memory remains readable, while the format example in fallbacks.md is
# never mistaken for real debt.
# args: fallback file
hermes_count_open_fallbacks() {
  local c
  [ -f "$1" ] || { printf '0'; return 0; }
  c="$(awk '
    /^[[:space:]]*```/       { fenced = !fenced; next }
    !fenced && /^Status: open([[:space:]]|$)/ { c++ }
    END { print c+0 }
  ' "$1" 2>/dev/null || true)"
  printf '%s' "${c:-0}"
}
