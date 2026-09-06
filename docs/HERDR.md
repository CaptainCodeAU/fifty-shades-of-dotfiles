# herdr — release cooldown, daemon persistence, and the tmux question

[herdr](https://github.com/herdrdev/herdr) is an agent multiplexer: a terminal
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

Four parts, each doing one thing:

| Part                                  | Role                                                            |
| ------------------------------------- | --------------------------------------------------------------- |
| `HERDR_COOLDOWN_DAYS` in `install.sh` | the canonical policy value (alongside the other floors)         |
| **Homebrew pin**                      | makes the binary immovable by a routine `brew upgrade`          |
| `herdr-cooldown-check`                | read-only: reports when a release has aged past the gate        |
| `_preflight_herdr_bump_check` (macOS) | acts on that report: unpin/upgrade/re-pin once it says ELIGIBLE |

**Why pin rather than trust a channel.** herdr's own `update.channel` only selects
stable-vs-preview, not age. And upstream states that Homebrew installs ignore
`herdr update` entirely — so on a brew-managed box the binary can only move when
Homebrew moves it. `brew pin` is therefore the single switch that closes the door,
and `_preflight_herdr_pin_check` in `install.sh` re-asserts it on every run (an
unpin for an upgrade otherwise leaves the gate open if the re-pin is forgotten
mid-sequence — `_preflight_herdr_bump_check` re-pins even when the upgrade step
itself fails, for exactly that reason).

**Checker vs actor stay separate.** `herdr-cooldown-check` never installs, unpins,
upgrades or edits config — see its own header. That contract does not change.
`_preflight_herdr_bump_check` is a second, separate piece of code that reads the
checker's `--json` report and runs the three-step upgrade only when the `cooldown`
subject says `ACTION` (and only when the checker's own self-test passes — a broken
detector skips instead of guessing). The checker stays fully usable standalone.

## What the checker checks (5 subjects)

| #   | Subject        | Question                                                                                  |
| --- | -------------- | ----------------------------------------------------------------------------------------- |
| 1   | `homebrew-lag` | informational: is Homebrew's current formula version behind GitHub's absolute newest tag? |
| 2   | `version`      | is the installed build behind the gating candidate (see below)?                           |
| 3   | `cooldown`     | has the gating candidate aged past `HERDR_COOLDOWN_DAYS`?                                 |
| 4   | `pin`          | is the Homebrew formula still pinned?                                                     |
| 5   | `phone-home`   | are `update.version_check` and `update.manifest_check` disabled?                          |

Subjects 4 and 5 exist because a gate nobody re-checks is a gate that quietly
lapses. A missing config key is reported as **not** disabled — the upstream
default is `true`, so silence is not consent.

**The gating candidate is not always GitHub's absolute newest tag.** For a
brew install, it's whatever `brew upgrade herdr` would actually install right
now (`brew info herdr --json=v2`) — Homebrew-core only moves the formula when
a maintainer notices and bumps it, which lags behind upstream releases
unpredictably. Gating cooldown against GitHub's `releases/latest` regardless
was a real bug: found live on 2026-08-20, when GitHub's newest was v0.8.2 but
Homebrew still only offered v0.8.0 (already 16+ days past cooldown) — the old
logic held every Mac at v0.7.5, waiting on a release Homebrew couldn't even
deliver yet, instead of upgrading to the older release that was genuinely
safe and already installable. Non-brew (Linux/WSL) installs have no such
intermediary, so GitHub's absolute latest is the candidate there, same as
before.

**Data source.** GitHub's `releases/latest` and `releases/tags/<tag>`
endpoints, which already exclude prereleases — so the vendor's near-daily
`preview-*` tags can never be proposed — plus `brew info herdr --json=v2` for
brew installs (local, no network). Unauthenticated (`$GH_TOKEN` is used only
to raise the rate ceiling).

## How it runs

- **Engine:** `home/.local/bin/herdr-cooldown-check` (PEP 723 via `uv run`,
  stdlib only, stow-deployed to `~/.local/bin`).
- **Session surface:** `.claude/hooks/herdr-cooldown-check.sh`, wired into
  `SessionStart` beside the [toolchain-CVE](TOOLCHAIN_CVE_CHECK.md),
  [Zed-PR](ZED_PREVIEW_CHANGELOG.md) and [CI](CI_WATCH.md) watchers.
- **Cache:** 6h verdict cache in `$TMPDIR`. A release crossing the 7-day line is
  not a sub-6h event.
- **Read-only:** it never installs, unpins, upgrades or edits config. It prints
  the command it thinks you want and stops.
- **Silent when herdr is absent** — checked before the tool is even located, so a
  machine that never adopted herdr gets no line at all. Per the
  alert-design rule, a passive identical banner every session is exactly how an
  alert stops being read.

### The self-test runs every time

A guard that can only ever print OK is decoration. Rather than asking a human to
periodically unpin the formula and eyeball the output, the checker proves its own
detectors on every invocation, against the **same pure functions the real run
uses** — `parse_phone_home`, `version_verdict`, `brew_pinned`:

| Assertion                                                       | Guards against                     |
| --------------------------------------------------------------- | ---------------------------------- |
| `version_check = true` is read as enabled                       | a regex that stops matching        |
| an **absent** key reads as unset, not false                     | silence being mistaken for consent |
| a 1-day-old release is HELD, a 7-day-old is ELIGIBLE            | the cooldown rule inverting        |
| a missing pin marker reads as UNPINNED, a present one as PINNED | the pin check going blind          |

The pin assertions run against a synthetic Homebrew prefix in a temp directory,
so both directions are proven without touching the real pin. Cost is
microseconds: no network, no subprocess, no state changed.

If any assertion fails the tool emits `DETECTOR BROKEN`, marks the run
actionable, and says the checks below cannot be trusted — because a green report
from a broken detector is worse than no report. Verified by sabotage: inverting
the cooldown rule in a throwaway copy produced two `DETECTOR BROKEN` rows and
exit 1.

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

On macOS this is now handled for you: `herdr` is part of the core formulae in
`install.sh`, and the pin guard runs immediately after the install step so a
freshly installed formula cannot sit unpinned.

**Linux and WSL are handled too, by a different route.** They were manual until
2026-08-02, on the reasoning that no verified supply chain existed: there is no
apt/dnf/pacman package, homebrew-core publishes only an `arm64_tahoe` bottle,
and every remaining method — the vendor's `curl … | sh`, `mise` (which resolves
via aqua, whose registry entry for herdr is `type: github_release` /
`format: raw` with no `checksum:` block), and a raw download — fetches the same
GitHub asset. Upstream publishes **no `.sha256` and no `.sig`** beside it, so
none of them verify anything.

