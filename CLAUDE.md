# Environment Conventions

This environment uses `uv` for Python and `pnpm` for Node.js. These tools manage isolated environments per project, so all commands should go through them to maintain isolation and avoid version conflicts.

## Python

- Always use `uv run` to execute Python scripts and commands (e.g., `uv run python script.py`).
- Use `uv add` to manage dependencies.
- Use `uv run pytest`, `uv run ruff`, etc. for dev tools.
- Let `uv` manage virtual environments — it handles `.venv` creation and activation automatically.

## Node.js

- Use `pnpm` for all package management (`pnpm install`, `pnpm add`, `pnpm run`).
- Use `pnpm dlx` instead of `npx` to run one-off packages.
