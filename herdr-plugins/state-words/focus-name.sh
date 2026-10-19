#!/bin/sh
# Puts each agent row's project name in gold while its pane has focus, and in
# white when it does not (Gavin, 19 Oct 2026, dotfiles-main Q88: 1).
#
# herdr colours a token by its NAME and cannot style a row by whether it is
# selected, so the name comes from two tokens this script sets, instead of
# herdr's own workspace token: $name_on on the focused agent pane (gold in
# config.toml), $name_off on every other agent pane (white). Exactly one pane in
# herdr is focused at a time (pane list, measured 19 Oct).
#
# It runs on pane.focused, and on the two agent events, so a new agent gets its
# name at its first status change. Each run walks every agent pane and reports
# only the panes whose tokens are not already right, so a status change on one
# agent costs two list calls and no reports.
#
# Known limits: an agent on another machine is not in this server's pane list,
# so its row shows no project name; a server restart wipes the tokens until the
# next event; a renamed workspace catches up at the next event.
#
# Payload: HERDR_PLUGIN_EVENT_JSON; this script does not need its fields.
set -eu

SOURCE="dotfiles-state-words-name"
H="$HERDR_BIN_PATH"
TAB=$(printf '\t')

labels=$("$H" workspace list | jq -c '[.result.workspaces[] | {(.workspace_id): (.label // .workspace_id)}] | add // {}')

"$H" pane list | jq -r --argjson L "$labels" '
    .result.panes[] | select(.agent != null)
    | ($L[.workspace_id] // .workspace_id) as $n
    | (if .focused then {on: $n, off: null} else {on: null, off: $n} end) as $w
    | select((.tokens.name_on // null) != $w.on or (.tokens.name_off // null) != $w.off)
    | [.pane_id, .agent, (if .focused then "on" else "off" end), $n] | @tsv' |
# No field is ever empty: read merges runs of tabs, so an empty field would shift the rest.
while IFS="$TAB" read -r pane agent mode name; do
    if [ "$mode" = on ]; then
        set -- --token "name_on=$name" --clear-token name_off
    else
        set -- --token "name_off=$name" --clear-token name_on
    fi
    # --agent ties the token to this agent, so herdr drops it when the agent exits.
    "$H" pane report-metadata "$pane" --source "$SOURCE" --agent "$agent" "$@" >/dev/null || true
done