The fix is the gate used everywhere else in this estate: pin the artefact and
assert it. `install.sh` carries `HERDR_VERSION` plus a sha256 per architecture,
downloads that exact asset, and **refuses to install on mismatch**:

```bash
HERDR_VERSION="v0.7.5"
HERDR_SHA256_LINUX_X86_64="3dc83288…59253"
HERDR_SHA256_LINUX_AARCH64="32e763a1…a8b9"
```

It lands at `~/.local/bin/herdr`, needs no sudo, and skips its work when the
installed version already matches the pin. Be clear about what this buys: it is
trust-on-first-use, not upstream provenance — it cannot attest the binary was
good originally. What it guarantees is that every box gets **byte-identical** to
the artefact vetted here, and that a silently re-uploaded asset fails loudly.
That is the same guarantee `brew pin` gives on macOS, which is why herdr is now
counted as **required on both platforms** rather than optional on one.

Bumping the Linux pin is deliberate and never automatic — the runbook is in the
comment block above `HERDR_VERSION` in `install.sh`: confirm the cooldown has
elapsed, re-hash both assets, update version and hashes in one commit, then
re-run `./install.sh` on each box.

**`herdr-linux-pin-check`** ties the "confirm the cooldown has elapsed" step to
a real signal instead of a separate manual check: it compares the current
`HERDR_VERSION` against whatever version macOS's Homebrew pin has _already_
cleared cooldown on. Run it from the dev Mac, inside the repo:

