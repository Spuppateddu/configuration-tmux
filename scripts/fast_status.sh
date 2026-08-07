#!/usr/bin/env bash
# Swaps dracula's cwd command for a path-aware one. Passing the path as an
# argument changes the command string, which bypasses tmux's 1s per-job cache.

set -u
# Absolute: this gets baked into status-right and runs later from an unknown cwd.
# Resolved from this script's location, so the checkout can live anywhere.
scripts="$(cd -- "$(dirname -- "$0")" && pwd)"
dracula="$HOME/.tmux/plugins/tmux/scripts"
. "$scripts/tmux_quote.sh"

cwd_q="$(tmux_quote "$scripts/cwd.sh")"

right="$(tmux show-option -gqv status-right)"
[ -n "$right" ] || exit 0

right="${right//"#($dracula/cwd.sh)"/"#($cwd_q \"#{pane_current_path}\")"}"

tmux set-option -g status-right "$right"
