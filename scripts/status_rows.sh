#!/usr/bin/env bash
# Two status rows on a narrow terminal (a phone over ssh), one row on a wide one.
#   Top row:    cwd on the left, CPU/RAM on the right.
#   Bottom row: session name and tabs on the left, the updates counter on the right.
#
# status_rows.sh                     build both rows from status-right (after dracula,
#                                    fast_status.sh and updates_status.sh), then apply
#                                    them to every attached client.
# status_rows.sh <session> <width>   apply to one session (from the client-resized hooks).
#
# Set per session, not globally: each terminal is its own grouped session, so the
# phone gets two rows while the desk keeps one.

set -u
narrow=100   # columns: below this the bar wraps into two rows

apply() {
  local s="$1" w="$2"
  case "$w" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$w" -lt "$narrow" ]; then
    tmux set -t "$s" status 2 \; \
      set -t "$s" 'status-format[0]' "$(tmux show -gqv @status_rows_top)" \; \
      set -t "$s" 'status-format[1]' "$(tmux show -gqv @status_rows_bottom)"
  else
    tmux set -t "$s" -u status \; set -t "$s" -u status-format
  fi
}

if [ $# -ge 2 ]; then
  apply "$1" "$2"
  exit 0
fi

right="$(tmux show -gqv status-right)"
row0="$(tmux show -gqv 'status-format[0]')"
tabs="${row0%%#\[nolist align=right*}"
if [ -z "$right" ] || [ "$tabs" = "$row0" ]; then
  tmux display-message "status_rows.sh: status format not recognised — staying on one row"
  exit 0
fi

# status-right is: updates.sh, then the cwd, then (over ssh) CPU and RAM, then the
# window namer. The updates part, if any, is the first #(...) and ends at its first ')'.
upd=""
case "$right" in *updates.sh*) upd="${right%%)*})" ;; esac
rest="${right#"$upd"}"
# CPU starts at dracula's next segment colour; locally there's none and it all stays left.
cwd="${rest%%#\[fg=#282828\]*}"
tail="${rest#"$cwd"}"

tmux set -g @status_rows_top "#[align=left]${cwd}#[default]#[align=right]${tail}#[default]"
tmux set -g @status_rows_bottom "${tabs}#[nolist align=right default]${upd}#[default]"

tmux list-clients -F '#{session_name}	#{client_width}' 2>/dev/null |
  while IFS=$'\t' read -r s w; do apply "$s" "$w"; done