```bash
herdr-linux-pin-check
```

If Linux is behind, it downloads the matching `herdr-linux-x86_64` /
`herdr-linux-aarch64` release assets, computes their sha256, and prints them
ready to paste into the `HERDR_VERSION` / `HERDR_SHA256_LINUX_*` block above —
it never edits `install.sh` and never commits. Homebrew vetting the _source_
tarball for a tag is not the same as vetting that separately-built Linux
binary, so the hash review stays a human decision, same bar as before this
tool existed; it only removes the guesswork of "has macOS actually moved on
without Linux noticing."

Then close the phone-home half. The config is repo-managed at
`home/.config/herdr/config.toml` and stow-linked to `~/.config/herdr/config.toml`,
so it deploys with everything else — `stow -R --no-folding` creates the real
directory and symlinks the file, the same shape as the other `~/.config` entries:

```toml
# home/.config/herdr/config.toml  ->  ~/.config/herdr/config.toml
[update]
version_check = false
manifest_check = false
channel = "stable"
```

Both guards are surfaced rather than assumed. `install.sh --check` reports the
pin and whether the config is stow-linked, and the shell welcome banner carries
a `herdr:` line showing the version and pin state (read from a symlink under
`$HOMEBREW_PREFIX`, so it costs no `brew` subprocess). An unpinned herdr is
shown as an error, not a note — the pin _is_ the cooldown.

Pull agent-detection manifests deliberately instead, when you want them:

```bash
herdr server update-agent-manifests
```

### The upgrade runbook

On macOS, `./install.sh` runs this automatically now: every run calls
`herdr-cooldown-check`, and if the `cooldown` subject reports `ACTION` (the
newest release has cleared `HERDR_COOLDOWN_DAYS`), `_preflight_herdr_bump_check`
performs the same three-step upgrade below on its own, no confirmation prompt —
same posture as the pnpm floor-check. There is still no bare `brew upgrade`:
the pin is the only thing standing between herdr and a same-day release, and it
comes straight back after the bump.

Run the commands by hand only to force a check outside install.sh's own run, or
to troubleshoot a bump that didn't take:

```bash
herdr-cooldown-check                                    # confirm ELIGIBLE, not HELD
brew unpin herdr && brew upgrade herdr && brew pin herdr
herdr-cooldown-check                                    # confirm the pin is back
```

Linux/WSL is unchanged — `_preflight_herdr_release_check` already applies pinned,
hash-verified `HERDR_VERSION` bumps automatically; see the runbook above the
`HERDR_VERSION` comment block in `install.sh` for that side.

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

#### Hand over to launchd on an idle server, not a busy one

Enabling the service while a hand-started server is already running produces a
**respawn loop**, and nothing warns you. A second server refuses the socket:

```
$ herdr server
error: herdr server is already running
$ echo $?
1
```

The formula sets `keep_alive true`, which restarts the job regardless of exit
code — so launchd will relaunch it, it will exit 1 again, forever, throttled to
roughly one attempt every ten seconds.

The handover therefore has to happen while nothing holds the socket, and it is a
one-time cost:

```bash
herdr server stop          # kills running panes and agents -- pick your moment
brew services start herdr  # launchd owns it from here on
```

After that it is automatic: crash-restart via `keep_alive`, and start at console
login. There is no way to skip the stop — the socket can only have one owner.

#### Once launchd owns it, nothing else can stop it

`keep_alive true` is **unconditional** — launchd restarts the job on any exit,
including a clean one. So every stop request loses:

```
$ herdr server stop        # succeeds, exits 0, prints nothing
$ herdr server
error: herdr server is already running
```

