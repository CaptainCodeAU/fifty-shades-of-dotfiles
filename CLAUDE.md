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

## Shell Environment

- **zoxide overrides `cd`**: The shell has `eval "$(zoxide init zsh --cmd cd)"` which redefines `cd` as `__zoxide_z`. This can break in Claude Code's sandbox if the zoxide helper functions aren't fully loaded. **Do not use `cd` in Bash commands.** Instead:
  - Use `git -C /path/to/repo <command>` for git operations
  - Use absolute paths for all commands (e.g., `swift test` run from the correct working dir via the tool's cwd, or prefix with the full path)
  - If you must change directory, use `builtin cd` — but note this only works for actual shell builtins, not for external commands like `git`
- **`builtin` keyword**: Only use `builtin` with actual zsh builtins (`cd`, `echo`, `printf`, etc.). Never prefix external commands like `git`, `swift`, or `DEVELOPER_DIR=... swift` with `builtin` — zsh will reject them with "no such builtin".

## Git

- **Default branch is `master`**, not `main`. There is no `main` branch in this repo.
