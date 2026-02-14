# Repository Structure Documentation

This document explains the organization of the fifty-shades-of-dotfiles repository and how it maps to actual deployment locations.

## Overview

The repository uses a **one-to-one mapping** structure that mirrors actual deployment locations. This means:
- `home/.zshrc` → `~/.zshrc`
- `home/.config/direnv/direnvrc` → `~/.config/direnv/direnvrc`
- And so on...

This design eliminates confusion about where files should be deployed.

## Directory Structure

### `home/` - Files for `~/`

All files in `home/` are deployed directly to your home directory (`~/`).

#### Shell Configuration Files

| File | Purpose | Deployed To |
|------|---------|-------------|
| `.zshrc` | Main zsh configuration file | `~/.zshrc` |
| `.zsh_python_functions` | Python helper functions | `~/.zsh_python_functions` |
| `.zsh_node_functions` | Node.js helper functions | `~/.zsh_node_functions` |
| `.zsh_docker_functions` | Docker helper functions | `~/.zsh_docker_functions` |
| `.zsh_cursor_functions` | Cursor/VSCode integration | `~/.zsh_cursor_functions` |
| `.zsh_tmux` | Tmux integration functions | `~/.zsh_tmux` |
| `.zsh_onboarding` | Cross-platform onboarding script | `~/.zsh_onboarding` |
| `.zsh_welcome` | Unified cross-platform welcome script | `~/.zsh_welcome` |

#### Other Configuration Files

| File | Purpose | Deployed To |
|------|---------|-------------|
| `.tmux.conf` | Tmux configuration | `~/.tmux.conf` |
| `.p10k.zsh` | Powerlevel10k theme configuration | `~/.p10k.zsh` |

### `home/.config/` - Files for `~/.config/`

All files in `home/.config/` are deployed to `~/.config/`, maintaining the same subdirectory structure.

#### `home/.config/direnv/`

direnv configuration files for automatic environment management.

| File | Purpose | Deployed To |
|------|---------|-------------|
| `direnv.toml` | direnv settings | `~/.config/direnv/direnv.toml` |
| `direnvrc` | direnv hooks and scripts | `~/.config/direnv/direnvrc` |

The `direnvrc` file includes automatic VSCode/Cursor color setup based on machine type (see `docs/MEMENTO_vscode_machine_colors.md`).

#### `home/.config/yt-dlp/`

yt-dlp configuration template.

| File | Purpose | Deployed To |
|------|---------|-------------|
| `config` | yt-dlp configuration | `~/.config/yt-dlp/config` |

**Note**: The `yt()` function in `.zshrc` auto-generates this config file if it doesn't exist. This file serves as a template/reference.

### `platforms/` - Platform-Specific Files

Files that are specific to certain operating systems or platforms.

#### `platforms/macos/`

macOS-specific configuration files.

| Path | Purpose | Deployed To |
|------|---------|-------------|
| `Library/Application Support/Cursor/User/settings.json` | Cursor editor settings (macOS) | `~/Library/Application Support/Cursor/User/settings.json` |
| `Library/Application Support/Code/User/settings.json` | VSCode editor settings (macOS) | `~/Library/Application Support/Code/User/settings.json` |

**Note**: Linux/WSL editor settings are created dynamically by `direnvrc`, so they don't need to be in the repository.

### `docs/` - Documentation

Documentation and reference materials.

| File/Directory | Purpose |
|----------------|---------|
| `MEMENTO_vscode_machine_colors.md` | Complete guide for VSCode/Cursor machine-specific color setup |
| `reference/colors.md` | Color palette reference |
| `reference/mermaid_examples.md` | Mermaid diagram examples |
| `reference/tmux_cheatsheet.md` | Tmux quick reference guide |
| `reference/windows/` | Historical Windows batch scripts (reference only, not for deployment) |

#### `docs/reference/windows/`

Historical Windows batch scripts kept for reference. These scripts were used when working with Windows Command Prompt/PowerShell environments, but are no longer needed since the user now uses WSL.

**Note**: These files are **not part of the deployment structure** - they are kept for historical reference only.

| File | Purpose |
|------|---------|
| `activate.v1.bat` | Project activation script (version 1) - historical reference |
| `activate.v2.bat` | Project activation script (version 2) - historical reference |
| `run.cmd` | Project launcher script - historical reference |

## Deployment Mapping Reference

When deploying files, use this quick reference:

| Repository Location | Deployment Location |
|---------------------|---------------------|
| `home/.zshrc` | `~/.zshrc` |
| `home/.zsh_*` | `~/.zsh_*` |
| `home/.tmux.conf` | `~/.tmux.conf` |
| `home/.p10k.zsh` | `~/.p10k.zsh` |
| `home/.config/direnv/direnv.toml` | `~/.config/direnv/direnv.toml` |
| `home/.config/direnv/direnvrc` | `~/.config/direnv/direnvrc` |
| `home/.config/yt-dlp/config` | `~/.config/yt-dlp/config` |
| `platforms/macos/Library/Application Support/Cursor/User/settings.json` | `~/Library/Application Support/Cursor/User/settings.json` |
| `platforms/macos/Library/Application Support/Code/User/settings.json` | `~/Library/Application Support/Code/User/settings.json` |

## Benefits of This Structure

1. **One-to-one mapping**: Repository structure exactly matches deployment locations
2. **No confusion**: See `home/.zshrc` → know it goes to `~/.zshrc`
3. **Easy deployment**: Copy/symlink operations are straightforward
4. **Clear organization**: Files grouped by deployment location
5. **Scalable**: Easy to add new configs - just mirror the target location

## Adding New Configuration Files

When adding new configuration files:

1. **Determine the deployment location** (e.g., `~/.config/myapp/config`)
2. **Create the matching path in the repository** (e.g., `home/.config/myapp/config`)
3. **Add to this documentation** so others know where it goes

For platform-specific files, use the `platforms/` directory and mirror the full path structure.