The server did stop. launchd started a new one within milliseconds. herdr's own
restart flow then waits for the socket to disappear, which never happens:

```
error: shutdown was requested, but the old remote herdr server ... is still responding after 5 seconds
error: remote server stop failed: server did not stop within 15000ms; sockets are still reachable
```

Nothing in that output names launchd, which is what makes it expensive to
diagnose. `herdr --remote` produces it too, so it reads as a _remote_ problem
when the cause is entirely local to the server box.

Confirm it in one command — `runs` climbing with `last exit code = 0` is the
signature, and the running process will have PPID 1:

```bash
launchctl print "gui/$(id -u)/homebrew.mxcl.herdr" | grep -E 'state|runs|last exit|properties'
#   state = running
#   runs = 6
#   last exit code = 0
#   properties = keepalive | runatload | inferred program
```

**The rule: while the service is enabled, restart through its owner.**

```bash
brew services restart herdr    # not `herdr server stop`, not herdr's restart prompt
```

That kills live panes and agents, so pick the moment. If you want herdr's own
stop/restart to work again, hand the job back first with `brew services stop
herdr` — and accept that you lose crash-restart and start-at-login with it.

### Two machines: keep the versions in step

Remote attach is not version-agnostic. Client and server negotiate a protocol,
and `herdr status server` reports all three:

```
status: running
version: 0.7.5
protocol: 17
compatible: yes
```

When the two ends diverge far enough to change that protocol, herdr prompts to
stop and restart the old server to reconcile — which defeats the point of a
session that was supposed to be sitting there waiting for you. For remote attach
specifically, herdr prefers a matching binary already on the remote `PATH`, then
checks the common direct, Homebrew, mise and Nix install locations. If it finds
none, an interactive run offers to install one to `~/.local/bin/herdr`; a
non-interactive run fails rather than modifying the host.

**The consequence for the cooldown: it has to be applied on every machine that
attaches, not just the server.** A laptop left on `brew upgrade` autopilot will
drift ahead of a pinned server and start forcing restarts. So:

- `brew pin herdr` on **both** ends, not only the machine hosting the sessions.
- Upgrade them in the **same sitting** — unpin, upgrade, re-pin, on each box —
  rather than whenever each happens to be in front of you.
- `herdr-cooldown-check` is per-machine by design. Run it on the client too; it
  reports that machine's own pin, version and phone-home state.

This is the one place where the cooldown design needs a human to remember
something, because nothing on either box can see the other's version until they
try to talk.

### Two machines: the keymap drifts too

Versions are not the only thing that has to match. **`herdr --remote` interprets
keystrokes on the client**, and defaults to the client's own `config.toml`:

```
--remote-keybindings <local|server>   Choose local or server keybindings for remote attach
```

So a keybinding committed and stowed on the machine hosting the sessions is
simply not in force for a `--remote` user. The config on the server is read for
everything else; the keys come from the laptop.

**The symptom is misleading.** Older bindings keep working — the client pulled
those in some earlier deploy — while a newly added one does nothing. That reads
as "the new binding is broken", and `herdr config check` on the server will
cheerfully report `config: ok`, because it is validating a file that is not the
one being consulted. Reloading with `prefix+r` does not help either: it reloads
the client's config, and the server never logs a reload at all.

**How to tell which machine is reading your keys** — `~/.config/herdr/herdr-client.log`
records every local client's `app.startup` / `app.shutdown`. If the newest entry
there is older than the live activity in `herdr-server.log`, the client driving
the session is somewhere else, and its config is the one that matters.

Two ways to close the gap:

- **Deploy on the client too.** Pull and re-stow the dotfiles on every machine
  that attaches, then reload. Keeps the default `local` keymap, which is what
  bridges laptop-side desktop features such as image clipboard paste.
