#!/usr/bin/env bash
# gen_agents.sh — generate agents/<name>.md from a single source of truth.
#
#   manifest.yaml claude_binding.agents[]  = frontmatter SSOT (name/description/tools)
#   subagents/<name>.md                    = canonical body (verbatim)
#   agents/<name>.md                       = GENERATED (frontmatter + body)
#
# This kills the byte-drift between agents/ and subagents/ (they used to be hand-kept
# duplicates). The verifier runs `--check` to ensure agents/ was regenerated.
#
# Usage:
#   gen_agents.sh           generate/refresh all agents/<name>.md
#   gen_agents.sh --check   verify agents/ matches generated output; exit 1 on drift
#
# Exit codes:  0 ok / generated | 1 drift (in --check) or error

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(cd "$script_dir/.." && pwd)"
manifest="$plugin_root/manifest.yaml"

check=0
[ "${1:-}" = "--check" ] && check=1

parse_agents() {
  awk '
    /^claude_binding:/ { inb=1; next }
    inb && /^  agents:/ { ina=1; next }
    ina && /^  verify:/ { ina=0 }
    ina && /^    - name:/ {
      if (name != "") print name "\t" desc "\t" tools "\t" src
      name=$0; sub(/^    - name:[[:space:]]*/,"",name); gsub(/"/,"",name)
      desc=""; tools=""; src=""
    }
    ina && /^      description:/ { desc=$0; sub(/^      description:[[:space:]]*/,"",desc); gsub(/^"|"$/,"",desc) }
    ina && /^      tools:/ { tools=$0; sub(/^      tools:[[:space:]]*/,"",tools); gsub(/[][]/,"",tools) }
    ina && /^      source:/ { src=$0; sub(/^      source:[[:space:]]*/,"",src); gsub(/"/,"",src) }
    END { if (name != "") print name "\t" desc "\t" tools "\t" src }
  ' "$manifest"
}

emit() {
  # args: outpath name desc tools body_file
  {
    printf -- '---\n'
    printf 'name: %s\n' "$2"
    printf 'description: "%s"\n' "$3"
    printf 'tools: %s\n' "$4"
    printf -- '---\n\n'
    cat "$5"
  } > "$1"
}

drift=0 count=0
while IFS=$'\t' read -r name desc tools src; do
  [ -n "$name" ] || continue
  count=$((count + 1))
  body="$plugin_root/$src"
  out="$plugin_root/agents/$name.md"
  if [ ! -f "$body" ]; then
    echo "gen_agents: source body missing: $body" >&2
    exit 1
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/hermes-gen.XXXXXX")"
  emit "$tmp" "$name" "$desc" "$tools" "$body"
  if [ "$check" -eq 1 ]; then
    if [ ! -f "$out" ] || ! diff -q "$tmp" "$out" >/dev/null 2>&1; then
      echo "gen_agents: DRIFT agents/$name.md (regenerate with scripts/gen_agents.sh)" >&2
      drift=1
    fi
    rm -f "$tmp"
  else
    mv "$tmp" "$out"
    echo "gen_agents: wrote agents/$name.md" >&2
  fi
done < <(parse_agents)

if [ "$check" -eq 1 ]; then
  if [ "$drift" -eq 0 ]; then
    echo "gen_agents: OK — $count agents in sync" >&2
    exit 0
  fi
  exit 1
fi
echo "gen_agents: generated $count agents" >&2
exit 0
