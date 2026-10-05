#!/bin/bash
# enforce-no-worktree-discard.sh -- DENY Claude Code's ExitWorktree when it would throw away
# unsaved work: action "remove" with discard_changes true. Deny only. Runs on PreToolUse for
# ExitWorktree. Registered for BOTH targets (user and project) in settings/claude/hooks.json,
# because it belongs to the Deletion rules, like enforce-no-permanent-delete.sh.
#
# WHY IT EXISTS (W-20261005-A42, Gavin's yes 5 Oct, session f930d2c7). The delete guard
# watches only Bash, and ExitWorktree is not Bash. Measured 5 Oct on a demo worktree:
# ExitWorktree "remove" deleted the folder AND its branch outright, nothing in ~/.Trash. With
# an uncommitted file it refused on its own ("Removing will discard this work permanently"),
# but discard_changes: true overrides that, and nothing stopped a session setting it.
# A clean remove loses nothing (every file is in git), so only the discard is denied.
#
# THE SAFE ROUTE the denial names (measured the same day, git worktree remove being denied by
# enforce-no-permanent-delete.sh): ExitWorktree action "keep", then rm -r <the worktree>
# (Trash-routed; the uncommitted file came back intact from ~/.Trash), then git worktree prune.
#
# An unreadable payload (jq missing, invalid JSON) is DENIED when its raw text holds
# "discard_changes": true, and passes otherwise -- the same rule as the other guards
# (D-20260925-A03). `--selftest` proves every arm; HOOK_UNDER_TEST=<path> runs them on a copy.

deny(){
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "BLOCKED (worktree-discard): ExitWorktree remove with discard_changes deletes unsaved work outside the Trash (W-20261005-A42). SAFE ROUTE: ExitWorktree action keep, then rm -r <the worktree> (Trash-routed), then git worktree prune. A permanent delete is Gavin's call: stop and ask.$1"
}

judge(){
  local raw v
  raw="$(cat)"
  [ -n "$raw" ] || exit 0
  if v="$(printf '%s' "$raw" | jq -r 'select(.tool_name == "ExitWorktree") | "\(.tool_input.action // "") \(.tool_input.discard_changes // false)"' 2>/dev/null)"; then
    [ "$v" = "remove true" ] && deny ""
    exit 0
  fi
  # unreadable: deny only when the raw text holds the trigger
  [[ $raw =~ \"discard_changes\"[[:space:]]*:[[:space:]]*true ]] && deny " (The payload could not be read, and it mentions discard_changes true.)"
  exit 0
}

if [ "${1:-}" = "--selftest" ]; then
  H="${HOOK_UNDER_TEST:-$0}"; pass=0; fail=0
  arm(){ # arm <want: deny|allow> <name> <payload>
    local out got
    out="$(printf '%s' "$3" | "$H" 2>/dev/null)"; rc=$?
    case "$out" in *'"permissionDecision":"deny"'*) got=deny ;; '') got=allow ;; *) got="other: $out" ;; esac
    [ "$rc" -eq 0 ] || got="$got (rc $rc)"
    if [ "$got" = "$1" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$2"
    else fail=$((fail+1)); printf '  FAIL %s\n       want: %s\n       got : %s\n' "$2" "$1" "$got"; fi
  }
  E='"tool_name":"ExitWorktree"'
  arm deny  "remove with discard_changes true"                 "{$E,\"tool_input\":{\"action\":\"remove\",\"discard_changes\":true}}"
  arm deny  "the same, discard_changes first"                   "{$E,\"tool_input\":{\"discard_changes\":true,\"action\":\"remove\"}}"
  arm allow "control: remove with no discard (the tool refuses unsaved work itself)" "{$E,\"tool_input\":{\"action\":\"remove\"}}"
  arm allow "control: remove with discard_changes false"        "{$E,\"tool_input\":{\"action\":\"remove\",\"discard_changes\":false}}"
  arm allow "control: keep"                                     "{$E,\"tool_input\":{\"action\":\"keep\"}}"
  arm allow "control: keep with discard_changes true (keep deletes nothing)" "{$E,\"tool_input\":{\"action\":\"keep\",\"discard_changes\":true}}"
  arm allow "control: another tool with the same input"         '{"tool_name":"Bash","tool_input":{"action":"remove","discard_changes":true}}'
  arm deny  "unreadable payload holding discard_changes true"   "{$E,\"tool_input\":{\"action\":\"remove\",\"discard_changes\": true"
  arm allow "control: unreadable payload without it"            "{$E,\"tool_input\":{\"action\":\"remove\""
  arm allow "control: empty stdin"                              ""
  out="$(printf '%s' "{$E,\"tool_input\":{\"action\":\"remove\",\"discard_changes\":true}}" | "$H" 2>/dev/null)"
  case "$out" in *"rm -r <the worktree>"*"git worktree prune"*) pass=$((pass+1)); echo "  ok   the denial names the safe route" ;;
    *) fail=$((fail+1)); echo "  FAIL the denial names the safe route"; printf '       got : %s\n' "$out" ;; esac
  printf '%s passed, %s failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]; exit
fi

judge
