#!/usr/bin/env bash
# Wire @name_hidden (set by name_windows.sh) into the tab format, so a shell-prompt
# window shows only its number. Rewrites dracula's formats to keep its colors.

set -u

for opt in window-status-format window-status-current-format; do
  fmt="$(tmux show-option -gqv "$opt")"
  [ -n "$fmt" ] || continue
  case "$fmt" in
    *@name_hidden*) continue ;;   # already rewritten
  esac
  # The number, then the name and its leading space only when there's something
  # to announce.
  new="${fmt//'#I #W'/'#I#{?#{@name_hidden},, #W}'}"
  # This is an exact match against dracula's format, so a theme update that
  # respaces it must not fail silently — a miss would just drop the feature.
  if [ "$new" = "$fmt" ]; then
    # ## is a literal '#': display-message expands formats, so an unescaped
    # "#I #W" would name the *current* window as the thing it couldn't find.
    tmux display-message "tab_format.sh: '##I ##W' not found in $opt — window names not hidden"
    continue
  fi
  tmux set-option -g "$opt" "$new"
done
