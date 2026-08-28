#!/bin/sh
# Builds the outer terminal title from a fresh `herdr api snapshot` instead
# of herdr's workspace label, which lags after a plain `cd` -- see
# herdr#3200 and fix-title.sh, which only covers the no-agent case.
#
# Layout: "🔴 blocked...names 🔵 done...names 🟢 idle...names ⚪ unknown...names 🟡 working...names"
# No leading project name: the previous "<focused project>" prefix was
# dropped by request, so the title now starts directly with whichever
# group's icon comes first. A single space between groups, and one space
# after each icon; names within one group joined by " | ".
#
# Only panes where agent == "claude" are counted -- this fleet is
# Claude-only by design, and this filter makes that explicit rather than
# incidentally true because every other agent field happens to be null.
#
# done and idle are SEPARATE groups (🔵 and 🟢), not merged. They used to
# be merged because every pane observed live only ever went blocked ->
# working -> idle, never a literal "done" -- but "done" DID show up live on
# 2026-08-28 (chorustic), so that assumption was wrong and idle/done are
# both real, distinct states worth their own color.
#
# Runs on pane.agent_status_changed, pane.agent_detected, and pane.focused
# -- any of those, on ANY pane, can change what the group lists should say,
# not just the focused one, so every trigger does a full recompute from one
# fresh snapshot rather than reacting to just the one pane that changed.
#
# List-building goes through jq, not a shell word-split loop, because a
# project folder name can contain a space -- `for x in $names` would treat
# "My Project" as two entries.
#
# Herdr wraps plugin event payloads as {"event": "...", "data": {...}} --
# do not read fields off the top level, they are one level down under
# "data" (verified 2026-08-28 against a real fired event, not assumed from
# the socket API docs, which describe the raw subscription shape and do not
# match what plugins actually receive).
set -eu

NAME_JOIN=" | "
BLOCKED_ICON="🔴"
DONE_ICON="🔵"
IDLE_ICON="🟢"
UNKNOWN_ICON="⚪"
WORKING_ICON="🟡"

snapshot=$("$HERDR_BIN_PATH" api snapshot)

names_for_status() {
  # $1 = agent_status value; prints project names for every claude pane in
  # that status, joined by NAME_JOIN, across the whole fleet.
  printf '%s' "$snapshot" | jq -r --arg s "$1" --arg j "$NAME_JOIN" '
    [.result.snapshot.panes[]
     | select(.agent == "claude") | select(.agent_status == $s)
     | ((.foreground_cwd // .cwd // "") | split("/") | last)
     | select(length > 0)]
    | join($j)'
}

blocked_names=$(names_for_status "blocked")
done_names=$(names_for_status "done")
idle_names=$(names_for_status "idle")
unknown_names=$(names_for_status "unknown")
working_names=$(names_for_status "working")

groups=""
[ -n "$blocked_names" ] && groups="${groups:+$groups }${BLOCKED_ICON} ${blocked_names}"
[ -n "$done_names" ] && groups="${groups:+$groups }${DONE_ICON} ${done_names}"
[ -n "$idle_names" ] && groups="${groups:+$groups }${IDLE_ICON} ${idle_names}"
[ -n "$unknown_names" ] && groups="${groups:+$groups }${UNKNOWN_ICON} ${unknown_names}"
[ -n "$working_names" ] && groups="${groups:+$groups }${WORKING_ICON} ${working_names}"

title="$groups"
if [ -n "$title" ] && [ -f "$HERDR_PLUGIN_STATE_DIR/show_host" ]; then
  title="$(hostname) $title"
fi

if [ -z "$title" ]; then
  "$HERDR_BIN_PATH" terminal title clear >/dev/null
  exit 0
fi

"$HERDR_BIN_PATH" terminal title set "$title" >/dev/null
