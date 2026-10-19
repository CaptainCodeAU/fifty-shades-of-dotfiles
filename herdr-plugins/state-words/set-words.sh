#!/bin/sh
# Sets Gavin's state words on the agent pane an event names (Gavin, 18 Oct
# 2026, dotfiles-main Q60 and Q61), and the session name. Since 19 Oct the row
# is two lines, and since 11:55 PM that day line 2 is the session name, then the
# word, with no shape before it:
#
#    ○ engage
#      engage-main · your turn   <- $session token and state_text, this script
#
# The $bar_<state> tokens below belonged to the three-line form, which config.toml
# keeps commented; this script still sets them so that form can come back.
#
# The sidebar layout is in home/.config/herdr/config.toml, [ui.sidebar.agents].
# herdr cannot draw a border or put fixed text in a row, and it puts " · "
# between any two tokens except after the state icon (src/ui/sidebar/tokens.rs,
# separator), so the box characters have to live inside the token values.
#
# The bar takes the state's colour, like the word under it (Gavin, Q65: 1). A
# token's colour is fixed per token NAME in config.toml, so there is one bar
# token per state ($bar_working, $bar_done, ...), and this script sets the one
# for the pane's current state and clears the rest on every event. The bar has
# to be its own token for its own colour, which is why herdr's " · " sits
# between it and the session name (Gavin accepted that, Q65: 1).
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
# "your turn" only when the agent's last reply asks him something (Gavin,
# Q66 (v2): 1). His reply style ends a reply with a line starting 👉 exactly
# when something waits on him, and with none when nothing does. herdr's idle
# only says the prompt is empty: Network_Plan read idle with its workers still
# running on 18 Oct. So for idle and done this reads the session's transcript
# (<claude home>/projects/*/<session id>.jsonl, the lookup herdr-type uses):
# a last reply ending in a 👉 line gives "your turn"; one without gives a grey
# "resting", with a grey bar. No transcript found gives "your turn", so an
# agent that may need him is never shown as resting.
#
# Another source owns a pane's words when it has labelled idle with a word
# that is not one of ours. engage's worker panes will (engage #3313, source
# "engage": a worker waits on e-conductor, not on Gavin). So the labels are
# reported only when the pane has no idle label or one of our own words, and
# only when the word we want differs from the one it shows.
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
# No shape before the words since 19 Oct, 11:55 PM (Gavin: "remove and get rid of that shape
# thingy"); the session name now comes first on line 2, so nothing hangs under the project.
WORKING_WORD="thinking"
# 20 Oct, 12:20 AM (Gavin): "your turn" became the 🫵 emoji; 12:25 AM, 👉 instead.
DONE_WORD="👉"
# Seen "your turn" (idle) ends in a zero-width space (U+200B), so config.toml can colour it on
# its own: herdr trims labels and drops control characters, and the icon and word share one
# state colour, so an invisible difference is the only way to give the seen word a softer
# colour than its icon (Gavin, 19 Oct). Until 11:55 PM 19 Oct a square corner did this job.
# herdr keeps U+200B: reported and read back with pane get, 19 Oct.
IDLE_WORD=$(printf '\360\237\221\211\342\200\213')
BLOCKED_WORD="needs you"
RESTING_WORD="resting"
# Every idle word this script uses or has used; a pane holding one is ours.
OUR_IDLE_WORDS="your turn|╰ your turn|└ your turn|╰ resting|$(printf 'your turn\342\200\213')|$(printf '\360\237\253\265\342\200\213')|$IDLE_WORD|resting"
BAR="│"
# resting is not a herdr state: it is idle or done with no 👉 in the last reply.
STATES="working done idle blocked unknown resting"

event_json=${HERDR_PLUGIN_EVENT_JSON:-}
[ -n "$event_json" ] || exit 0

pane_id=$(printf '%s' "$event_json" | jq -r '.data.pane_id // empty')
agent=$(printf '%s' "$event_json" | jq -r '.data.agent // empty')
# No agent: a shell pane, or an agent that has just left. Nothing to label.
[ -n "$pane_id" ] && [ -n "$agent" ] || exit 0

