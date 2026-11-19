// Report opencode's state to tmux so name_windows.sh can paint a marker. Rendered
// by install.sh (JSON-encoded path, hence the bare placeholder) — edit this copy.

// opencode 2: a TUI plugin, not a server one. Every opencode window talks to one
// shared background server, so a server plugin only knows the $TMUX_PANE of the
// pane that started that server. This file runs inside each window's own process,
// with that window's pane. See the README before changing this.

import { execFile } from "node:child_process"

const AGENT_STATE = __AGENT_STATE_SH__

// A marker is never worth breaking the agent over: swallow every failure.
const run = (state) =>
  new Promise((resolve) => execFile(AGENT_STATE, [state], () => resolve()))

export default {
  id: "tmux-status",
  setup: (ctx) => {
    // Session ids, for every session on the server: this window still sees the
    // events of all the other windows, so paint() filters them below.
    const busy = new Set()
    // Permission and question ids still waiting on you -> their session id.
    const asking = new Map()
    // Session ids whose last turn failed: that needs you too.
    const failed = new Set()
    let painted = null

    // The top session: a sub-agent is a child session, and it counts for the
    // window that shows its parent.
    const root = (id) => {
      for (let i = 0; i < 20; i++) {
        const parent = ctx.data.session.get(id)?.parentID
        if (!parent) return id
        id = parent
      }
      return id
    }

    const paint = async () => {
      const route = ctx.ui.router.current()
      const mine = route.type === "session" ? root(route.sessionID) : null
      const here = (id) => mine !== null && root(id) === mine
      let state = "done"
      if ([...asking.values()].some(here) || [...failed].some(here)) state = "wait"
      else if ([...busy].some(here)) state = "busy"
      if (state === painted) return // don't spawn tmux for a no-op
      painted = state
      await run(state)
    }

    const handle = (event) => {
      const d = event.data ?? {}
      switch (event.type) {
        case "session.execution.started":
          busy.add(d.sessionID)
          failed.delete(d.sessionID)
          break
        case "session.execution.succeeded":
        case "session.execution.interrupted":
        case "session.idle":
          busy.delete(d.sessionID)
          break
        case "session.execution.failed":
          busy.delete(d.sessionID)
          failed.add(d.sessionID)
          break
        case "session.deleted":
          busy.delete(d.sessionID)
          failed.delete(d.sessionID)
          break
        case "permission.asked":
          asking.set(d.id, d.sessionID)
          break
        case "permission.replied":
          asking.delete(d.requestID)
          break
        // The question tool is a "form" in opencode 2.
        case "form.created":
          if (d.form) asking.set(d.form.id, d.form.sessionID)
          break
        case "form.replied":
        case "form.cancelled":
          asking.delete(d.id)
          break
      }
      // Repaint on every event, not only the ones above: the route (which session
      // this window shows) has no event of its own. paint() is a no-op when
      // nothing changed, so the message firehose costs no tmux call.
      paint().catch(() => {})
    }

    // No session exists until the first prompt, so paint at startup instead:
    // else a freshly opened window shows no marker at all.
    paint().catch(() => {})
    const stop = ctx.data.listen((e) => handle(e.details))

    // opencode is quitting: drop the marker rather than leave a stale [x].
    return async () => {
      stop()
      await run("clear")
    }
  },
}
