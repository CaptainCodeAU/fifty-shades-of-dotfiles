#!/bin/bash
# Block bare Python tooling — enforce uv for all Python commands
# Runs on PreToolUse for Bash

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOOKS_DIR/security.log"

log_blocked() {
  local reason="$1"
  local cmd="$2"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-uv \"$reason\" \"$cmd\"" >> "$LOG_FILE"
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Strip subshells and quoted strings to avoid false positives
# This removes $(...) blocks, "..." strings, and '...' strings
STRIPPED=$(echo "$COMMAND" | sed -E 's/\$\([^)]*\)//g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

# Block pip install / pip3 install → suggest uv add
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)pip3?\s+install\b'; then
  echo "BLOCKED: Use 'uv add <package>' instead of pip install"
  log_blocked "pip install → uv add" "$COMMAND"
  exit 2
fi

# Block pip uninstall / pip3 uninstall → suggest uv remove
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)pip3?\s+uninstall\b'; then
  echo "BLOCKED: Use 'uv remove <package>' instead of pip uninstall"
  log_blocked "pip uninstall → uv remove" "$COMMAND"
  exit 2
fi

# Block other bare pip commands (pip list, pip show, pip freeze, etc.)
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)pip3?\s+'; then
  # Allow uv pip (uv's own pip interface)
  if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)uv\s+pip\s+'; then
    : # allowed
  else
    echo "BLOCKED: Use 'uv run pip $*' or 'uv pip $*' instead of bare pip"
    log_blocked "bare pip → uv" "$COMMAND"
    exit 2
  fi
fi

# Block bare python/python3 → suggest uv run python
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)python3?\s+'; then
  # Allow if preceded by "uv run"
  if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)uv\s+run\s+python3?\s+'; then
    : # allowed
  else
    echo "BLOCKED: Use 'uv run python' instead of bare python"
    log_blocked "bare python → uv run python" "$COMMAND"
    exit 2
  fi
fi

# Block bare pytest → suggest uv run pytest
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)pytest\b'; then
  if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)uv\s+run\s+pytest\b'; then
    : # allowed
  else
    echo "BLOCKED: Use 'uv run pytest' instead of bare pytest"
    log_blocked "bare pytest → uv run pytest" "$COMMAND"
    exit 2
  fi
fi

# Block bare ruff → suggest uv run ruff
if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)ruff\b'; then
  if echo "$STRIPPED" | grep -qE '(^|[;&|]\s*)uv\s+run\s+ruff\b'; then
    : # allowed
  else
    echo "BLOCKED: Use 'uv run ruff' instead of bare ruff"
    log_blocked "bare ruff → uv run ruff" "$COMMAND"
    exit 2
  fi
fi

exit 0
