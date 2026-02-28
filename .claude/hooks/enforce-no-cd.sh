#!/bin/bash
# Block bare cd — enforce absolute paths or git -C
# Runs on PreToolUse for Bash

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOOKS_DIR/security.log"

log_blocked() {
  local reason="$1"
  local cmd="$2"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-no-cd \"$reason\" \"$cmd\"" >> "$LOG_FILE"
}

deny() {
  local reason="$1"
  jq -n --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Strip $(...) subshells, "..." strings, and '...' strings
# This avoids false positives on $(cd ...) patterns used in scripts
STRIPPED=$(echo "$COMMAND" | sed -E 's/\$\([^)]*\)//g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

# Block bare cd but allow "builtin cd"
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)cd\s+'; then
  # Allow "builtin cd"
  if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)builtin\s+cd\s+'; then
    : # allowed
  else
    log_blocked "bare cd → absolute paths" "$COMMAND"
    deny "Don't use 'cd' — use absolute paths, 'git -C <path>', or 'builtin cd' instead"
  fi
fi

exit 0
