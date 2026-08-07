#!/usr/bin/env bash
# Record an agent's state on its $TMUX_PANE so name_windows.sh can paint a marker.
# Usage: agent_state.sh <busy|wait|done|clear>   ('clear' drops the option)

set -u

state="${1:-}"
pane="${TMUX_PANE:-}"

# Nothing to do if we're not inside tmux (e.g. run in a plain terminal).
[ -n "$pane" ] || exit 0

if [ "$state" = "clear" ]; then
  tmux set-option -pu -t "$pane" @agent_state 2>/dev/null
else
  tmux set-option -p -t "$pane" @agent_state "$state" 2>/dev/null
fi

# Nudge the status line so the marker updates now instead of at the next tick.
tmux refresh-client -S 2>/dev/null

exit 0
