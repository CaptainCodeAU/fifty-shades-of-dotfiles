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
    echo "BLOCKED: Cannot modify $FILE_PATH — secrets file is protected"
    log_blocked "Secrets file" "$FILE_PATH"
    exit 2
    ;;
  .env.*)
    # Allow .env.example
    if [[ "$FILE_PATH" != ".env.example" ]]; then
      echo "BLOCKED: Cannot modify $FILE_PATH — secrets file is protected"
      log_blocked "Secrets file" "$FILE_PATH"
      exit 2
    fi
    ;;
  package-lock.json|yarn.lock|pnpm-lock.yaml)
    echo "BLOCKED: Cannot modify $FILE_PATH — lockfile managed by package manager"
    log_blocked "Lockfile" "$FILE_PATH"
    exit 2
    ;;
  .git/*)
    echo "BLOCKED: Cannot modify $FILE_PATH — .git directory is read-only"
    log_blocked ".git directory" "$FILE_PATH"
    exit 2
    ;;
esac

exit 0
