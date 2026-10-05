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

**Note**: The `yt()` function in `.zshrc` auto-generates this config file if it doesn't exist. This file serves as a template/reference. `yt-dlp` itself is never installed — `yt()` runs it on demand via `uvx --prerelease allow yt-dlp`.

#### `home/.config/herdr/`

herdr (agent multiplexer) configuration. Carries the ported tmux keymap and, more importantly, the two phone-home guards — `version_check` and `manifest_check` both `false`, since a missing key reads as enabled upstream. See `docs/HERDR.md`.

| File          | Purpose                                                     | Deployed To                   |
| ------------- | ----------------------------------------------------------- | ----------------------------- |
| `config.toml` | Keymap, phone-home guards, speak-selection command bindings | `~/.config/herdr/config.toml` |

**Note**: keybindings in this file only govern the machine running the herdr **client**. A `herdr --remote` session reads the client's own config unless launched with `--remote-keybindings server`.

#### `home/.config/lazygit/`

lazygit configuration, themed to match the terminal (Catppuccin Macchiato).

| File         | Purpose                            | Deployed To                    |
| ------------ | ---------------------------------- | ------------------------------ |
| `config.yml` | lazygit settings and colour scheme | `~/.config/lazygit/config.yml` |

### `home/.local/bin/` - Standalone Commands

Executable commands exposed on `PATH` via `~/.local/bin`. Two kinds:

- **Direct** scripts live entirely in `home/.local/bin/<name>`.
- **Wrapper** scripts are thin stubs that exec a source script in `home/.local/share/fifty-shades-of-dotfiles/scripts/<name>.sh` - see that directory's `README.md` for the wrapper architecture and the add-a-script workflow.

