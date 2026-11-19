#!/usr/bin/env bash
# Two status rows, on every terminal (the desk and a phone over ssh alike).
#   Top row:    cwd on the left, CPU/RAM on the right (over ssh only).
#   Bottom row: session name and tabs on the left, the updates counter on the right.
#
# Builds both rows from status-right (after dracula, fast_status.sh and
# updates_status.sh) and sets them globally, so every session gets them.

set -u

# Start from tmux's own single-row format, so a re-source (or a session left with
# its own rows by an older version of this script) splits the real one again.
# A session behind F12 (key-table off) keeps its own `status off`: clearing it would
# bring the outer bar back over the nested tmux.
tmux set -gu status \; set -gu status-format
tmux list-sessions -F '#{session_name}' 2>/dev/null |
  while IFS= read -r s; do
    tmux set -t "$s" -u status-format
    [ "$(tmux show -t "$s" -qv key-table)" = off ] || tmux set -t "$s" -u status
  done

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

tmux set -g status 2 \; \
  set -g 'status-format[0]' "#[align=left]${cwd}#[default]#[align=right]${tail}#[default]" \; \
  set -g 'status-format[1]' "${tabs}#[nolist align=right default]${upd}#[default]"
