# Cross-Platform Zsh Development Environment

![Shell](https://img.shields.io/badge/Shell-Zsh-lightgrey.svg?logo=gnome-terminal&logoColor=white)
![Python with uv](https://img.shields.io/badge/Python-uv-hotpink.svg?logo=python&logoColor=white)
![Node.js with nvm](https://img.shields.io/badge/Node.js-nvm%20%2B%20pnpm%2Fbun-green.svg?logo=nodedotjs&logoColor=white)
![Docker](https://img.shields.io/badge/Tools-Docker-blue.svg?logo=docker&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude-Code-blueviolet.svg?logo=anthropic&logoColor=white)
![OS Support](https://img.shields.io/badge/OS-macOS%20%7C%20Linux%20%7C%20WSL-blue.svg?logo=apple)

My Zsh dotfiles. One install gives you the same shell on **macOS, Linux and Windows (via WSL)**, built around `uv`, `pnpm`/`bun`, `direnv` and GNU Stow.

---

## Overview and history

I created this repo because I kept losing my shell setup. Not dramatically, no hard drive failures or anything, just the slow erosion that happens when you set up a new machine, SSH into a Linux box, or spin up a WSL instance and realise you can't remember how you had things configured last time. Every time, I'd spend a day or two getting my terminal back to "normal," swearing I'd write it down this time, and then not writing it down.

The first commit was just a `.zshrc` with some Python virtual environment helpers. I'd switched to `uv` and kept forgetting the incantations for setting up a new project with direnv, so I wrapped them in a function. Then I wrapped a few more things. Then I added Node.js scaffolding because I was tired of the same twenty minutes of boilerplate every time I started a TypeScript project. You can see where this is going.

At some point it stopped being a dotfiles backup and became something closer to an operating philosophy for how I want to work. I have two GitHub accounts and a couple of machines / VMs, and I needed all of them to feel the same. Same aliases, same git identity routing, same safety rails, same muscle memory. One `./install.sh` on a fresh box and I'm home.

A lot of what's in here exists because I got burned. The `rm` wrapper exists because I deleted a symlink target once when I meant to delete the link. The `gh auth` blocker exists because GitHub's credential helper silently broke my SSH-only setup twice before I caught it. The npm/yarn interceptors exist because a stray `npm install` in a pnpm project creates a `package-lock.json` that ghosts you for hours. Every guardrail in this repo is a scar from a past mistake, turned into a rule so I never make it again. I am not a fast learner but I am a stubborn one.

The system is built around GNU Stow, which symlinks everything from one directory into your home folder. The `home/` directory mirrors `~/` exactly, so what you see in the repo is what you get on disk. The installer handles the rest: prerequisites, Oh My Zsh plugins, nvm, pnpm, bun, Nerd Fonts, tmux plugin manager, git identity. All interactive, all idempotent, all skippable if you already have your own setup for something.

If you just want the shell functions without the full install, you can symlink individual files. But the real value is in having all the pieces wired together: direnv auto-activating environments, tmux windows naming themselves after git branches, per-machine colour profiles so you know at a glance whether you're on your laptop or SSHed into something else. It's the kind of thing that sounds like overkill until you've used it for a week and can't go back.

---

## What you get

- **One shell everywhere.** macOS, Linux and WSL, with the OS differences handled for you.
- **Project scaffolding.** `python_new_project 3.13` gives you a working Python project, git and all. `node_new_project` does the same for TypeScript, minus the git.
- **Environments that switch themselves.** direnv activates the Python venv when you `cd` in, and nvm follows `.nvmrc`.
- **Guardrails.** `rm` goes to the Trash. `npm`, `pip` and bare `python` refuse and tell you the `pnpm` or `uv` command instead. `gh auth login` is blocked so it can't wreck SSH auth.
- **Docker helpers.** One-liners for Postgres, Qdrant and Jupyter.
- **Colour per machine.** VS Code and Cursor tint their title bar by machine, so you know which box you're on. The profiles are tuned to my machines, so expect to adjust them.
- **Claude Code wiring.** Launchers, safety hooks and commit attribution for when an agent is doing the typing.

---

## Read this before you install: `rm` goes to the Trash

This is the most opinionated thing in here and it touches your whole machine, so decide about it on purpose.

On a machine running these dotfiles, `rm` doesn't delete. It moves things to the Trash, and you get them back with **Put Back** in Finder (macOS) or `trash-restore` (Linux).

Most "safe rm" setups are a shell alias, which only covers what you type. Every script, every `make clean`, every `xargs rm` sails straight past and deletes for real. When I tested mine, `xargs rm` destroyed a test file while the "protection" was fully installed. So this one goes further:

| Piece                                                       | Covers                                               |
| ----------------------------------------------------------- | ---------------------------------------------------- |
| `rm()` shell function                                       | what you type                                        |
| `~/.local/bin/rm`, a real command ahead of `/bin` on `PATH` | scripts, `xargs`, `find -exec`, `make`, agent shells |
| `sudo()` wrapper                                            | `sudo rm`, re-run as you so it lands in _your_ Trash |

It still can't reach anything that calls `/bin/rm` by its full path, or runs with its own `PATH`, like cron jobs, launchd and Docker.

All three end at [`safe-rm`](home/.local/bin/safe-rm). It never unlinks anything, and it needs a `trash` command to work. Without one it refuses every delete and exits non-zero, because quietly falling back to a real delete is the one thing a safety net must never do.

It also refuses deletes that nothing else refuses: your home folder, system folders, the folder you're standing in, any git repository outside a temp folder, and emptying `~/Downloads`, `~/Desktop`, `~/Documents` or `~/CODE` in one command. That git rule surprises people. `rm -rf oldproject` on a checkout gets refused.

**What it costs you.** Your Trash fills up with build output, and disk space doesn't come back until you empty it. Deleting a huge tree is slower too, because moving isn't the same as unlinking. I took that trade on purpose.

**Getting out of it.** `/bin/rm ...`, typed by its full path, deletes for real. That is the only way: there is no environment switch (an older `SAFE_RM_OFF=1` was removed, and setting it now changes nothing). `command rm` and `\rm` also go to the Trash.

**Don't want it?** The installer has no switch for this, so leave `home/.local/bin/rm` out when you stow. You keep the Trash for what you type and for `sudo rm`, and scripts go back to deleting for real.

**What it isn't.** A backup. `> file`, `git clean`, `git reset --hard`, `rsync --delete` and a dying SSD never go near `rm`. Keep real backups.

Run `safe-rm-selftest` after you change anything in the delete chain. The full story, including what was measured and what can't be covered, is in [`docs/DELETION_SAFETY.md`](docs/DELETION_SAFETY.md).

---

## Install

```bash
git clone https://github.com/CaptainCodeAU/fifty-shades-of-dotfiles.git ~/fifty-shades-of-dotfiles
cd ~/fifty-shades-of-dotfiles
./install.sh
```

The installer finds your package manager (Homebrew, apt, dnf, pacman or zypper), installs Homebrew on a Mac if it's missing, and offers everything else. It sorts out the quirks too, like `fd` being called `fdfind` on Debian.

Rather install the Mac tools yourself first? This is the core set:

```bash
brew install stow uv direnv jq zoxide eza fzf tmux ripgrep fd gh git-lfs neovim glow aria2 ffmpeg herdr lazygit lazydocker
brew install --cask font-symbols-only-nerd-font
```

`rm` needs a real trash command: macOS 15 and later ship `/usr/bin/trash`, and that is the only one used (don't `brew install trash`, it's a different tool). On Linux, install `trash-cli`. `herdr` is the terminal multiplexer I use for coding agents. Optional extras: `brew install tree fastfetch yazi`.

### What it will ask you

It asks before most steps. A few you'll want to know about:

- **Existing dotfiles.** Before Stow runs, it lists any files in the way and offers to move them into `~/dotfiles-backup/`. The default answer is yes. Say no and it stops, so you can deal with them yourself or re-run with `--force`.
- **Your Python and Node setup.** If it finds one already (pyenv, conda, npm globals and so on), it tells you what it found, writes a report on which of your projects would be affected, and makes you type a real word before handing Python to `uv` or blocking `npm`. Say no and your existing `python` and `npm` keep working. The install carries on, and pnpm still gets installed alongside. On a machine with nothing of its own, it just goes ahead. See [`docs/TOOLCHAIN_TAKEOVER_CONSENT.md`](docs/TOOLCHAIN_TAKEOVER_CONSENT.md).
- **"Which machine is this?"** That's for my four machines and my project tooling. Press Enter to skip it.

On a machine without my private repos, the install finishes with a red "pj is not ready" banner and exit code 3. That's expected. See [Claude Code](#claude-code).

| Command                    | Does                                                                                                                          |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `./install.sh --check`     | checks everything, changes nothing                                                                                            |
| `./install.sh --update`    | pulls and restows. If a file is in the way it stops before removing any link, and if linking fails it puts the old links back |
| `./install.sh --stow-only` | just links the files, and registers any new Claude hooks                                                                      |
| `./install.sh --force`     | adopts your existing files into the repo with `stow --adopt`, overwriting the repo's copies. Check `git diff` afterwards.     |
| `./install.sh --uninstall` | removes the symlinks only. Tools stay installed and nothing comes back from `~/dotfiles-backup/`.                             |
| `./install.sh --dry-run`   | shows what it would do (combine with anything)                                                                                |

If your links ever vanish (an interrupted install, say), `sh ~/.local/state/dotfiles/links/restore` puts the last good set back from any terminal. It needs none of the dotfiles, moves anything in the way aside, and deletes nothing. `sh ~/.local/state/dotfiles/links/restore check` just reports. On macOS a small watcher also tells you within seconds when links go missing.

Rather wire it up by hand? Every file in `home/` goes to the same place under `~/`, so `ln -s` works. You'll miss what the installer does after linking, like the platform files and the Claude hook registration. [`docs/STRUCTURE.md`](docs/STRUCTURE.md) has a longer map.

---

## Your private settings

Secrets don't belong in this repo. Anything personal goes in files that stay on your machine.

| File                     | For                                                                                         |
| ------------------------ | ------------------------------------------------------------------------------------------- |
| `~/.zshrc.private`       | aliases, `PATH` additions, anything machine-specific. Read last, so it wins.                |
| `~/.zshrc.private.early` | the few switches startup reads before the late file loads, like `_ONBOARDING_COMPLETE=true` |
| `~/.gitconfig.private`   | your git name and email, plus account routing                                               |

`.gitignore_global` keeps `~/.zshrc.private` and `~/.gitconfig.private` out of commits.

One thing I'd steer you away from: exporting API tokens here. Anything you export, every program you run can read.

---

## GitHub: SSH by default

Git talks to GitHub over SSH. The shared `.gitconfig` wipes any credential helper it inherits, Xcode's keychain one for example, so a token can't get cached behind your back. Out of the box an HTTPS push has nothing to sign in with, and fails.

`gh auth login`, `gh auth setup-git` and `gh auth refresh` are blocked, because they quietly add an HTTPS helper back. `gh auth login --git-protocol ssh` still works.

Two accounts work like this. Each one gets a key, an SSH host alias, and a small identity file:

```ini
# ~/.ssh/config.local (the shipped ~/.ssh/config includes it)
Host git-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/work

# ~/.ssh/gitconfig-work
[user]
    name = Work Name
    email = you@company.com
[core]
    sshCommand = ssh -i ~/.ssh/work

# ~/.gitconfig.private
[user]
    name = Your Name
    email = you@example.com
[includeIf "gitdir:~/WORK/"]
    path = ~/.ssh/gitconfig-work
[url "git-work:WorkOrg/"]
    insteadOf = https://github.com/WorkOrg/
```

Now a repo under `~/WORK/` commits as work-you with the work key, and everything else commits as you. `ssh -T git-work` should greet you by your work username.

Keep the `insteadOf` rewrites scoped to your own accounts. A blanket rewrite of `https://github.com/` breaks `brew update` and every anonymous clone.

There's one opt-in exception. `github-agent-flip` moves a single repo onto a GitHub App that hands out short-lived tokens. The wipe sits above the line that loads your private file, so a helper you add there on purpose survives it. Nothing moves over on its own. See [`docs/GITHUB_AGENT_USAGE.md`](docs/GITHUB_AGENT_USAGE.md).

SSH hardening and the reasoning behind it are in [`docs/SECURITY.md`](docs/SECURITY.md).

---

## Day to day

### Python

```bash
mkdir my-app && cd my-app
python_new_project 3.13      # git, uv venv, pyproject, tests, .envrc (with direnv), first commit

python_setup 3.13 api        # existing project: fresh .venv, the project plus its dev and api extras
python_delete                # .venv, .envrc, caches and build output go to the Trash; code and uv.lock stay
```

The installer puts Python 3.13 on the machine. For another version, run `uv python install 3.12` first.

If your project defines a command, `uv_tool_install_current_project --no-extras` (or name the extras you want) puts it on your `PATH`. Run it with the project's venv active. It's editable by default, so your edits show up straight away. Pass `--frozen` when a git hook or cron job runs the command, so a half-saved file can't break it, then reinstall with `--frozen` to pick up changes. A project can pin that choice in `pyproject.toml` with `[tool.uv-tool] install-mode = "frozen"`. Only these functions read it, not uv itself.

### Node

```bash
node_new_project             # TypeScript, asks pnpm or bun (--pnpm / --bun to skip, --no-ts for JS)
node_setup                   # existing project: .nvmrc's Node version, pnpm or bun from the lockfile, install
node_info                    # versions, scripts, link status
node_clean                   # node_modules, builds, caches and the lockfile go to the Trash
```

In your shell, `npm` and `yarn` refuse and tell you the pnpm or bun command, and `npx` points you at `pnpm dlx` or `bunx`. That's not because they're bad. Two package managers in one project fight over lockfiles and waste your afternoon. Scripts and Makefiles still reach the real tools.

### Docker

`pg_dev_start`, `qdrant_start`, `jupyter_start`, and `dev_stack_start web|ai|full` for the lot. `docker_help` lists everything else.

### The small stuff

- `yt <url>` downloads video or audio. It runs yt-dlp through `uvx`, so it's always current and never installed. `yt --help` shows the options.
- `l` and `ll` are `eza` listings, `lg` is lazygit, and `cd` is zoxide.
- `pip install` refuses and tells you the `uv add` command. Editable installs and read-only `pip` commands go through `uv pip`. Bare `python` refuses and points you at `uv run`.
- `cp` and `mv` ask before overwriting.
- The welcome banner shows everything by default. Set `ZSH_WELCOME=minimal` or `none` in `~/.zshrc.private` to shrink or hide it.
- `~/.config/zshrc/init-vscode-project-settings.sh -r` (or `-p <name>`) gives a project its own VS Code colours, from ten profiles in `color-profiles.json`.
- iTerm2 users: `settings/iterm2/prefs/` holds my entire iTerm2 setup in one sanitised file. On a Mac with iTerm2 the installer offers to restore it, and backs yours up first.
- Zed users: `md-hardbreak` fixes line breaks in the Markdown preview by editing the source, and `--strip` undoes it. See [`docs/ZED_MARKDOWN_FORMATTING.md`](docs/ZED_MARKDOWN_FORMATTING.md).

---

## Claude Code

The dotfiles also carry some wiring for Claude Code. Most of it is built around my setup, so read it before you lean on it.

- **Launchers.** `home/.zsh_claude_launch` holds the one launch function. It starts Claude Code with a throwaway SSH agent that holds my GitHub key (`~/.ssh/captaincodeau`) for that session only, and sets a few environment variables for the `claude` process alone. Without that key file it starts with no agent. My `engage` launcher (a separate repo) and the `ci` alias (piped, non-interactive, skips permission prompts) both go through it. `c` on its own starts nothing and prints a menu of my other launchers. The other `c` aliases were retired on 2026-10-06. [`docs/CLAUDE_LAUNCH_ENV.md`](docs/CLAUDE_LAUNCH_ENV.md) lists every variable the launch sets and why.
- **Hooks.** `home/.claude/hooks/` has guards that block the common ways an agent's Bash commands could permanently delete files or print a secret into its transcript. When jq is installed and `~/.claude/settings.json` exists, the installer registers them there without asking, along with a few of my personal hooks. The list is in `settings/claude/hooks.json`, and [`docs/CLAUDE_HOOKS.md`](docs/CLAUDE_HOOKS.md) explains how it works.
- **Commit attribution.** Turn on the global git hooks (the installer offers them as the pnpm-audit pre-push hook) and a commit made inside a Claude session gets stamped with the session it came from. See [`docs/CLAUDE_SESSION_ATTRIBUTION.md`](docs/CLAUDE_SESSION_ATTRIBUTION.md).
- **Language servers.** `uv tool install pyright` and `pnpm add -g typescript-language-server typescript`, then enable the `pyright-lsp` and `typescript-lsp` plugins in Claude Code. The installer does neither.

The `.claude/` folder at the top of this repo is this repo's own setup, not something to copy into yours. Some of it only makes sense here.

If you've seen `pj` mentioned around the place, that's my project launcher. It needs two private repos you won't have, so you can ignore it, and the red banner at the end of the install. For future me, it's all in [`docs/PJ_PROFILES.md`](docs/PJ_PROFILES.md).

---

## What's where

```text
fifty-shades-of-dotfiles/
├── install.sh        the installer
├── home/             mirrors ~/ exactly: .zshrc, the function files, .config/, .local/bin/, .claude/
├── platforms/        per-OS files (Cursor and VS Code settings on macOS)
├── settings/         app exports (iTerm2, WezTerm) and the Claude Code hook list
├── docs/             the long versions of everything above
├── .claude/          this repo's own Claude Code setup, not for copying
└── CLAUDE.md         instructions for agents working in this repo
```

[`docs/STRUCTURE.md`](docs/STRUCTURE.md) is a longer map. When anything here disagrees with the code, the code wins.

---

## FAQ

**Can I use parts of this without installing everything?**

Yeah. Each function file (`.zsh_python_functions`, `.zsh_node_functions`, etc.) can be symlinked individually and sourced from your own `.zshrc`. Some of them reference shared helpers defined in the main `.zshrc`, so you might need to grab a function or two, but there's no "all or nothing" requirement. The installer is the easy path, not the only path.

**Will this nuke my existing dotfiles?**

No. Before Stow runs, the installer scans your home directory for clashes. If it finds a real file where it wants a symlink, it lists them and offers to move them into `~/dotfiles-backup/`. Say no and it stops, so you can sort them out yourself or re-run with `--force`, which adopts your versions into the repo. Stow itself also refuses to overwrite a real file, so that's two layers before anything gets touched.

**Will it also mess with my existing Python or Node setup?**

Not without asking. If the installer finds a Python or Node setup of your own, it tells you what it found, writes a report on which projects would be affected, and asks. You have to type a real word to say yes, and saying no keeps your existing `python` and `npm` working.

**Why GNU Stow instead of chezmoi / yadm / a bare git repo?**

Stow is dumb in the best way. It makes symlinks. That's it. No templating language, no special commands to remember, no database of managed files. The repo structure mirrors your home directory exactly, so you can see what goes where just by looking at the file tree. I tried fancier tools and kept fighting them. Stow gets out of the way.

**Why uv? Why pnpm and bun? Why not [thing I'm already using]?**

These are my opinions, not universal truths. `uv` is absurdly fast and replaces pip, pip-tools, virtualenv, and pyenv in one binary. pnpm and bun are both faster and stricter than npm, and bun doubles as a runtime. If you disagree, the wrappers are easy to find and easier to delete.

**Does this work on my machine?**

If you're running zsh on macOS, Ubuntu/Debian, Fedora, Arch, openSUSE, or WSL, probably yes. It does not support bash or fish. It's zsh all the way down, and converting it would be a different project entirely.

**How do I update after pulling new changes?**

`./install.sh --update` pulls and restows. New files get linked and existing links stay put. If a pull brings new Claude hooks, run `./install.sh --stow-only` as well, which registers them. If you've edited a symlinked file, you've edited it in the repo too, because that's how symlinks work. Which is either a feature or a footgun depending on your perspective.
