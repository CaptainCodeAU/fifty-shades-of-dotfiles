#!/bin/bash
# Generic pre-commit quality gate
# Detects project type and runs appropriate lint/build checks
# Runs on PreToolUse for Bash — reads stdin JSON to detect git commit commands

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only run for git commit commands
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit\b|&&\s*git\s+commit\b|\|\|\s*git\s+commit\b'; then
  exit 0
fi

if [[ -f "package.json" ]]; then
  # Node.js project (takes priority when both markers exist)
  pnpm run lint && pnpm run build
elif [[ -f "pyproject.toml" ]]; then
  # Python project — lint + format check (fast gate, no tests)
  uv run ruff check . && uv run ruff format --check .
else
  # Unknown project type — no-op for language-specific checks
  true
fi

# Markdown lint (runs for all project types)
MD_FILES=$(git diff --cached --name-only --diff-filter=ACM -- '*.md')
if [[ -n "$MD_FILES" ]]; then
  echo "$MD_FILES" | xargs pnpm dlx markdownlint-cli
fi
