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

| File                    | Purpose                               | Deployed To               |
| ----------------------- | ------------------------------------- | ------------------------- |
| `.zshrc`                | Main zsh configuration file           | `~/.zshrc`                |
| `.zsh_python_functions` | Python helper functions               | `~/.zsh_python_functions` |
| `.zsh_node_functions`   | Node.js helper functions              | `~/.zsh_node_functions`   |
| `.zsh_docker_functions` | Docker helper functions               | `~/.zsh_docker_functions` |
| `.zsh_cursor_functions` | Cursor/VSCode integration             | `~/.zsh_cursor_functions` |
| `.zsh_tmux`             | Tmux integration functions            | `~/.zsh_tmux`             |
| `.zsh_onboarding`       | Cross-platform onboarding script      | `~/.zsh_onboarding`       |
| `.zsh_welcome`          | Unified cross-platform welcome script | `~/.zsh_welcome`          |

#### Other Configuration Files

| File         | Purpose                           | Deployed To    |
| ------------ | --------------------------------- | -------------- |
| `.tmux.conf` | Tmux configuration                | `~/.tmux.conf` |
| `.p10k.zsh`  | Powerlevel10k theme configuration | `~/.p10k.zsh`  |
| `.vimrc`     | Lightweight Vim configuration     | `~/.vimrc`     |

### `home/.config/` - Files for `~/.config/`

All files in `home/.config/` are deployed to `~/.config/`, maintaining the same subdirectory structure.

#### `home/.config/direnv/`

direnv configuration files for automatic environment management.

| File          | Purpose                  | Deployed To                    |
| ------------- | ------------------------ | ------------------------------ |
| `direnv.toml` | direnv settings          | `~/.config/direnv/direnv.toml` |
| `direnvrc`    | direnv hooks and scripts | `~/.config/direnv/direnvrc`    |

The `direnvrc` file includes automatic VSCode/Cursor color setup based on machine type (see `docs/MEMENTO_vscode_machine_colors.md`).

#### `home/.config/yazi/`

Yazi terminal file manager configuration with catppuccin-mocha theme, vim-style keybindings, and plugins.

| File                             | Purpose                                           | Deployed To                                     |
| -------------------------------- | ------------------------------------------------- | ----------------------------------------------- |
| `yazi.toml`                      | Main config (layout, openers, sort, plugins)      | `~/.config/yazi/yazi.toml`                      |
| `keymap.toml`                    | Keybindings (vim-style navigation + zoom)         | `~/.config/yazi/keymap.toml`                    |
| `theme.toml`                     | Theme overrides and file-type icons               | `~/.config/yazi/theme.toml`                     |
| `init.lua`                       | Init script (loads git plugin)                    | `~/.config/yazi/init.lua`                       |
| `package.toml`                   | Plugin and flavor dependencies                    | `~/.config/yazi/package.toml`                   |
| `plugins/git.yazi/`              | Git status indicators in file list                | `~/.config/yazi/plugins/git.yazi/`              |
| `plugins/zoom.yazi/`             | Image zoom in preview pane (requires ImageMagick) | `~/.config/yazi/plugins/zoom.yazi/`             |
| `flavors/catppuccin-mocha.yazi/` | Catppuccin Mocha color scheme                     | `~/.config/yazi/flavors/catppuccin-mocha.yazi/` |

**Note**: The zoom plugin requires ImageMagick (`brew install imagemagick` on macOS) for the `magick` command.

#### `home/.config/zed/`

Zed editor settings. Only `settings.json` is managed; `prompts/` and `themes/` remain user-local.

| File            | Purpose             | Deployed To                   |
| --------------- | ------------------- | ----------------------------- |
| `settings.json` | Zed editor settings | `~/.config/zed/settings.json` |

#### `home/.config/yt-dlp/`

yt-dlp configuration template.

| File     | Purpose              | Deployed To               |
| -------- | -------------------- | ------------------------- |
| `config` | yt-dlp configuration | `~/.config/yt-dlp/config` |

