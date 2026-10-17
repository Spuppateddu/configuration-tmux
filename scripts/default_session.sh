#!/bin/sh
# Open tmux's main session, named after the PC (hostname): create it, or join it
# with a new window.
# Alacritty runs it as its shell; bashrc/zshrc run it with --ssh (exit 1 = skipped).

# Each terminal is its own session in the main one's group (<host>-2…): same windows,
# its own current one. A plain `attach` would make two terminals mirror each other.
# The status bar shows the group's name, so every view reads as the hostname.

SESSION=$(hostname -s 2>/dev/null | tr -c 'A-Za-z0-9_\n-' _)
[ -n "$SESSION" ] || SESSION=default
mode=${1:-}

skip() {
    [ "$mode" = --ssh ] && exit 1
    exec "${SHELL:-/bin/sh}"
}

[ -n "${TMUX:-}" ] && skip
[ -n "${BLE_NO_TMUX:-}" ] && skip
command -v tmux >/dev/null 2>&1 || skip
# VS Code's remote terminal is its own tab, not a place to run tmux in.
[ "${TERM_PROGRAM:-}" = vscode ] && skip

# Detached first: of two terminals opened at once, the loser fails here and
# joins as a second view instead of erroring out.
fresh=false
if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
    tmux new-session -d -s "$SESSION" -c "$PWD" 2>/dev/null && fresh=true
fi
tmux has-session -t "=$SESSION" 2>/dev/null || skip

# First free <host>-N; the create itself is the check, so a name race moves on.
n=2
while ! tmux new-session -d -t "=$SESSION" -s "$SESSION-$n" 2>/dev/null; do
    n=$((n + 1))
    [ "$n" -gt 99 ] && skip
done

# destroy-unattached drops this view when the terminal closes; windows stay.
# A fresh main session already has its first, empty window: show that one.
set -- attach-session -t "=$SESSION-$n" \; set-option destroy-unattached on
[ "$fresh" = true ] || set -- "$@" \; new-window -c "$PWD"

[ "$mode" = --ssh ] && { tmux "$@"; exit; }
exec tmux "$@"
