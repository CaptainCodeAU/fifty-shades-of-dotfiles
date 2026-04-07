#!/bin/bash
# Block npm/yarn/npx — enforce pnpm or bun for all Node.js commands
# Runs on PreToolUse for Bash

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOOKS_DIR/security.log"

log_blocked() {
  local reason="$1"
  local cmd="$2"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-pnpm \"$reason\" \"$cmd\"" >> "$LOG_FILE"
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

# Strip subshells and quoted strings to avoid false positives
STRIPPED=$(echo "$COMMAND" | sed -E 's/\$\([^)]*\)//g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

# Block npm commands → suggest pnpm or bun
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)npm\s+'; then
  log_blocked "npm → pnpm/bun" "$COMMAND"
  deny "Use 'pnpm' or 'bun' instead of npm"
fi

# Block yarn commands → suggest pnpm or bun
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)yarn\s+'; then
  log_blocked "yarn → pnpm/bun" "$COMMAND"
  deny "Use 'pnpm' or 'bun' instead of yarn"
fi

# Block bare yarn (no args = yarn install)
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)yarn\s*$'; then
  log_blocked "yarn → pnpm install/bun install" "$COMMAND"
  deny "Use 'pnpm install' or 'bun install' instead of yarn"
fi

# Block npx → suggest pnpm dlx or bunx
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)npx\s+'; then
  log_blocked "npx → pnpm dlx/bunx" "$COMMAND"
  deny "Use 'pnpm dlx' or 'bunx' instead of npx"
fi

exit 0
