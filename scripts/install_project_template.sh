#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: install_project_template.sh [--dry-run] [--force] [--create-target] [--with-scripts] [--refresh-scripts] [--backup-dir DIR] [TARGET]

Modes:
  default   Merge only missing files. Existing files are never overwritten.
  --dry-run Show what would happen without writing.
  --force   Overwrite existing files, but first copy them to a timestamped backup.
            WARNING: applies to the whole memory/ tree, including memory/*.md — it will
            overwrite a fork's own memory with empty templates (backed up first). To
            upgrade only the runtime scripts on an existing fork, use --refresh-scripts.
  --create-target Allow creating TARGET when it does not exist.
  --with-scripts  Also copy the runtime backbone scripts (+ lib/) into TARGET/memory/scripts/.
                  Without this, only the markdown templates are installed — but those
                  templates and the lapac skill call scripts/*.sh, so a docs-only install
                  references tooling that is not there. Existing scripts are skipped unless
                  --force is also given (which then also overwrites memory/*.md — see above).
  --refresh-scripts  Safe engine upgrade for an existing fork: force-overwrites ONLY the
                  backbone scripts + lib/ (backed up first, see --backup-dir), and NEVER
                  touches memory/*.md — the markdown template merge is skipped entirely.
                  Use this instead of --force to bring a fork's engine current without
                  risking its memory. Stamps memory/.fmc-source with the source version/dir
                  so drift between a fork and this source can be detected later.
  --backup-dir DIR  Where timestamped backups (for --force and --refresh-scripts) are
                  written. Default: TARGET/memory/.backups/ — persistent, not TMPDIR (which
                  the OS may clean and would make the backup vanish right when it's needed).

Side effect of EVERY install mode (docs-only included since 0.3.9): appends TARGET/.gitignore
entries for the runtime artefacts the engine HOOKS generate under memory/ (.backups/,
.fmc-source, _rejstrik.md, _hot.md, .recall-state/, .recall-hits.log, .close-state/,
.capability-snapshot, .watch-state) — append-if-missing, announced on stdout. The hooks write
these regardless of whether the backbone scripts were copied locally, so a docs-only install
needs the ignore entries just as much (field report cc_chobotnice 2026-07-16: per-session
.close-state/*.env and a generated _rejstrik.md ended up committed).

Examples:
  install_project_template.sh --with-scripts .        # full install (templates + engine) — the normal path
  install_project_template.sh --dry-run --with-scripts /path/to/project
  install_project_template.sh --refresh-scripts /path/to/existing-fork
  install_project_template.sh .                       # docs-only (templates reference scripts you will not have)
USAGE
}

dry_run=0
force=0
create_target=0
with_scripts=0
refresh_scripts=0
backup_root=""
target=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --force)
      force=1
      echo "install: ⚠️  --force is DEPRECATED (F3) — it overwrites memory/*.md too (YOUR data; backed up first)." >&2
      echo "install:    To refresh a fork's engine use --refresh-scripts (backbone + lib only, memory untouched)." >&2
      echo "install:    Use --force only for a DELIBERATE reset of the template/memory tree." >&2
      shift
      ;;
    --create-target)
      create_target=1
      shift
      ;;
    --with-scripts)
      with_scripts=1
      shift
      ;;
    --refresh-scripts)
      refresh_scripts=1
      shift
      ;;
    --backup-dir)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --backup-dir" >&2
        exit 2
      fi
      backup_root="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$target" ]; then
        echo "Only one TARGET argument is allowed" >&2
        usage >&2
        exit 2
      fi
      target="$1"
      shift
      ;;
  esac
done

if [ -z "$target" ]; then
  target="."
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="$(cd "$script_dir/.." && pwd)"
template_root="$plugin_root/templates/memory-folder"

if [ ! -d "$template_root" ]; then
  echo "Template root not found: $template_root" >&2
  exit 1
fi

if [ ! -f "$template_root/MEMORY.md" ] || [ ! -f "$template_root/CAN.md" ]; then
  echo "Template root is incomplete: expected MEMORY.md and CAN.md" >&2
  exit 1
fi

if [ ! -e "$target" ]; then
  if [ "$create_target" -eq 1 ]; then
    if [ "$dry_run" -eq 0 ]; then
      mkdir -p "$target"
    fi
  else
    echo "Target does not exist: $target (use --create-target to create it)" >&2
    exit 2
  fi
fi

if [ -e "$target" ] && [ ! -d "$target" ]; then
  echo "Target is not a directory: $target" >&2
  exit 2
fi

if command -v realpath >/dev/null 2>&1; then
  target_abs="$(realpath "$target" 2>/dev/null || true)"
else
  target_abs="$(cd "$target" 2>/dev/null && pwd -P || true)"
fi

if [ -z "$target_abs" ]; then
  if [ "$dry_run" -eq 1 ] && [ "$create_target" -eq 1 ]; then
    target_abs="$target"
  else
    echo "Could not resolve target path: $target" >&2
    exit 2
  fi
fi

target_memory="$target_abs/memory"

# Refuse a symlinked memory/ (0.1.33 hardening): every template/script write and the
# default backup root live under this path — a symlink would redirect them outside
# the chosen project without any visible sign.
if [ -L "$target_memory" ]; then
  echo "Refusing to install into a symlinked memory dir: $target_memory" >&2
  exit 1
fi

if [ -z "$backup_root" ]; then
  # Persistent, under the target's own memory/ — NOT TMPDIR. --force/--refresh-scripts backups
  # are the only way back after an overwrite; TMPDIR is OS-cleaned (macOS periodic cleanup), so
  # a TMPDIR-default backup can vanish right when it's needed, which is de facto silent data loss.
  backup_root="$target_memory/.backups"
fi

if [ "$dry_run" -eq 1 ]; then
  mode_desc="dry-run"
elif [ "$refresh_scripts" -eq 1 ]; then
  mode_desc="refresh-scripts"
elif [ "$force" -eq 1 ]; then
  mode_desc="force"
else
  mode_desc="merge"
fi

echo "FMC template install"
echo "Target: $target_memory"
echo "Mode: $mode_desc"
echo "Backup root: $backup_root"

if [ "$dry_run" -eq 0 ]; then
  mkdir -p "$target_memory"
fi

installed=0
skipped=0
overwritten=0

# --refresh-scripts is a scripts-only engine upgrade: it must NEVER touch memory/*.md, not even
# to add a missing template. Skip the markdown merge/overwrite loop entirely in that mode so the
# invariant holds regardless of --force (Fix 1/2).
if [ "$refresh_scripts" -eq 0 ]; then
while IFS= read -r -d '' source_file; do
  rel_path="${source_file#$template_root/}"
  dest_file="$target_memory/$rel_path"
  dest_dir="$(dirname "$dest_file")"

  case "$rel_path" in
    /*|*../*|../*)
      echo "Unsafe template relative path: $rel_path" >&2
      exit 1
      ;;
  esac

  case "$dest_file" in
    "$target_memory"/*) ;;
    *)
      echo "Refusing to write outside target hermes folder: $dest_file" >&2
      exit 1
      ;;
  esac

  if [ -L "$dest_file" ]; then
    echo "Refusing to overwrite or skip symlink: $dest_file" >&2
    exit 1
  fi

  if [ -e "$dest_file" ] && [ ! -f "$dest_file" ]; then
    echo "Refusing non-regular existing path: $dest_file" >&2
    exit 1
  fi

  if [ -e "$dest_file" ] && [ "$force" -eq 0 ]; then
    echo "skip existing: $dest_file"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$dry_run" -eq 1 ]; then
    if [ -e "$dest_file" ]; then
      echo "would overwrite with backup: $dest_file"
    else
      echo "would install: $dest_file"
    fi
    continue
  fi

  mkdir -p "$dest_dir"

  if [ -e "$dest_file" ]; then
    if [ -z "${backup_dir:-}" ]; then
      mkdir -p "$backup_root"
      backup_dir="$(mktemp -d "$backup_root/hermes-template.XXXXXX")"
    fi
    backup_file="$backup_dir/memory/$rel_path"
    mkdir -p "$(dirname "$backup_file")"
    cp -p "$dest_file" "$backup_file"
    rm -f "$dest_file"
    cp "$source_file" "$dest_file"
    echo "overwrote with backup: $dest_file -> $backup_file"
    overwritten=$((overwritten + 1))
  else
    cp "$source_file" "$dest_file"
    echo "installed: $dest_file"
    installed=$((installed + 1))
  fi
done < <(find "$template_root" -type f -print0)
else
  echo "refresh-scripts mode: skipping markdown template merge (memory/*.md untouched)"
fi

# --with-scripts / --refresh-scripts: deliver the runtime backbone the templates/lapac
# actually call. Without either, the install is docs-only and references tooling that is
# not present.
scripts_installed=0
scripts_skipped=0
scripts_refreshed=0
if [ "$with_scripts" -eq 1 ] || [ "$refresh_scripts" -eq 1 ]; then
  # Backbone derived from manifest.yaml (SSOT: backbone_scripts.scripts) so this list can
  # never go stale against the source. A hardcoded copy silently drifted before — it missed
  # kandidat/goqueue/close_state, so a re-install did not deliver newer capabilities (§6b:
  # don't hand-maintain a second list that duplicates the SSOT). Scoped to the
  # `backbone_scripts:` section only (not the whole file) so an unrelated future
  # "- scripts/foo.sh" line elsewhere in the manifest (e.g. in prose or another list) cannot
  # sneak into the backbone. No silent-subset fallback: if the manifest is missing or the
  # section can't be parsed, fail hard rather than install an incomplete engine quietly.
  manifest="$script_dir/../manifest.yaml"
  backbone=""
  if [ -f "$manifest" ]; then
    backbone="$(awk '/^backbone_scripts:/{flag=1; next} /^[^[:space:]]/{flag=0} flag' "$manifest" \
      | grep -oE '^[[:space:]]*- scripts/[a-z_]+\.sh' \
      | sed -E 's#^[[:space:]]*- scripts/##' \
      | tr '\n' ' ' || true)"
  fi
  if [ -z "${backbone// /}" ]; then
    echo "Cannot derive the backbone script list: manifest.yaml is missing, unreadable, or its" >&2
    echo "backbone_scripts: section is empty at: $manifest" >&2
    echo "Refusing to install a silently incomplete script subset — restore manifest.yaml." >&2
    exit 1
  fi

  # Preflight (0.1.33, pre-publication audit): every manifest-declared backbone source
  # must exist BEFORE any write. The old in-loop "warn & skip" let a damaged checkout
  # install a PARTIAL engine, stamp .fmc-source and report success — a silent subset
  # through another door.
  missing=""
  for rel in $backbone "lib/hermes_blocks.sh"; do
    [ -f "$script_dir/$rel" ] || missing="$missing $rel"
  done
  if [ -n "${missing// /}" ]; then
    echo "Backbone source file(s) missing from this plugin checkout:$missing" >&2
    echo "Refusing to install an incomplete engine (damaged release/checkout?)." >&2
    exit 1
  fi

  # Fix 3: stamp memory/.fmc-source with the source version/dir so a fork-drift check
  # (state_guard.sh --fork-drift) can later tell how stale a fork's engine is against this
  # source. Written whenever backbone scripts are delivered (--with-scripts or
  # --refresh-scripts); never on a docs-only install.
  version_file="$plugin_root/.claude-plugin/plugin.json"
  source_version=""
  if [ -f "$version_file" ]; then
    source_version="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$version_file" | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')"
  fi
  installed_at="${HERMES_FAKE_TS:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

  target_scripts="$target_memory/scripts"
  if [ "$refresh_scripts" -eq 1 ]; then
    echo "Refresh scripts: $target_scripts"
  else
    echo "With scripts: $target_scripts"
  fi

  for rel in $backbone "lib/hermes_blocks.sh"; do
    src="$script_dir/$rel"
    dest="$target_scripts/$rel"
    [ -f "$src" ] || { echo "internal: preflighted source vanished: $rel" >&2; exit 1; }
    if [ -L "$dest" ]; then
      echo "Refusing to overwrite symlink: $dest" >&2
      exit 1
    fi
    if [ -e "$dest" ] && [ ! -f "$dest" ]; then
      echo "Refusing non-regular existing path: $dest" >&2
      exit 1
    fi

    if [ "$refresh_scripts" -eq 1 ]; then
      # Force-overwrite (backed up first) regardless of existing content — that is the
      # whole point of a scripts-only engine refresh. Never touches memory/*.md (Fix 1).
      if [ "$dry_run" -eq 1 ]; then
        if [ -e "$dest" ]; then
          echo "would refresh script (with backup): $dest"
        else
          echo "would install script: $dest"
        fi
        continue
      fi
      mkdir -p "$(dirname "$dest")"
      if [ -e "$dest" ]; then
        if [ -z "${scripts_backup_dir:-}" ]; then
          mkdir -p "$backup_root"
          scripts_backup_dir="$(mktemp -d "$backup_root/refresh-scripts.XXXXXX")"
        fi
        backup_file="$scripts_backup_dir/scripts/$rel"
        mkdir -p "$(dirname "$backup_file")"
        cp -p "$dest" "$backup_file"
        rm -f "$dest"
        cp "$src" "$dest"
        chmod +x "$dest" 2>/dev/null || true
        echo "refreshed script (backup): $dest -> $backup_file"
        scripts_refreshed=$((scripts_refreshed + 1))
      else
        cp "$src" "$dest"
        chmod +x "$dest" 2>/dev/null || true
        echo "installed script: $dest"
        scripts_installed=$((scripts_installed + 1))
      fi
      continue
    fi

    # --with-scripts (non-refresh): skip existing unless --force.
    if [ -e "$dest" ] && [ "$force" -eq 0 ]; then
      echo "skip existing script: $dest"
      scripts_skipped=$((scripts_skipped + 1))
      continue
    fi
    if [ "$dry_run" -eq 1 ]; then
      if [ -e "$dest" ]; then
        echo "would overwrite script (with backup): $dest"
      else
        echo "would install script: $dest"
      fi
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ]; then
      # --force overwrite of an existing script: back it up like --refresh-scripts does.
      # Templates always got a --force backup; scripts silently did not (0.1.33 audit fix)
      # — an adopter's customized runtime would have been destroyed irreversibly.
      if [ -z "${scripts_backup_dir:-}" ]; then
        mkdir -p "$backup_root"
        scripts_backup_dir="$(mktemp -d "$backup_root/force-scripts.XXXXXX")"
      fi
      backup_file="$scripts_backup_dir/scripts/$rel"
      mkdir -p "$(dirname "$backup_file")"
      cp -p "$dest" "$backup_file"
      rm -f "$dest"
      cp "$src" "$dest"
      chmod +x "$dest" 2>/dev/null || true
      echo "overwrote script (backup): $dest -> $backup_file"
      scripts_refreshed=$((scripts_refreshed + 1))
    else
      cp "$src" "$dest"
      chmod +x "$dest" 2>/dev/null || true
      echo "installed script: $dest"
      scripts_installed=$((scripts_installed + 1))
    fi
  done

  marker_file="$target_memory/.fmc-source"
  if [ "$dry_run" -eq 1 ]; then
    echo "would write source marker: $marker_file"
  else
    tmp_marker="$(mktemp "$target_memory/.fmc-source.XXXXXX")"
    {
      printf 'source_version=%s\n' "$source_version"
      printf 'source_dir=%s\n' "$plugin_root"
      printf 'installed_at=%s\n' "$installed_at"
    } > "$tmp_marker"
    mv "$tmp_marker" "$marker_file"
    echo "wrote source marker: $marker_file"
  fi

fi

# Fix 4 (0.1.24, cc_pas field-report 2026-07-07; widened 0.3.9, cc_chobotnice field-report
# 2026-07-16): runtime artefacts under memory/ are generated by the ENGINE HOOKS (close loop,
# recall, capability snapshot, watch) regardless of whether the backbone scripts were copied
# locally — so the gitignore-append runs on EVERY install mode, docs-only included. It used to
# be a --with-scripts/--refresh-scripts side effect, which left docs-only adopters committing
# per-session runtime state (.close-state/*.env, generated _rejstrik.md). Entries live in ONE
# list below and the warn/dry-run texts derive from it — a hardcoded copy in the symlink
# warning drifted from the real list before (mentioned 2 entries out of 6). session.md +
# .session-archive/ ARE appended since Fáze A (2026-07-18): the prompt journal is a LOCAL-ONLY
# black box (bounded prompt excerpts) and must never be pushed by accident — gitignore is the one
# real privacy default (installing the container is consent to LOCAL writes, not to publishing a
# prompt log). Curated continuity (STATE/log/KNOWLEDGE/sessions/) stays tracked. Deliberately NOT
# appended: INDEX.md — curated, git tracks it (see README "What belongs in git").
gi_file="$(dirname "$target_memory")/.gitignore"
gi_base="$(basename "$target_memory")"
gi_entries=".backups/ .fmc-source _rejstrik.md _hot.md .recall-state/ .recall-hits.log .close-state/ .capability-snapshot .watch-state session.md .session-archive/ .capability-inbox"
gi_display=""
for gi_rel in $gi_entries; do
  gi_display="${gi_display:+$gi_display, }$gi_base/$gi_rel"
done
if [ -L "$gi_file" ]; then
  echo "warn: $gi_file is a symlink — skipping auto-append; add these to your gitignore yourself: $gi_display" >&2
elif [ "$dry_run" -eq 1 ]; then
  echo "would ensure gitignore entries in $gi_file ($gi_display)"
else
  # Ensure the existing .gitignore ends with a newline before appending — else the first new entry
  # concatenates onto a non-LF-terminated last line (".watch-statememory/session.md") and the
  # privacy entry silently fails to apply/match. (Codex audit 2026-07-18.)
  if [ -f "$gi_file" ] && [ -s "$gi_file" ] && [ -n "$(tail -c1 "$gi_file" 2>/dev/null)" ]; then
    printf '\n' >> "$gi_file"
  fi
  for gi_rel in $gi_entries; do
    gi_line="$gi_base/$gi_rel"
    if [ -f "$gi_file" ] && grep -qxF "$gi_line" "$gi_file" 2>/dev/null; then
      continue
    fi
    printf '%s\n' "$gi_line" >> "$gi_file"
    echo "gitignore ensured: $gi_line ($gi_file)"
  done
fi

if [ "$dry_run" -eq 1 ]; then
  echo "Dry run complete. No files changed."
else
  if [ "$refresh_scripts" -eq 0 ]; then
    echo "Install complete. installed=$installed skipped=$skipped overwritten=$overwritten"
    if [ "$overwritten" -gt 0 ]; then
      echo "Backups: $backup_dir/memory"
    fi
  else
    echo "Templates: skipped (memory/*.md untouched by --refresh-scripts)"
  fi
  if [ "$with_scripts" -eq 1 ] || [ "$refresh_scripts" -eq 1 ]; then
    echo "Scripts: installed=$scripts_installed skipped=$scripts_skipped refreshed=$scripts_refreshed"
    if [ "$scripts_refreshed" -gt 0 ]; then
      echo "Script backups: $scripts_backup_dir/scripts"
    fi
  fi
fi