**Note**: The `yt()` function in `.zshrc` auto-generates this config file if it doesn't exist. This file serves as a template/reference.

### `home/.local/bin/` - Standalone Commands

Executable commands exposed on `PATH` via `~/.local/bin`. Two kinds:

- **Direct** scripts live entirely in `home/.local/bin/<name>`.
- **Wrapper** scripts are thin stubs that exec a source script in `home/.local/share/fifty-shades-of-dotfiles/scripts/<name>.sh` - see that directory's `README.md` for the wrapper architecture and the add-a-script workflow.

| Command                   | Purpose                                                                                                                                                    | Kind    |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `md-hardbreak`            | On-demand Markdown formatting for Zed: hard breaks / paragraph gaps / strip (see `docs/ZED_MARKDOWN_FORMATTING.md`)                                        | direct  |
| `migrate-claude-projects` | **Local-only (gitignored 2026-07-30) - NOT shipped by stow.** Rename Claude Code project dirs after the repo moves to a new path                           | direct  |
| `pnpm-audit-tree`         | Recursive supply-chain auditor for pnpm / JS project trees (see `docs/PNPM_AUDIT_TREE.md`)                                                                 | direct  |
| `pnpm-audit-hook`         | Git pre-commit/pre-push hook that blocks on supply-chain findings; wraps `pnpm-audit-tree` (see `docs/PNPM_AUDIT_PREPUSH_HOOK.md`)                         | direct  |
| `nvm-verify-node`         | Verify an nvm-installed Node against official GPG-signed nodejs.org releases, bypassing mirrors (see `docs/NVM_SECURITY.md`)                               | direct  |
| `toolchain-cve-check`     | Check pnpm/nvm version floors + installed versions against live CVE advisories (see `docs/TOOLCHAIN_CVE_CHECK.md`)                                         | direct  |
| `herdr-cooldown-check`    | Enforce the 3-day release cooldown for herdr: version/age gate, brew pin, phone-home guards (see `docs/HERDR.md`)                                          | direct  |
| `speak-clipboard`         | Speak the clipboard aloud with terminal furniture stripped (ANSI, PUA glyphs, rule runs); the a11y path herdr's mouse capture breaks (see `docs/HERDR.md`) | direct  |
| `git-leak-scan`           | Pre-commit scan of the staged diff for identity/secret leaks; invoked by the `_audit-chain` git-hook chainer                                               | direct  |
| `git-trailer-audit`       | Audit `C-*` attribution-trailer coverage across history; partial stamps fail, unstamped commits are flagged ambiguous                                      | direct  |
| `p10k-contrast-check`     | WCAG contrast audit of every ENABLED p10k prompt segment against each iTerm2 profile's real palette; catches a theme swap making the prompt illegible      | direct  |
| `ci-watch`                | Escalating, exception-based CI-status dashboard surfaced at session start (see `docs/CI_WATCH.md`)                                                         | direct  |
| `dirdiff`                 | Directory comparison tool (Left vs Right; size / content / by-type, JSON output)                                                                           | wrapper |
| `sysinfo`                 | Terminal system-information dashboard                                                                                                                      | wrapper |
| `watch-history-sync`      | Export YouTube watch history to a local SQLite database                                                                                                    | wrapper |

### `platforms/` - Platform-Specific Files

Files that are specific to certain operating systems or platforms.

#### `platforms/macos/`

macOS-specific configuration files.

| Path                                                    | Purpose                        | Deployed To                                               |
| ------------------------------------------------------- | ------------------------------ | --------------------------------------------------------- |
| `Library/Application Support/Cursor/User/settings.json` | Cursor editor settings (macOS) | `~/Library/Application Support/Cursor/User/settings.json` |
| `Library/Application Support/Code/User/settings.json`   | VSCode editor settings (macOS) | `~/Library/Application Support/Code/User/settings.json`   |

**Note**: Linux/WSL editor settings are created dynamically by `direnvrc`, so they don't need to be in the repository.

