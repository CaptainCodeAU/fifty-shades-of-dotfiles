#!/bin/bash
# Block `gh auth login|setup-git|refresh` in the Claude Bash tool.
# These re-add HTTPS credential helpers to ~/.gitconfig and undermine the
# SSH-only GitHub auth model. Mirrors the interactive gh() wrapper in .zshrc,
# which does NOT apply to the non-interactive Bash tool.
# Runs on PreToolUse for Bash.

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOOKS_DIR/security.log"

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Strip subshells and quoted strings to avoid false positives.
STRIPPED=$(echo "$COMMAND" | sed -E 's/\$\([^)]*\)//g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

# Block gh auth login / setup-git / refresh (re-add HTTPS credential helpers).
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)gh\s+auth\s+(login|setup-git|refresh)(\s|$)'; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-gh-ssh-only \"$COMMAND\"" >> "$LOG_FILE"
  deny "Blocked: 'gh auth login/setup-git/refresh' re-add HTTPS credential helpers and break SSH-only GitHub auth. For API reads, use the read-only \$GH_TOKEN already set in Claude sessions (e.g. 'gh run list', 'gh pr list', 'gh api ...')."
fi

exit 0