| Command                   | Purpose                                                                                                                                                                                                                                                                                                                                                                          | Kind    |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `safe-rm`                 | Delete by moving to the system Trash; never unlinks, and refuses rather than falling back to `rm`. The one owner of "how do we delete" - the `.zshrc` `rm()`/`rmdir()` wrappers and every script call it                                                                                                                                                                         | direct  |
| `md-hardbreak`            | On-demand Markdown formatting for Zed: hard breaks / paragraph gaps / strip (see `docs/ZED_MARKDOWN_FORMATTING.md`)                                                                                                                                                                                                                                                              | direct  |
| `migrate-claude-projects` | **Local-only (gitignored 2026-07-30) - NOT shipped by stow.** Rename Claude Code project dirs after the repo moves to a new path                                                                                                                                                                                                                                                 | direct  |
| `pnpm-audit-tree`         | Recursive supply-chain auditor for pnpm / JS project trees (see `docs/PNPM_AUDIT_TREE.md`)                                                                                                                                                                                                                                                                                       | direct  |
| `pnpm-audit-hook`         | Git pre-commit/pre-push hook that blocks on supply-chain findings; wraps `pnpm-audit-tree` (see `docs/PNPM_AUDIT_PREPUSH_HOOK.md`)                                                                                                                                                                                                                                               | direct  |
| `nvm-verify-node`         | Verify an nvm-installed Node against official GPG-signed nodejs.org releases, bypassing mirrors (see `docs/NVM_SECURITY.md`)                                                                                                                                                                                                                                                     | direct  |
| `toolchain-cve-check`     | Check pnpm/nvm/bun floors + installed versions + installed Claude Code against live CVE advisories (7 subjects, plus Homebrew via `--brew`) (see `docs/TOOLCHAIN_CVE_CHECK.md`)                                                                                                                                                                                                  | direct  |
| `vuln-scan`               | Incremental CVE scan of INSTALLED Homebrew formulae via NVD; SQLite-backed, revision-aware, filters Homebrew-backported fixes (see `docs/VULN_SCAN.md`)                                                                                                                                                                                                                          | direct  |
| `vulnlib.py`              | Shared NVD/CPE/Homebrew/scan-store library behind `vuln-scan` (imported, not executed)                                                                                                                                                                                                                                                                                           | direct  |
| `herdr-cooldown-check`    | Enforce the release cooldown for herdr (length: `HERDR_COOLDOWN_DAYS` in `install.sh`): version/age gate, brew pin, phone-home guards (see `docs/HERDR.md`)                                                                                                                                                                                                                      | direct  |
| `herdr-linux-pin-check`   | Compare Linux/WSL's pinned `HERDR_VERSION` against macOS's already-cooldown-cleared Homebrew pin; computes (never commits) sha256 for the matching Linux release assets (see `docs/HERDR.md`)                                                                                                                                                                                    | direct  |
| `speak-clipboard`         | Speak the clipboard aloud with terminal furniture stripped (ANSI, PUA glyphs, rule runs) and typography mapped to ASCII, through one `say2` process per press, streamed into `ffplay` so speech starts in ~0.3 s (falls back to Simone, then plain `say`, if the premium voice is unavailable); toggle = any press while speaking stops, next press speaks (see `docs/HERDR.md`) | direct  |
| `imsg`                    | Send-only iMessage CLI for agents/hooks/cron; needs Automation consent, never Full Disk Access; message passed via argv so nothing in it parses as script (see `docs/IMSG.md`)                                                                                                                                                                                                   | direct  |
| `pj-ping`                 | The one attention signal (D-20260921-A10): four sounds, then two `imsg` messages 1 s apart carrying a never-reused 4-character id, logged to `~/.local/state/pj/ping.log`; `--detach` for hooks (see `docs/PJ_PING.md`)                                                                                                                                                          | direct  |
| `git-leak-scan`           | Pre-commit scan of the staged diff for identity leaks: usernames, API tokens, private keys, E.164 phone numbers; invoked by the `_audit-chain` git-hook chainer                                                                                                                                                                                                                  | direct  |
| `git-trailer-audit`       | Audit `C-*` attribution-trailer coverage across history; partial stamps fail, unstamped commits are flagged ambiguous                                                                                                                                                                                                                                                            | direct  |
| `p10k-contrast-check`     | WCAG contrast audit of every ENABLED p10k prompt segment against each iTerm2 profile's real palette; catches a theme swap making the prompt illegible                                                                                                                                                                                                                            | direct  |
| `ci-watch`                | Escalating, exception-based CI-status dashboard surfaced at session start (see `docs/CI_WATCH.md`)                                                                                                                                                                                                                                                                               | direct  |
| `deploy-parity-check`     | Is every git-tracked `home/` file actually symlinked into `~/`? Reports MISSING vs SHADOWED separately; self-tests its own detectors on every run                                                                                                                                                                                                                                | direct  |
| `toolchain-stocktake`     | Read-only survey of the machine's EXISTING Python/Node toolchain (pyenv/conda/asdf/mise, pipx tools, npm globals, non-default registry) before install.sh's opinionated takeover lands (see `docs/TOOLCHAIN_TAKEOVER_CONSENT.md`)                                                                                                                                                | direct  |
| `project-impact-scan`     | Read-only scan of existing Python/Node PROJECTS for which npm/venv-based ones break once pnpm/uv are enforced, with a per-project migration hint and a durable report for a later Claude Code session (see `docs/TOOLCHAIN_TAKEOVER_CONSENT.md`)                                                                                                                                 | direct  |
| `python-scaffold-check`   | Scaffolds a throwaway project and validates what the generators actually EMIT (README placeholders, `.envrc` runs clean under bash, `uv.lock` not ignored)                                                                                                                                                                                                                       | direct  |
| `dirdiff`                 | Directory comparison tool (Left vs Right; size / content / by-type, JSON output)                                                                                                                                                                                                                                                                                                 | wrapper |
| `cmd-spy`                 | Prove whether a program calls a command: runs it with a logging fake of each named command first on PATH (verified reachable before the run), reports every call with its arguments and states a zero positively; `--pass` also runs the real command; `--selftest` proves 8 arms                                                                                                | direct  |
| `sysinfo`                 | Terminal system-information dashboard                                                                                                                                                                                                                                                                                                                                            | wrapper |
| `watch-history-sync`      | Export YouTube watch history to a local SQLite database                                                                                                                                                                                                                                                                                                                          | wrapper |

More commands, grouped by area. All are direct scripts.

#### Deletion safety

How a delete reaches the Trash. The reasoning: `docs/DELETION_SAFETY.md`.

| Command          | Purpose                                                                                                                            |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `rm`             | PATH shim: a bare `rm` in any script, Makefile, `find -exec` or `xargs` goes to the Trash through `safe-rm`, not to `/bin/rm`      |
| `trash`          | PATH shim in front of the system `trash`: every target passes `trash-guard` first (an empty argument once trashed a whole repo)    |
| `trash-guard`    | The one place that decides whether a path may go to the Trash; `trash`, `safe-rm` and the deletion hook all ask it                 |
| `rm-reach-check` | Does a plain, non-interactive shell reach the Trash-routed `rm`, and is a look-alike `safe-rm` or `trash` waiting earlier on PATH? |

