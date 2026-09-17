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

# Block npm commands → suggest pnpm or bun
if echo "$STRIPPED" | grep -qE '(^|[;&|(]|[[:space:]])([A-Za-z0-9_./-]*/)?npm\s+'; then
  log_blocked "npm → pnpm/bun" "$COMMAND"
  deny "Use 'pnpm' or 'bun' instead of npm"
fi

# Block yarn commands → suggest pnpm or bun
if echo "$STRIPPED" | grep -qE '(^|[;&|(]|[[:space:]])([A-Za-z0-9_./-]*/)?yarn\s+'; then
  log_blocked "yarn → pnpm/bun" "$COMMAND"
  deny "Use 'pnpm' or 'bun' instead of yarn"
fi

# Block bare yarn (no args = yarn install)
if echo "$STRIPPED" | grep -qE '(^|[;&|(]|[[:space:]])([A-Za-z0-9_./-]*/)?yarn\s*$'; then
  log_blocked "yarn → pnpm install/bun install" "$COMMAND"
  deny "Use 'pnpm install' or 'bun install' instead of yarn"
fi

# Block npx → suggest pnpm dlx or bunx
if echo "$STRIPPED" | grep -qE '(^|[;&|(]|[[:space:]])([A-Za-z0-9_./-]*/)?npx\s+'; then
  log_blocked "npx → pnpm dlx/bunx" "$COMMAND"
  deny "Use 'pnpm dlx' or 'bunx' instead of npx"
fi

# Block pnpm link --global / -g (shims land at root, not bin/)
if echo "$STRIPPED" | grep -qE '(^|[;&|(]|[[:space:]])([A-Za-z0-9_./-]*/)?pnpm\s+(link|ln)\s+.*(-g|--global)'; then
  log_blocked "pnpm link --global → pnpm install -g" "$COMMAND"
  deny "Use 'pnpm install -g .' instead of 'pnpm link --global' (v11 shim layout bug)"
fi

exit 0
