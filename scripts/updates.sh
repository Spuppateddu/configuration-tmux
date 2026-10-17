#!/usr/bin/env bash
# Waiting apt updates, for status-right — only for a client attached over ssh:
# at the desk the i3 bar already shows them. $1 is #{client_pid}, so each client
# decides for itself. The count is best-linux-environment's `b-update --count`
# (cached there, so this is cheap every tick); without it, or at 0, prints nothing.

set -u
pid="${1:-}"
b="$HOME/.local/bin/b-update"
[ -n "$pid" ] && [ -x "$b" ] || exit 0
# The client's own environment, not the server's: the server may have been
# started at the desk and an ssh client attached to it later.
tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep '^SSH_CONNECTION=' >/dev/null || exit 0

n="$("$b" --count 2>/dev/null)"
case "$n" in ''|0|*[!0-9]*) exit 0 ;; esac
printf '#[fg=#282828,bg=#D79921] 󰚰 %s ' "$n"
