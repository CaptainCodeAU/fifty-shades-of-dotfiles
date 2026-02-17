#!/bin/bash
# Generic pre-commit quality gate
# Detects project type and runs appropriate lint/build checks
# Runs on PreToolUse for Bash(git commit:*)

if [[ -f "package.json" ]]; then
  # Node.js project (takes priority when both markers exist)
  pnpm run lint && pnpm run build
elif [[ -f "pyproject.toml" ]]; then
  # Python project — lint + format check (fast gate, no tests)
  uv run ruff check . && uv run ruff format --check .
else
  # Unknown project type — no-op
  exit 0
fi