#### Links

Keeping the stowed links in place. Added 2026-10-05, after a failed restow removed every link for 6.5 minutes.

| Command          | Purpose                                                                                                                                                                                             |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `dotlinks`       | Check or restore every stowed link from the manifest `install.sh` writes after each good deploy. Its real-file copy, `sh ~/.local/state/dotfiles/links/restore`, works even when every link is gone |
| `dotlinks-watch` | Polls that manifest and notifies within seconds when the links break or come back; runs as the launchd agent `com.captaincodeau.dotlinks-watch` (macOS)                                             |

#### Claude Code hooks and settings

How hooks get registered: `docs/CLAUDE_HOOKS.md`.

| Command                          | Purpose                                                                                                                                              |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude-hooks-sync`              | Registers this repo's hooks from `settings/claude/hooks.json` into `~/.claude/settings.json` and the project settings; `--check` reports drift       |
| `claude-project-settings-render` | Renders `~/.claude/settings.project.json` from the repo's template without dropping the hooks registered into it                                     |
| `mods-api-drift`                 | Notices when a Claude Code update changes the Claude Mods API; keeps the declarations per version under `~/.local/state/pj/mods-api/`                |
| `zsh-helper-namespace-check`     | Proves no public shell function depends on a single-underscore helper, which Claude Code's shell snapshot drops (see `docs/ZSH_HELPER_NAMESPACE.md`) |

#### The session framework

The tools behind every Claude session's start card, wrap-up and temp folder. Since 4 Oct 2026 sessions are launched by `engage`.

| Command            | Purpose                                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------------------------- |
| `pj`               | Retired 4 Oct 2026: prints "pj is retired. Type engage." and exits 1                                        |
| `pj-prompt-file`   | Builds the one system-prompt file a session launch appends, and prints its path                             |
| `pj-launch-check`  | SessionStart hook: did this session launch with the current launcher (prompt file, plugin dirs, settings)?  |
| `pj-launcher-menu` | What `c` prints now: a signpost, not a launcher (exits 1)                                                   |
| `pj-start-card`    | The 20-line start card every session opens with; `--json` gives the same facts as one object                |
| `pj-session-end`   | SessionEnd hook: flags a session that did work and ended without `/pj:wrap-up`, for the next start card     |
| `pj-wrap`          | The helper behind `/pj:wrap-up`: `status`, `done`, `push` (see `docs/PJ_WRAP_UP.md`)                        |
| `pj-temp`          | Gives every session its own temp folder and empties it into the Trash (see `docs/PJ_TEMP_CLEANUP.md`)       |
| `pj-worker`        | Starts a conductor's herdr worker as a real session, proves it, and holds the session caps                  |
| `pj-health`        | Is the session framework wired on this machine? One row per check, writes nothing (see `docs/PJ_HEALTH.md`) |
| `pj-id`            | The one ID allocator behind `open-items add` and `decided add`                                              |

#### Records

Open items and decisions, kept per project and machine-wide.

| Command      | Purpose                                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------------------------ |
| `open-items` | What is still open, scoped to the project you stand in; add, close, park, decline (see `docs/OPEN_ITEMS.md`) |
| `decided`    | Has this already been settled? Searches the decisions register by topic (see `docs/DECIDED.md`)              |

#### GitHub credentials

The GitHub App system and the narrow tokens. Reference: `docs/GITHUB_AGENT_USAGE.md`; steps: `docs/GITHUB_AGENT_RECIPES.md`.

| Command                    | Purpose                                                                                                                |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `github-api-token`         | Prints the narrow read-only GitHub API token, so gh-calling tools stop using whatever credential is in the environment |
| `github-agent-token`       | Mints a 1-hour GitHub App installation token scoped to the one repo you stand in                                       |
| `github-agent-flip`        | Moves one repo onto the GitHub App system: an HTTPS `origin` plus one `githubagent.tier` key                           |
| `github-agent-flip-all`    | Flips every local clone of one account in one pass, reading each repo's tier from GitHub                               |
| `github-agent-create-app`  | Registers a new GitHub App through GitHub's manifest flow (one confirm click in a browser)                             |
| `github-agent-verify-app`  | Checks an App end to end: key stored, key valid, a real installation token can be minted                               |
| `github-agent-public-post` | Opens an issue or comments on a public repo you do not own; deliberately not silent                                    |
| `gh-cred-matrix`           | Measures what each GitHub credential on this machine can actually do; writes only to one throwaway repo                |

#### herdr

Helpers for the herdr agent multiplexer (see `docs/HERDR.md`).

| Command                   | Purpose                                                                                   |
| ------------------------- | ----------------------------------------------------------------------------------------- |
| `hwt`                     | Creates a herdr-tracked git worktree inside this project's folder, not herdr's shared one |
| `herdr-pane-read`         | A `herdr pane read` that cannot land in the blank region below a short program's output   |
| `herdr-skill-drift-check` | Has a herdr upgrade moved the upstream agent skill under our locally annotated copy?      |

#### Checks and watchers

Small instruments, most of them run at session start or at commit.

| Command                  | Purpose                                                                                                       |
| ------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `peek`                   | A `head` that says what it hid: always ends with "showed N of M lines", or that nothing was hidden            |
| `ccw-watch`              | Session-start check that transcript capture is still happening (it once stopped for ten days unnoticed)       |
| `bun-cooldown-check`     | Is a global bun package stuck behind the `minimumReleaseAge` supply-chain cooldown?                           |
| `env-python-floor-check` | Proves every `#!/usr/bin/env python3` tool still runs on the oldest python3 that name can reach (macOS's 3.9) |
| `shift-lint`             | Finds every `shift N` (N >= 2) that a value flag given last can hang; runs on staged shell files at commit    |
| `selftest-whole-read`    | Proves every bash selftest reads itself whole before running, so an edit made mid-run cannot change it        |

