# install.sh profiles, skip flags and unattended runs

Gavin's design, decided on the codebox build (Q24, 2026-10-10): every optional part of
`install.sh` has a skip flag; without the flag the part asks its yes/no question as it
always did. On top of that sit named profiles and a no-questions mode. First profile:
`codebox`.

```
./install.sh --profile codebox              # the named bundle
./install.sh --profile codebox --dry-run    # what it would do, no prompt, nothing changed
./install.sh --no-questions --skip-tmux     # any flag can be combined with any action
```

## The three modes

| Flag             | What it does                                                                                                                                                                                                                                                                                 |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--no-questions` | Every yes/no prompt takes its **recorded** answer and never reads stdin. A typed gate (the toolchain takeover) is always declined: nobody typed the word.                                                                                                                                    |
| `--no-sudo`      | A command that starts with `sudo` is printed as `[no-sudo] NOT run` and skipped, exactly as `--dry-run` treats it, so a user without sudo gets a full run with no password prompt and no abort. The closing summary lists every command root still owes. Nothing escalates by another route. |
| `--profile NAME` | A named bundle of the flags below, applied **before** the flags typed on the line. A typed flag can add a skip; nothing typed can take a profile's skip away (the flags are one-way switches, so a profile's promises stay simple). `--profile none` means, and records, no profile.         |

### A profile describes the box, so it persists

A good stow records its profile in `~/.local/state/dotfiles/links/profile` and the
names it left out of stow in `links/stow-skip` (one basename per line; empty when
nothing was skipped, which is a positive answer, not an absent file). Then:

- A later run with **no profile and no skip flags typed** (`./install.sh --update`,
  `--stow-only`, a bare `./install.sh`) re-applies the stored profile and says so on
  its first line. Without this, the first plain `--update` on codebox would have
  stowed `~/.claude`.
- `--profile none` clears the stored profile. A run that types bare skip flags uses
  only what it typed, for that run, and leaves the stored profile as it was.
- The welcome banner's deploy-parity line and `deploy-parity-check` both read
  `stow-skip`, so a skipped tree is never reported as "NOT linked" at login.
  `install.sh` passes its own list to the checker (`DOTFILES_STOW_SKIP`) during a
  run, so a run's flags win over the file while it runs.

### Where the no-questions answers live

`confirm PROMPT [DEFAULT] [NO_QUESTIONS_ANSWER]`. The third argument records what an
unattended run answers, next to the question itself, so every decision taken on the
operator's behalf is reviewable in one grep:

```
grep -n 'confirm ".*" [yn] [yn]' install.sh
```

The rule used to record them: an install the dotfiles depend on (uv, Python 3.13, nvm,
Node, pnpm, bun, the core tools) answers **yes**; anything that removes, replaces or
reaches outside this repo's remit (EOL Node removal, the brew sweep, the pnpm-audit
git hook, iTerm2 preferences) keeps the safe **no**. A prompt with no third argument
answers its interactive default, and the log line `[no-questions] <prompt> -> yes|no`
says which.

## Skip flags

| Flag                     | Leaves out                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--skip-claude`          | `home/.claude` (not stowed), Claude hook registration, the pj settings render, the pj machine letter, the pj prerequisites report. Also records `DOTFILES_PLAIN_CLAUDE=1` in `~/.zshrc.private.early`, which makes `home/.zshrc` leave its `claude()` pane guard and the `c` signpost undefined: on a box without `~/.claude`, engage or pj, the guard would refuse every bare `claude` and point at a launcher that does not exist. |
| `--skip-ssh`             | `home/.ssh` (not stowed).                                                                                                                                                                                                                                                                                                                                                                                                            |
| `--skip-system-packages` | The package-manager installs: the apt/dnf/pacman/zypper core and optional tool lists, and the Homebrew formula lists. Everything the user can install without root (uv, nvm, pnpm, bun, herdr's release, lazygit, glow, Oh My Zsh) still runs.                                                                                                                                                                                       |
| `--skip-tmux`            | `home/.tmux.conf`, `home/.zsh_tmux` (not stowed), TPM.                                                                                                                                                                                                                                                                                                                                                                               |
| `--skip-docker`          | `home/.zsh_docker_functions` (not stowed), lazydocker (becomes optional in the prerequisite check).                                                                                                                                                                                                                                                                                                                                  |
| `--skip-rust`            | rustup.                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `--skip-yazi`            | yazi.                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `--skip-fonts`           | The Nerd Font.                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `--skip-git-hooks`       | The pnpm-audit pre-push hook (`core.hooksPath` in `~/.gitconfig.private`).                                                                                                                                                                                                                                                                                                                                                           |
| `--skip-git-identity`    | The `user.name` / `user.email` prompt.                                                                                                                                                                                                                                                                                                                                                                                               |
| `--skip-nvm`             | nvm and the default Node.                                                                                                                                                                                                                                                                                                                                                                                                            |
| `--skip-pnpm`            | The standalone pnpm.                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `--skip-bun`             | bun.                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `--skip-uv`              | uv and Python 3.13 (both become optional in the prerequisite check).                                                                                                                                                                                                                                                                                                                                                                 |
| `--skip-herdr`           | herdr: install, Linux release pin, systemd unit, plugin link, skill link.                                                                                                                                                                                                                                                                                                                                                            |
| `--skip-omz`             | Oh My Zsh, its plugins and Powerlevel10k.                                                                                                                                                                                                                                                                                                                                                                                            |

The stow skips (`claude`, `ssh`, `tmux`, `docker`) are one list, `_stow_skip_names`, read
by four things so they cannot disagree: the `--ignore` arguments stow is given, the
conflict check, the link manifest (`~/.local/state/dotfiles/links/current.tsv`) and the
parity checker (`DOTFILES_STOW_SKIP`, colon-separated basenames). Stow's `--ignore` is a
Perl regex against the **basename**: `--ignore='^\.claude$'` dropped every link under
`.claude` and never descended into it, while the slash-anchored `^/\.claude$` ignored
nothing (measured with stow 2.4.1, 2026-10-10, with `.zshrc` still linking as the
control).

## Profile `codebox`

Gavin's throwaway Claude Code box: VM 205, Ubuntu 24.04, user `codeuser` with **no sudo**,
GitHub over HTTPS only (tcp 22 is blocked), plain Claude Code with none of Gavin's hooks
or skills (Q17), herdr only, no tmux (Q18), no Docker (Q16). Plan and decisions:
`Network_Plan/docs/plans/2026-10-10-codebox-throwaway.md`.

```
--profile codebox  =  --no-questions --no-sudo
                      --skip-claude --skip-ssh --skip-system-packages
                      --skip-tmux --skip-docker --skip-rust --skip-yazi
                      --skip-fonts --skip-git-hooks
```

**Root installs first** (the box's golden script,
`Network_Plan/boxes/codebox-vm-205/scripts/golden-system.sh`): zsh (and `chsh` for the
user), stow, jq, trash-cli, fzf, zoxide, direnv, plus git, curl, ripgrep, fd, bat, eza,
tree, git-lfs, gh, glow. trash-cli is the one that matters: the stowed `~/.local/bin/rm`
routes every delete through `trash-put` and refuses without it, and `install.sh` counts
`trash-put` as a required Linux prerequisite. jq is required too, and
`--skip-system-packages` means the profile cannot add it: on a box where root forgot it,
the run stops at "still missing" by design. Ubuntu's `fd-find` gets its `fd` name
(`~/.local/bin/fd`) from the profile run itself, outside the apt step.

**The profile installs as the user:** uv + Python 3.13, nvm `NVM_MIN_VERSION` + Node
`NODE_DEFAULT_VERSION` (set as default), the standalone pnpm with the stowed cooldown
config, bun, herdr `HERDR_VERSION` from its pinned, sha256-verified Linux release to
`~/.local/bin`, Oh My Zsh + the three plugins + Powerlevel10k, lazygit (GitHub release to
`~/.local/bin`). Then it stows `home/` minus the skipped names, enables the herdr systemd
user unit, applies the npm guard to the new Node, adds the two marked blocks to
`~/.zshenv`, and records `DOTFILES_PLAIN_CLAUDE=1`.

**It does not:** install Claude Code (nothing in `install.sh` ever does; the summary only
points at the docs), touch git's remote URLs (the SSH `insteadOf` rewrites live only in
`~/.gitconfig.private`, which is never stowed), or run anything as root.

