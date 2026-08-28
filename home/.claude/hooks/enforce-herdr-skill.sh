#!/bin/bash
# Block a `herdr` Bash command until the herdr skill has been read this session.
# Runs on PreToolUse for Bash. Sibling of enforce-gh-ssh-only / enforce-census.
#
# WHY IT EXISTS
#   The herdr skill (~/.agents/skills/herdr/SKILL.md, symlinked from
#   ~/.claude/skills/herdr) already documents hard-won gotchas -- a reserved
#   zsh variable name that silently breaks scripts, a wrong JSON field path
#   that wastes a debugging session, sandbox requirements, busy-pane races.
#   The skill's own description already matches ad-hoc herdr scripting, but
#   nothing forces it to actually be read before the first `herdr` call --
#   confirmed 2026-08-28: an entire session ran many herdr commands and hit
#   two of those exact documented gotchas before ever reading the skill.
#
# HOW THE "ONCE PER SESSION" PART IS VERIFIED, NOT JUST CLAIMED
#   This hook denies every `herdr` Bash command until a marker file exists
#   for this session_id. The marker is written by the SIBLING hook
#   mark-herdr-skill-read.sh, which fires on PostToolUse for the Skill tool
#   and only touches the marker when the skill actually invoked was "herdr".
#   So the block does not lift just because it fired once -- it lifts only
#   after the herdr skill was genuinely invoked.

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

if [ -z "$COMMAND" ] || [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Strip subshells and quoted strings to avoid false positives (e.g. a string
# that merely mentions "herdr").
STRIPPED=$(echo "$COMMAND" | sed -E 's/\$\([^)]*\)//g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

# Only fire when `herdr` is the actual command being invoked, at the start
# or right after a chain operator -- not a substring of some other word.
echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)herdr(\s|$)' || exit 0

MARKER="/tmp/.claude-herdr-skill-read-${SESSION_ID}"
[ -f "$MARKER" ] && exit 0

deny "Read the herdr skill first this session (Skill tool, skill name \"herdr\") -- it documents hard-won gotchas (a reserved zsh variable name that silently breaks scripts, a wrong agent-status JSON path, sandbox requirements, busy-pane races) that will otherwise cost real time. Then retry this herdr command; it will go through once the skill has been read."