#### Selftests

Each one drives its tool to pass and to fail on throwaway fixtures, and touches nothing real.

| Command                                   | Purpose                                                                                    |
| ----------------------------------------- | ------------------------------------------------------------------------------------------ |
| `safe-rm-selftest`                        | The Trash-routed deletion chain                                                            |
| `trash-guard-selftest`                    | Both Trash routes and the deletion hook                                                    |
| `mv-wrapper-selftest`                     | The `mv`/`cp` wrappers report a declined overwrite as a failure and never wait on a prompt |
| `git-leak-scan-selftest`                  | The global pre-commit leak gate still bites                                                |
| `audit-chain-selftest`                    | The `C-*` commit trailers written by `_audit-chain`                                        |
| `claude-hooks-sync-selftest`              | `claude-hooks-sync`, including the engage cross-check                                      |
| `claude-project-settings-render-selftest` | `claude-project-settings-render`, including the hooks merge                                |
| `install-preflight-selftest`              | `install.sh`'s toolchain quirk checks fire                                                 |
| `mandatory-checks-selftest`               | Every script in `mandatory-checks/` against its pass and fail fixtures                     |
| `ccw-watch-selftest`                      | `ccw-watch`                                                                                |
| `ci-watch-selftest`                       | `ci-watch` cannot show a cached result as live                                             |
| `vulnlib-selftest`                        | `vuln-scan`'s backport detection and cache freshness                                       |
| `github-agent-token-selftest`             | git's credential cache does not hand back an expired token                                 |
| `decided-selftest`                        | Every arm of `decided`                                                                     |
| `open-items-selftest`                     | `open-items` tells three kinds of "nothing" apart and finds the right drawer               |
| `open-items-xp-selftest`                  | The cross-project read side of `open-items`                                                |
| `pj-health-selftest`                      | Every arm of `pj-health`                                                                   |
| `pj-ping-selftest`                        | Every arm of `pj-ping`, with fake sound and message senders                                |
| `pj-session-end-selftest`                 | Every arm of `pj-session-end`                                                              |
| `pj-start-card-selftest`                  | Every arm of `pj-start-card`                                                               |
| `pj-worker-selftest`                      | Every arm of `pj-worker`, with fake herdr                                                  |
| `pj-wrap-selftest`                        | Every arm of `pj-wrap`, including push conflicts                                           |
| `zsh-claude-paneguard-selftest`           | `.zshrc`'s `claude()` herdr pane guard                                                     |
| `zsh-node-functions-selftest`             | `pnpm_update`'s deny list refuses                                                          |
| `zsh-welcome-selftest`                    | The welcome banner's pnpm-vs-nvm PATH check fires                                          |

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

