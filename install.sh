#!/usr/bin/env bash
# Wire this repo in: apt deps, ~/.tmux.conf -> ./config, TPM + plugins, reload.
# Idempotent. Usage: ./install.sh [--dry-run]   (or DRY_RUN=true from the env)
set -euo pipefail

# Physical path: $REPO is baked into three files, and a direct run vs one through
# the ~/.tmuxrc symlink would otherwise disagree and rewrite each other forever.
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# Reject unknown flags: a typo'd --dryrun silently doing a real install is the
# one mistake this script must not make.
case "${1:-}" in
    '')        ;;
    --dry-run) DRY_RUN=true ;;
    *)         printf 'Unknown argument: %s\nUsage: %s [--dry-run]\n' \
                   "$1" "${BASH_SOURCE[0]}" >&2
               exit 1 ;;
esac
# Same for the rest of argv: matching only $1 would let `--dry-run --dryrun` pass.
if [[ $# -gt 1 ]]; then
    printf 'Unexpected extra arguments: %s\nUsage: %s [--dry-run]\n' \
        "${*:2}" "${BASH_SOURCE[0]}" >&2
    exit 1
fi
DRY_RUN="${DRY_RUN:-false}"

# ── Self-contained helpers (no external lib — this repo installs alone) ──────
if [[ -t 1 ]]; then
    C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
    C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi
step()  { printf '%s▸%s %s\n' "$C_BLUE"  "$C_OFF" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
skip()  { printf '%s·%s %s%s%s\n' "$C_DIM" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_OFF" "$*"; }
title() { printf '\n%s══ %s ══%s\n' "$C_BOLD" "$*" "$C_OFF"; }
# would <verb> <what…> — the one place a dry run says what it skipped.
would() { printf '%s  would %s:%s %s\n' "$C_DIM" "$1" "$C_OFF" "${*:2}"; }
run() {
    if [[ "$DRY_RUN" == true ]]; then
        would run "$*"
    else
        "$@"
    fi
}
has_cmd() { command -v "$1" >/dev/null 2>&1; }
# We write via tmp file + mv, and mv replaces a symlink instead of writing
# through it — which would detach a dotfiles-symlinked config from its repo.
resolve_link() { readlink -f "$1" 2>/dev/null || printf '%s' "$1"; }
# Only with a terminal or cached credentials: boot/cron runs must never hang
# waiting for a password.
can_sudo() { [[ -t 0 ]] || sudo -n true 2>/dev/null; }
apt_ensure() {
    local pkg missing=()
    for pkg in "$@"; do dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg"); done
    [[ ${#missing[@]} -eq 0 ]] && { skip "apt: nothing to install (${*})."; return 0; }
    if [[ "$DRY_RUN" == true ]]; then
        would install "${missing[*]}"; return 0
    fi
    if ! can_sudo; then
        warn "sudo unavailable (non-interactive) — skipped apt install: ${missing[*]}"; return 0
    fi
    step "apt: installing ${missing[*]}"
    sudo apt-get update -qq || warn "apt update reported errors — continuing."
    # Tolerated: set -e would otherwise abort before ~/.tmux.conf is even wired,
    # over a held dpkg lock or a non-Debian box.
    sudo apt-get install -y "${missing[@]}" ||
        warn "apt install failed (${missing[*]}) — continuing without them."
}
clone_or_pull() {
    local url="$1" dest="$2"
    if [[ -d "$dest/.git" ]]; then
        run git -C "$dest" pull --ff-only --quiet || warn "Could not pull $dest — leaving as-is."
    elif [[ -e "$dest" ]]; then
        warn "$dest exists but is not a git checkout — leaving untouched."
    else
        step "Cloning $url → $dest"
        # Tolerated: a boot-time re-apply before the network is up is exactly
        # when this fails, and set -e would kill the script mid-install.
        run git clone --quiet "$url" "$dest" ||
            warn "Could not clone $url — plugins unavailable until the next run."
    fi
}
# ensure_source_line <line> <file> [stale_regex] — stale_regex matches lines an
# earlier install wrote, dropped first so a moved checkout isn't sourced twice.
ensure_source_line() {
    local line="$1" file stale_re="${3:-}"
    file="$(resolve_link "$2")"
    if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
        skip "$file already wired."
        return
    fi
    # Append, never truncate — the rest of the file is the user's. Backup name is
    # fixed and never overwritten: only the first one holds their pristine config.
    if [[ -s "$file" ]]; then
        if [[ -e "$file.backup" ]]; then
            warn "$file exists — appending our line (keeping earlier $file.backup)"
        else
            warn "$file exists — appending our line (backup: $file.backup)"
            run cp "$file" "$file.backup"
        fi
    fi
    if [[ "$DRY_RUN" == true ]]; then
        would write "$line → $file"
        return
    fi
    if [[ -n "$stale_re" && -f "$file" ]] && grep -qE "$stale_re" "$file"; then
        step "Dropping a previous install's source line from $file"
        # grep exits 1 on no lines selected — normal for a file holding only our
        # line — so guard it, or the mv is skipped and both lines survive.
        grep -vE "$stale_re" "$file" > "$file.tmp.$$" || [ $? -eq 1 ]
        mv "$file.tmp.$$" "$file"
    fi
    printf '%s\n' "$line" >> "$file"
    ok "wired $file"
}

# ── Install ──────────────────────────────────────────────────────────────────
title "Tmux"

apt_ensure tmux git xclip jq

# apt_ensure swallows its failures, so reaching here proves nothing. Without this
# gate we exit 0 with "Tmux ready." on a box with no tmux, and callers believe it.
if ! has_cmd tmux; then
    warn "tmux is not installed and could not be installed — nothing to configure."
    exit 1
fi

# #{current_file} needs tmux 3.3+; older (Ubuntu 22.04 ships 3.2) falls back to
# ~/.tmuxrc, so a checkout elsewhere loses naming/markers/cwd — silently.
tmux_ver="$(tmux -V)"                 # "tmux 3.2a", "tmux next-3.4"
tmux_ver="${tmux_ver##* }"            # "3.2a" / "next-3.4"
tmux_ver="${tmux_ver##*-}"            # "3.2a" / "3.4"
tmux_ver="${tmux_ver%%[!0-9.]*}"      # "3.2"  / "3.4"
if [[ -n "$tmux_ver" ]] \
   && [[ "$(printf '%s\n3.3\n' "$tmux_ver" | sort -V | head -1)" != "3.3" ]] \
   && [[ "$REPO" != "$(resolve_link "$HOME/.tmuxrc")" ]]; then
    warn "tmux $tmux_ver is older than 3.3, so the config cannot locate this"
    warn "checkout at $REPO — window naming, agent markers and the cwd segment"
    warn "will not load. Symlink it:  ln -s '$REPO' ~/.tmuxrc  and re-run."
fi

# The trailing marker lets a later run replace this line; both patterns are
# anchored to `source-file` so a user's own `# tmuxrc-managed` comment survives.
ensure_source_line "source-file \"$REPO/config\"  # tmuxrc-managed" \
    "$HOME/.tmux.conf" \
    '(^source-file .*# tmuxrc-managed[[:space:]]*$)|(^source-file ~/\.tmuxrc/config[[:space:]]*$)'

# TPM — the plugin manager the config drives.
clone_or_pull https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"

# Install plugins non-interactively if TPM ships its installer.
tpm_install="$HOME/.tmux/plugins/tpm/bin/install_plugins"
if [[ -x "$tpm_install" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        # Not via run(): >/dev/null would swallow its "would run" line.
        would run "$tpm_install"
    else
        step "Installing tmux plugins via TPM"
        # ok inside the success branch: chained after `|| warn` it prints even on
        # failure, reporting both lines at once.
        if "$tpm_install" >/dev/null 2>&1; then
            ok "tmux plugins installed."
        else
            warn "TPM install failed — inside tmux press: prefix + I"
        fi
    fi
else
    warn "TPM installer not found — inside tmux press: prefix + I (backtick + I)."
fi

# Reload: apply the config to any running tmux server right now.
if tmux info >/dev/null 2>&1; then
    step "Reloading running tmux"
    # Same shape as the TPM block above, for the same two reasons.
    if [[ "$DRY_RUN" == true ]]; then
        would run "tmux source-file $HOME/.tmux.conf"
    elif tmux source-file "$HOME/.tmux.conf"; then
        ok "tmux reloaded."
    else
        warn "tmux reload failed."
    fi
else
    skip "No running tmux server — config loads on next start."
fi

ok "Tmux ready."

# ── AI-agent status markers ──────────────────────────────────────────────────
# @agent_state must be set by each agent's own config — wired here, if installed.
title "AI agent status"

AGENT_STATE_SH="$REPO/scripts/agent_state.sh"

# Rebuild our hooks from agents/claude-hooks.json, dropping any we wrote before so
# re-runs never duplicate. Stripped by script name, so an old path still matches.
CLAUDE_JQ='
  def strip_ours:
    with_entries(
      .value |= ( map(.hooks |= ((. // []) | map(select((.command // "") | test("agent_(state|notify)\\.sh") | not))))
                | map(select((.hooks | length) > 0)) )
    )
    | with_entries(select((.value | length) > 0));

  ($map[0]
   | del(.["_comment"])
   | with_entries(.value = [{ hooks: [{ type: "command",
                                        command: ([($dir + "/" + .value[0])] + .value[1:]
                                                  | map(@sh) | join(" ")),
                                        timeout: 5 }] }])) as $ours
  | .hooks = ((.hooks // {}) | strip_ours)
  | reduce ($ours | to_entries[]) as $e (.; .hooks[$e.key] += $e.value)
'

wire_claude() {
    local map="$REPO/agents/claude-hooks.json"
    local settings current new
    settings="$(resolve_link "$HOME/.claude/settings.json")"

    # Checked separately so its absence isn't blamed on settings.json below;
    # after this, a jq failure can only be the settings side.
    if ! jq -e . "$map" >/dev/null 2>&1; then
        warn "claude: $map is missing or not valid JSON — no hooks wired."
        return
    fi

    # Blank counts as absent: jq exits 0 on empty input, so a 0-byte settings.json
    # would compare equal and report "already wired" having written nothing.
    current="$(cat "$settings" 2>/dev/null || true)"
    [[ -n "${current//[[:space:]]/}" ]] || current='{}'

    if ! new="$(printf '%s' "$current" |
                jq --arg dir "$REPO/scripts" --slurpfile map "$map" "$CLAUDE_JQ" 2>/dev/null)"; then
        warn "claude: could not rewrite $settings (not valid JSON, or a hooks" \
             "entry in a shape this script doesn't understand) — left untouched."
        return
    fi

    # Normalised compare: Claude Code watches this file and reloads on any write.
    if [[ "$(printf '%s' "$current" | jq -S .)" == "$(printf '%s' "$new" | jq -S .)" ]]; then
        skip "claude: status hooks already wired."
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        would write "status hooks → $settings"
        return
    fi

    mkdir -p "$(dirname "$settings")"
    # Fixed backup name, written once — see ensure_source_line above for why.
    if [[ -f "$settings" && ! -e "$settings.backup" ]]; then
        cp "$settings" "$settings.backup"
    fi
    printf '%s\n' "$new" > "$settings.tmp.$$" && mv "$settings.tmp.$$" "$settings"
    ok "claude: status hooks wired into $settings"
}

wire_opencode() {
    local src="$REPO/agents/opencode-tmux-status.js"
    local rendered template path_js stale
    local dir="$HOME/.config/opencode/plugins"
    local dest="$dir/tmux-status.js"

    # jq -Rs yields a JSON string (quotes included) that is also a valid JS literal,
    # hence the bare placeholder. Not sed: a path with & or / would corrupt it.
    path_js="$(printf '%s' "$AGENT_STATE_SH" | jq -Rs .)"
    template="$(<"$src")"
    rendered="${template//__AGENT_STATE_SH__/$path_js}"

    # opencode reads both plugin/ and plugins/, so a copy an earlier install left
    # in plugin/ fires every event twice. Remove it, if it's recognisably ours.
    stale="$HOME/.config/opencode/plugin/tmux-status.js"
    if [[ -f "$stale" ]] && grep -q 'export const TmuxStatus' "$stale"; then
        if [[ "$DRY_RUN" == true ]]; then
            would remove "$stale"
        else
            rm -f "$stale"
            ok "opencode: removed duplicate plugin at $stale"
        fi
    fi

    if [[ -f "$dest" ]] && [[ "$(cat "$dest")" == "$rendered" ]]; then
        skip "opencode: plugin already current at $dest"
        return
    fi
    if [[ "$DRY_RUN" == true ]]; then
        would write "$dest"
        return
    fi
    mkdir -p "$dir"
    printf '%s\n' "$rendered" > "$dest"
    ok "opencode: plugin installed at $dest"
}

if ! has_cmd jq; then
    warn "jq not installed — skipped agent status wiring (install jq, then re-run)."
else
    if has_cmd claude || [[ -d "$HOME/.claude" ]]; then
        wire_claude
    else
        skip "claude not installed — no hooks to wire."
    fi

    if has_cmd opencode || [[ -d "$HOME/.config/opencode" ]]; then
        wire_opencode
    else
        skip "opencode not installed — no plugin to wire."
    fi
fi

ok "Agent status ready."
