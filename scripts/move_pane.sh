#!/bin/sh
# Move a pane inside its session: into a window side by side or stacked, or out
# into a window alone at any position. Run by `prefix m` in a popup. Usage: move_pane.sh PANE_ID CLIENT_TTY

pane=${1:?usage: move_pane.sh PANE_ID CLIENT_TTY}
client=${2:?usage: move_pane.sh PANE_ID CLIENT_TTY}
# The terminal's own session: in a group (<host>-2…) the windows are shared, the current one is not.
sess=$(tmux display-message -p -c "$client" '#{session_id}')
here=$(tmux display-message -p -t "$pane" '#{window_id}')
herei=$(tmux display-message -p -t "$pane" '#{window_index}')
panes=$(tmux display-message -p -t "$pane" '#{window_panes}')

# One line per window: id, index, name, panes. renumber-windows keeps the indexes 1..n.
list=$(tmux list-windows -t "$sess" -F '#{window_id}	#{window_index}	#{window_name}	#{window_panes}')
last=$(printf '%s\n' "$list" | tail -n 1 | cut -f2)

# What the list shows: join a window, then a slot of its own before each window and
# at the end. A pane alone in its window moves the whole window: that reorders them.
if [ "$panes" -gt 1 ]; then verb='alone, as window'; else verb='move window to position'; fi
choices=$(printf '%s\n' "$list" | while IFS='	' read -r id i name n; do
    s=s; [ "$n" -gt 1 ] || s=
    mark=; [ "$id" = "$here" ] && mark=' ← here'
    printf 'join:%s\t%s: %s (%s pane%s)%s\n' "$id" "$i" "$name" "$n" "$s" "$mark"
done
printf '%s\n' "$list" | while IFS='	' read -r id i name n; do
    # Alone already: the slots just before and after its window change nothing.
    [ "$panes" -eq 1 ] && { [ "$i" = "$herei" ] || [ "$i" = $((herei + 1)) ]; } && continue
    to=$i; [ "$panes" -eq 1 ] && [ "$herei" -lt "$i" ] && to=$((i - 1))
    printf 'before:%s\t%s %s (before %s)\n' "$id" "$verb" "$to" "$name"
done
if [ "$panes" -gt 1 ]; then
    printf 'end\t%s %s (the last)\n' "$verb" $((last + 1))
elif [ "$herei" != "$last" ]; then
    printf 'end\t%s %s (the last)\n' "$verb" "$last"
fi)

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

dest=$(printf '%s\n' "$choices" | pick 'move pane to' | cut -f1)
[ -n "$dest" ] || exit 0

case $dest in
before:* | end)
    if [ "$dest" = end ]; then where="-a -t $sess:$last"; else where="-b -t ${dest#before:}"; fi
    # renumber-windows acts only when a window closes, not when one moves: renumber by hand.
    if [ "$panes" -eq 1 ]; then
        # shellcheck disable=SC2086 # $where is two flags and a target
        tmux move-window -s "$here" $where \; move-window -r -t "$sess"
    else
        # shellcheck disable=SC2086
        tmux break-pane -s "$pane" $where \; select-layout -t "$here" -E
    fi
    tmux select-window -t "$pane"
    exit 0
    ;;
esac
dest=${dest#join:}

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