Application settings exported for reference and manual import. Most are not
auto-deployed by the installer — `settings/iterm2/DynamicProfiles/` (symlinked)
and `settings/iterm2/prefs/` (offered, confirm-gated) are the exceptions.

#### `settings/iterm2/`

| File / Directory | Purpose                                                                                                                                                                                                                                                                                                                                     |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `prefs/`         | Full portable iTerm2 preferences: every profile, color scheme, font, key binding, pointer/ctrl-click binding, the Hotkey Window, and general prefs — the entire `com.googlecode.iterm2` macOS preferences domain in one sanitized, public-safe file. See `settings/iterm2/prefs/NOTICE.md` for its adapted-from-upstream attribution (MIT). |

`prefs/export.sh` (run manually, dev Mac only) captures this Mac's current
settings, strips volatile/machine-specific fields, and **refuses to write**
if it finds anything that still looks like a secret, token, or absolute home
path — review the diff before committing, same discipline as `git-leak-scan`.
`prefs/restore.sh` (standalone, or offered during `./install.sh` on macOS)
backs up whatever is currently set, then imports the repo's version. Both
require iTerm2 to be fully quit first.

#### `settings/wezterm/`

| File          | Purpose                                                                    |
| ------------- | -------------------------------------------------------------------------- |
| `wezterm.lua` | WezTerm config (Coolnight colors, SSH detection, keybindings, tab styling) |

### `docs/` - Documentation

Documentation and reference materials.

