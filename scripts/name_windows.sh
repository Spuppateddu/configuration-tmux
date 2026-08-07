#!/usr/bin/env bash
# Name every window after its active pane's program, re-run each status-interval
# from a hidden #(). automatic-rename can't see through node, so we do it here.

set -u
# Relative to this script so the checkout can live anywhere. Parameter expansion,
# not a $(cd …) subshell: this runs once a second.
dir="${0%/*}"
[ "$dir" = "$0" ] && dir=.
NAME="$dir/window_name.sh"

# Marker for agent windows, from @agent_state. Glyph not emoji so it survives
# urxvt; TABFG is restored after, as #[default] clobbers the focused tab.
TABFG='#EBDBB2'                            # dracula white = normal window-tab fg
BUSY="#[fg=#83A598][~]#[fg=$TABFG] "       # working            (bright blue)
WAIT="#[fg=#FE8019][ ]#[fg=$TABFG] "       # waiting for input  (bright orange)
DONE="#[fg=#B8BB26][x]#[fg=$TABFG] "       # finished / ready   (bright green)

# US/RS rather than printable delimiters: window names are free text, and one
# containing the separator would shift every field after it.
FS="$(printf '\037')"
RS="$(printf '\036')"

# How long an argv-resolved name stays trusted: the cache key can't tell one node
# tool from another, so swapping claude for codex within a tick would stick.
TTL=10
printf -v now '%(%s)T' -1          # bash builtin, no fork

declare -A pname wstate

# A shell means "just a prompt": the name says nothing the tab number doesn't,
# so it gets hidden (see pass 2).
is_shell() {
  case "$1" in
    ash | bash | csh | dash | elvish | fish | ksh | mksh | nu | sh | tcsh | xonsh | zsh) return 0 ;;
  esac
  return 1
}

panes="$(tmux list-panes -a \
  -F "#{window_id}${FS}#{pane_id}${FS}#{pane_active}${FS}#{pane_current_command}${FS}#{pane_tty}${FS}#{@agent_state}${FS}#{@name_cache}${FS}#{@auto_name}${FS}#{@name_hidden}${FS}#{window_name}")"

# Pass 1 — resolve a name per pane and collect agent state. All panes, since an
# agent in a background split counts — but only if its own program still matches.
while IFS="$FS" read -r wid pid active cmd tty state cache auto hidden name; do
  # Resolving costs ~27ms of forks per interpreter pane, every second. Cache it on
  # the pane as "<cmd>RS<resolved-at>RS<name>" so steady state forks nothing.
  desired=""
  c_cmd="${cache%%"$RS"*}"
  c_rest="${cache#*"$RS"}"
  c_ts="${c_rest%%"$RS"*}"
  c_name="${c_rest#*"$RS"}"
  # Three fields or it isn't ours — an older layout's entry parses as two, and
  # re-resolving once is the cheapest migration.
  if [ -n "$cache" ] && [ "$cache" != "$c_rest" ] && [ "$c_rest" != "$c_name" ] \
     && [ "$c_cmd" = "$cmd" ] \
     && { [ "$c_name" = "$cmd" ] || [ "$((now - c_ts))" -lt "$TTL" ]; }; then
    desired="$c_name"
  else
    desired="$("$NAME" "$tty" "$cmd")"
    [ -n "$desired" ] || continue
    tmux set-option -p -t "$pid" @name_cache "$cmd$RS$now$RS$desired"
  fi
  pname[$pid]="$desired"

  case "$desired" in
    claude | claude-* | opencode )
      # Worst news wins: a window shows "finished" only once nothing in it is
      # still running or blocked.
      case "$state" in
        wait) wstate[$wid]=wait ;;
        busy) [ "${wstate[$wid]-}" = wait ] || wstate[$wid]=busy ;;
        done) [ -n "${wstate[$wid]-}" ]     || wstate[$wid]=done ;;
      esac
      ;;
  esac
done <<< "$panes"

# Pass 2 — name each window from its active pane, marker first.
while IFS="$FS" read -r wid pid active cmd tty state cache auto hidden name; do
  [ "$active" = 1 ] || continue
  desired="${pname[$pid]-}"
  [ -n "$desired" ] || continue

  # A shell-only window shows just its number: @name_hidden drops #W from the tab
  # (tab_format.sh). A marker wins, since it lives in the name and would go too.
  hide=0
  if [ -z "${wstate[$wid]-}" ] && is_shell "$desired"; then
    hide=1
  fi

  case "${wstate[$wid]-}" in
    busy) desired="$BUSY$desired" ;;
    wait) desired="$WAIT$desired" ;;
    done) desired="$DONE$desired" ;;
  esac

  # Hands off a window the user renamed, or `prefix + ,` is undone within the
  # second. @auto_name is our last name, so a mismatch means someone else set it.
  if [ -n "$auto" ] && [ "$name" != "$auto" ]; then
    # A name you chose yourself is never the redundant one, so always show it.
    [ "$hidden" = 0 ] || tmux set-option -w -t "$wid" @name_hidden 0
    continue
  fi

  [ "$hidden" = "$hide" ] || tmux set-option -w -t "$wid" @name_hidden "$hide"
  [ "$name" = "$desired" ] || tmux rename-window -t "$wid" "$desired"
  # Recorded even when no rename was needed, so an already-correct window is
  # still claimed and a later manual rename is respected.
  [ "$auto" = "$desired" ] || tmux set-option -w -t "$wid" @auto_name "$desired"
done <<< "$panes"
