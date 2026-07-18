#!/usr/bin/env bash
# recall_inject.sh — per-prompt recall nerve (UserPromptSubmit; Claude Code and Codex hosts).
#
# The retrieval trigger the brain was missing: when the user's prompt matches stored atoms,
# inject POINTERS to them (slug + one-line title) as context BEFORE the model answers — so the
# instance pulls its own knowledge instead of answering from its head. The boot registry shows
# WHAT you know once; this fires AT THE MOMENT of the question (attention decay countermeasure).
#
# Design (researched + plan-reviewed, 0.3.2):
#   - corpus  = gen_rejstrik.sh --tsv, ALWAYS regenerated fresh (machine contract; no stale file
#               parsing). Generation failure => FAIL-CLOSED: inject nothing, log `gen-failed`.
#   - matching = zero-dep awk: Czech diacritics fold (gsub table — macOS iconv //TRANSLIT is
#               broken) -> CZ+EN stopwords -> Dolamic/Savoy light Czech stem (on folded ASCII)
#               -> BM25 (k1=1.2, b=0.75) + tiny importance tiebreak. Measured ~16 ms / 200 rows.
#   - anti-noise gates (precision over recall — a missed atom costs one recall.sh call, a wrong
#               injection pollutes the answer): no content terms -> silence; keep only >=60% of
#               top score AND (>=2 matched terms OR single-term query OR rare-term hit); top 3.
#   - dedupe  = a slug is injected at most once per session (.recall-state/seen-<sidhash>);
#               at-least-once semantics (seen written AFTER emit, under lock).
#   - output  = plain stdout on exit 0 (auto-added to context; JSON additionalContext has a
#               documented VS Code delivery bug + JSON blobs trip prompt-injection detection).
#   - telemetry = appends `<ts> TAB emitted TAB <sidhash> TAB <slugs>` to .recall-hits.log;
#               recall.sh logs the `consumed` side; brain_health reads both (honest labels).
#
# Invariants: ALWAYS exit 0 (non-zero blocks the prompt) · no stderr noise · output far below
# the 10k-char hook cap · total runtime bounded (stdin read: <=256 KiB, <=2000 lines, <=5 s).
# Kill switch: HERMES_RECALL_OFF=1 -> immediate silent exit (rollback without unwiring).
#
# Usage:
#   recall_inject.sh --memory-dir <dir>                  # hook mode (reads hook JSON on stdin)
#   recall_inject.sh --match-only "<query>" < rows.tsv   # test mode: match query against TSV rows
#                                                        #   (gen_rejstrik --tsv format) on stdin
set -uo pipefail

[ "${HERMES_RECALL_OFF:-0}" = "1" ] && exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/hermes_blocks.sh" 2>/dev/null || exit 0

memory_dir="./memory" match_only="" top_cap="${HERMES_RECALL_TOP:-3}"
while [ $# -gt 0 ]; do
  case "$1" in
    --memory-dir|--hermes-dir) memory_dir="${2:-./memory}"; shift 2 ;;
    --match-only)              match_only="${2:-}"; shift 2 ;;
    -h|--help)                 grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

