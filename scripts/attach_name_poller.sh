#!/usr/bin/env bash
# Append the window-namer to status-right so tmux runs it as a side-effect of
# drawing the bar. A script because run-shell would expand the #() at parse time.

set -u

right="$(tmux show-option -gqv status-right)"
case "$right" in
  *name_windows.sh*) exit 0 ;;   # already attached
esac

# Absolute so the checkout can live anywhere, quoted because it is about to be
# baked into status-right.
dir="$(cd -- "$(dirname -- "$0")" && pwd)"
. "$dir/tmux_quote.sh"

tmux set-option -ga status-right "#($(tmux_quote "$dir/name_windows.sh"))"
