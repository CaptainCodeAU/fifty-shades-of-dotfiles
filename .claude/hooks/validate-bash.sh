#!/bin/bash
# Block destructive Bash commands
# Runs on PreToolUse for Bash

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Block rm -rf with root or broad paths
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?(/|~|\$HOME)\s*$'; then
  echo "BLOCKED: Destructive rm command targeting root or home directory"
  exit 2
fi

# Block force push to main/master
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force.*\s+(main|master)'; then
  echo "BLOCKED: Force push to main/master is not allowed"
  exit 2
fi
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*\s+(main|master)\s+.*--force'; then
  echo "BLOCKED: Force push to main/master is not allowed"
  exit 2
fi

# Block git reset --hard without explicit ref
if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard\s*$'; then
  echo "BLOCKED: git reset --hard without a ref — specify a commit"
  exit 2
fi

# Block git clean -fd on entire repo
if echo "$COMMAND" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f[a-zA-Z]*d'; then
  echo "BLOCKED: git clean -fd would remove untracked files and directories"
  exit 2
fi

exit 0
