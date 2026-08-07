#!/usr/bin/env bash
# Pick a window name from a pane ($1 = pane_tty, $2 = pane_current_command). An
# interpreter -> dig the tool out of argv, or claude and codex all read "node".

# -f (noglob): the argv scan splits on whitespace deliberately, but without it a
# token containing *, ? or [...] would also glob into a filename.
set -uf

tty="${1:-}"
cmd="${2:-}"

case "$cmd" in
  node | nodejs | deno | bun | python | python2 | python3 | ruby | perl | php)
    dev="${tty#/dev/}"
    # Full argv of the foreground process on this tty (the one with '+' in STAT).
    args="$(ps -t "$dev" -o stat=,args= 2>/dev/null | awk '$1 ~ /\+/ { $1=""; sub(/^ /,""); print }' | tail -1)"

    # The script path is the first token that is neither a flag nor the
    # interpreter; flags taking a separate value must skip it too.
    script=""
    skip_next=""
    take_next=""
    # deno/bun put a subcommand first (`bun run dev`), which would otherwise name
    # every such window "run". Only the first word, only for those two.
    case "$cmd" in
      deno | bun) sub=1 ;;
      *)          sub="" ;;
    esac
    for tok in $args; do
      if [ -n "$take_next" ]; then script="$tok"; break; fi
      if [ -n "$skip_next" ]; then skip_next=""; continue; fi
      case "$tok" in
        # Preloads — the value is a helper, not the program:
        # `node -r ts-node/register app.js` must name the window after app.
        -r | --require | --import | --loader | --experimental-loader)
          skip_next=1; continue ;;
        # `python -m pkg.mod` — here the value *is* the program.
        -m) take_next=1; continue ;;
        -*) continue ;;                                # flags
        "$cmd" | */"$cmd" | */"$cmd".*) continue ;;    # the interpreter itself
        *) if [ -n "$sub" ]; then
             sub=""
             case "$tok" in
               run | exec | task | x) continue ;;
             esac
           fi
           script="$tok"; break ;;
      esac
    done

    # Walk the path backwards to the first meaningful component, skipping generic
    # names and npm scopes: …/@anthropic-ai/claude-code/cli.js -> claude-code.
    name=""
    rest="$script"
    first=1
    while [ -n "$rest" ]; do
      comp="${rest##*/}"          # last path component
      rest="${rest%/*}"           # drop it
      [ "$rest" = "$comp" ] && rest=""   # no more slashes
      leaf="$first"; first=""     # is this the path's own basename?
      # Only real script extensions: a blanket ${comp%.*} turns `python -m
      # http.server` into "http".
      case "$comp" in
        *.js | *.mjs | *.cjs | *.ts | *.mts | *.cts | *.py | *.rb | *.pl | *.php)
          comp="${comp%.*}" ;;
      esac
      case "$comp" in
        # Generic entrypoint/scope names, skipped wherever they turn up.
        '' | .* | @* | cli | index | main | __main__) continue ;;
        # Generic *directory* names — skipped only in a directory position; as a
        # basename they are the real script and must be kept.
        bin | dist | src | lib | build | out | node_modules)
          [ -n "$leaf" ] && { name="$comp"; break; }
          continue ;;
        *) name="$comp"; break ;;
      esac
    done

    # '#' introduces a tmux format, honoured even inside a window name — and this
    # came from another process's argv, so a #[…] in it could garble the bar.
    name="${name:-$cmd}"
    printf '%s\n' "${name//\#/}"
    exit 0
    ;;
esac

printf '%s\n' "${cmd//\#/}"
