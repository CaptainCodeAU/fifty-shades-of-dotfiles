#!/bin/sh
# Builds the outer terminal title from a fresh `herdr api snapshot` instead
# of herdr's workspace label, which lags after a plain `cd` -- see herdr#3200
# (still open on 0.8.2). This script covers the no-agent case itself, via the
# focused-pane-cwd fallback below -- there is no companion rename script.
# Earlier this ran alongside fix-title.sh, which "fixed" herdr#3200 by calling
# `herdr workspace rename` on every new workspace. That rename permanently
# pins the workspace's sidebar label (writes session.json's custom_name,
# which then always wins over the real, live-tracked cwd) -- it does not
# self-clear, and there is no supported way to un-pin a workspace once
# renamed (upstream herdr#3252, closed not_planned). That script pinned a
# real workspace to the wrong name on 2026-08-28 and was deleted for it.
#
# Layout: "🔴 blocked...names 🔵 done...names 🟢 idle...names ⚪ unknown...names 🟡 working...names"
# No leading project name: the previous "<focused project>" prefix was
# dropped by request, so the title now starts directly with whichever
# group's icon comes first. A single space between groups, and one space
# after each icon; names within one group joined by " | ".
#
# Whichever pane herdr currently has focused gets its name wrapped in
# [brackets], in whichever status group it happens to be sitting in. Matched
# by the pane's own `.focused` field, not by comparing name text -- two
# panes can share a display name (same folder basename, different parent
# path), and matching by pane identity is what keeps that from bracketing
# the wrong one, or both.
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
  # that status, joined by NAME_JOIN, across the whole fleet. The focused
  # pane's own name comes back wrapped in [brackets] -- see the [brackets]
  # note in the header comment above.
  printf '%s' "$snapshot" | jq -r --arg s "$1" --arg j "$NAME_JOIN" '
    [.result.snapshot.panes[]
     | select(.agent == "claude") | select(.agent_status == $s)
     | {name: ((.foreground_cwd // .cwd // "") | split("/") | last), focused: .focused}
     | select(.name | length > 0)
     | if .focused then "[" + .name + "]" else .name end]
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

# No claude panes in any status (e.g. a plain shell workspace, or every agent
# just exited) -- fall back to the focused pane's real project name instead
# of clearing the title. Clearing would hand rendering back to herdr's own
# window_title = "{hostname}: {workspace}" template, which is exactly
# herdr#3200: it shows the directory the workspace was CREATED from, not its
# live cwd, until a human renames it. This keeps the title correct without
# ever renaming (and therefore permanently pinning) the workspace.
if [ -z "$groups" ]; then
  fallback_name=$(printf '%s' "$snapshot" | jq -r '
    [.result.snapshot.panes[] | select(.focused == true)
     | ((.foreground_cwd // .cwd // "") | split("/") | last)
     | select(length > 0)] | first // ""')
  [ -n "$fallback_name" ] && groups="[${fallback_name}]"
fi

title="$groups"
if [ -n "$title" ] && [ -f "$HERDR_PLUGIN_STATE_DIR/show_host" ]; then
  title="$(hostname) $title"
fi

# Last resort: no panes at all (e.g. an empty workspace). Nothing to build a
# title from, so clear it rather than show stale text.
if [ -z "$title" ]; then
  "$HERDR_BIN_PATH" terminal title clear >/dev/null
  exit 0
fi

"$HERDR_BIN_PATH" terminal title set "$title" >/dev/null