### `settings/` - Exported App Configurations

Application settings exported for reference and manual import. These are not auto-deployed by the installer.

#### `settings/iterm2/`

| File            | Purpose                                                                      |
| --------------- | ---------------------------------------------------------------------------- |
| `profiles.json` | iTerm2 profiles (import via Profiles > Other Actions > Import JSON Profiles) |

#### `settings/wezterm/`

| File          | Purpose                                                                    |
| ------------- | -------------------------------------------------------------------------- |
| `wezterm.lua` | WezTerm config (Coolnight colors, SSH detection, keybindings, tab styling) |

### `docs/` - Documentation

Documentation and reference materials.

| File/Directory                     | Purpose                                                                                                                                                                                       |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AGENT_BRIEF.md`                   | Safe cross-agent interaction patterns and stow/branch-switching hazards for sibling-project agents                                                                                            |
| `CLAUDE_SESSION_ATTRIBUTION.md`    | Auto-stamp commits with C-Sess-Id / C-Web-Id / C-Branch / C-Worktree / C-Wt-Path trailers (SessionStart identity hook + \_audit-chain step); fresh-machine runbook, verification, and gotchas |
| `SECURITY.md`                      | Strict SSH posture rationale, alternative postures table, and drift-check commands                                                                                                            |
| `MEMENTO_vscode_machine_colors.md` | Complete guide for VSCode/Cursor machine-specific color setup                                                                                                                                 |
| `ZED_MARKDOWN_FORMATTING.md`       | md-hardbreak: hard breaks / paragraph gaps / strip, Zed tasks + key bindings, and the rationale                                                                                               |
| `ZED_PREVIEW_CHANGELOG.md`         | Living record of Zed Preview UI / configuration / theme changes, plus the standing watch-items; refreshed via the SessionStart version check                                                  |
| `CLAUDE_CODE_SECURITY.md`          | Claude Code's own security surface — sandbox, permission modes, CVEs. Scope-stamped to a dated investigation; treat the version as history, not a currency claim                              |
| `CLAUDE_CODE_AND_PAI_INTERNALS.md` | How `~/.claude/` is actually organised: the three-system model, project-path encoding, and the migration hazards when a repo moves                                                            |
| `CLAUDE_CODE_RESEARCH_NOTES.md`    | Living notes on researched Claude Code behaviour and mechanics (hook loading, permission modes, interactive quirks)                                                                           |
| `GH_AUTH_GUARD_USER_LEVEL.md`      | GitHub API read-only token plus the `gh` auth guard, user-level install                                                                                                                       |
| `NVM_SECURITY.md`                  | nvm / Node.js hardening: mirror pin, version floor, EOL policy, and GPG signature verification                                                                                                |
| `TOOLCHAIN_CVE_CHECK.md`           | `toolchain-cve-check`: are the pinned floors and the installed versions CVE-exposed? Cites historically vulnerable pins on purpose as negative controls                                       |
| `PNPM_SETUP_GUIDE.md`              | pnpm setup: where pnpm reads config from, the kebab-case silent-failure trap, macOS vs XDG paths                                                                                              |
| `PNPM_AUDIT_TREE.md`               | `pnpm-audit-tree`: recursive supply-chain auditor for pnpm / JS project trees                                                                                                                 |
| `PNPM_AUDIT_PREPUSH_HOOK.md`       | The global, opt-in pnpm-audit pre-push git hook                                                                                                                                               |
| `CI_WATCH.md`                      | `ci-watch`: the escalating, dismiss-only-by-fixing CI status line in the session dashboard                                                                                                    |
| `HERDR.md`                         | herdr: the 3-day release cooldown, daemon persistence, speak-selection bindings, and the tmux comparison                                                                                      |
| `comms/`                           | Dated outbound notes to peer agent projects (CONVENTION.md spec v1.15; read on-demand only — see `comms/README.md` for the index; contents are NOT enumerated here by design)                 |
| `reference/colors.md`              | Color palette reference                                                                                                                                                                       |
| `reference/mermaid_examples.md`    | Mermaid diagram examples                                                                                                                                                                      |
| `reference/tmux_cheatsheet.md`     | Tmux quick reference guide                                                                                                                                                                    |
| `reference/pai_memory_system.md`   | How Claude remembers across conversations, projects and sessions — the memory and persistence mechanisms, written as a read-at-leisure explainer                                              |
| `reference/windows/`               | Historical Windows batch scripts (reference only, not for deployment)                                                                                                                         |

**Hook documentation lives outside `docs/`** — two files, and knowing which is which matters:

- [`.claude/hooks/README.md`](../.claude/hooks/README.md) — the **living inventory**. One
  section per shell hook, and the doc the root README links to. Keep this one current.
- [`.claude/docs/HOOKS_ARCHITECTURE.md`](../.claude/docs/HOOKS_ARCHITECTURE.md) — the
  original deep architecture reference (TypeScript handler design, event flow). Much
  larger, but last substantively updated 2026-02 and it covers only a subset of the
  current hooks; read it for architecture, not for what is installed.

**Files prefixed `_` are deliberately untracked** (`_CODE_FOLDER_STRUCTURE.md`,
`_MLBOX_SEALED_DAY_TO_DAY.md`) — they carry real usernames or host detail. They are
intentionally absent from the table above; do not "fix" that by indexing them.

#### `docs/reference/windows/`

Historical Windows batch scripts kept for reference. These scripts were used when working with Windows Command Prompt/PowerShell environments, but are no longer needed since the user now uses WSL.

**Note**: These files are **not part of the deployment structure** - they are kept for historical reference only.

| File              | Purpose                                                      |
| ----------------- | ------------------------------------------------------------ |
| `activate.v1.bat` | Project activation script (version 1) - historical reference |
| `activate.v2.bat` | Project activation script (version 2) - historical reference |
| `run.cmd`         | Project launcher script - historical reference               |

### `.github/` - GitHub Repository Configuration

GitHub-specific configuration files. Not deployed by stow — consumed directly by GitHub.

#### `.github/rulesets/`

Reusable branch protection ruleset templates. Import via: Repository → Settings → Rules → Rulesets → Import a ruleset.

| File                            | Purpose                                                                                  |
| ------------------------------- | ---------------------------------------------------------------------------------------- |
| `branch-protection-master.json` | Blocks force pushes and deletion on `master`; requires a PR before merging (0 approvals) |

**Note**: To reuse on a repo with a different default branch, swap `refs/heads/master` for `~DEFAULT_BRANCH` in `conditions.ref_name.include`.

## Deployment Mapping Reference

When deploying files, use this quick reference:

| Repository Location                                                     | Deployment Location                                       |
| ----------------------------------------------------------------------- | --------------------------------------------------------- |
| `home/.zshrc`                                                           | `~/.zshrc`                                                |
| `home/.zsh_*`                                                           | `~/.zsh_*`                                                |
| `home/.tmux.conf`                                                       | `~/.tmux.conf`                                            |
| `home/.p10k.zsh`                                                        | `~/.p10k.zsh`                                             |
| `home/.config/direnv/direnv.toml`                                       | `~/.config/direnv/direnv.toml`                            |
| `home/.config/direnv/direnvrc`                                          | `~/.config/direnv/direnvrc`                               |
| `home/.config/yazi/`                                                    | `~/.config/yazi/`                                         |
| `home/.config/zed/settings.json`                                        | `~/.config/zed/settings.json`                             |
| `home/.config/yt-dlp/config`                                            | `~/.config/yt-dlp/config`                                 |
| `platforms/macos/Library/Application Support/Cursor/User/settings.json` | `~/Library/Application Support/Cursor/User/settings.json` |
| `platforms/macos/Library/Application Support/Code/User/settings.json`   | `~/Library/Application Support/Code/User/settings.json`   |
| `settings/`                                                             | Manual import (not auto-deployed)                         |

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
