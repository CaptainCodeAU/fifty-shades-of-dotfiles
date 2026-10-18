#!/bin/sh
# Sets Gavin's state words on the agent pane an event names (Gavin, 18 Oct
# 2026, dotfiles-main Q60 and Q61), and the session name with a bar in front
# of it, so lines 2 and 3 of the sidebar row form a bracket hanging under the
# project name (Q64: 1):
#
#    ○ engage · 2
#      │ engage-main          <- $session token, this script
#      ╰ your turn            <- state_text, this script's state labels
#
# The sidebar layout is in home/.config/herdr/config.toml, [ui.sidebar.agents].
# herdr cannot draw a border or put fixed text in a row, and it puts " · "
# between any two tokens except after the state icon (src/ui/sidebar/tokens.rs,
# separator), so the box characters have to live inside the token values.
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
# Another source owns a pane's words when it has labelled idle with a word
# that is not one of ours. engage's worker panes will (engage #3313, source
# "engage": a worker waits on e-conductor, not on Gavin). So the labels are
# reported only when the pane has no idle label, or an older wording of our
# own (which moves a pane labelled before the bracket onto the new words).
# The $session token comes from a SEPARATE source and is reported on every
# event, so a renamed session catches up at its next status change without
# the label report ever overriding engage's word.
#
# Known limits: a server restart wipes every label and token; this script
# sets its own again on the next status change, but a source that reported
# only at start (engage-worker) does not. A /rename shows on line 2 only at
# the pane's next status change: plugins cannot hook pane.updated (#4912).
#
# Payload shape: {"event": "...", "data": {...}}; the fields are under
# "data" (see ../window-title-fix/update-title.sh).
set -eu

LABEL_SOURCE="dotfiles-state-words"
TOKEN_SOURCE="dotfiles-state-words-box"
WORKING_WORD="╰ thinking"
DONE_WORD="╰ your turn"
IDLE_WORD="╰ your turn"
BLOCKED_WORD="╰ needs you"
# Idle words this script has used before; a pane holding one is still ours.
OUR_OLD_IDLE_WORDS="your turn"
SESSION_BAR="│ "

event_json=${HERDR_PLUGIN_EVENT_JSON:-}
[ -n "$event_json" ] || exit 0

pane_id=$(printf '%s' "$event_json" | jq -r '.data.pane_id // empty')
agent=$(printf '%s' "$event_json" | jq -r '.data.agent // empty')
# No agent: a shell pane, or an agent that has just left. Nothing to label.
[ -n "$pane_id" ] && [ -n "$agent" ] || exit 0

pane_json=$("$HERDR_BIN_PATH" pane get "$pane_id")
idle_now=$(printf '%s' "$pane_json" | jq -r '.result.pane.state_labels.idle // empty')
title=$(printf '%s' "$pane_json" | jq -r '.result.pane.terminal_title_stripped // empty')

ours=no
if [ -z "$idle_now" ] || [ "$idle_now" = "$IDLE_WORD" ]; then
    ours=yes
elif [ "$idle_now" = "$OUR_OLD_IDLE_WORDS" ]; then
    ours=yes
fi

# --agent ties labels and tokens to this agent: herdr drops them when it
# exits, so a shell left behind in the pane carries none.
if [ "$ours" = yes ] && [ "$idle_now" != "$IDLE_WORD" ]; then
    "$HERDR_BIN_PATH" pane report-metadata "$pane_id" \
        --source "$LABEL_SOURCE" \
        --agent "$agent" \
        --state-label "working=$WORKING_WORD" \
        --state-label "done=$DONE_WORD" \
        --state-label "idle=$IDLE_WORD" \
        --state-label "blocked=$BLOCKED_WORD" \
        >/dev/null
    echo "labelled $pane_id ($agent)"
fi

if [ -n "$title" ]; then
    "$HERDR_BIN_PATH" pane report-metadata "$pane_id" \
        --source "$TOKEN_SOURCE" \
        --agent "$agent" \
        --token "session=$SESSION_BAR$title" \
        >/dev/null
fi
