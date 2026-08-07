// Report opencode's state to tmux so name_windows.sh can paint a marker. Rendered
// by install.sh (JSON-encoded path, hence the bare placeholder) — edit this copy.

const AGENT_STATE = __AGENT_STATE_SH__

export const TmuxStatus = async ({ $ }) => {
  // A marker is never worth breaking the agent over: swallow every failure.
  const mark = (state) => $`${AGENT_STATE} ${state}`.quiet().nothrow()

  return {
    "session.created": async () => { await mark("busy") },
    // Re-assert busy after each tool: this clears [ ] once you've answered.
    "tool.execute.after": async () => { await mark("busy") },
    "permission.asked": async () => { await mark("wait") },
    "permission.replied": async () => { await mark("busy") },
    "session.idle": async () => { await mark("done") },
    "session.error": async () => { await mark("wait") },
  }
}