# ---------- matcher (shared by hook mode and --match-only test mode) ----------
# stdin: gen_rejstrik --tsv rows (imp/kind/id/slug/title/tags). Query via ENVIRON (NOT -v:
# awk -v mangles backslash sequences in user text). stdout: score TAB slug TAB imp TAB kind TAB title.
run_matcher() { # $1 = query text
  RQ="$1" awk '
    function fold(s) {
      s = tolower(s)
      gsub(/Á/,"a",s); gsub(/Č/,"c",s); gsub(/Ď/,"d",s); gsub(/É/,"e",s); gsub(/Ě/,"e",s)
      gsub(/Í/,"i",s); gsub(/Ň/,"n",s); gsub(/Ó/,"o",s); gsub(/Ř/,"r",s); gsub(/Š/,"s",s)
      gsub(/Ť/,"t",s); gsub(/Ú/,"u",s); gsub(/Ů/,"u",s); gsub(/Ý/,"y",s); gsub(/Ž/,"z",s)
      gsub(/á/,"a",s); gsub(/č/,"c",s); gsub(/ď/,"d",s); gsub(/é/,"e",s); gsub(/ě/,"e",s)
      gsub(/í/,"i",s); gsub(/ň/,"n",s); gsub(/ó/,"o",s); gsub(/ř/,"r",s); gsub(/š/,"s",s)
      gsub(/ť/,"t",s); gsub(/ú/,"u",s); gsub(/ů/,"u",s); gsub(/ý/,"y",s); gsub(/ž/,"z",s)
      return s
    }
    # Dolamic & Savoy light Czech stemmer (RemoveCase subset), on FOLDED ascii; length guards
    # per Lucene CzechStemmer. Suffix lists deduplicated after diacritic folding.
    function stem(w,   n) {
      n = length(w)
      if (n > 7 && w ~ /atech$/) return substr(w, 1, n-5)
      if (n > 6 && w ~ /(etem|atum)$/) return substr(w, 1, n-4)
      if (n > 5 && w ~ /(ech|ich|eho|emi|emu|ete|eti|iho|imi|imu|ach|ata|aty|ych|ama|ami|ove|ovi|ymi)$/)
        return substr(w, 1, n-3)
      if (n > 4 && w ~ /(em|es|im|um|at|am|os|us|ym|mi|ou)$/) return substr(w, 1, n-2)
      if (n > 3 && w ~ /[aeiouy]$/) return substr(w, 1, n-1)
      return w
    }
    BEGIN {
      FS = "\t"
      sw = "a i o u k s v z na se je to do ze pro pri od po za ale jak co coz kdy kde kdo aby "
      sw = sw "ze by byl byla bylo jsou jsem jsi ma mam mas muj tvuj svuj ten ta ty tento tato "
      sw = sw "nebo ani az uz jen jeste vsak tak tam pak nas vas jeho jeji nej neni ano ne mame "
      sw = sw "podle pres bez mezi nad pod pred potom tady tohle toho tim tom byt bude budes "
      sw = sw "budeme muze muzes musi musis mel mela melo meli jsme jste vsechno vsech neco "
      sw = sw "nic nejak jde slo maji mit tedy proste jestli kdyz takze protoze "
      sw = sw "the an of in on at to for and or is are was be as by with from it this that "
      sw = sw "what how when where who why do does did can could should i you we my our me our"
      nsw = split(sw, swa, " ")
      for (si = 1; si <= nsw; si++) stop[swa[si]] = 1
      k1 = 1.2; b = 0.75
    }
    # pass 1: index corpus rows (imp TAB kind TAB id TAB slug TAB title TAB tags)
    NF >= 5 {
      n_docs++
      imp[n_docs] = $1 + 0; kind[n_docs] = $2; slug[n_docs] = $4; title[n_docs] = $5
      txt = $4; gsub(/-/, " ", txt); txt = txt " " $5; if (NF >= 6) txt = txt " " $6
      line = fold(txt); gsub(/[^a-z0-9]+/, " ", line)
      nt = split(line, toks, " "); dl = 0
      delete seen
      for (ti = 1; ti <= nt; ti++) {
        t = toks[ti]
        if (t == "" || stop[t] || length(t) < 2) continue
        t = stem(t); tf[n_docs "," t]++; dl++
        if (!(t in seen)) { df[t]++; seen[t] = 1 }
      }
      doclen[n_docs] = dl; totlen += dl
    }
    END {
      if (n_docs == 0) exit
      avgdl = totlen / n_docs
      q = fold(ENVIRON["RQ"]); gsub(/[^a-z0-9]+/, " ", q)
      nq = split(q, qt, " "); nqterms = 0
      for (qi = 1; qi <= nq; qi++) {
        t = qt[qi]
        if (t == "" || stop[t] || length(t) < 2) continue
        t = stem(t)
        if (!(t in qseen)) { qseen[t] = 1; qterms[++nqterms] = t }
      }
      if (nqterms == 0) exit                       # nothing to match -> silence
      best = 0
      for (d = 1; d <= n_docs; d++) {
        score = 0; matched = 0
        for (qi = 1; qi <= nqterms; qi++) {
          t = qterms[qi]; f = tf[d "," t]
          if (f == 0) continue
          matched++
          idf = log((n_docs - df[t] + 0.5) / (df[t] + 0.5) + 1)
          score += idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * doclen[d] / avgdl))
        }
        if (score > 0) {
          score += imp[d] * 0.02                   # importance = tiebreak only, relevance dominates
          s[d] = score; m[d] = matched
          if (score > best) best = score
        }
      }
      if (best == 0) exit                          # no match -> quiet default
      cap = ENVIRON["RTOP"] + 0; if (cap < 1) cap = 3
      for (rank = 1; rank <= cap; rank++) {
        top = 0; td = 0
        for (d = 1; d <= n_docs; d++) if (s[d] > top) { top = s[d]; td = d }
        if (td == 0) break
        # >=2 matched terms required (single-term escape at score>=1.5 misfired on long titles —
        # a lone common word like "podle" cleared it); a one-word query is the deliberate exception.
        if (top >= 0.6 * best && (m[td] >= 2 || nqterms == 1))
          printf "%.2f\t%s\t%s\t%s\t%s\n", top, slug[td], imp[td], kind[td], title[td]
        s[td] = 0
      }
    }
  '
}

