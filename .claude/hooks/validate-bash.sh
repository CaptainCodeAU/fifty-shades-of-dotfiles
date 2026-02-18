#!/bin/bash
# Block destructive Bash commands
# Runs on PreToolUse for Bash

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOOKS_DIR/security.log"

log_blocked() {
  local reason="$1"
  local cmd="$2"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED validate-bash \"$reason\" \"$cmd\"" >> "$LOG_FILE"
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Block rm -rf with root or broad paths
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?(/|~|\$HOME)\s*$'; then
  echo "BLOCKED: Destructive rm command targeting root or home directory"
  log_blocked "Destructive rm targeting root/home" "$COMMAND"
  exit 2
fi

# Block force push to main/master (--force, -f, --force-with-lease)
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*(--force|--force-with-lease).*\s+(main|master)'; then
  echo "BLOCKED: Force push to main/master is not allowed"
  log_blocked "Force push to main/master" "$COMMAND"
  exit 2
fi
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*\s+(main|master)\s+.*(--force|--force-with-lease)'; then
  echo "BLOCKED: Force push to main/master is not allowed"
  log_blocked "Force push to main/master" "$COMMAND"
  exit 2
fi
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*-[a-zA-Z]*f[a-zA-Z]*\s+.*(main|master)'; then
  echo "BLOCKED: Force push to main/master is not allowed"
  log_blocked "Force push to main/master (short flag)" "$COMMAND"
  exit 2
fi

# Block git reset --hard without explicit ref
if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard\s*$'; then
  echo "BLOCKED: git reset --hard without a ref — specify a commit"
  log_blocked "git reset --hard without ref" "$COMMAND"
  exit 2
fi

# Block git clean -fd on entire repo (combined or separated flags)
if echo "$COMMAND" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f[a-zA-Z]*d'; then
  echo "BLOCKED: git clean -fd would remove untracked files and directories"
  log_blocked "git clean -fd" "$COMMAND"
  exit 2
fi
if echo "$COMMAND" | grep -qE 'git\s+clean\s+.*-f.*-d|git\s+clean\s+.*-d.*-f'; then
  echo "BLOCKED: git clean -f -d would remove untracked files and directories"
  log_blocked "git clean -f -d (separated flags)" "$COMMAND"
  exit 2
fi

exit 0
