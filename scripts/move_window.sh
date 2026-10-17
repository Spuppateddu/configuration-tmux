#!/bin/sh
# Move a window to another session and follow it there; a new name makes a new
# session. Run by `prefix m` in a popup. Usage: move_window.sh WINDOW_ID CLIENT_TTY

win=${1:?usage: move_window.sh WINDOW_ID CLIENT_TTY}
client=${2:?usage: move_window.sh WINDOW_ID CLIENT_TTY}
group='#{?session_group,#{session_group},#{session_name}}'
here=$(tmux display-message -p -t "$win" "$group")

# One name per group: <host>-2, <host>-3… are views of the main <host> session.
targets=$(tmux list-sessions -F "$group" | sort -u | grep -vxF -- "$here")

if command -v fzf >/dev/null 2>&1; then
    # --print-query: line 1 is what was typed, line 2 the pick. Typed text is the
    # name (new session unless it exists); the pick counts only with nothing typed.
    out=$(printf '%s\n' "$targets" | grep . |
        fzf --print-query --reverse --prompt="move window to > " \
            --header="Type a name + Enter (new or existing), or pick one")
    dest=$(printf '%s\n' "$out" | sed -n 1p)
    [ -n "$dest" ] || dest=$(printf '%s\n' "$out" | sed -n 2p)
else
    printf '%s\n' "$targets"
    printf 'move window to (new name = new session): '
    read -r dest
fi
[ -n "$dest" ] || exit 0

# tmux reads '.' and ':' in a session name as window/pane separators.
case "$dest" in
    *[.:]*) tmux display-message "No '.' or ':' in a session name"; exit 0 ;;
esac

# new-session needs a window of its own; it is dropped once ours has moved in.
spare=""
tmux has-session -t "=$dest" 2>/dev/null ||
    spare=$(tmux new-session -d -s "$dest" -P -F '#{window_id}') || exit 1

# The terminal follows the window there. One tmux call: the popup dies with the
# switch, and switching first keeps a last window's session from closing it.
set -- switch-client -c "$client" -t "=$dest" \; move-window -s "$win" -t "=$dest:" \
    \; select-window -t "=$dest:$win"
[ -n "$spare" ] && set -- "$@" \; kill-window -t "$spare"
# -d: tmux-sensible's display-time keeps a message up for 4 s; this one needs 1.
tmux "$@" \; display-message -d 1000 -c "$client" "Window moved to session '$dest'"
