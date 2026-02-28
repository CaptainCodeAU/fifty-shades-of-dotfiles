#!/bin/bash
# Block builtin with non-builtins — only allow with actual zsh builtins
# Runs on PreToolUse for Bash

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOOKS_DIR/security.log"

log_blocked() {
  local reason="$1"
  local cmd="$2"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-builtin \"$reason\" \"$cmd\"" >> "$LOG_FILE"
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
STRIPPED=$(echo "$COMMAND" | sed -E 's/\$\([^)]*\)//g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

# Check for "builtin <word>" usage
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)builtin\s+'; then
  # Extract the word after "builtin"
  BUILTIN_ARG=$(echo "$STRIPPED" | grep -oE '(^|[;&|]\s*)builtin\s+\S+' | head -1 | sed -E 's/.*builtin[[:space:]]+//')

  # Allowed zsh builtins
  case "$BUILTIN_ARG" in
    cd|echo|printf|print|pushd|popd|pwd|read|set|shift|test|trap|true|false|type|typeset|ulimit|umask|unset|wait|export|local|return|exit|source|eval|exec|hash|kill|let|unalias|unfunction|declare|readonly|dirs|bg|fg|jobs|disown|suspend|times|builtin|command|whence|where|which|getopts|break|continue|:|.)
      exit 0
      ;;
    *)
      log_blocked "builtin with non-builtin: $BUILTIN_ARG" "$COMMAND"
      deny "'builtin $BUILTIN_ARG' is invalid — builtin only works with zsh builtins (cd, echo, printf, etc.)"
      ;;
  esac
fi

exit 0
