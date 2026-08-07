#!/usr/bin/env bash
# Print the given path with $HOME collapsed to '~'. Takes it as an argument, so
# tmux re-runs the job the moment the path changes.

set -u

path="${1:-}"
[ -n "$path" ] || exit 0

case "$path" in
  "$HOME")   out='~' ;;
  "$HOME"/*) out="~${path#"$HOME"}" ;;
  *)         out="$path" ;;
esac

# tmux honours a #[…] style found in a #() job's output, and this is a directory
# name — so a dir called '#[bg=red]x' would garble the bar. As in window_name.sh.
printf '%s' "${out//\#/}"