pane_json=$("$HERDR_BIN_PATH" pane get "$pane_id")
idle_now=$(printf '%s' "$pane_json" | jq -r '.result.pane.state_labels.idle // empty')
done_now=$(printf '%s' "$pane_json" | jq -r '.result.pane.state_labels.done // empty')
working_now=$(printf '%s' "$pane_json" | jq -r '.result.pane.state_labels.working // empty')
blocked_now=$(printf '%s' "$pane_json" | jq -r '.result.pane.state_labels.blocked // empty')
title=$(printf '%s' "$pane_json" | jq -r '.result.pane.terminal_title_stripped // empty')
status=$(printf '%s' "$pane_json" | jq -r '.result.pane.agent_status // "unknown"')
session_id=$(printf '%s' "$pane_json" \
    | jq -r 'select(.result.pane.agent_session.kind == "id") | .result.pane.agent_session.value // empty')

# asks: the last reply's last non-empty line starts with 👉. Prints yes, no,
# or unknown (no transcript, or no reply in its last 400 lines).
last_reply_asks() {
    transcript=""
    for f in "$HOME"/.claude*/projects/*/"$1".jsonl; do
        [ -f "$f" ] && { transcript=$f; break; }
    done
    [ -n "$transcript" ] || { echo unknown; return; }
    tail -n 400 "$transcript" | jq -Rrs '
        [split("\n")[] | fromjson? | select(.type == "assistant" and (.isSidechain | not))
         | .message.content[]? | select(.type == "text") | .text]
        | if length == 0 then "unknown"
          else (last | split("\n") | map(select(test("\\S"))) | last // ""
                | if startswith("👉") then "yes" else "no" end)
          end'
}

asks=unknown
case "$status" in
    idle|done) [ -z "$session_id" ] || asks=$(last_reply_asks "$session_id") ;;
esac
if [ "$asks" = no ]; then
    want_idle=$RESTING_WORD; want_done=$RESTING_WORD
else
    want_idle=$IDLE_WORD; want_done=$DONE_WORD
fi

ours=no
if [ -z "$idle_now" ]; then
    ours=yes
else
    case "|$OUR_IDLE_WORDS|" in *"|$idle_now|"*) ours=yes ;; esac
fi

# --agent ties labels and tokens to this agent: herdr drops them when it
# exits, so a shell left behind in the pane carries none.
if [ "$ours" = yes ] && [ "$idle_now" != "$want_idle" ]; then
    "$HERDR_BIN_PATH" pane report-metadata "$pane_id" \
        --source "$LABEL_SOURCE" \
        --agent "$agent" \
        --state-label "working=$WORKING_WORD" \
        --state-label "done=$want_done" \
        --state-label "idle=$want_idle" \
        --state-label "blocked=$BLOCKED_WORD" \
        >/dev/null
    echo "labelled $pane_id ($agent, $status, asks=$asks)"
elif [ "$ours" = no ] && { [ "$done_now" != "$want_done" ] || [ "$working_now" != "$WORKING_WORD" ] \
        || [ "$blocked_now" != "$BLOCKED_WORD" ]; }; then
    # Another source owns the idle word (engage's worker panes), so ours is left out of the
    # report, but the other three words are still ours and must not go stale: before 20 Oct,
    # 12:05 AM this branch did not exist, and two worker panes kept "╰ your turn" and
    # "╰ thinking" after the shapes were removed (Gavin's screenshot).
    "$HERDR_BIN_PATH" pane report-metadata "$pane_id" \
        --source "$LABEL_SOURCE" \
        --agent "$agent" \
        --state-label "working=$WORKING_WORD" \
        --state-label "done=$want_done" \
        --state-label "blocked=$BLOCKED_WORD" \
        >/dev/null
    echo "labelled $pane_id ($agent, $status, asks=$asks, idle left to its owner)"
fi

case " $STATES " in *" $status "*) ;; *) status=unknown ;; esac
bar_state=$status
[ "$asks" != no ] || bar_state=resting

# One report: the bar for this state set, every other state's bar cleared,
# and the session name.
set -- --token "bar_$bar_state=$BAR"
for other in $STATES; do
    [ "$other" = "$bar_state" ] || set -- "$@" --clear-token "bar_$other"
done
[ -z "$title" ] || set -- "$@" --token "session=$title"
"$HERDR_BIN_PATH" pane report-metadata "$pane_id" \
    --source "$TOKEN_SOURCE" \
    --agent "$agent" \
    "$@" \
    >/dev/null