| File/Directory                        | Purpose                                                                                                                                                                                       |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AGENT_BRIEF.md`                      | Safe cross-agent interaction patterns and stow/branch-switching hazards for sibling-project agents                                                                                            |
| `CLAUDE_SESSION_ATTRIBUTION.md`       | Auto-stamp commits with C-Sess-Id / C-Web-Id / C-Branch / C-Worktree / C-Wt-Path trailers (SessionStart identity hook + \_audit-chain step); fresh-machine runbook, verification, and gotchas |
| `SECURITY.md`                         | Strict SSH posture rationale, alternative postures table, and drift-check commands                                                                                                            |
| `MEMENTO_vscode_machine_colors.md`    | Complete guide for VSCode/Cursor machine-specific color setup                                                                                                                                 |
| `ZED_MARKDOWN_FORMATTING.md`          | md-hardbreak: hard breaks / paragraph gaps / strip, Zed tasks + key bindings, and the rationale                                                                                               |
| `ZED_PREVIEW_CHANGELOG.md`            | Living record of Zed Preview UI / configuration / theme changes, plus the standing watch-items; refreshed via the SessionStart version check                                                  |
| `CLAUDE_CODE_SECURITY.md`             | Claude Code's own security surface — sandbox, permission modes, CVEs. Scope-stamped to a dated investigation; treat the version as history, not a currency claim                              |
| `CLAUDE_CODE_AND_PAI_INTERNALS.md`    | How `~/.claude/` is actually organised: the three-system model, project-path encoding, and the migration hazards when a repo moves                                                            |
| `CLAUDE_CODE_RESEARCH_NOTES.md`       | Living notes on researched Claude Code behaviour and mechanics (hook loading, permission modes, interactive quirks)                                                                           |
| `GH_AUTH_GUARD_USER_LEVEL.md`         | GitHub API read-only token plus the `gh` auth guard, user-level install                                                                                                                       |
| `NVM_SECURITY.md`                     | nvm / Node.js hardening: mirror pin, version floor, EOL policy, and GPG signature verification                                                                                                |
| `TOOLCHAIN_CVE_CHECK.md`              | `toolchain-cve-check`: are the pinned floors and the installed versions CVE-exposed? Cites historically vulnerable pins on purpose as negative controls                                       |
| `VULN_SCAN.md`                        | `vuln-scan`: incremental CVE scan of installed Homebrew formulae via NVD. Covers the Homebrew-revision false positive, the shell-safety cap, and the portable briefing file                   |
| `PNPM_SETUP_GUIDE.md`                 | pnpm setup: where pnpm reads config from, the kebab-case silent-failure trap, macOS vs XDG paths                                                                                              |
| `PNPM_AUDIT_TREE.md`                  | `pnpm-audit-tree`: recursive supply-chain auditor for pnpm / JS project trees                                                                                                                 |
| `PNPM_AUDIT_PREPUSH_HOOK.md`          | The global, opt-in pnpm-audit pre-push git hook                                                                                                                                               |
| `CI_WATCH.md`                         | `ci-watch`: the escalating, dismiss-only-by-fixing CI status line in the session dashboard                                                                                                    |
| `TOOLCHAIN_TAKEOVER_CONSENT.md`       | `toolchain-stocktake` + `project-impact-scan`: survey + disclose + gate before install.sh's Python/uv and pnpm/npm takeover lands on a foreign machine                                        |
| `IMSG.md`                             | `imsg`: send-only iMessage CLI. Covers the AppleScript injection trap, why the recipient is an argument in a public repo, and the Apple Events block inside Claude's Bash sandbox             |
| `PJ_PING.md`                          | `pj-ping`: the numbered attention signal. Message format, the id and its log, how to confirm which ping arrived and in what order, and the sandbox                                            |
| `HERDR.md`                            | herdr: the release cooldown, daemon persistence, speak-selection bindings, and the tmux comparison                                                                                            |
| `WHO_DENIED_THIS.md`                  | Which of five layers refused a command (our guards, this repo's hooks, Claude Code's built-in checks, permission rules, the sandbox), told apart by the message, and what to do for each      |
| `DELETION_SAFETY.md`                  | What routes a delete to the Trash and what does not: the `rm` shim, `safe-rm`, the agent guard's rules, and what none of them can see                                                         |
| `CLAUDE_HOOKS.md`                     | How a hook gets deployed and registered (`claude-hooks-sync`); the per-hook inventory is `.claude/hooks/README.md`                                                                            |
| `ZSH_HELPER_NAMESPACE.md`             | Why private shell helpers are named `__like_this`: Claude Code's shell snapshot drops single-underscore functions                                                                             |
| `DECIDED.md`                          | `decided`: why the decisions register exists, where it looks, and the 2026-09-21 split                                                                                                        |
| `OPEN_ITEMS.md`                       | `open-items`: the reasoning behind the tool (the flags are in `--help`)                                                                                                                       |
| `OPEN_ITEMS_CROSS_PROJECT.md`         | Open items across projects, and IDs unique across the machine: the 2026-09-23 rulings                                                                                                         |
| `OPEN_ITEMS_CROSS_PROJECT_SAFETY.md`  | The read-only safety review of the cross-project design, with its rules P1 to P12                                                                                                             |
| `PJ_HEALTH.md`                        | `pj-health`: what each check measures and what NOT MEASURED means                                                                                                                             |
| `PJ_PROFILES.md`                      | Session launch profiles, the three roots, and `c2`                                                                                                                                            |
| `PJ_TEMP_CLEANUP.md`                  | `pj-temp`: every session gets its own temp folder and empties it into the Trash                                                                                                               |
| `PJ_WRAP_UP.md`                       | `/pj:wrap-up`: rulings, the state contract and the rewrites                                                                                                                                   |
| `PROJECT_LIFEOS_BOUNDARY.md`          | What belongs to this repo and what to LifeOS: the 2026-09-19 plan and its execution log                                                                                                       |
| `MEMORY_INDEX_CAP.md`                 | The per-project memory index cap, and why `CLAUDE_MEMORY_STORES` stays off                                                                                                                    |
| `REDTEAM_20260928_RULINGS.md`         | Gavin's rulings on the gaps the 2026-09-28 red team found                                                                                                                                     |
| `GITHUB_AGENT_USAGE.md`               | The GitHub App credential system: how it works, every flag, what lives where (real values are in a private companion)                                                                         |
| `GITHUB_AGENT_RECIPES.md`             | Step-by-step recipes for the GitHub App system; the reference is `GITHUB_AGENT_USAGE.md`                                                                                                      |
| `GITHUB_CREDENTIAL_LANES.md`          | Every GitHub credential on this machine, what each can do, and what is still open                                                                                                             |
| `AGENTIC_CODING_SECURITY_RESEARCH.md` | Research dossier on git/GitHub authentication and on securing a coding agent with real repository access                                                                                      |
| `HERDR_AGENT_SKILL.md`                | herdr for agents, group A: read before issuing any `herdr` command                                                                                                                            |
| `HERDR_AGENT_AUTOMATION.md`           | herdr for agents, group B: automation                                                                                                                                                         |
| `HERDR_PLUGINS.md`                    | herdr for agents, group C: plugins                                                                                                                                                            |
| `attic/`                              | Code removed on purpose, kept for reading. Nothing here runs, and it sits outside `home/` so stow never links it back                                                                         |
| `lexer-comparison/`                   | Comparison of the three shell lexers in `home/.claude/hooks/`, with the case table and the script that runs it                                                                                |
| `trash-guard/`                        | Brief, progress log and report from building the machine-wide trash guard (2026-09-29)                                                                                                        |
| `comms/`                              | Dated outbound notes to peer agent projects (CONVENTION.md spec v1.15; read on-demand only — see `comms/README.md` for the index; contents are NOT enumerated here by design)                 |
| `reference/colors.md`                 | Color palette reference                                                                                                                                                                       |
| `reference/mermaid_examples.md`       | Mermaid diagram examples                                                                                                                                                                      |
| `reference/tmux_cheatsheet.md`        | Tmux quick reference guide                                                                                                                                                                    |
| `reference/pai_memory_system.md`      | How Claude remembers across conversations, projects and sessions — the memory and persistence mechanisms, written as a read-at-leisure explainer                                              |
| `reference/windows/`                  | Historical Windows batch scripts (reference only, not for deployment)                                                                                                                         |

**Hook documentation lives outside `docs/`** — and since 2026-09-21 there is exactly **one**
file, not two:

- [`.claude/hooks/README.md`](../.claude/hooks/README.md) — the **living inventory** and the
  only hook document. One section per shell hook, and the doc the root README links to.
  Keep this one current. Machine-wide travel (which hooks reach a `pj` session in other
  projects) is declared in [`settings/claude/hooks.json`](../settings/claude/hooks.json)
  via each entry's `targets`.

`.claude/docs/HOOKS_ARCHITECTURE.md` was **deleted on 2026-09-21** (W-20260921-A11). Do not
look for it, and do not recreate it. It is worth knowing why, because the obvious fix was
tried first and failed:

- On **2026-07-30** its per-hook inventory was retired — it had fallen four months behind
  and covered 5 of 14 hooks — leaving it as "architecture only" so the two docs would stop
  competing. Its architecture content was re-verified against the code that same day.
- By **2026-09-21** the rump had drifted anyway. At 1647 lines it still named
  `pre-commit-check.sh` (retired) in six places and `export_transcript.sh` (deleted
  2026-08-18) in one, and its file tree and `settings.json` excerpt predated the three
  travelling guards.

**Splitting a document by "inventory vs architecture" does not stop drift. It moves the
drift into the half nobody audits.** One document, audited, or none.

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

| Repository Location                                                     | Deployment Location                                                                 |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `home/.zshrc`                                                           | `~/.zshrc`                                                                          |
| `home/.zsh_*`                                                           | `~/.zsh_*`                                                                          |
| `home/.tmux.conf`                                                       | `~/.tmux.conf`                                                                      |
| `home/.p10k.zsh`                                                        | `~/.p10k.zsh`                                                                       |
| `home/.config/direnv/direnv.toml`                                       | `~/.config/direnv/direnv.toml`                                                      |
| `home/.config/direnv/direnvrc`                                          | `~/.config/direnv/direnvrc`                                                         |
| `home/.config/yazi/`                                                    | `~/.config/yazi/`                                                                   |
| `home/.config/zed/settings.json`                                        | `~/.config/zed/settings.json`                                                       |
| `home/.config/yt-dlp/config`                                            | `~/.config/yt-dlp/config`                                                           |
| `home/.config/herdr/config.toml`                                        | `~/.config/herdr/config.toml`                                                       |
| `home/.config/lazygit/config.yml`                                       | `~/.config/lazygit/config.yml`                                                      |
| `home/.config/zshrc/color-profiles.json`                                | `~/.config/zshrc/color-profiles.json`                                               |
| `home/.config/zshrc/init-vscode-project-settings.sh`                    | `~/.config/zshrc/init-vscode-project-settings.sh`                                   |
| `home/.config/uv/uv.toml`                                               | `~/.config/uv/uv.toml`                                                              |
| `platforms/macos/Library/Application Support/Cursor/User/settings.json` | `~/Library/Application Support/Cursor/User/settings.json`                           |
| `platforms/macos/Library/Application Support/Code/User/settings.json`   | `~/Library/Application Support/Code/User/settings.json`                             |
| `settings/iterm2/DynamicProfiles/`                                      | `~/Library/Application Support/iTerm2/DynamicProfiles/` (symlinked by `install.sh`) |
| `settings/` (everything else)                                           | Manual import (not auto-deployed)                                                   |

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
