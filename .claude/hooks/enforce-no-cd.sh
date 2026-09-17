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
# Strip heredoc BODIES first, keeping the line that opens them (that line is a real
# command and must still be scanned). Without this, the command name written as PROSE
# inside a heredoc matches, and writing documentation about this guard gets blocked.
# Measured 2026-09-17: that exact false positive refused a commit message.
NOHEREDOC=$(printf '%s\n' "$COMMAND" | awk '
  BEGIN { in_h = 0; term = "" }
  {
    if (in_h) {
      stripped = $0
      sub(/^[ \t]+/, "", stripped)
      if ($0 == term || stripped == term) { in_h = 0 }
      next
    }
    if (match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
      t = substr($0, RSTART, RLENGTH)
      sub(/^<<-?[ \t]*/, "", t)
      gsub(/["\047]/, "", t)
      term = t
      in_h = 1
    }
    print
  }')

STRIPPED=$(echo "$NOHEREDOC" | sed -E 's/\$\([^)]*\)//g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

# Block bare cd but allow "builtin cd"
if echo "$STRIPPED" | grep -qE '(^|[;&|(]|[[:space:]])([A-Za-z0-9_./-]*/)?cd\s+'; then
  # Allow "builtin cd"
  if echo "$STRIPPED" | grep -qE '(^|[;&|(]|[[:space:]])([A-Za-z0-9_./-]*/)?builtin\s+cd\s+'; then
    : # allowed
  else
    log_blocked "bare cd → absolute paths" "$COMMAND"
    deny "Don't use 'cd' — use absolute paths, 'git -C <path>', or 'builtin cd' instead"
  fi
fi

exit 0