# ---------- test mode: rows on stdin, query from arg ----------
if [ -n "$match_only" ]; then
  RTOP="$top_cap" run_matcher "$match_only"
  exit 0
fi

# ---------- hook mode ----------
state_dir="$memory_dir/.recall-state"
hits_log="$memory_dir/.recall-hits.log"

# Bounded stdin read, THREE caps (<=256 KiB, <=2000 lines, <=5 s) — a hook must never hang
# or stream forever (line-accumulating `read -t` alone renews its timeout per line).
payload="" lines=0
if [ ! -t 0 ]; then
  ri_line=""
  while [ "${#payload}" -lt 262144 ] && [ "$lines" -lt 2000 ] && [ "$SECONDS" -lt 5 ]; do
    if IFS= read -r -t 2 ri_line; then payload="$payload$ri_line"$'\n'; lines=$((lines+1)); ri_line=""
    else break; fi
  done
  payload="$payload$ri_line"
fi
[ -n "$payload" ] || exit 0

# Extract prompt + session_id. jq preferred; zero-dep sed/awk fallback (single-pass unescape,
# journal_prompt 0.1.35 pattern — five sequential sed passes were NOT order-safe).
if [ -z "${HERMES_NO_JQ:-}" ] && command -v jq >/dev/null 2>&1; then
  prompt="$(printf '%s' "$payload" | jq -r '(.prompt // "")' 2>/dev/null | head -c 4000 || true)"
  sid="$(printf '%s' "$payload" | jq -r '(.session_id // "")' 2>/dev/null | head -c 64 || true)"
else
  prompt="$(printf '%s' "$payload" \
    | tr -d '\000-\010\013\014\016-\037' \
    | sed -nE 's/.*"prompt"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' \
    | head -n1 \
    | awk '{
        s = $0; out = ""
        while (length(s) > 0 && length(out) < 4000) {
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
  sid="$(printf '%s' "$payload" | sed -nE 's/.*"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9._-]{1,64})".*/\1/p' | head -n1)"
fi
prompt="$(printf '%s' "$prompt" | tr '\n\t' '  ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
[ -n "$prompt" ] || exit 0

# Query window: head 700 + tail 300 (a long paste often carries the question at the end).
qtext="${prompt:0:700}"
if [ "${#prompt}" -gt 1000 ]; then qtext="$qtext ${prompt: -300}"; fi

