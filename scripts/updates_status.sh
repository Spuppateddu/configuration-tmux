#!/usr/bin/env bash
# Puts scripts/updates.sh at the left of status-right. Runs after dracula, like
# fast_status.sh; a reload that keeps status-right gets no second copy.

set -u
# Absolute: this gets baked into status-right and runs later from an unknown cwd.
scripts="$(cd -- "$(dirname -- "$0")" && pwd)"
. "$scripts/tmux_quote.sh"

right="$(tmux show-option -gqv status-right)"
case "$right" in *updates.sh*) exit 0 ;; esac

tmux set-option -g status-right "#($(tmux_quote "$scripts/updates.sh") #{client_pid})$right"
