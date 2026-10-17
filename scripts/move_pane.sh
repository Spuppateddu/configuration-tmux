#!/bin/sh
# Move a pane inside its session: into a window side by side or stacked, or out
# into a window alone. Run by `prefix M` in a popup. Usage: move_pane.sh PANE_ID CLIENT_TTY

pane=${1:?usage: move_pane.sh PANE_ID CLIENT_TTY}
client=${2:?usage: move_pane.sh PANE_ID CLIENT_TTY}
# The terminal's own session: in a group (<host>-2…) the windows are shared, the current one is not.
sess=$(tmux display-message -p -c "$client" '#{session_id}')
here=$(tmux display-message -p -t "$pane" '#{window_id}')
alone='new window (alone)'

# One line per window: id, then what the list shows. Our own window is marked.
windows=$(tmux list-windows -t "$sess" -F \
    "#{window_id}	#{window_index}: #{window_name} (#{window_panes} panes)#{?#{==:#{window_id},$here}, ← here,}")

# pick PROMPT: a line from stdin, by fzf when there is one, else by its number.
pick() {
    if command -v fzf >/dev/null 2>&1; then
        fzf --reverse --delimiter='	' --with-nth=2.. --prompt="$1 > "
    else
        list=$(cat)
        printf '%s\n' "$list" | cut -f2- | nl -w2 -s') ' >&2
        printf '%s (number): ' "$1" >&2
        read -r n </dev/tty
        printf '%s\n' "$list" | sed -n "${n}p"
    fi
}

dest=$(printf 'new\t%s\n%s\n' "$alone" "$windows" | pick 'move pane to' | cut -f1)
[ -n "$dest" ] || exit 0

panes=$(tmux display-message -p -t "$pane" '#{window_panes}')
if [ "$dest" = new ]; then
    [ "$panes" -gt 1 ] || { tmux display-message -d 1000 'Pane is already alone'; exit 0; }
    tmux break-pane -s "$pane" \; select-layout -t "$here" -E
    exit 0
fi

# In its own window it joins another pane there, which flips the split direction.
target=$dest
if [ "$dest" = "$here" ]; then
    [ "$panes" -gt 1 ] || { tmux display-message -d 1000 'Pane is alone in this window'; exit 0; }
    target=$(tmux list-panes -t "$here" -F '#{pane_id}' | grep -vxF -- "$pane" | head -n 1)
fi

how=$(printf -- '-h\tside by side │\n-v\tstacked ─\n' | pick 'split' | cut -f1)
[ -n "$how" ] || exit 0

tmux join-pane "$how" -s "$pane" -t "$target" \; select-window -t "$sess:$dest" \
    \; select-pane -t "$pane" \; select-layout -t "$dest" -E
# Spread what is left behind; fails when the pane was the window's last one.
[ "$dest" = "$here" ] || tmux select-layout -t "$here" -E 2>/dev/null || true
