# herdr — release cooldown, daemon persistence, and the tmux question

herdr-verified: 0.9.5

Re-verified 2026-10-18 against the installed 0.9.5 with a running 0.9.5 server,
2026-10-07 against 0.9.3, 2026-09-22 (F9b) against 0.9.1, and 2026-09-17
against 0.8.2. The `herdr-verified:` line is machine-read by
`herdr-skill-drift-check`, which reports every `docs/HERDR*.md` that has fallen
behind the binary. It replaced six hand-typed version mentions across four docs,
all six of which had gone stale without anyone noticing. Move it only after
actually re-checking.

**WHAT THE 0.9.5 RE-VERIFY COVERED (2026-10-18).** The upgrade was 0.9.3 to
0.9.5 under the new 3-day gate (D-20261018-A01, below), typed by hand with
`HOMEBREW_NO_INSTALL_CLEANUP=1`, and the server restart was Gavin's, by hand.
RE-RUN on 0.9.5: `herdr status` (client and server both 0.9.5, protocol 22,
`restart_needed: no`) and `herdr status server --json` (`running: true`,
`compatible: true`); `herdr config check` ok with both phone-home keys still
`false`; `herdr-cooldown-check` (0 actionable, pin OK), `herdr-linux-pin-check`
(Linux pin v0.9.5 matches) and `herdr-skill-drift-check`; `brew info herdr`
(`pinned: true`, `service: null`, kegs 0.9.3 and 0.9.5 both installed); the
running server's process tree, which corrected the PPID 1 claim in the
persistent-server section; the server log, which now names why a server stopped
(0.9.4, #4920); the multi-key and bad-key `config check` arms in throwaway
configs; `herdr integration status` and a throwaway-home install of the Claude
hook, now v11 (item 13 and the hooks section); `check-herdr-fda.py` PASS. Diffed
against the kept 0.9.3 binary: `--help` identical (74 lines each), every command
group's usage identical except the new `herdr plugin update`, and
`--default-config` differs only by the Windows-only `allow_unelevated_clients`.
NOT RE-MEASURED, because each needs a step that ends or disturbs the running
session: that closing the shell that started herdr, or a `SIGHUP`, no longer
stops the server (0.9.4, #4920), and that sessions survive a Mac restart (0.9.4,

# 4414). Also not re-measured: anything on codebox (reported on 0.9.5, not measured here), the Linux system

unit and the `herdr()` guard on Linux, remote attach and the keymap-drift
claims, the tmux comparison and copy mode, and speak-selection. The 0.9.4 and
0.9.5 notes touch none of those beyond what is marked. A coverage audit of every
0.9.2 to 0.9.5 release-note bullet followed the same day, and the gaps it found
are added in the sections they belong to, each marked measured or release notes.

**WHAT THE 0.9.3 RE-VERIFY COVERED (2026-10-07).** RE-RUN: the cooldown and
pin path end to end (`herdr-cooldown-check` ELIGIBLE at 7.2 days, the hand
upgrade, pin back on, then 0 actions); `herdr status` still printing separate
client and server blocks, both 0.9.3 on protocol 22; `herdr status server --json`
reading `running: false` against an absent socket and `true` against the live
one; `herdr config check` ok with both phone-home keys still `false`; and a real
server stop and start, with the workspaces restored. That restart is what
F9b could not do, and it found two things this document had wrong: Homebrew no
longer ships a herdr service (the persistent-server section is rewritten), and
an upgrade does not rewrite the Claude hook (item 13 and the hooks section are
corrected). The Linux pin moved to v0.9.3 with three-way hash agreement. NOT
RE-RUN: the Linux systemd unit and the herdr() guard on Linux (no Linux box in
this session), remote attach and the keymap-drift claims, the tmux comparison,
and speak-selection; they keep their earlier evidence. The 0.9.2 CHANGELOG
said two of those may have moved, and both had (re-run 2026-10-08 on 0.9.3,
W-20261007-A02): `send-keys ctrl+shift+c` into a shell no longer arrives as
`0x03` (changelog #4581; "Who copies on a drag" is corrected), and an action
now takes several keys, not one (the ported keymap's "single key per action"
is corrected; #4653 is the related change that allows several prefix keys).
0.9.3 itself only fixed Escape-prefixed keys (#4751), which 0.9.2 had broken;
"Keys in a Ghostty pane since 0.9.2" below has what broke.

**WHAT THE 0.9.1 RE-VERIFY COVERED HERE.** This document is about the cooldown
machinery, running herdr as a persistent server, and where it overlaps with
tmux, so the delta that matters to it is 0.9.0's client and server split rather
than any agent behaviour. RE-RUN: `herdr status server --json` and its `.running`
and `.restart_needed` fields, read at 0.9.1 running with `restart_needed: false`
and `compatible: true`; `herdr status` printing separate client and server
version blocks, which is the shape 0.9.0's split produced and which this document
should be read against; the pin and the cooldown gate, exercised by the
SessionStart hook on every launch that day; and the Cellar keg and cached bottle
facts in the rollback section, re-measured for W-20260922-A22, which also added
the `HOMEBREW_NO_INSTALL_CLEANUP` guard to `install.sh` and the two Homebrew
cleanup defaults (30 days periodic, 120 days cache) read from Homebrew's own
`env_config.rb` with a control. NOT RE-RUN, and the reason is the same one that
blocked F9: anything that requires stopping or restarting the server, including
the systemd and launchd service paths and the hand-started-server warning. Those
carry their original 2026-09-06 and 0.8.2 evidence and are unchanged by this
stamp. Checked and found absent rather than assumed: this document makes no claim
about `--no-session`, which 0.9.0 removed.

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

**The number is 3 days since 2026-10-18** (D-20261018-A01, Gavin). It was 7
until 2026-09-22, then 5 (D-20260922-A10), then 3 when he asked for v0.9.5 at
3.4 days old with the 5-day gate still holding it. v0.9.5 was a hotfix that
followed v0.9.4 by a day, which is the follow-up release the shorter wait is
priced on; the accepted cost is less warning on every future herdr release.
`install.sh` holds the value, and `herdr-cooldown-check` falls back to 3 when
`HERDR_COOLDOWN_DAYS` is unset. Only the number moved: pin, checker and auto-bump
are unchanged. `decided herdr cooldown` prints both rulings.

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

## What the checker checks (6 subjects)

| #   | Subject        | Question                                                                                  |
| --- | -------------- | ----------------------------------------------------------------------------------------- |
| 0   | `brew`         | can Homebrew answer **at all**? (see "A broken brew is not a direct install")             |
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

### A broken brew is not a direct install

**Measured 2026-09-18, and it had silently disabled three guards.** An Xcode 27
update left its licence unaccepted, so every `brew` command on the Mac exited 1
with its message on stderr. Four separate places then read that failure as
_"herdr is not managed by Homebrew"_:

| Place                                   | The line                                                 | What it did                                                                                                                                                                                            |
| --------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `herdr-cooldown-check`                  | `install_method()` probing `brew list --versions herdr`  | reported `install_method: "direct"`, which **removed the `pin` row from the report entirely** — not a `SKIPPED` line, gone — and printed a download-from-GitHub fix for a brew-managed, pinned install |
| `_preflight_herdr_pin_check`            | `brew list --versions herdr &>/dev/null \|\| return 0`   | pin guard off, no output                                                                                                                                                                               |
| `_preflight_herdr_bump_check`           | same line                                                | **cooldown auto-bump off, no output** — an eligible release would simply never have been adopted                                                                                                       |
| `_preflight_herdr_service_health_check` | `command -v brew` then an unchecked `brew services info` | service check off, no output                                                                                                                                                                           |

The root cause is one fact: **`brew list --versions <formula>` exits 1 with
EMPTY stdout both when the formula is genuinely absent and when Homebrew is
broken.** It cannot distinguish them, and `&>/dev/null` discarded the stderr
that could. This is the count-and-absence rule in `CLAUDE.md` wearing a
different hat — a refusal to answer is not an answer of "no".

**The fix is a self-controlling probe.** `brew list --formula` is used instead,
because a non-empty roster is itself proof that Homebrew can answer; only then
does "herdr is not in the roster" support a conclusion. A failed _or empty_
roster yields a third state, `brew-broken`, which is reported **loudly** and
still runs the pin check (the pin marker is read off disk and needs no working
brew). `install.sh` gained `_brew_health` / `_brew_has` / `_warn_brew_unusable`
for the same three-way answer, and says once, in full, that its guards are
degraded.

Both detectors are self-tested in both directions on every run:
`classify_install()` has six arms (including "a FAILED roster is BROKEN, not
`direct`" and "an EMPTY roster proves nothing"), and the installer helpers were
driven against a fake `brew` that replays the exact Xcode error.

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
- **Cache:** 6h verdict cache in `$TMPDIR`. A release crossing the cooldown line is
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
HERDR_VERSION="v0.7.5"   # illustrative -- install.sh holds the current pin
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
brew unpin herdr; HOMEBREW_NO_INSTALL_CLEANUP=1 brew upgrade herdr; brew pin herdr
herdr-cooldown-check                                    # confirm the pin is back
readlink -f "$(brew --prefix herdr)/bin/herdr"          # the path to re-grant (below)
```

**Then re-grant Full Disk Access, by hand, every time.** macOS stores herdr's
grant against the versioned path the symlink resolved to
(`/opt/homebrew/Cellar/herdr/<v>/bin/herdr`) and the binary's code hash, so an
upgrade drops it silently: every herdr-hosted session then gets EPERM on network
volumes while Terminal and Finder still work. System Settings > Privacy &
Security > Full Disk Access > +, add the new path, remove the old entries.
`install.sh`'s auto-bump prints the exact path and, when
`~/CODE/CaptainCodeAU/Network_Plan/tools/check-herdr-fda.py` is on the box, runs
it. Measured 2026-10-07 on 0.9.3: the 0.9.1 grant was stale after the upgrade,
the re-grant gave `check-herdr-fda.py --check` PASS, and no herdr restart was
needed (W-20261007-A16). Measured 2026-10-18 on 0.9.5: re-granted by hand at
3:32 PM, and `check-herdr-fda.py --check` PASS (re-run for this re-verify,
`granted + installed: /opt/homebrew/Cellar/herdr/0.9.5/bin/herdr`). Before that
re-grant, with a 0.9.5 server and only the 0.9.3 grant, `/Volumes/mac` was still
readable from a herdr pane. The likely reason is that Ghostty holds Full Disk
Access and started the server, so macOS credited Ghostty's grant. Likely, not
proven: do not count on it, and re-grant anyway.

`;` rather than `&&` so the pin comes back even when the upgrade fails, and
`HOMEBREW_NO_INSTALL_CLEANUP=1` because without it Homebrew deletes the old
version and its cached bottle, which are the only way back. Measured 2026-10-07:
the 0.9.1 to 0.9.3 upgrade was typed by hand without it, and cleanup removed both.
`install.sh` has always set it; the hand-typed line printed here did not.
Measured 2026-10-18: the 0.9.3 to 0.9.5 upgrade was typed with it, and the 0.9.3
keg stayed (`brew info` lists 0.9.3 and 0.9.5). The 0.9.3 bottle is not in the
Homebrew cache, where the 0.9.5 one is, so the kept keg is the way back.

Linux/WSL is unchanged — `_preflight_herdr_release_check` already applies pinned,
hash-verified `HERDR_VERSION` bumps automatically; see the runbook above the
`HERDR_VERSION` comment block in `install.sh` for that side.

#### When the aged release is one Homebrew no longer offers

**The gate weighs exactly ONE candidate: whatever `brew upgrade herdr` would
install right now.** That is deliberate (gating against a version Homebrew
cannot deliver was the 2026-08-20 bug above), but it has a consequence nobody
had written down: when upstream ships faster than the cooldown, the release
that HAS aged out can be one Homebrew has already moved past, and there is then
no supported `brew` route to it.

Measured 2026-09-18, on a Mac sitting at 0.8.2:

| Release | Age      | Status                                                    |
| ------- | -------- | --------------------------------------------------------- |
| v0.9.0  | 11 days  | past the 7-day gate, but the formula had already moved on |
| v0.9.1  | 1.4 days | what `brew upgrade` offers, and HELD by the gate          |

So the gate correctly reported `HELD`, and the only genuinely-aged release was
unobtainable. This is not a defect to fix; it is the gate preferring "wait a
few more days" over "leave the pin". Usually waiting is right, and the newer
release is strictly better anyway.

If a specific superseded version really is wanted, this route keeps Homebrew's
checksum guarantee rather than reaching for the unvetted GitHub binary. Find
the homebrew-core commit that shipped it, take the bottle sha for this
platform out of that formula, and pull the bottle from ghcr by that digest:

```bash
# 1. the commit that bottled the version you want
curl -s "https://api.github.com/repos/Homebrew/homebrew-core/commits?path=Formula/h/herdr.rb&per_page=10" \
  | grep -E '"(sha|message)"'
# 2. that formula's bottle block -> the sha256 for your platform (e.g. arm64_tahoe)
curl -sL "https://raw.githubusercontent.com/Homebrew/homebrew-core/<commit>/Formula/h/herdr.rb"
# 3. the bottle IS that sha256, as a ghcr blob digest
TOK=$(curl -s "https://ghcr.io/token?service=ghcr.io&scope=repository:homebrew/core/herdr:pull" | jq -r .token)
curl -sL -H "Authorization: Bearer $TOK" \
  "https://ghcr.io/v2/homebrew/core/herdr/blobs/sha256:<bottle-sha>" -o bottle.tar.gz
shasum -a 256 bottle.tar.gz   # MUST equal <bottle-sha>, or stop
```

**Verified 2026-09-18 for v0.9.0/arm64_tahoe** (formula commit `3015bef7f7b4`,
bottle `c9c87784...41242f5`): the blob downloads and its sha256 matches the
formula exactly. **Not verified: that `brew install` accepts the local bottle
without falling back to a source build** (herdr needs rust + `zig@0.15`).

Two caveats before using it at all. The keg lands outside the
`unpin/upgrade/pin` path the auto-bump assumes. And the auto-bump will replace
it with the newer release as soon as that clears the cooldown, so this buys a
few days, not a resting place.

#### What a bump actually touches

Asked on 2026-09-17 and worth writing down, because most of the list is ours,
not Homebrew's.

Homebrew does these on its own:

| Path                                         | What happens                                                                                      |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `$(brew --prefix)/Cellar/herdr/<new>/`       | new tree: `bin/herdr`, `CHANGELOG.md`, `sbom.spdx.json`, `INSTALL_RECEIPT.json`, `.brew/herdr.rb` |
| `$(brew --prefix)/bin/herdr`, `opt/herdr`    | symlinks repointed                                                                                |
| `$(brew --prefix)/var/homebrew/pinned/herdr` | removed by `brew unpin`, recreated by `brew pin`                                                  |
| the 6h cache in `$TMPDIR`                    | `herdr-cooldown-check`'s verdict goes stale                                                       |

These are ours, and nothing upstream will do them for you:

| #   | File                                                                                | Version-bound thing                                                          |
| --- | ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| 1   | `install.sh`                                                                        | `HERDR_VERSION` (Linux pin)                                                  |
| 2   | `install.sh`                                                                        | both `HERDR_SHA256_LINUX_*` hashes                                           |
| 3   | `home/.claude/skills/herdr/UPSTREAM.md`                                             | the skill merge base -- 0.8.2 revised the bundled skill wholesale (#2847)    |
| 4   | `home/.claude/skills/herdr/UPSTREAM.version`                                        | the tag that capture came from                                               |
| 5   | `home/.claude/skills/herdr/SKILL.md`                                                | whatever the merge pulls in                                                  |
| 6-9 | `docs/HERDR*.md`                                                                    | one `herdr-verified:` line each                                              |
| 10  | `home/.config/herdr/config.toml`                                                    | only when a release retires or adds a key -- run `herdr config check`        |
| 11  | `herdr-plugins/*/herdr-plugin.toml`                                                 | `min_herdr_version`, and the plugin API if it moved                          |
| 12  | `home/.config/systemd/user/herdr.service`                                           | only if service flags change                                                 |
| 13  | `~/.claude/hooks/herdr-agent-state.sh` + its `~/.claude/settings.json` registration | **NOT rewritten by an upgrade**: `herdr integration status` says `outdated`  |
| 14  | macOS Full Disk Access (System Settings, not a file)                                | the grant names `Cellar/herdr/<v>/bin/herdr`: **re-grant by hand** (runbook) |

Item 13 is the odd one. herdr installs a state-reporting hook into each agent
CLI it finds, each file declaring itself "managed by herdr; reinstalling or
updating the integration overwrites this file". This row used to say a bump
rewrites it on its own. **Measured 2026-10-07, it does not:** the Claude hook
was still `HERDR_INTEGRATION_VERSION=8`, dated 2026-09-06, after two upgrades
(0.9.1 on 2026-09-22, 0.9.3 on 2026-10-07), and `herdr integration status`
reported `claude: outdated (v8 < v10)`. The 0.9.5 upgrade on 2026-10-18 did the
same: the live hook stayed v10 and `herdr integration status` read
`claude: outdated (v10 < v11)` until Gavin applied v11 by hand that day (step 4
below). The rewrite happens only on
`herdr integration install claude`, so after a bump, check `herdr integration
status` and decide. It is executable code in real files under `~/.claude`, not
stow symlinks, so a restow does not restore them. The section further down,
"It installs hooks into your agent CLIs", has the full account.

(Since 2026-09-24 a Claude worker starts only through `pj-worker start`, and the plain
`--kind claude` route below is refused in herdr panes; D-20260924-A05. Kept as history.)

**And the herdr spawn path does NOT run our credential wrapper.** Measured
2026-09-17 in a throwaway workspace: `herdr agent start --kind claude` echoes
the bare command `claude` into the pane, not the `c` alias, so `_claude_launch`
never runs. That session came up with `GH_TOKEN` of length 0 and `NVD_API_KEY`
unset (control: `${#HOME}` was 17 in the same command, so the probe did run).
`gh` then falls through to its own keyring, which holds a `repo`-scoped token.
Nothing about this is herdr-specific: `_claude_launch` is reachable only through
zsh aliases, which no spawned process inherits. Incident:
`INC-20260915-herdr-spawn-bypasses-credential-path.md` in lifeos-private.

**THE FIX IS ALREADY RULED ON, AND IT IS NOT A HERDR CHANGE.** See
`docs/GITHUB_CREDENTIAL_LANES.md` sections 4 and 8: fix the consumers, not the
launcher. A shell-layer fix (alias, `claude()` function, PATH shim) was costed
and dropped on measurements, twice. This cross-reference exists because the
second time happened entirely because this paragraph did not carry it -- the
ruling was one hop away from where anyone stands when the question comes up.
`decided herdr spawn credential` prints it without the reading.

`herdr-skill-drift-check` reports 3, 4 and 6-9 with no thinking required: it
compares the live `herdr --skill` to the stored snapshot, the snapshot's version
to the binary, and every doc stamp to the binary. Items 1, 2, 10, 11 and 14 are
still a human's job. `herdr-linux-pin-check` covers 1 and 2.

#### What install.sh does after stow

`_post_stow_herdr_plugins_and_skill` (added 2026-09-17) closes three gaps
between "stow put the files there" and "herdr actually works here":

- **`herdr plugin link`** for every plugin in `herdr-plugins/`, linked from the
  repo itself. herdr only knows a plugin exists once it is in
  `~/.config/herdr/plugins.json` -- machine-local state this repo does not track,
  because it holds absolute paths. Before this, a fresh box got the files and a
  silently broken window title. `link`, never `install`: see `HERDR_PLUGINS.md`
  section 1. Until 18 Oct 2026 `window-title-fix` was stowed from
  `home/.config/herdr/plugins/`; it moved to `herdr-plugins/` so plugins sit
  apart from the settings and can later move to a repo of their own in one step
  (Gavin, dotfiles-main Q63: 1). A plugin still registered at its old path is
  unlinked and linked again, and the dangling links stow left go to the Trash.
- **The `~/.agents` skill symlink.** Codex discovers `~/.agents/skills` as a
  skill root by convention, with no config entry and nothing to grep for. Until
  2026-09-17 that was a separate copy of the herdr skill and it had drifted from
  Claude's. Both now point at the one file in this repo. A REAL file found there
  is backed up, not overwritten.
- **`herdr config check`.** 0.8.2 made it report unknown built-in theme names
  instead of accepting them silently (#2452). It reports; it never repairs.
  `config.toml` is tracked, and an installer that edits it can lose your
  keybindings. It earned its place the day it was added, catching two settings
  written under `[ui]` that belong under `[server]`.

## Running herdr as a persistent server

herdr is a server/client design: panes and agents live in a background server,
clients attach and detach. `herdr server` is the documented headless entrypoint
("use it for supervised or service-style setups").

**On macOS there is no service any more.** Homebrew removed herdr's service
definition on 2026-09-24 (homebrew-core `fe0006641fba`, "herdr: remove service
definition"), so `brew services start|stop|restart herdr` no longer applies. The
0.9.3 formula reports `service: null` and its keg ships 12 files where 0.9.1's
shipped 14; 0.9.5 is the same (`service: null`, the same 12 files, not counting
Finder's `.DS_Store`). herdr starts its own detached server when you attach, with
no launchd job behind it. On 0.9.3 that server's parent was PID 1 (measured
2026-10-07: `launchctl list` had no herdr job; the server was PID 95343, PPID 1).
**On 0.9.5 its parent is the `herdr` client that started it**, but in a session
of its own with no terminal (measured 2026-10-18: server PID 16675, PPID 16674,
which is `herdr` in a Ghostty login shell; `ps` shows the server `Ss`, PGID
16675, tty `??`; `launchctl list` had no herdr job, control: the Ghostty job
listed in the same command). What its PPID becomes once that client exits was
not measured.

Measured on this Mac, 2026-10-07:

| Command                       | What it does now                                                                                                                                 |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `herdr server stop`           | Asks the server over its socket to save and exit. Every pane and agent ends. Nothing restarts it.                                                |
| `herdr` (attach)              | Starts a fresh server from the installed binary and restores the saved workspaces (0.9.1 stopped at 11:27 AM, 0.9.3 up at 11:29 AM, 13 restored) |
| `brew services restart herdr` | Nothing to restart: the formula has no service. Not run.                                                                                         |
| `brew services stop herdr`    | Only ever stopped a launchd job; it never touched a server herdr started itself.                                                                 |

So **to restart onto a new build: `herdr server stop`, then open `herdr`.**
`./install.sh` offers exactly that after an upgrade (`_herdr_offer_restart
--stop-only`): it lists what runs inside herdr and stops only on a typed
`restart`, and never from inside a herdr pane. The server log shows the same
clean cycle three times before this was written down (2026-09-30, and twice on
2026-10-04), each one ending in `session restore evaluated ... workspaces=N`.
It ran again on 2026-10-18 onto 0.9.5: the 0.9.3 server stopped at 3:27 PM and
0.9.5 was up at 3:28 PM, then stopped and started once more at 3:32 to 3:33 PM;
both 0.9.5 starts logged `workspaces=11`.

**Restored agents start one at a time** since 0.9.2, 100 ms apart by default,
rather than all at once (#4102, per the 0.9.2 release notes).
`[session] startup_per_agent_delay_ms` sets the spacing, and 0 starts them
with none. Measured 2026-10-18 on 0.9.5: `herdr --default-config` lists it at
100, and a scratch config setting it passes `herdr config check` while a
misspelt `startup_per_agent_delay_mz` is flagged as an unknown key. This config
does not set it, and the stagger itself was not timed.

**A restore no longer stalls on slow Git** (#4945, #4926, per the 0.9.4 release
notes). The report was a launchd-started server that never answered after
restoring a save written by a shell-started one. The same fix keeps worktree
groups through a checkout that is briefly unavailable, and opening the same
repository twice no longer nests the second workspace inside the first one's
worktree group, where it could only be closed with the whole group (#4736). Not
re-measured.

**Since 0.9.4 the shell that started herdr no longer takes the server with it**
(#4920, release notes): on macOS and Linux, closing that shell does not stop the
server, and neither does `SIGHUP`. Stop it with `herdr server stop` or `SIGTERM`.
Not re-measured here, because the test is closing the window that holds the
server. What 0.9.4 also added, and this one IS measured, is that the server log
now names the cause of every stop. The 0.9.3 log did not:

```
04:27:46Z server shutdown initiated                           # 0.9.3
04:28:10Z server shutdown initiated reason=SIGINT             # 0.9.5
04:32:03Z server shutdown initiated reason=server.stop request from pid 13659 (herdr), parent pid 52262 (zsh)
```

(`~/.config/herdr/herdr-server.log`, 2026-10-18, times UTC.) So the first
question about an unexpected stop, "who asked?", is now one line of the log.

What the Mac gave up: **crash-restart.** A crashed server stays down until the
next attach. Start-at-login never mattered much, because attach starts it anyway.
Linux keeps both through its systemd unit (below).

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
| first `herdr` attach          | starting the server after any boot or crash       | nothing runs until then     |
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

And since 0.9.4 a planned restart keeps the sessions: herdr saves before macOS
starts closing apps, so the agents come back where they were on the next attach
(#4414, release notes). Saves are also written to disk before they replace the
old file (#5150), so a crash or power cut cannot leave an unreadable save. Not
re-measured: no restart was done for this re-verify.

**If a restore goes wrong, older layouts are kept.** Since 0.9.2 herdr keeps up
to 48 layout snapshots in `session-snapshots/` for recovery by hand, and on
Linux with logind (codebox) it saves before the system shuts down (#4320, per
the 0.9.2 release notes). Measured 2026-10-18 on 0.9.5:
`~/.config/herdr/session-snapshots/` holds 48 `session-*.json` files, the cap
exactly. How to restore from one was not tried, and the logind half was not
measured.

### A leftover LaunchAgent from before 2026-09-24

A Mac that ran `brew services start herdr` while the formula still had a service
can still carry `~/Library/LaunchAgents/homebrew.mxcl.herdr.plist`. Removing the
service from the formula does not unload it, so launchd keeps running herdr with
the formula's old `keep_alive true`, and everything below still happens there.
`./install.sh` reports the file and prints how to remove it; the `herdr()` guard
refuses a hand start while it exists. Neither removes it, because that ends
every pane.

`keep_alive true` is **unconditional**: launchd restarts the job on any exit,
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
when the cause is entirely local to the server box. A hand-started second
server is worse: it exits 1 on the socket, and `keep_alive` relaunches it
forever, throttled to about one attempt every ten seconds.

**PPID 1 does NOT tell the two apart.** This section used to give a launchd
server's PPID 1 as part of the signature, but a server herdr 0.9.x starts itself
detaches to PPID 1 too (PID 95343, 2026-10-07, no launchd job). On 0.9.5 a
self-started server shows its attaching client as the parent instead
(2026-10-18), which settles nothing either. Only launchd can
answer, and `runs` climbing with `last exit code = 0` is the signature:

```bash
launchctl print "gui/$(id -u)/homebrew.mxcl.herdr" | grep -E 'state|runs|last exit|properties'
#   state = running
#   runs = 6
#   last exit code = 0
#   properties = keepalive | runatload | inferred program
```

No such job (`Could not find service`) means there is no leftover. To remove
one, when nothing in herdr needs to survive:

```bash
launchctl bootout "gui/$(id -u)/homebrew.mxcl.herdr"   # ends the server and every pane
rm ~/Library/LaunchAgents/homebrew.mxcl.herdr.plist      # bare rm goes to the Trash
```

### Two machines: keep the versions in step

Remote attach is not version-agnostic. Client and server negotiate a protocol,
and `herdr status server` reports the version, the protocol and whether they fit
(0.9.5, 2026-10-18; 0.7.5 printed one `protocol: 17` and one `compatible: yes`
line instead of the last four):

```
status: running
version: 0.9.5
endpoint_compatible: yes
private_protocol: 22
private_protocol_compatible: yes
socket: ~/.config/herdr/herdr.sock
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

Not every wire change forces the step. Since 0.9.2 a saved machine sends only
the rows that changed when output scrolls, and a pre-0.9.2 client or server
keeps working with the old format rather than refusing (#4711, per the 0.9.2
release notes). Not measured; keep the ends in step anyway.

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
  export HERDR_REMOTE_KEYBINDINGS=server   # same choice, without the flag; NOT globally, see below
  ```

  This is the option that removes the failure class rather than re-fixing it per
  machine: one file, one commit, no drift. The cost is that the client can no
  longer hold keybindings of its own — which costs nothing when both ends stow
  the same config anyway. There is no `[remote]` config key for this; the flag
  and the environment variable are the only routes. (A `[remote]` table does
  exist, but its one key is `manage_ssh_config`: on 0.9.5 `herdr config check`
  reports `unknown config key remote.keybindings`, while
  `remote.manage_ssh_config` passes. Both flag and variable are still in the
  0.9.5 binary, and a misspelt `--remote-keybinding` is refused with exit 2.)

Confirmed 2026-08-01 the hard way: `previous_agent` / `next_agent` were added
here, validated, and reloaded, and did nothing on the laptop until the attach was
re-made with `--remote-keybindings server`.

Hit again 2026-10-16: the speak keys (`[[keys.command]]`) did nothing in a
`herdr --remote codebox.lan` tab until the attach was re-made with
`--remote-keybindings server`; then the first press spoke (Gavin's test). From
then `home/.zshrc` exported `HERDR_REMOTE_KEYBINDINGS=server` on every machine,
so every remote attach used the far box's keys without the flag. A far box must
pull the dotfiles to get a newly added key.

**That export broke saved machines, so since 2026-10-18 only `--remote` gets it.**
With the variable set, the Mac's NORMAL `herdr` screen never joined saved machines:
no "machines" section, no ssh helper started, and nothing in the client log even
with `HERDR_LOG=debug`, while `herdr machine status` read `reachable` and codebox had
a workspace. Measured 18 Oct, the same screen and moment: plain `herdr` showed no
codebox; `env -u HERDR_REMOTE_KEYBINDINGS herdr` showed `machines`, Local and
codebox.lan at once. The `herdr()` function in `home/.zshrc` now adds
`--remote-keybindings server` only when the arguments contain `--remote` and no
explicit `--remote-keybindings`; nothing is exported. A shell opened before the
change still carries the old variable until it is closed or runs
`unset HERDR_REMOTE_KEYBINDINGS`.

### Linux / WSL: the systemd user service

Added 2026-09-06. The Linux counterpart of what `brew services start herdr` was on
macOS until Homebrew dropped herdr's service on 2026-09-24.
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
   same respawn loop the leftover-LaunchAgent section above describes. The
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
foreground server also died with the SSH session (on 0.8.x; since 0.9.4 a
`SIGHUP` no longer stops the server, #4920, so on 0.9.5 that half may not hold
any more. Not re-measured on Linux; the environment half does not depend on
it). systemd gives a clean
environment, crash-restart, and (with linger) survival across logout.

**Running out of processes no longer takes every pane down.** Before 0.9.4, a
server whose systemd user slice hit `TasksMax` exited and every pane went with
it; since 0.9.4 the server keeps running when the machine runs out of processes
or threads (#3324, #4958, per the 0.9.4 release notes). That is this unit's
shape exactly. Not measured on codebox.

The unit sets `PATH` explicitly because the user manager's default has no
`~/.local/bin`, which is where install.sh puts the pinned binary. It does not
add `/usr/lib/wsl/lib`: `gpu-status.sh` calls `nvidia-smi` by absolute path.

The service fixes the banner symptom, not its cause. The cause is that
`home/.zshrc` exports the two once-only flags for the life of every child
process. Scoping them per-tty would make any child -- a tmux server, a
hand-started herdr on the Mac -- show the banner too. That is a separate
change, not made here.

**The GPU status command runs wherever the server runs.** `config.toml`'s
`tab_bar_right` used to point at the Mac's repo checkout by absolute path. On
the Linux box that path does not exist, so the server logged one exit-127
warning every five seconds -- 12188 of 12641 lines in a 3 MB log before anyone
looked. It now runs `~/.config/herdr/gpu-status.sh` (stowed, same path on every
box), and the script reads `nvidia-smi` locally when it finds the WSL binary,
over SSH otherwise.

### The `herdr()` shell guard: hand starts are refused

Added 2026-09-06, tag `herdr-guard-v1`. A `herdr()` function in `home/.zshrc`
(next to the `gh()` guard, same shape) sits in front of the binary. It acts
only where a service manages the server, detected by the file the service
leaves behind: the stowed unit symlink on Linux, the brew plist on macOS. A
box with neither is untouched.

| You type                                     | What happens                                                                                                                   | Why                                                                                                                                                                                                                                                                                           |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `herdr server`                               | **Refused.** Prints `systemctl --user start herdr.service` (Linux), or on a Mac with a leftover LaunchAgent, how to remove it. | A hand-started server inherits the shell's environment and dies with the session -- the whole reason the service exists. With a leftover LaunchAgent it also exits 1 on the socket and `keep_alive` respawns it forever. A Mac without one is not guarded: herdr starts its own server there. |
| `herdr server stop`, `reload-config`, ...    | Pass through.                                                                                                                  | Only the bare form starts a server.                                                                                                                                                                                                                                                           |
| `herdr update`                               | **Refused** (2026-09-17). Prints `herdr-cooldown-check` and `./install.sh`.                                                    | herdr ships its own updater. It downloads and installs a release directly, walking around Homebrew, `brew pin` and the whole `HERDR_COOLDOWN_DAYS` gate in one command.                                                                                                                       |
| `herdr channel set preview`                  | **Refused** (2026-09-17).                                                                                                      | Same hole by another route: it repoints that updater at preview builds. `channel set stable` passes through.                                                                                                                                                                                  |
| `herdr` (attach), Linux, unit down           | Starts the unit first, then attaches.                                                                                          | Upstream attach "starts or attaches to" a server: with the unit down it would spawn the same hand-started server with no visible command.                                                                                                                                                     |
| Anything inside a herdr pane (`HERDR_ENV=1`) | No check at all.                                                                                                               | The server is by definition running; agents call the CLI constantly and should pay nothing.                                                                                                                                                                                                   |

Its notices go to stderr, so `herdr status server --json | jq` keeps working
(the first live test broke exactly that).

**Limit, stated plainly.** It is a shell function: it covers a prompt and
Claude's Bash tool (which loads the snapshotted functions), not a script that
calls the binary by full path. Nothing in this repo does that, and while the
unit is running a second server cannot take the socket anyway -- the guard is
the polite refusal, the socket is the hard one.

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

What the screen does differently since 0.9.2, all per the release notes and
none of it measured here:

- **Images** (#4561, #4652, #4686). An app that draws Kitty graphics in a pane
  reaches a local Ghostty through temporary files rather than terminal output,
  popups and notifications crop around images instead of hiding them, and an
  image scrolled out of view stays loaded. Nothing here draws images in a pane.
- **No torn frames** (#2968, #4303). Apps that use synchronized output no
  longer tear while you type, and the cursor no longer flickers when herdr
  redraws status. Whether Claude Code uses synchronized output was not checked.
- **Stale prompt rows after a resize are a known bug** (#3672, #4977, 0.9.4).
  0.9.4 stopped Fish repeating prompt fragments on a pane resize; the same
  problem with zsh and Powerlevel10k, this estate's prompt, is still open and
  waits on a Ghostty fix. Repeated prompt rows after a split or resize are that
  bug, not a broken config.

Default keymap against this repo's `.tmux.conf`:

| Action              | herdr                   | this repo's tmux         |
| ------------------- | ----------------------- | ------------------------ |
| Prefix              | `ctrl+b`                | `ctrl+Space`             |
| New tab / window    | `prefix+c`              | `prefix+c`               |
| Split right / down  | `prefix+v` / `prefix+-` | `prefix+\|` / `prefix+-` |
| Move between panes  | `prefix+h/j/k/l`        | `prefix+h/j/k/l`         |
| Zoom / close / copy | `prefix+z` / `x` / `[`  | `prefix+z` / `x` / `[`   |
| Detach              | `prefix+q`              | `prefix+d`               |

**Detaching by typing: `herdr-detach`** (`home/.local/bin`, 18 Oct 2026, Gavin's ask).
herdr 0.9.5 has no typed detach: not in `--help`, not in `herdr session` (stop ends
the whole session), not in the API schema. `herdr-detach` sends SIGTERM to the herdr
CLIENT only, which measured as a detach on a throwaway session: the client logged a
completed shutdown, the session's server stayed `running`, and the client's last
output left full screen and turned mouse reporting off. It never signals a server
or a helper (`--pid` on the server's pid is refused), and with more than one
matching screen it refuses to guess and lists them (`--pid N` or `--all`).
`--list` and `--dry-run` change nothing; `--selftest` proves its 12 classifier arms.

Two remote modes, and the second has no tmux equivalent:

```bash
ssh <host> && herdr        # tmux-style: client and server both remote
herdr --remote <host>      # thin client: UI streams to the local terminal
```

`--remote` runs the client locally, so it can bridge local desktop features
(including image clipboard paste) into the remote session and use **local**
keybindings against a remote server. It honours `~/.ssh/config` host aliases and
normal OpenSSH auth.

Two SSH fixes worth knowing, both per the release notes and not measured here:

- **Stray characters after a focus switch** (#4630, 0.9.2). Over SSH, a mouse
  report split across two reads used to leak into the shell as junk after a
  focus switch. Junk like that in a codebox pane on 0.9.2 or later is a new
  bug, not this one.
- **A forwarded SSH agent is no longer polled every second** (#4931, #4962,
  0.9.4). Before, a remote session with agent forwarding could make the Mac's
  SSH agent unresponsive and break SSH and Git authentication. This matters for
  a `ForwardAgent yes` host (which `install.sh` suggests for trusted LAN boxes);
  the codebox machine route uses no forwards (`HERDR_SIDEBAR.md`).

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
  nothing to it, so no reclaim is required. Before 0.9.4, an outer-terminal
  reset (the report was VS Code's Reload Window) could make Shift+Enter reach
  the pane as a bare Enter, which submits a Claude prompt instead of adding a
  newline; 0.9.4 keeps Shift+Enter and the other enhanced keys working across a
  reset (#4985, #5088, per the 0.9.4 release notes, not measured).
- **Copy mode — already equivalent.** herdr's copy mode is vi-style out of the
  box (`v` selects, `y` copies, `q`/Esc leaves), matching the `mode-keys vi`
  setup in `.tmux.conf`. Only `ctrl+v` rectangle-select has no counterpart.
  Since 0.9.2 it also stays open while the pane keeps printing and a movement
  key is held (#3812, #4281, per the 0.9.2 release notes, not measured), so on
  an older build, output arriving mid-selection could drop you out of it.

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

**Closing asks first, and one key turns it off.** Closing a workspace's last tab
asks for confirmation since 0.9.2 (#4379), and closing its only pane does too
since 0.9.4 (#5143, #5173), per the release notes. The key is
`[ui] confirm_close`, and `confirm_close = false` turns the only-pane question
off; the notes do not say whether it also silences the last-tab one, and that
was not tried. Measured 2026-10-18 on 0.9.5: `herdr --default-config` lists
`confirm_close = true` ("Ask for confirmation before closing a workspace"),
and a scratch config
with `confirm_close = false` passes `herdr config check` while a misspelt
`confirm_closee` is flagged as an unknown key. This config does not set it, so
both questions are on. A close from the CLI or API does not ask
(`HERDR_AGENT_AUTOMATION.md`, from the release notes, not measured).

The one structural difference, **as of 0.9.1: herdr took a single key per
action**, where tmux allowed several. `.tmux.conf` bound the right-hand split
four ways (`|`, `Right`, `%`, `h`); only one survived the port. The same
constraint meant Alt+Arrow pane switching and `prefix+h/j/k/l` could not both
exist, so the config keeps the vim keys and documents the swap.

**That constraint is gone on 0.9.3** (measured 2026-10-08, W-20261007-A02): a key
takes a list, `split_vertical = ["prefix+|", "prefix+right", "prefix+%", "prefix+h"]`
passes `herdr config check`, a bad entry in the list is flagged by name
(`invalid keybinding: keys.split_vertical = "prefix+nosuchkey"`), and
`prefix = ["ctrl+space", "ctrl+s"]` passes too (#4653). Measured with a
throwaway `HOME` and a known-bad key as the control; whether the running server
then answers every entry was not tested, and the live config is unchanged.
Re-run on 0.9.5 on 2026-10-18 with the same throwaway configs, through
`HERDR_CONFIG_PATH`: the four-key list and the two-key prefix pass, and the bad
entry is flagged in the same words.
Validate any change with `herdr config check`.

**Recommendation: do not nest them, and do not delete tmux either.** Stop
launching tmux and drive herdr for a couple of weeks instead. The tmux config
costs nothing sitting on disk, and herdr is a young project — keep the retreat
path intact. Prefixes do not collide (`ctrl+Space` vs `ctrl+b`) if you do end up
nested, but layered multiplexers mangle keys and you will blame the wrong thing.

### Keys in a Ghostty pane since 0.9.2

What changed for keys and clicks between 0.9.2 and 0.9.5. All of it is per the
release notes, and none of it was re-tested on Ghostty here unless marked.

- **0.9.2 broke Escape-prefixed keys; 0.9.3 fixed them** (#4751). On 0.9.2, in
  a pane, Option+Left/Right typed `b`/`f` instead of moving by word,
  Option+Backspace deleted one character instead of a word (Ghostty's defaults
  and iTerm2's Natural Text Editing preset both send these), and an
  Escape-based Shift+Enter binding submitted to Claude Code instead of adding a
  newline. 0.9.3 restored all three. The same fix stopped Alt+[ followed
  quickly by another key merging into a different key; no binding here uses
  Alt+[. If any of these misbehave, check the server is not on 0.9.2.
- **A click no longer interrupts a working agent** (#3480, 0.9.2). Before 0.9.2,
  clicking into a pane could send a stray Escape, which interrupts a Claude
  turn in progress. 0.9.3 kept that fix while restoring the Escape-prefixed
  keys above. On 0.9.1 or older, do not click into a pane whose agent is
  working.
- **The key after the prefix can arrive as plain text** (#5255, 0.9.5). 0.9.4
  ignored it when the terminal sent it as text rather than a key event, which
  broke Tern and the macOS Chinese, Japanese and Korean input methods, Ghostty `text:`
  keybinds that send the prefix and a key together, and workspace navigation
  the same way; 0.9.5 fixed it. This config sets
  `[experimental] switch_ascii_input_source_in_prefix = true`, and the repo's
  Ghostty config has no `text:` binds (2 `keybind` lines, 0 `text:`; read
  2026-10-18). If a prefix chord ever does nothing again, suspect this before
  the keymap.
- **Ctrl+[ leaves workspace navigation** (#1431, #2340, 0.9.4). Ctrl+[ is the
  Escape chord.
- **The welcome screen shows the configured prefix** (#4745, #4747, 0.9.4),
  `ctrl+Space` here, not the default `ctrl+b`. This config sets
  `onboarding = false`, and whether the welcome screen still appears with it
  was not checked.

## Speak-selection stops working inside herdr

macOS "Speak selection" (Accessibility > Spoken Content) asks the **focused
application** for its selected text over the accessibility API. Inside herdr
there is nothing to ask for: herdr captures the mouse, so a drag creates
herdr's own internal selection and the host terminal never has one. The hotkey
stays enabled system-wide, finds an empty selection, and says nothing. It is the
same root cause as `cmd+C` appearing to do nothing — the selection is not where
the OS is looking.

The bridge is the clipboard, since a drag has already copied by the time you
release it (which setting does the copying depends on the pane: see "Who copies
on a drag" below). The bindings in `config.toml`
(`ctrl+alt+backtick` and `prefix+backtick`) run `speak-clipboard --toggle`,
which:

1. strips the terminal furniture before speaking — ANSI escapes, box drawing,
   Nerd Font glyphs, rule runs — and maps curly quotes, dashes, and accented
   letters to ASCII instead of dropping them. Tables (box-drawn or markdown)
   are read row by row with the column names, each its own sentence so the
   voice pauses: "Row 1. Source. The record body... When. Any time...". The
   raw accessibility hotkey cannot do any of this: it reads the screen,
   borders and all;
2. hands the cleaned text to one `say2` process per press
   (`say2`, <https://github.com/CaptainCodeAU/say2> -- a real Siri "natural" tier
   neural voice, Aaron by default). say2 streams raw audio to stdout as it
   renders (`--format pcm -o -`) and `ffplay` plays it, so speech starts in
   about 0.3 s whatever the length (MEASURED 2026-09-28: 3,360 chars, first
   audio 0.33 s, against 35.1 s of silence when say2 plays it itself, because
   its own playback renders everything first). Without `ffplay`, or with an
   explicit `--voice`, it falls back to say2's own slower playback. Speech
   plays at 60 of 100 under the system volume (`--volume N`, streaming path
   only; about -4.4 dB), so it can sit a little below everything else.
   Rate, volume, voice and notify are saved for every press, the hotkey
   included (since 2026-10-08), in `~/.config/speak-clipboard/settings`,
   which any run writes with the default values if it is missing.
   `speak-clipboard --settings` shows them in a box, each marked (default) or
   (changed, default ...); `--get [KEY]` prints the bare values;
   `--set rate|volume N` (or `+N`/`-N` to step), `--set voice N` (the
   number from `--voices` only: names repeat across tiers) and
   `--set notify on|off` change them, `--reset KEY|all` puts the defaults
   back, and each shows a changed row as "old -> new". A bad or missing
   value, a voice that is not installed, or a file that cannot be read
   still speaks, with the default, and exits 10, 11 or 12 (`--help` lists
   every code). More hotkeys in `config.toml` step them, each showing the
   change as a macOS notification: `ctrl+alt+1`/`2` rate -20/+20,
   `ctrl+alt+3`/`4` volume -10/+10, `ctrl+alt+0` all back to the defaults,
   and `ctrl+alt+9` shows the current settings. Notifications follow the
   notify setting (on by default; `--notify`/`--no-notify` override it for
   one command; `ctrl+alt+9` always shows). They go through `osascript`,
   not `herdr notification show`, which joins a multi-line body into one
   line (measured 2026-10-08);
3. applies the toggle rule: **any** press while it speaks = stop, whatever the
   clipboard holds; the next press speaks the current selection (since
   2026-09-28; before that, a press with new text replaced the speech).
   `speak-clipboard --stop` stops unconditionally. The text itself is never
   logged. It DOES reach `say2` as a command-line argument, so it is visible
   in `ps` output while speaking: a deliberate speed-over-privacy trade made
   2026-09-10 (the stdin form measured seconds slower). The script header's
   v4.1 note has the measurements.

Why one process per press and not a warm daemon: the daemon that briefly
existed (2026-09-01 to 2026-09-03) saved about half a second per press, and in
exchange rendered the whole selection before playing any of it — 10+ seconds of
silence on a long selection, during which a second press was taken as "stop" —
never exited, and held a power assertion that kept the Mac from idle-sleeping.
A 2026-09-03 through 2026-09-10 era built a hand-rolled Swift chunker
(`speak-render.swift`) that spoke the first sentence while rendering the rest.
It was deleted on 2026-09-10 on the belief that say2 already streams its own
playback. That belief was wrong (found 2026-09-28): the 16 s test paragraph
rendered too fast to show the difference, and long selections then sat silent
for over a minute. say2 does stream, but only to stdout, which is why the
`ffplay` pipe above exists. With a per-press process group, killing it is the
entire stop mechanism and nothing runs between presses.

That kill has to be a SIGKILL once speech is audible (found 2026-09-28).
say2 catches SIGTERM as "cancel the render", but by the time audio plays the
render is finished and its playback loop never checks for cancel, so a plain
`kill` was ignored and the voice ran to the end. `speak-clipboard` now sends
SIGKILL straight away (a SIGTERM-then-wait version cost ~0.6 s of lag per
stop and was dropped the same evening). The proper fix is in say2's own
playback loop.

`~/.local/state/herdr/speak-clipboard.log` keeps one metadata line per press
(mode, outcome, character count): a new line means the key reached herdr; no
line means the key or the spawn is at fault.

Copy mode feeds it too — `prefix+[`, `v`, `y`, then speak — which matters when
the text is a screen away from the pointer.

Requires _"Applications in terminal may access clipboard"_ in iTerm2, without
which the drag never reaches the clipboard and the key appears dead.

**Who copies on a drag** (measured 2026-10-02 on herdr 0.9.1 and Claude Code
2.1.287; these are behaviours, not settings this repo makes):

- In a Claude pane the drag is Claude Code's own fullscreen selection, not
  herdr's. Only Claude Code's `/config` **Copy on select** decides whether it
  copies. herdr's `copy_on_select` covers shell panes only. Both were on when
  checked 2026-10-04 (`copyOnSelect: true` in `~/.claude.json`; herdr's
  default, unset in `config.toml`).
- `Cmd+C` goes to iTerm2's menu, which cannot see either selection and offers
  to disable mouse reporting. Decline it.
- A key bound to a herdr `plugin_action` gets no `selected_text` for a Claude
  highlight (absent in 4 of 4 presses), so a plugin cannot read it directly.
- `herdr config check` passes a `plugin_action` name that does not exist
  (`dotfiles.nope.speak` was ok); it checks the type only.
- `herdr pane send-keys <pane> ctrl+shift+c` did not interrupt an idle Claude
  pane. In a shell it arrived as `0x03`, the same byte as `Ctrl+C`, on 0.9.1.
  **Since 0.9.2 it does not** (#4581): re-measured 2026-10-08 on 0.9.3 with a raw
  byte reader in a throwaway shell tab, it arrives as `ESC [99;6u` (CSI-u for
  Ctrl+Shift+C), twice, while the controls in the same tab gave `03` for
  `ctrl+c` and `61` for `a`. A shell or program that does not decode CSI-u may
  still act on that sequence, so the rule stays: never send it to a pane not
  known to be Claude. **0.9.4 changed this again** (#4356, #5017, per the 0.9.4
  release notes): Ctrl+Shift+letter now reaches a plain shell as the Ctrl key,
  as in Alacritty and WezTerm, and Super, Hyper and Meta shortcuts no longer
  type escape-code junk into apps that cannot read them (the report, #4356, was
  Super+Space typing `;9u` into a zsh pane in Ghostty). So a typed
  Ctrl+Shift+C in a shell may be Ctrl+C again; whether
  `send-keys ctrl+shift+c` into a shell is `0x03` again on 0.9.5 was not
  re-measured. The rule above covers both.

**So every drag overwrites what the clipboard held before**, and
`speak-clipboard` cannot put it back: it only reads (`pbpaste`) and never sees
the earlier contents. A borrow-and-restore version (no copy on drag; the speak
key copies the highlight, reads it, restores the old clipboard, then speaks)
was built on 2026-10-02 and reverted on 2026-10-03 at Gavin's choice.
`git revert d11b782` brings it back; its measurements and the untested real
arm are in the byte copy of the old drawer, `~/CODE/Scaffoldings/fifty-shades-of-dotfiles-isolinear/workbench/pj-drawer/pj-memory/WORK/speak-selection/20261002/REPORT.md`.

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
reinstalling or updating the integration overwrites this file."_ That overwrite
happens on `herdr integration install <name>`, not on a binary upgrade (measured
2026-10-07: v8 hook left in place across two upgrades, reported as `outdated
(v8 < v10)`). So the newer hook is a separate, deliberate step, and the pin
governs only when the newer hook becomes available, not when it lands.

### Updating the Claude hook: compare first, never install blind

Gavin, 2026-10-07: herdr's changes are merged against what we have, never pasted
over it. Two facts make that matter:

- **`herdr integration install claude` rewrites `~/.claude/settings.json`,** which
  holds about ten of our own SessionStart entries, to add an entry that is already
  there. Do not run it against the real config.
- **`~/.claude/hooks/` is locked** (D-20260929-A14): a session cannot change the live
  hook. The update itself is Gavin's hand; a session prepares and compares.

The reference copy is `docs/reference/herdr-agent-state.UPSTREAM.sh`: herdr's
UNTOUCHED output for the version it names on its `HERDR_INTEGRATION_VERSION` line
(v11, herdr 0.9.5, 2026-10-18; v10 from herdr 0.9.3 before that). The steps:

1. **Local edits?** `diff docs/reference/herdr-agent-state.UPSTREAM.sh
~/.claude/hooks/herdr-agent-state.sh`. Empty means none; anything else is ours and
   must be carried into the new version.
2. **New herdr output, real files untouched:** install into a throwaway home.

   ```bash
   F=$(mktemp -d "$TMPDIR/herdr-fakehome.XXXXXX"); mkdir -p "$F/.claude"
   echo '{}' > "$F/.claude/settings.json"
   HOME="$F" herdr integration install claude
   ```

3. **What herdr changed:** `diff` the reference copy against
   `$F/.claude/hooks/herdr-agent-state.sh`. Also compare the hook EVENTS in
   `$F/.claude/settings.json` with ours and with engage's template
   (`engage/templates/settings/hooks.json`, entry "Tells herdr which agent runs in
   the pane"). A new event must be added to engage's template too, or engage sessions
   never fire it.
4. **Apply:** the session writes the merged file to a temp path and gives Gavin the
   one copy-and-commit command for `~/.claude`; then it replaces the reference copy
   here and commits the dotfiles repo.

Measured 2026-10-07, v8 to v10: the live v8 had no local edits (one commit in
`~/.claude`, byte-identical to herdr's output). v10 differs only in exiting on every
event except SessionStart, skipping Cursor, and dropping a now-moot SubagentStop
special case. User settings and engage's settings register SessionStart only, so the
behaviour is the same here. After the update `herdr integration status` reads
`claude: current (v10)`.

Measured 2026-10-18, v10 to v11 (herdr 0.9.5), steps 1 to 3 only. The live hook
is still byte-identical to the reference copy. herdr's v11 hook differs from it
in the `HERDR_INTEGRATION_VERSION` line alone. Its registration is SessionStart
only, as before, but carries the matcher `^(startup|resume|clear|compact|fork)$`
where ours has `*`; whether v10's registration already had that matcher was not
recorded. Our registration keeps `*`: the hook exits on every event but
SessionStart, and `*` covers every source the matcher names. Step 4 done the same
day (Gavin, dotfiles-main Q15): the session wrote herdr's v11 output to a temp
path, Gavin copied it over the live hook and committed `~/.claude`, and the
reference copy here was replaced. After it, `herdr integration status` reads
`claude: current (v11)`, and the live hook is byte-identical to the reference.

## Scope (and deliberate non-scope)

- **In scope:** age-gating the herdr binary, keeping the pin asserted, keeping the
  two phone-home paths closed, and reporting all three at session start.
- **The checker never installs or upgrades.** It prints commands and stops.
  Upgrading is `install.sh`'s job: `_preflight_herdr_bump_check` adopts a
  release only once it has cleared the cooldown (see "The upgrade runbook").
  Same-day adoption is what the cooldown exists to prevent.
- **Not in scope:** the vendor's plugin marketplace. Plugins are a separate
  supply-chain surface and none of the cooldown machinery covers them. The
  standing rule is `herdr plugin link` against a locally authored directory,
  never `herdr plugin install`, which clones a repo and executes its
  `[[build]]` commands. See [`docs/HERDR_PLUGINS.md`](HERDR_PLUGINS.md) §1.
  `herdr plugin update`, new in 0.9.4, updates only plugins installed from
  GitHub and leaves linked ones alone (release notes); the one plugin here,
  `dotfiles.window-title-fix`, is linked (`herdr plugin list`, 2026-10-18).

## Related

- [`docs/SECURITY.md`](SECURITY.md) — the estate-wide release-cooldown posture
- [`docs/TOOLCHAIN_CVE_CHECK.md`](TOOLCHAIN_CVE_CHECK.md) — the sibling floor watcher
- [`docs/CI_WATCH.md`](CI_WATCH.md) — the alert-design rules this hook follows
- [`docs/reference/tmux_cheatsheet.md`](reference/tmux_cheatsheet.md) — the incumbent
- [`docs/HERDR_SIDEBAR.md`](HERDR_SIDEBAR.md) — the left sidebar, colours, naming, and
  what an outside program can change (events, metadata, plugins, a pane's background)

### Capability references (written for an AI agent, not a human)

Written against herdr 0.7.5 by executing every command, 2026-08-02; all three
re-verified against 0.8.2 on 2026-09-17, and each carries its own
`herdr-verified:` stamp. The re-verify corrected real things -- a read trap that
had been fixed upstream, a plugin gotcha that no longer applies, and a fetch
recipe made obsolete by `herdr --skill`.

- [`docs/HERDR_AGENT_SKILL.md`](HERDR_AGENT_SKILL.md) — driving herdr from
  inside a pane: split, run, `wait-output`, read. Includes the Claude-sandbox
  socket block and the JSON-vs-plain-text output map.
- [`docs/HERDR_AGENT_AUTOMATION.md`](HERDR_AGENT_AUTOMATION.md) — agent
  lifecycle states, `blocked` detection, and why `interactive_ready` lies.
- [`docs/HERDR_PLUGINS.md`](HERDR_PLUGINS.md) — manifest format, the
  focused-pane context trap, and why `link` is the only safe registration path.