- **Hand keymap ownership to the server**, so the tracked config here is the
  single source of truth:

  ```bash
  herdr --remote ssh://<host> --remote-keybindings server
  export HERDR_REMOTE_KEYBINDINGS=server   # same choice, without the flag
  ```

  This is the option that removes the failure class rather than re-fixing it per
  machine: one file, one commit, no drift. The cost is that the client can no
  longer hold keybindings of its own — which costs nothing when both ends stow
  the same config anyway. There is no `[remote]` config key for this; the flag
  and the environment variable are the only routes.

Confirmed 2026-08-01 the hard way: `previous_agent` / `next_agent` were added
here, validated, and reloaded, and did nothing on the laptop until the attach was
re-made with `--remote-keybindings server`.

### Linux / WSL: the systemd user service

Added 2026-09-06. The Linux counterpart of `brew services start herdr`.
`home/.config/systemd/user/herdr.service` is stowed like everything else (it
lands on the Mac too, where it is inert: macOS has no systemd), and
`install.sh` enables it in `_post_stow_herdr_systemd_service`, which runs after
`stow_home` because the unit has to be on disk first.

What it does on a Linux/WSL box, in order:

1. Skips silently unless herdr is installed, `systemctl` exists, and the stowed
   unit symlink is present.
2. Checks `systemctl --user is-system-running`. Only `running` or `degraded`
   count. On WSL the user manager only exists when `/etc/wsl.conf` has
   `[boot] systemd=true`; otherwise install.sh says so and stops.
3. **Refuses to enable over a hand-started server.** `herdr status server --json`
   reporting `running: true` while the unit is not active means someone ran
   `herdr server` by hand and owns the socket. Enabling the unit then would
   start a second server that exits 1, and `Restart=` would retry it -- the
   same respawn loop the Homebrew `keep_alive` section above describes. The
   unit caps that at five tries in two minutes, but install.sh does not get
   there: it prints the two-command fix and leaves the running server alone.
4. `daemon-reload`, then `enable --now`.
5. `loginctl enable-linger $USER`. Without linger the user manager, and this
   service with it, stops at the last logout -- which on a headless box is
   every SSH disconnect. Enabling linger for your own user goes through polkit
   and needs no sudo on Ubuntu 24.04; if it fails, install.sh prints the sudo
   form instead of aborting.

The prerequisites summary reports the real state (`is-active`, plus linger),
not whether the unit file exists.

**Why a service and not a hand start.** Every hand-started `herdr server`
inherits the shell it was started from. On the 3090 box that shell had already
shown the dotfiles welcome banner and exported the once-only flags
(`_ONBOARDING_COMPLETE`, `_WELCOME_MESSAGE_SHOWN`), so every pane the server
opened skipped the banner -- measured 2026-09-06 with
`echo $_ONBOARDING_COMPLETE` inside a fresh pane returning `true`. The
foreground server also died with the SSH session. systemd gives a clean
environment, crash-restart, and (with linger) survival across logout.

The unit sets `PATH` explicitly: the user manager's default has neither
`~/.local/bin` (where install.sh puts the pinned binary) nor `/usr/lib/wsl/lib`
(where WSL keeps `nvidia-smi`, which the tab-bar GPU status command needs).

**The GPU status command runs wherever the server runs.** `config.toml`'s
`tab_bar_right` used to point at the Mac's repo checkout by absolute path. On
the Linux box that path does not exist, so the server logged one exit-127
warning every five seconds -- 12188 of 12641 lines in a 3 MB log before anyone
looked. It now runs `~/.config/herdr/gpu-status.sh` (stowed, same path on every
box), and the script reads `nvidia-smi` locally when it finds the WSL binary,
over SSH otherwise.

Useful on the box:

```bash
systemctl --user status herdr.service
journalctl --user -u herdr.service -n 50
systemctl --user restart herdr.service   # drops every attached session
```

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
- **`shift+Enter` — resolved, no action needed.** `.tmux.conf` had to reclaim it
  from tmux-tilit so Claude Code received newlines. herdr's default keymap binds
  nothing to it, so no reclaim is required.
