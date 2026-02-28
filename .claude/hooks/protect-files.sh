#!/bin/bash
# Block edits to protected files
# Runs on PreToolUse for Edit|Write

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOOKS_DIR/security.log"

log_blocked() {
  local reason="$1"
  local file="$2"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED protect-files \"$reason\" \"$file\"" >> "$LOG_FILE"
}

deny() {
  local reason="$1"
  jq -n --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Normalize to relative path from project root
FILE_PATH="${FILE_PATH#"$CLAUDE_PROJECT_DIR"/}"

# Protected patterns
case "$FILE_PATH" in
  .env|.env.keys|.env.local)
    log_blocked "Secrets file" "$FILE_PATH"
    deny "Cannot modify $FILE_PATH — secrets file is protected"
    ;;
  .env.*)
    # Allow .env.example
    if [[ "$FILE_PATH" != ".env.example" ]]; then
      log_blocked "Secrets file" "$FILE_PATH"
      deny "Cannot modify $FILE_PATH — secrets file is protected"
    fi
    ;;
  package-lock.json|yarn.lock|pnpm-lock.yaml)
    log_blocked "Lockfile" "$FILE_PATH"
    deny "Cannot modify $FILE_PATH — lockfile managed by package manager"
    ;;
  .git/*)
    log_blocked ".git directory" "$FILE_PATH"
    deny "Cannot modify $FILE_PATH — .git directory is read-only"
    ;;
esac

exit 0