**Known on codebox:** the stowed `~/.gitconfig` sets `core.editor = cursor --wait` and
resets credential helpers to empty above its `[include]` of `~/.gitconfig.private`, so a
helper or editor set in the private file wins; one set anywhere above it would be wiped.

**First-shell noise on a box without sudo.** The onboarding check (`run_onboarding`, first
interactive shell) used to offer `sudo apt-get install` for every missing optional tool
and wait on a y/N, which no user without sudo can answer usefully, and zsh prints that
prompt on stderr. It now detects a user who cannot sudo (not root, not in `sudo`, `wheel`
or `admin`) and prints the command for an admin instead of asking. The `uv cooldown`
staleness warning in `.zshrc` still goes to stderr when stderr is a terminal; that one is
load-bearing (the cutoff must be bumped by hand) and stays. `LC_ALL=en_AU.UTF-8` falls
back to `C.UTF-8` on a Linux box where that locale is not generated, so perl and gettext
tools stop printing `setlocale` warnings; root can `locale-gen en_AU.UTF-8` instead.

## Two bugs this work fixed for every Ubuntu box

- `glow` was on the apt core-tools line. It is not an Ubuntu 24.04 package, and apt fails
  the whole command on one unknown name, so none of the core tools installed on plain
  Ubuntu. glow now comes from its GitHub release into `~/.local/bin` (Linux only; macOS
  keeps the formula).
- lazygit was installed with `sudo install ... /usr/local/bin`. It now goes to
  `~/.local/bin`, so a user without sudo gets it and the `--no-sudo` run has nothing to
  skip there.

And one gap: `install.sh` installed nvm and never a Node, so a fresh box had `nvm` and
no `node` until someone ran `nvm install` by hand. After nvm is present it now installs
`NODE_DEFAULT_VERSION` and sets it as default when nvm holds no Node at all; an existing
Node is never touched.

## Installers that edit shell rc files

Once stow has run, `~/.zshrc` is `home/.zshrc` in this repo, so an installer that
appends to it pollutes tracked source. nvm's installer is run with `PROFILE=/dev/null`
and uv's with `INSTALLER_NO_MODIFY_PATH=1`; the stowed `.zshrc` already sets PATH for
both. bun and pnpm offer no such switch and look for their own lines first; after
`post_install`, `_rc_pollution_check` reports any change to the repo's rc files rather
than assuming. Reported, never reverted: the diff may be yours.

## What a dry run can and cannot show

`--dry-run` always declines a prompt (the branches behind a prompt are not all dry-run
safe) and prints what the real run would answer: at the prompt, by default with no
terminal, or by the recorded no-questions answer. So an unattended install shows as
`[dry-run] Would ask: uv not found. Install it? -- a real run would go ahead
(no-questions answer: yes)`, not as the `curl` it would run. The stow step is the
exception: a dry run prints stow's own `-v2` plan (`stow -n` prints nothing at default
verbosity, CLAUDE.md), so the LINK, UNLINK and MKDIR lines are listed.