- **Copy mode — already equivalent.** herdr's copy mode is vi-style out of the
  box (`v` selects, `y` copies, `q`/Esc leaves), matching the `mode-keys vi`
  setup in `.tmux.conf`. Only `ctrl+v` rectangle-select has no counterpart.

### The ported keymap

`home/.config/herdr/config.toml` carries the tmux muscle memory across: the
`ctrl+Space` prefix, `prefix+|` / `prefix+minus` splits, `prefix+d` to detach,
`prefix+r` to reload config, and prefix-free `shift+left` / `shift+right` for
tabs. Everything else already matched tmux by default.

One binding is **not** a tmux port: prefix-free `shift+up` / `shift+down` walk
`previous_agent` / `next_agent`. herdr ships both actions as _"optional, unset by
default"_, so out of the box there is no agent-switching key at all — moving
between agents means moving between the panes and tabs they happen to live in.
They complete the arrow cluster: left/right across tabs, up/down across agents.
Scope is the whole session rather than the current workspace, and because
`agent_panel_sort = "priority"` is set, they walk the sidebar's own order — next
by which agent wants attention, not by position.

The one structural difference: **herdr takes a single key per action**, where
tmux allowed several. `.tmux.conf` bound the right-hand split four ways
(`|`, `Right`, `%`, `h`); only one survives. The same constraint means
Alt+Arrow pane switching and `prefix+h/j/k/l` cannot both exist — the config
keeps the vim keys and documents the swap. Validate any change with
`herdr config check`.

**Recommendation: do not nest them, and do not delete tmux either.** Stop
launching tmux and drive herdr for a couple of weeks instead. The tmux config
costs nothing sitting on disk, and herdr is a young project — keep the retreat
path intact. Prefixes do not collide (`ctrl+Space` vs `ctrl+b`) if you do end up
nested, but layered multiplexers mangle keys and you will blame the wrong thing.

## Speak-selection stops working inside herdr

macOS "Speak selection" (Accessibility > Spoken Content) asks the **focused
application** for its selected text over the accessibility API. Inside herdr
there is nothing to ask for: herdr captures the mouse, so a drag creates
herdr's own internal selection and the host terminal never has one. The hotkey
stays enabled system-wide, finds an empty selection, and says nothing. It is the
same root cause as `cmd+C` appearing to do nothing — the selection is not where
the OS is looking.

The bridge is the clipboard, since `copy_on_select` means a drag has already
copied by the time you release it. The bindings in `config.toml`
(`ctrl+alt+backtick` and `prefix+backtick`) run `speak-clipboard --toggle`,
which:

1. strips the terminal furniture before speaking — ANSI escapes, box drawing,
   Nerd Font glyphs, rule runs — and maps curly quotes, dashes, and accented
   letters to ASCII instead of dropping them. The raw accessibility hotkey
   cannot do any of this: it reads the screen, borders and all;
2. hands the cleaned text to one `speak-render` process per press
   (`home/.local/share/fifty-shades-of-dotfiles/scripts/speak-render.swift`,
   built by `install.sh` on macOS, or lazily on first use). It splits at
   sentence ends, renders the first sentence to a temp file, starts playing it
   within about a second, and renders each next sentence while the current one
   plays. Rendering runs ~8x faster than speech, so playback never runs dry;
3. applies the toggle rule: press on the **same** text while it speaks = stop;
   press with **new** text while it speaks = stop the old, speak the new.
   `speak-clipboard --stop` stops unconditionally. Text identity is a SHA-256
   of the cleaned text kept in `~/.local/state/herdr/`. The text itself is
   never logged and never passed on a command line; it reaches `speak-render`
   through a pipe. The rendered audio goes to the per-user temp directory
   (private, purged by the OS) and is deleted after playback, on stop, and by
   a ten-minute stale sweep at the next start.

