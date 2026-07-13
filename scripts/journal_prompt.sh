#!/usr/bin/env bash
# journal_prompt.sh — cc_farky LOCAL per-turn nerve (Phase 2, plan ted-keen-shore).
#
# UserPromptSubmit hook: silently feeds the user's prompt into the session journal
# (session.md black box), so it fills itself DURING work instead of "when I remember".
# Safe per-turn trigger: UserPromptSubmit runs BEFORE the reply (not Stop-every-turn),
# and this hook is WRITE-ONLY.
#
# Hard invariants:
#   1) NEVER echo to stdout — zero context noise.
#   2) NEVER exit non-zero — a UserPromptSubmit hook with exit!=0 BLOCKS the prompt.
#
# Audit-hardened (Phase 1+2 audit, 3 lenses):
#   - UTF-8 safe truncation via jq codepoints (not `cut -c`, which is byte-wise under C locale
#     and would split Czech diacritics -> mojibake). jq is PREFERRED, not required (0.1.33):
#     without jq a sed/awk fallback extracts+truncates — no hard dependency, no silent no-op.
#   - Secret redaction before write (session.md is git-tracked; an API key pasted into a prompt
#     must never land in git — Farky red line). Conservative patterns, redact-more is safe side.
#   - Trim so a newline-only prompt doesn't write a junk "USER:   " entry.
#   - Neutralize literal `hermes:entry` so session_note doesn't reject (rc=3) & silently drop the turn.
#   - Timestamp prefix so two identical short prompts ("ok"/"continue") on different turns don't
#     collide on the text-keyed block id and get deduped away (would lose a real turn).
set -uo pipefail
MEMORY_DIR="./memory"
while [ $# -gt 0 ]; do case "${1:-}" in --memory-dir|--hermes-dir) MEMORY_DIR="${2:-./memory}"; shift 2 ;; *) shift ;; esac; done  # --hermes-dir = legacy alias

# Bounded stdin read — same hang-guard family as close_state.sh (0.1.30) / ledger_carry.sh
# (0.1.29), but LINE-ACCUMULATING (0.1.35): bash 3.2 `read -t` DISCARDS everything already
# read when the timeout fires, so a single whole-payload read could silently drop a large,
# slowly-delivered prompt. Reading per-line keeps every completed line; only a line still
# unfinished when its own 2s window expires is lost. EOF without a trailing newline leaves
# the tail in $jp_line (rc!=0 but data kept — EOF, unlike timeout, preserves the buffer).
payload=""
if [ ! -t 0 ]; then
  jp_line=""
  while IFS= read -r -t 2 jp_line; do payload="$payload$jp_line"; jp_line=""; done 2>/dev/null
  payload="$payload$jp_line"
fi
# Extract + truncate. Preferred: jq (codepoint-safe truncation, full JSON unescape).
# Fallback (zero-dep promise — stock macOS < 15 and many Linux boxes have no jq):
# ERE sed extraction of the "prompt" string + minimal unescape + char truncation.
# Worst case vs jq: truncation may split one multibyte char at the 280 boundary.
if [ -z "${HERMES_NO_JQ:-}" ] && command -v jq >/dev/null 2>&1; then   # HERMES_NO_JQ=1 forces the fallback (tests)
  prompt="$(printf '%s' "$payload" | jq -r '(.prompt // "") | .[0:280]' 2>/dev/null || true)"
else
  prompt="$(printf '%s' "$payload" \
    | tr -d '\000-\010\013\014\016-\037' \
    | sed -nE 's/.*"prompt"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' \
    | head -n1 \
    | awk '{
        # SINGLE left-to-right pass: \\ \" \n \t \r are mutually exclusive 2-char tokens.
        # Five sequential global sed passes were NOT order-safe: in "C:\\new" the second
        # backslash of the escaped pair was eaten by the \n rule and the text silently
        # corrupted to "C:\ ew" (re-audit 0.1.35; jq path = ground truth). Early-exit at
        # 280 chars keeps this O(limit), not O(payload).
        s = $0; out = ""
        while (length(s) > 0 && length(out) < 280) {
          c = substr(s, 1, 1)
          if (c == "\\" && length(s) >= 2) {
            d = substr(s, 2, 1)
            if (d == "n" || d == "t" || d == "r") { out = out " "; s = substr(s, 3); continue }
            if (d == "\"" || d == "\\")           { out = out d;  s = substr(s, 3); continue }
          }
          out = out c; s = substr(s, 2)
        }
        print out
      }')"
fi
[ -z "$prompt" ] && exit 0

# Flatten newlines, then trim; a whitespace-only prompt becomes empty here.
prompt="$(printf '%s' "$prompt" | tr '\n\t' '  ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
[ -z "$prompt" ] && exit 0

# Redact common secrets (conservative; false-positive redaction is the safe side).
prompt="$(printf '%s' "$prompt" | sed -E \
  -e 's/(sk-|sk-ant-|AIza|ghp_|gho_|ghs_|ghu_|ghr_|glpat-|xox[baprs]-)[A-Za-z0-9_-]{16,}/[REDACTED]/g' \
  -e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' \
  -e 's/([Bb]earer|[Tt]oken|[Pp]assword|[Aa]pi[_-]?key|[Ss]ecret)([=:[:space:]]+)[A-Za-z0-9._-]{12,}/\1\2[REDACTED]/g' \
  -e 's/-----BEGIN[A-Z ]*PRIVATE KEY-----/[REDACTED-KEY]/g')"

# Neutralize the block sentinel so session_note never rejects the entry.
prompt="$(printf '%s' "$prompt" | sed 's/hermes:entry/hermes\/entry/g')"
[ -z "$prompt" ] && exit 0

# Timestamp prefix -> unique text -> no dedup collision on repeated short prompts.
stamp="$(date +%H:%M:%S 2>/dev/null || true)"

SN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session_note.sh"   # sibling in the engine
# NB: session_note needs </dev/null — after cat drained stdin, open-but-empty stdin makes it
# silently fail (documented gotcha in CAN.md; bit us in testing).
[ -f "$SN" ] && bash "$SN" --memory-dir "$MEMORY_DIR" --note "USER [$stamp]: $prompt" </dev/null >/dev/null 2>&1 || true
exit 0
