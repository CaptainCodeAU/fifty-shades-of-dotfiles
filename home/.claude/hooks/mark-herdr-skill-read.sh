#!/bin/bash
# Mark the herdr skill as read for this session, the moment it is actually
# invoked -- so enforce-herdr-skill.sh's block lifts on real compliance,
# not merely on having fired once. Runs on PostToolUse for Skill. Never
# blocks; only ever writes a marker file or does nothing.

INPUT=$(cat)
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Under `pj` the skill is loaded as a plugin (--plugin-dir ~/.claude/skills/herdr),
# so the Skill tool's parameter is "herdr:herdr", not "herdr". Measured 2026-09-20 in
# a fresh pj pane: with only the bare name matched, the gate closed and never opened.
# Exactly these two spellings, no wildcard (Gavin's ruling, 2026-09-20).
if { [ "$SKILL" = "herdr" ] || [ "$SKILL" = "herdr:herdr" ]; } && [ -n "$SESSION_ID" ]; then
  touch "/tmp/.claude-herdr-skill-read-${SESSION_ID}"
fi

exit 0
