#!/bin/sh
# Workaround for https://github.com/herdrdev/herdr/issues/3200: a freshly
# created workspace's ui.window_title stays frozen on the workspace it was
# created FROM until a human renames it by hand -- the sidebar label is
# correct the whole time, only the title's internal copy is stale. Renaming
# the workspace to its own current label forces that copy to refresh, with
# no visible change.
#
# Deliberately re-queries `workspace get` instead of trusting the label
# embedded in $HERDR_PLUGIN_EVENT_JSON: that embedded value can still be the
# creation-time cwd if the shell hasn't reported its real cwd yet, which
# would just re-freeze the WRONG name a beat earlier than upstream does.
set -eu

workspace_id=$(printf '%s' "$HERDR_PLUGIN_EVENT_JSON" | jq -r '.data.workspace.workspace_id // empty')
[ -n "$workspace_id" ] || exit 0

sleep 0.5

label=$("$HERDR_BIN_PATH" workspace get "$workspace_id" | jq -r '.result.workspace.label // empty')
[ -n "$label" ] || exit 0

"$HERDR_BIN_PATH" workspace rename "$workspace_id" "$label" >/dev/null
