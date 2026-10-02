#!/bin/sh
# Routes a speak key press (2026-10-02, Gavin's design). Herdr runs this with
# a minimal environment and HERDR_PLUGIN_CONTEXT_JSON describing the focused
# pane (MEASURED by the conductor: 4 of 4 key presses from a Claude pane
# carried focused_pane_id and focused_pane_agent; selected_text was absent in
# all 4, because Claude Code owns its highlight, not herdr).
#
#   focused pane runs Claude -> speak-clipboard --toggle --from-pane <id>
#                               (borrows the clipboard: Ctrl+Shift+C into the
#                               pane, read, restore; see speak-clipboard)
#   anything else            -> speak-clipboard --toggle, and NO keys are sent:
#                               Ctrl+Shift+C into a shell or another agent can
#                               arrive as ^C and interrupt it
#
# When the context cannot be read (no JSON, no jq, a field missing) it takes
# the second branch: a press that cannot see the pane never sends keys.
# Prints nothing in normal use: herdr keeps a plugin's stdout in its plugin
# log, and the text must never be logged. SPEAK_SELECTION_DRYRUN=1 prints the
# command it would run instead (for testing the routing).
# HOME may be missing from herdr's minimal environment (not measured); a
# tilde falls back to the password database when it is.
: "${HOME:=$(cd ~ 2>/dev/null && pwd)}"
PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

sc="$HOME/.local/bin/speak-clipboard"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"
agent=""
pane=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  agent=$(printf '%s' "$ctx" | jq -r '.focused_pane_agent // empty' 2>/dev/null)
  pane=$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty' 2>/dev/null)
fi

if [ "$agent" = "claude" ] && [ -n "$pane" ]; then
  set -- --toggle --from-pane "$pane"
else
  set -- --toggle
fi

if [ -n "${SPEAK_SELECTION_DRYRUN:-}" ]; then
  printf '%s\n' "$sc $*"
  exit 0
fi
exec "$sc" "$@"
