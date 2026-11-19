// Empty on purpose. opencode 2 loads a plugin folder on its shared server too, and
// fails with "Plugin entrypoint not found" when the folder has no server entry.
// The real work is in tui.js: see the README for why it can't live here.
export default { id: "tmux-status", setup: () => {} }
