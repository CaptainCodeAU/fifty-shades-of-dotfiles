# Standalone Shell Scripts (Canonical Guide)

This directory is the canonical source for standalone shell scripts that should be available system-wide as commands.

If you are a future AI agent or contributor in a fresh context window: treat this file as the source of truth for how scripts are added, exposed, verified, and maintained in this repository.

## Purpose and Scope

Use this subsystem for standalone command-style scripts that should be runnable directly from the shell (for example, `sysinfo`).

Use other files for other concerns:

- Keep core shell behavior and aliases in `home/.zshrc`
- Keep language/tool workflows in:
  - `home/.zsh_python_functions`
  - `home/.zsh_node_functions`
  - `home/.zsh_docker_functions`
  - `home/.zsh_cursor_functions`
  - `home/.zsh_tmux`

## Architecture

This setup follows the existing XDG-style layout already used in `~/.local`:

- Executable entrypoints: `~/.local/bin`
- Shared script sources: `~/.local/share/fifty-shades-of-dotfiles/scripts`
- Runtime state: `~/.local/state` (not used for script source files)

Repository mapping (via stow):

- Repo source script: `home/.local/share/fifty-shades-of-dotfiles/scripts/<name>.sh`
- Repo command entrypoint: `home/.local/bin/<name>`
- Runtime paths after stow:
  - `~/.local/share/fifty-shades-of-dotfiles/scripts/<name>.sh`
  - `~/.local/bin/<name>`

### Why wrappers in `~/.local/bin`?

Command entrypoints in `~/.local/bin` are thin wrapper scripts that execute their matching source script in `~/.local/share/...`.

This is intentional:

- Keeps command names stable and discoverable on PATH
- Keeps implementation scripts organized away from PATH clutter
- Avoids alias chains and avoids symlink-to-symlink complexity
- Allows source script refactors while preserving public command names

## Stow Deployment Model

This repository deploys with GNU Stow (`home/` to `~/`).

Operational consequence:

- If the repository path changes, existing stow symlinks can break (for all stowed files, not just scripts).
- Fix by restowing from the new repo location.

Restow commands:

```bash
./install.sh --stow-only
```

or:

```bash
stow -R -t "$HOME" home
```

## Conventions

Naming:

- Source script file: `<name>.sh`
- Public command wrapper: `<name>` (no extension)

Shebang:

- Prefer `#!/usr/bin/env bash` unless a script specifically requires another shell.

Permissions:

- Both source script and wrapper must be executable (`chmod +x`).

Error handling:

- Use `set -euo pipefail` where practical.
- Wrappers should fail fast with actionable errors if source file is missing or not executable.

Arguments:

- Wrappers should forward all args with `"$@"`.

Runtime path resolution:

- Wrappers should execute home-based paths (`$HOME/.local/...`), not repo-absolute paths.

## Wrapper Contract (Template)

Use this pattern for command wrappers in `home/.local/bin/<name>`:

```bash
#!/usr/bin/env bash
set -euo pipefail

script_path="$HOME/.local/share/fifty-shades-of-dotfiles/scripts/<name>.sh"

if [[ ! -e "$script_path" ]]; then
  echo "<name>: script not found at $script_path" >&2
  echo "Restow dotfiles from current repo location (e.g. ./install.sh --stow-only)." >&2
  exit 1
fi

if [[ ! -x "$script_path" ]]; then
  echo "<name>: script is not executable: $script_path" >&2
  echo "Run: chmod +x \"$script_path\"" >&2
  exit 1
fi

exec "$script_path" "$@"
```

## Add a New Script (Checklist)

1. Create source script in:
   - `home/.local/share/fifty-shades-of-dotfiles/scripts/<name>.sh`
2. Ensure source has executable bit:
   - `chmod +x home/.local/share/fifty-shades-of-dotfiles/scripts/<name>.sh`
3. Create wrapper entrypoint:
   - `home/.local/bin/<name>`
4. Ensure wrapper is executable:
   - `chmod +x home/.local/bin/<name>`
5. If there is a legacy alias/path in `.zshrc` or docs, migrate to command-first usage.
6. Update docs as needed:
   - This README (if conventions or script index needs updates)
   - Root `README.md` (high-level mention only)
   - Any topic docs that reference old direct paths
7. Run verification (see below).
8. Commit with clear message (for example: `feat: add <name> standalone script and wrapper`).

## Verification Checklist

For a script `<name>`:

```bash
command -v <name>
<name> --help  # or run a safe smoke command
```

Also verify no stale path references remain:

```bash
rg '~/<name>\.sh|\.local/share/fifty-shades-of-dotfiles/scripts/<name>\.sh' README.md docs home/.zshrc
```

Expected:

- `command -v <name>` resolves to `~/.local/bin/<name>`
- Wrapper runs source script successfully
- No unexpected stale references to deprecated paths

## Migration Policy (Legacy Paths)

Policy is clean break:

- Do not keep permanent aliases to legacy direct script paths like `~/sysinfo.sh`.
- Prefer command-first usage (`sysinfo`) everywhere.
- Update docs and shell aliases/functions accordingly.

## Troubleshooting

Command not found:

- Confirm `~/.local/bin` is on PATH.
- Confirm wrapper exists and is executable.
- Confirm stow has been run from this repo.

Permission denied:

- Run `chmod +x` on both wrapper and source script.

Script missing after repo move:

- Restow links from new repo location:
  - `./install.sh --stow-only` (preferred) or `stow -R -t "$HOME" home`

Wrong command behavior due to old alias:

- Check for stale alias/function in shell config:
  - `type <name>`
- Remove conflicting alias/function and reload shell.

`dirdiff` config behavior:

- Runtime config is local-only at `~/.config/dirdiff/config` (do not keep `home/.config/dirdiff/config` in repo).
- Existing config is never overwritten by `dirdiff`.
- `.bak` config files are not created.

## Current Script Index

- `dirdiff` -> `~/.local/share/fifty-shades-of-dotfiles/scripts/dirdiff.sh`
- `sysinfo` -> `~/.local/share/fifty-shades-of-dotfiles/scripts/sysinfo.sh`
- `watch-history-sync` -> `~/.local/share/fifty-shades-of-dotfiles/scripts/watch-history-sync.sh`
