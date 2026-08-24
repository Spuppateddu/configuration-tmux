// Report opencode's state to tmux so name_windows.sh can paint a marker. Rendered
// by install.sh (JSON-encoded path, hence the bare placeholder) — edit this copy.

// Every state change arrives on the generic `event` hook: a bus event used as a
// hook key binds nothing, silently. See the README before changing this.

const AGENT_STATE = __AGENT_STATE_SH__

export const TmuxStatus = async ({ $ }) => {
  // A marker is never worth breaking the agent over: swallow every failure.
  const run = (state) => $`${AGENT_STATE} ${state}`.quiet().nothrow()

  // A sub-agent is its own session, so one idle event is not the end of the turn:
  // count the busy ones and only say "done" at zero.
  const busy = new Set()
  // Permission ids still waiting on you. A set, not a flag: two prompts can queue.
  const asking = new Set()
  let painted = null

  const paint = async () => {
    const state = asking.size ? "wait" : busy.size ? "busy" : "done"
    if (state === painted) return // don't spawn tmux for a no-op
    painted = state
    await run(state)
  }

  // No session exists until the first prompt, so paint at startup instead: else a
  // freshly opened window shows no marker at all.
  await paint()

  return {
    event: async ({ event }) => {
      const p = event.properties ?? {}
      switch (event.type) {
        // The turn's own signal: "retry" is a provider backoff, still working.
        case "session.status":
          if (p.status?.type === "idle") busy.delete(p.sessionID)
          else busy.add(p.sessionID)
          break
        // Belt and braces: older builds emit only this one.
        case "session.idle":
          busy.delete(p.sessionID)
          break
        case "session.created":
          break // repaint: a sub-agent's session must not leave the tab stale
        case "session.deleted":
          busy.delete(p.sessionID)
          break
        // Needs an answer from you. `permission.updated` is the older spelling
        // the SDK types still carry, so honour both.
        case "permission.asked":
        case "permission.updated":
        case "question.asked":
          asking.add(p.id ?? p.requestID)
          break
        // The runtime says `requestID`, the published types `permissionID`.
        case "permission.replied":
        case "question.replied":
        case "question.rejected":
          asking.delete(p.requestID ?? p.permissionID ?? p.id)
          break
        // A failed turn needs you, and no session.status follows it — so force it.
        case "session.error":
          busy.delete(p.sessionID)
          painted = "wait"
          await run("wait")
          return
        default:
          return // ignore the message.part.updated firehose without touching tmux
      }
      await paint()
    },

    // opencode is quitting: drop the marker rather than leave a stale [x].
    dispose: async () => {
      await run("clear")
    },
  }
}
