#!/usr/bin/env bash
# Sourced, not executed. A #() job runs through /bin/sh, so a path baked into
# status-right must be shell-quoted or a space in it breaks the whole segment.

tmux_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}
