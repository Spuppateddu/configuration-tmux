#!/usr/bin/env bash
# Claude's Notification hook fires for permission prompts *and* the post-turn idle
# nudge, which mean opposite things — so read the JSON on stdin and pick a state.

set -u

input="$(cat 2>/dev/null || true)"

case "$input" in
  # Idle nudge: the turn is over, so keep showing "finished".
  *"waiting for your input"*) state=done ;;
  # Anything else counts as needing you: a false [ ] is cheap, a missed one isn't.
  *) state=wait ;;
esac

exec "$(dirname "$0")/agent_state.sh" "$state"