# Sanitized session identity for the dedupe file (raw SID may hold /, .., spaces). No SID ->
# dedupe off (a shared constant would couple unrelated sessions).
sidhash=""
[ -n "$sid" ] && sidhash="$(printf '%s' "$sid" | hermes_sha1 2>/dev/null | cut -c1-12 || true)"

# Corpus: ALWAYS fresh machine rows; generation failure = fail-closed (inject nothing) but
# leave an observer-visible trace (debounced: skip if the log already ends with gen-failed).
rows="$(bash "$here/gen_rejstrik.sh" --memory-dir "$memory_dir" --tsv 2>/dev/null)" || rows=""
if [ -z "$rows" ]; then
  if [ -s "$hits_log" ] && tail -n 1 "$hits_log" 2>/dev/null | grep -q 'gen-failed'; then :
  else
    for f in KNOWLEDGE.md CAN.md ZNALOST.md umim.md; do
      [ -f "$memory_dir/$f" ] || continue
      printf '%s\tgen-failed\t%s\t-\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${sidhash:--}" >> "$hits_log" 2>/dev/null || true
      break
    done
  fi
  exit 0
fi

matches="$(printf '%s\n' "$rows" | RTOP="$top_cap" run_matcher "$qtext")" || matches=""
[ -n "$matches" ] || exit 0

# Session dedupe: drop slugs already injected this session.
seen_file=""
if [ -n "$sidhash" ]; then
  seen_file="$state_dir/seen-$sidhash"
  if [ -f "$seen_file" ]; then
    matches="$(printf '%s\n' "$matches" | while IFS="$(printf '\t')" read -r sc sl im kd ti; do
      [ -n "$sl" ] || continue
      grep -Fxq "$sl" "$seen_file" 2>/dev/null || printf '%s\t%s\t%s\t%s\t%s\n' "$sc" "$sl" "$im" "$kd" "$ti"
    done)"
  fi
fi
[ -n "$matches" ] || exit 0

# Emit the pointer block (plain stdout -> context). Pointers, not payloads: a wrong match
# degrades to one ignored line. Secret redaction on the way out (belt & suspenders).
block="$(printf '%s\n' "$matches" | while IFS="$(printf '\t')" read -r sc sl im kd ti; do
  [ -n "$sl" ] || continue
  t="$ti"; [ "${#t}" -gt 120 ] && t="${t:0:120}…"
  printf -- '- `%s` — %s (imp %s, %s)\n' "$sl" "$t" "$im" "$kd"
done)"
[ -n "$block" ] || exit 0
block="$(printf '%s' "$block" | sed -E \
  -e 's/(sk-|sk-ant-|AIza|ghp_|gho_|ghs_|ghu_|ghr_|glpat-|xox[baprs]-)[A-Za-z0-9_-]{16,}/[REDACTED]/g' \
  -e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g')"

echo "🧠 RECALL — stored atoms match this prompt (pull the atom BEFORE answering; do not answer from memory):"
printf '%s\n' "$block"
echo "→ drill: recall.sh --memory-dir $memory_dir <slug>"

# Record seen (AFTER emit = at-least-once; a crash loses nothing, a race duplicates at worst)
# + telemetry line. Both under the state lock; one-line appends, never rewrites.
slugcsv="$(printf '%s\n' "$matches" | awk -F'\t' 'NF>=2{printf "%s%s", (c++?",":""), $2}')"
mkdir -p "$state_dir" 2>/dev/null || true
lockdir="$state_dir/.write.lock"
if hermes_lock "$lockdir" 2>/dev/null; then
  if [ -n "$seen_file" ]; then
    printf '%s\n' "$matches" | awk -F'\t' 'NF>=2{print $2}' >> "$seen_file" 2>/dev/null || true
  fi
  printf '%s\temitted\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${sidhash:--}" "$slugcsv" >> "$hits_log" 2>/dev/null || true
  hermes_unlock "$lockdir" 2>/dev/null || true
fi
exit 0
