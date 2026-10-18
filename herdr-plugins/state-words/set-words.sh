#!/bin/sh
# Sets Gavin's state words on the agent pane an event names (Gavin, 18 Oct
# 2026, dotfiles-main Q60 and Q61). The sidebar's state_text token shows them
# (home/.config/herdr/config.toml, [ui.sidebar.agents]).
#
# Why idle gets a word: herdr turns "done" into "idle" the moment Gavin looks
# at the tab, and idle had no word, so "your turn" vanished before he could
# act on it. With idle labelled too, the word stays until he sends a prompt.
#
# How herdr combines labels, measured 2026-10-18 on 0.9.5 (and read in
# src/terminal/metadata.rs, effective_metadata_state_labels):
# - per state, the NEWEST label wins, whichever --source reported it;
# - each report REPLACES its own source's whole label set, so a report must
#   carry every label it wants, never just the one that changed.
#
# Another source owns a pane's words when it has labelled idle. engage's
# worker panes do (engage #3313, source "engage": a worker waits on
# e-conductor, not on Gavin). So this script acts only when the pane has no
# idle label at all, and leaves any pane that already has one alone. That
# also makes repeat events free: once set, nothing is reported again.
#
# Known limit: a server restart wipes every label. This script sets its own
# again on the next status change, but a source that reported only at start
# (engage-worker) does not, so a restored worker reads "your turn".
#
# Payload shape: {"event": "...", "data": {...}}; the fields are under
# "data" (see ../window-title-fix/update-title.sh).
set -eu

SOURCE="dotfiles-state-words"
WORKING_WORD="thinking"
DONE_WORD="your turn"
IDLE_WORD="your turn"
BLOCKED_WORD="needs you"

event_json=${HERDR_PLUGIN_EVENT_JSON:-}
[ -n "$event_json" ] || exit 0

pane_id=$(printf '%s' "$event_json" | jq -r '.data.pane_id // empty')
agent=$(printf '%s' "$event_json" | jq -r '.data.agent // empty')
# No agent: a shell pane, or an agent that has just left. Nothing to label.
[ -n "$pane_id" ] && [ -n "$agent" ] || exit 0

has_idle=$("$HERDR_BIN_PATH" pane get "$pane_id" \
    | jq -r '.result.pane.state_labels.idle // empty')
[ -z "$has_idle" ] || exit 0

# --agent ties the labels to this agent: herdr drops them when it exits, so
# a shell left behind in the pane carries none.
"$HERDR_BIN_PATH" pane report-metadata "$pane_id" \
    --source "$SOURCE" \
    --agent "$agent" \
    --state-label "working=$WORKING_WORD" \
    --state-label "done=$DONE_WORD" \
    --state-label "idle=$IDLE_WORD" \
    --state-label "blocked=$BLOCKED_WORD" \
    >/dev/null
echo "labelled $pane_id ($agent)"
