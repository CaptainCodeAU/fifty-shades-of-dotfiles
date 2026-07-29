# herdr — release cooldown, daemon persistence, and the tmux question

[herdr](https://github.com/ogulcancelik/herdr) is an agent multiplexer: a terminal
UI that runs several AI coding agents side by side in real panes, with a status
column showing which are working, blocked or done. Single Rust binary, sessions
detach and reattach, including over SSH.

It is adopted here under the same supply-chain rules as everything else — which
takes deliberate work, because herdr is the one tool in this estate that can move
on its own. This document covers the cooldown machinery, how to run it as a
persistent server, and where it overlaps with tmux.

## Why it exists

The [release-cooldown posture](SECURITY.md) is that nothing ships into this estate
on the day it is published. Every other tool has a native knob for that:

| Tool           | Native cooldown mechanism          |
| -------------- | ---------------------------------- |
| pnpm           | `minimumReleaseAge` (3 days)       |
| bun            | `.bunfig.toml` `minimumReleaseAge` |
| uv             | `UV_EXCLUDE_NEWER`                 |
| GitHub Actions | SHA-pinning                        |
| **herdr**      | **none**                           |

herdr has no age gate at all. Worse, it ships **three** paths by which it can
change without anyone asking:

1. **`herdr update`** — a self-updater that installs the newest build immediately.
2. **`update.version_check`** (default `true`) — background check to the vendor's
   host for new versions, surfaced as an in-app prompt.
3. **`update.manifest_check`** (default `true`) — this one is easy to misread. It
   is **not** a version check. It fetches agent-detection manifests from the
   vendor at runtime and reloads them into the **running server**: remote
   behaviour change, no pin, no cooldown, no review.

So the gate has to be enforced from outside the tool.

## The design

Three parts, each doing one thing:

| Part                                  | Role                                                    |
| ------------------------------------- | ------------------------------------------------------- |
| `HERDR_COOLDOWN_DAYS` in `install.sh` | the canonical policy value (alongside the other floors) |
| **Homebrew pin**                      | makes the binary immovable by a routine `brew upgrade`  |
| `herdr-cooldown-check`                | reports when a release has aged past the gate           |

**Why pin rather than trust a channel.** herdr's own `update.channel` only selects
stable-vs-preview, not age. And upstream states that Homebrew installs ignore
`herdr update` entirely — so on a brew-managed box the binary can only move when
Homebrew moves it. `brew pin` is therefore the single switch that closes the door,
and `_preflight_herdr_pin_check` in `install.sh` re-asserts it on every run (an
unpin for a deliberate upgrade otherwise leaves the gate open if the re-pin is
forgotten).

## What the checker checks (4 subjects)

| #   | Subject      | Question                                                         |
| --- | ------------ | ---------------------------------------------------------------- |
| 1   | `version`    | is the installed build behind the newest upstream stable?        |
| 2   | `cooldown`   | has that release aged past `HERDR_COOLDOWN_DAYS`?                |
| 3   | `pin`        | is the Homebrew formula still pinned?                            |
| 4   | `phone-home` | are `update.version_check` and `update.manifest_check` disabled? |

Subjects 3 and 4 exist because a gate nobody re-checks is a gate that quietly
lapses. A missing config key is reported as **not** disabled — the upstream
default is `true`, so silence is not consent.

**Data source.** GitHub's `releases/latest` endpoint, which already excludes
prereleases — so the vendor's near-daily `preview-*` tags can never be proposed.
Unauthenticated (`$GH_TOKEN` is used only to raise the rate ceiling).

## How it runs

- **Engine:** `home/.local/bin/herdr-cooldown-check` (PEP 723 via `uv run`,
  stdlib only, stow-deployed to `~/.local/bin`).
- **Session surface:** `.claude/hooks/herdr-cooldown-check.sh`, wired into
  `SessionStart` beside the [toolchain-CVE](TOOLCHAIN_CVE_CHECK.md),
  [Zed-PR](ZED_PREVIEW_CHANGELOG.md) and [CI](CI_WATCH.md) watchers.
- **Cache:** 6h verdict cache in `$TMPDIR`. A release crossing the 3-day line is
  not a sub-6h event.
- **Read-only:** it never installs, unpins, upgrades or edits config. It prints
  the command it thinks you want and stops.
- **Silent when herdr is absent** — checked before the tool is even located, so a
  machine that never adopted herdr gets no line at all. Per the
  alert-design rule, a passive identical banner every session is exactly how an
  alert stops being read.

### Exit codes

| Code | Meaning                                                               |
| ---- | --------------------------------------------------------------------- |
| `0`  | nothing actionable — current, held by the gate, or skipped            |
| `1`  | an upgrade is ELIGIBLE, or a guard (pin / phone-home) is not in place |

The hook itself always exits `0` and degrades to a note when offline or when `uv`
is missing.

## Install and first-run setup

Prefer Homebrew over the vendor's `curl … | sh` installer. The installer performs
**no checksum or signature verification**, and the releases carry no `.sha256` or
`.sig` assets to verify against manually; the Homebrew route substitutes a
reviewed formula and a checksummed bottle.

```bash
brew install herdr
brew pin herdr
```

Then close the phone-home half:

```toml
# ~/.config/herdr/config.toml
[update]
version_check = false
manifest_check = false
channel = "stable"
```

Pull agent-detection manifests deliberately instead, when you want them:

```bash
herdr server update-agent-manifests
```

### The upgrade runbook

Upgrades are three-step and deliberate — never a bare `brew upgrade`:

```bash
herdr-cooldown-check                                    # confirm ELIGIBLE, not HELD
brew unpin herdr && brew upgrade herdr && brew pin herdr
herdr-cooldown-check                                    # confirm the pin is back
```

## Running herdr as a persistent server

herdr is a server/client design: panes and agents live in a background server,
clients attach and detach. `herdr server` is the documented headless entrypoint
("use it for supervised or service-style setups"), and the Homebrew formula ships
a service definition with `keep_alive` for it:

```bash
brew services start herdr
```

That gives crash-restart and start-on-console-login.

### The FileVault ceiling

On a headless always-on Mac, "comes back after an accidental reboot" runs into a
hard limit that has nothing to do with herdr. Check the machine's state first:

```bash
fdesetup status                                              # FileVault on/off
defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser
pmset -g | grep autorestart
```

**With FileVault enabled**, a cold boot stops at the pre-boot unlock screen. No
LaunchAgent, no LaunchDaemon, not even `sshd` is running until someone unlocks the
volume — and macOS does not offer auto-login while FileVault is on. No service
configuration can work around this.

What each control actually buys you:

| Control                       | Covers                                            | Does not cover              |
| ----------------------------- | ------------------------------------------------- | --------------------------- |
| `brew services start herdr`   | herdr crashing; start at console login            | cold boot before login      |
| `sudo pmset -a autorestart 1` | powering back on after a power cut                | the FileVault unlock itself |
| `sudo fdesetup authrestart`   | **planned** reboots — returns unlocked, `sshd` up | power cuts, panics          |

`fdesetup authrestart` escrows the unlock key for exactly one restart, so it is
the right tool before an OS update and useless for anything unplanned. `man
fdesetup` warns that FileVault protections are reduced while that key is held (an
extra copy sits in system memory and, on supported hardware, the SMC); pair
regular use with `sudo pmset -a destroyfvkeyonstandby 1`.

**In practice this matters less than it first appears**, because herdr starts its
own server on attach — upstream: _"connects over SSH, starts or attaches to the
remote Herdr server."_ After any reboot, the first attach brings the server up.
The service definition's real value is crash-restart, not cold start.

Note also that `brew services start` without `sudo` installs a **LaunchAgent**,
which loads in the GUI session at login. A LaunchDaemon would start earlier but is
the wrong tool here: the server needs the user's `HOME`, `PATH`, ssh-agent and
agent credentials.

## herdr and tmux

Upstream positions herdr as a tmux-class multiplexer — the keyboard docs open with
_"Coming from tmux or zellij? You already know this model"_, and the remote docs
describe SSH-then-`herdr` as _"the tmux-style path"_. Panes are genuine terminals
(it vendors libghostty-vt, the Ghostty VT engine) with splits, tabs, scrollback,
copy mode, named sessions and detach/reattach.

Default keymap against this repo's `.tmux.conf`:

| Action              | herdr                   | this repo's tmux         |
| ------------------- | ----------------------- | ------------------------ |
| Prefix              | `ctrl+b`                | `ctrl+Space`             |
| New tab / window    | `prefix+c`              | `prefix+c`               |
| Split right / down  | `prefix+v` / `prefix+-` | `prefix+\|` / `prefix+-` |
| Move between panes  | `prefix+h/j/k/l`        | `prefix+h/j/k/l`         |
| Zoom / close / copy | `prefix+z` / `x` / `[`  | `prefix+z` / `x` / `[`   |
| Detach              | `prefix+q`              | `prefix+d`               |

Two remote modes, and the second has no tmux equivalent:

```bash
ssh <host> && herdr        # tmux-style: client and server both remote
herdr --remote <host>      # thin client: UI streams to the local terminal
```

`--remote` runs the client locally, so it can bridge local desktop features
(including image clipboard paste) into the remote session and use **local**
keybindings against a remote server. It honours `~/.ssh/config` host aliases and
normal OpenSSH auth.

### What dropping tmux would cost

Measured against this repo's `home/.tmux.conf` and `home/.zsh_cursor_functions`:

- **vim-tmux-navigator** — seamless `ctrl+hjkl` between nvim splits and panes. No
  herdr equivalent found.
- **The catppuccin status bar** with the CPU/RAM readout. herdr has its own
  theming and sidebar, but it is a different thing, not a port.
- **tmux-yank** and **tmux-tilit** auto-layouts.
- **The `client-attached` hook** that broadcasts `source ~/.cache/cursor_env.zsh`
  to every pane (`.tmux.conf`, Cursor/VSCode env sync). Bespoke; would need
  re-solving. The `tmux()` wrapper in `.zsh_cursor_functions` goes dead with it.
- **Unverified:** `.tmux.conf` reclaims `S-Enter` so Claude Code receives newlines
  rather than a plugin action. Whether herdr binds `S-Enter` was not confirmed —
  test it early, it would bite daily.

**Recommendation: do not nest them, and do not delete tmux either.** Stop
launching tmux and drive herdr for a couple of weeks instead. The tmux config
costs nothing sitting on disk, and herdr is a young project — keep the retreat
path intact. Prefixes do not collide (`ctrl+Space` vs `ctrl+b`) if you do end up
nested, but layered multiplexers mangle keys and you will blame the wrong thing.

## Scope (and deliberate non-scope)

- **In scope:** age-gating the herdr binary, keeping the pin asserted, keeping the
  two phone-home paths closed, and reporting all three at session start.
- **Not in scope:** installing or upgrading herdr. The checker prints commands; a
  human runs them. Automatic adoption is precisely what the cooldown exists to
  prevent.
- **Not in scope:** the vendor's plugin marketplace. Plugins are a separate
  supply-chain surface and are not covered by any of this.

## Related

- [`docs/SECURITY.md`](SECURITY.md) — the estate-wide release-cooldown posture
- [`docs/TOOLCHAIN_CVE_CHECK.md`](TOOLCHAIN_CVE_CHECK.md) — the sibling floor watcher
- [`docs/CI_WATCH.md`](CI_WATCH.md) — the alert-design rules this hook follows
- [`docs/reference/tmux_cheatsheet.md`](reference/tmux_cheatsheet.md) — the incumbent