Why one process per press and not a warm daemon: the daemon that briefly
existed (2026-09-01 to 2026-09-03) saved about half a second per press, and in
exchange rendered the whole selection before playing any of it — 10+ seconds of
silence on a long selection, during which a second press was taken as "stop" —
never exited, and held a power assertion that kept the Mac from idle-sleeping.
With a per-press process, killing it is the entire stop mechanism and nothing
runs between presses. `~/.local/state/herdr/speak-clipboard.log` keeps one
metadata line per press (mode, outcome, character count): a new line means the
key reached herdr; no line means the key or the spawn is at fault.

Copy mode feeds it too — `prefix+[`, `v`, `y`, then speak — which matters when
the text is a screen away from the pointer.

Requires _"Applications in terminal may access clipboard"_ in iTerm2, without
which the drag never reaches the clipboard and the key appears dead.

The no-config alternative is to hold **option while dragging**, producing a
native terminal selection the real accessibility hotkey can read. Fine
occasionally, awkward across splits: the host terminal selects a rectangle over
the whole grid and does not know pane borders exist.

## It installs hooks into your agent CLIs

Worth knowing, because nothing announces it. herdr writes an executable
state-reporting hook into each agent CLI it finds, so the sidebar can show
working / idle / blocked and so sessions can be resumed by id. Check what is
present with:

```bash
herdr integration status
herdr integration uninstall <name>
```

On a machine with several agent CLIs installed this can be three or more files,
each landing in that tool's own config directory — for Claude Code that means a
hook inside `~/.claude/hooks/` plus a registration in `~/.claude/settings.json`.

Two properties keep this defensible:

- **They are inert outside herdr.** The Claude hook exits immediately unless
  `HERDR_ENV`, `HERDR_SOCKET_PATH` and `HERDR_PANE_ID` are all set, so a normal
  terminal session never executes its body.
- **They land outside this repo.** `~/.claude/settings.json` is a real file
  here, not a stow symlink, so the edit did not reach the dotfiles tree.

One property that deserves attention: each file declares _"managed by herdr;
reinstalling or updating the integration overwrites this file."_ Upgrading herdr
therefore rewrites executable code in your agent config directories. The release
cooldown governs when that happens — which is a reason the pin matters beyond
the binary itself.

## Scope (and deliberate non-scope)

- **In scope:** age-gating the herdr binary, keeping the pin asserted, keeping the
  two phone-home paths closed, and reporting all three at session start.
- **Not in scope:** installing or upgrading herdr. The checker prints commands; a
  human runs them. Automatic adoption is precisely what the cooldown exists to
  prevent.
- **Not in scope:** the vendor's plugin marketplace. Plugins are a separate
  supply-chain surface and none of the cooldown machinery covers them. The
  standing rule is `herdr plugin link` against a locally authored directory,
  never `herdr plugin install`, which clones a repo and executes its
  `[[build]]` commands. See [`docs/HERDR_PLUGINS.md`](HERDR_PLUGINS.md) §1.

## Related

- [`docs/SECURITY.md`](SECURITY.md) — the estate-wide release-cooldown posture
- [`docs/TOOLCHAIN_CVE_CHECK.md`](TOOLCHAIN_CVE_CHECK.md) — the sibling floor watcher
- [`docs/CI_WATCH.md`](CI_WATCH.md) — the alert-design rules this hook follows
- [`docs/reference/tmux_cheatsheet.md`](reference/tmux_cheatsheet.md) — the incumbent

### Capability references (written for an AI agent, not a human)

Verified against herdr 0.7.5 by executing every command, 2026-08-02.

- [`docs/HERDR_AGENT_SKILL.md`](HERDR_AGENT_SKILL.md) — driving herdr from
  inside a pane: split, run, `wait-output`, read. Includes the Claude-sandbox
  socket block and the JSON-vs-plain-text output map.
- [`docs/HERDR_AGENT_AUTOMATION.md`](HERDR_AGENT_AUTOMATION.md) — agent
  lifecycle states, `blocked` detection, and why `interactive_ready` lies.
- [`docs/HERDR_PLUGINS.md`](HERDR_PLUGINS.md) — manifest format, the
  focused-pane context trap, and why `link` is the only safe registration path.
