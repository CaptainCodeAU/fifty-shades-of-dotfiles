# pnpm-audit pre-push hook (global, opt-in)

Run the pnpm supply-chain auditor automatically on **every `git push`, in every
repo**, so a push carrying high-severity supply-chain findings is blocked before
it leaves your machine -- while every repo's own git hooks keep working.

This is an **opt-in** layer on top of the auditor described in
[`PNPM_AUDIT_TREE.md`](./PNPM_AUDIT_TREE.md). That doc covers the engine
(`pnpm-audit-tree`) and the thin git wrapper (`pnpm-audit-hook`); this doc covers
the one specific trigger: wiring it globally as a `pre-push` hook.

It is **dormant until you turn it on** -- nothing changes on your machine just by
pulling these dotfiles.

**The same switch turns on more than this audit.** The hook script it points git
at also runs a leak scan before every commit and every push, and stamps session
lines on commits made in a Claude session. Turning the switch off turns all of
them off. The full list is in "How it works" below.

---

## TL;DR

```sh
# Turn ON (either one):
./install.sh                                            # answer yes at the prompt
git config --file ~/.gitconfig.private core.hooksPath ~/.config/git/hooks  # or set it directly

# Check it's on:
git config --get core.hooksPath                # -> ~/.config/git/hooks

# Bypass the audit for ONE push (the leak scan still runs):
PNPM_AUDIT_DISABLE=1 git push

# Turn OFF (also turns off the leak scans and session lines):
git config --file ~/.gitconfig.private --unset core.hooksPath
```

Severity that blocks defaults to `high`. Override with `PNPM_AUDIT_FAILON`
(`low` | `moderate` | `high` | `critical`).

---

## What it does

When enabled, every `git push` first runs `pnpm-audit-hook full` over the repo
you are pushing. That is a network scan (registry cooldown + `pnpm audit`
advisories, plus the offline structural checks). If it finds anything at or above
the blocking severity (`high` by default), the push is **aborted** with a
non-zero exit and a message telling you how to review or bypass.

Only `pre-push` runs the audit. The other steps the hook script runs (a leak
scan on commit and on push, session lines on commits) are listed in "How it
works".

What the audit's result does to the push:

| Audit result                                                | Push                                                                                           |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| No findings at or above the blocking severity               | goes through                                                                                   |
| Findings at or above it                                     | **blocked**                                                                                    |
| Incomplete: some lookups failed, nothing at the floor found | goes through with a loud `SCAN INCOMPLETE` warning; `PNPM_AUDIT_ON_INCOMPLETE=block` blocks it |
| The scan did not run (auditor missing, uv failed, a crash)  | goes through with `THE SCAN DID NOT RUN`; that is not a clean result                           |

What it checks is exactly what `pnpm-audit-tree` checks (advisories, cooldown,
exotic sources, missing integrity, the `packageManager` pin bypass, lockfile
hygiene) -- see [`PNPM_AUDIT_TREE.md`](./PNPM_AUDIT_TREE.md). A repo with no
`package.json` is a no-op (nothing to audit), so non-JS repos push normally. That
no-op stays silent by default; run `PNPM_AUDIT_VERBOSE=1 git push` to surface the
"No JS projects found ..." confirmation when you want to see the guard fire.

---

## How to turn it on

### Prerequisites

1. The dotfiles are stowed, so the chainer exists at `~/.config/git/hooks/`.
   After pulling these dotfiles on a new machine, **re-stow** (run `./install.sh`)
   so `~/.config/git/hooks/pre-push` appears.
2. `pnpm-audit-hook` and `pnpm-audit-tree` are on `PATH` (stowed to
   `~/.local/bin`). If `pnpm-audit-hook` is missing, the hook **fails open** --
   it never blocks a push just because the auditor is absent.

### Option A -- via install.sh (recommended)

Run the installer's default action:

```sh
./install.sh
```

After stowing, it prompts:

```
Optional: run the pnpm supply-chain auditor on every git push (all repos).
  Writes core.hooksPath -> ~/.config/git/hooks into ~/.gitconfig.private ...
Enable the pnpm-audit pre-push hook (writes to ~/.gitconfig.private)? [y/N]
```

Answer `y`. The step is **idempotent** (re-running is safe) and **never
clobbers** an existing `core.hooksPath` that points somewhere else -- in
that case it warns and skips, leaving your setup alone.

> Note: the prompt only appears on the full `./install.sh` run, not on
> `--stow-only` or `--update`.

### Option B -- manually

```sh
git config --file ~/.gitconfig.private core.hooksPath ~/.config/git/hooks
```

Identical effect to answering yes in the installer.

> Why `~/.gitconfig.private` and not `git config --global`? On these dotfiles,
> `~/.gitconfig` is a stow symlink into the repo, so `--global` would write the
> setting straight into the tracked `home/.gitconfig` (repo pollution). The stowed
> `~/.gitconfig` already `[include]`s the machine-local, untracked
> `~/.gitconfig.private`, so the hook still takes effect from there. Verify with
> `git config --get core.hooksPath` -- it follows the include; `--global --get` does not.

---

## How it works

A global `core.hooksPath` tells git to look for **all** hooks in one directory,
for **every** repo -- and it **REPLACES** each repo's `.git/hooks` rather than
adding to it. Pointing it naively at a directory that only contained a `pre-push`
script would therefore silently disable every repo's _other_ hooks (pre-commit,
commit-msg, ...).

To avoid that, `~/.config/git/hooks/` contains a single chainer,
`_audit-chain`, with a symlink for **every standard client-side hook name**
pointing at it. When git runs any hook, the chainer runs these steps in order
(numbered as in the script):

| Step | Hook               | What                                                                                          | Off switch                                   |
| ---- | ------------------ | --------------------------------------------------------------------------------------------- | -------------------------------------------- |
| 1    | every              | the repo's own `.git/hooks/<name>` (main checkout's, in a worktree), args and stdin forwarded | --                                           |
| 2    | pre-push           | `pnpm-audit-hook full`                                                                        | `PNPM_AUDIT_DISABLE=1`                       |
| 2d   | pre-push           | `git-leak-scan` of every pushed commit to a public or unknown remote; fails CLOSED            | none (`leakscan.skip` rules still honoured)  |
| 2b   | pre-commit         | `git-leak-scan` of the staged diff                                                            | `leakscan.skip` (prefer), `leakscan.disable` |
| 2c   | pre-commit         | `shift-lint --staged`, opt-in                                                                 | on only with `shiftlint.enable true`         |
| 3    | prepare-commit-msg | `C-*` session lines on commits made inside a Claude Code session                              | `trailers.disable true`                      |

"Fails CLOSED" means the push is refused when the scan cannot run: `git-leak-scan`
missing, or the remote's commit not in this repo (`git fetch` first). A repo GitHub
reports as private is not scanned at push time. The same table is in
[`PNPM_AUDIT_TREE.md`](./PNPM_AUDIT_TREE.md); keep the two in step.

```
git push
   |
   v
~/.config/git/hooks/pre-push  (symlink -> _audit-chain)
   |
   |-- 1.  run <repo>/.git/hooks/pre-push  (if present)   <- your existing hook
   |
   |-- 2.  run pnpm-audit-hook full                       <- the supply-chain audit
   |
   '-- 2d. run git-leak-scan on the pushed commits        <- public or unknown remote only
```

### Repos that use husky / lefthook are unaffected

Hook managers like husky set a **repo-local** `core.hooksPath` (e.g. `.husky`).
A repo-local setting **overrides** the global one, so those repos never touch the
chainer and behave exactly as before. The global hook only applies to repos that
use the default `.git/hooks` (or no hooks at all).

### Files involved

| Path                                       | Role                                                              |
| ------------------------------------------ | ----------------------------------------------------------------- |
| `home/.config/git/hooks/_audit-chain`      | the chainer script (stowed to `~/.config/git/hooks/_audit-chain`) |
| `home/.config/git/hooks/<hook-name>`       | symlinks (one per standard hook) -> `_audit-chain`                |
| `install.sh` -> `setup_pnpm_audit_hooks()` | the confirm-gated enable step                                     |
| `~/.local/bin/pnpm-audit-hook`             | the git wrapper the chainer calls on pre-push                     |
| `~/.local/bin/pnpm-audit-tree`             | the underlying auditor engine                                     |

---

## Configuration

These are read from the environment at push time.

| Variable                   | Default | Effect                                                                                                                                                                                       |
| -------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PNPM_AUDIT_FAILON`        | `high`  | Minimum severity that blocks the push: `low`, `moderate`, `high`, `critical`.                                                                                                                |
| `PNPM_AUDIT_DISABLE`       | (unset) | Set to `1` to skip the audit entirely for that command.                                                                                                                                      |
| `PNPM_AUDIT_VERBOSE`       | (unset) | Set to `1` to print the "No JS projects found" no-op confirmation on a push; suppressed by default for non-JS (Python/Rust/Go) repos.                                                        |
| `PNPM_AUDIT_ON_INCOMPLETE` | `warn`  | `block` refuses a push when the audit could not finish all its lookups and found nothing at the floor. `warn` lets it through with a loud warning (Gavin's pick 2026-10-06, D-20261006-A03). |

Examples:

```sh
# Stricter: block on moderate-or-worse for this push
PNPM_AUDIT_FAILON=moderate git push

# Persist a stricter threshold for your shell
export PNPM_AUDIT_FAILON=moderate   # add to ~/.zshrc.private if you want it permanent
```

---

## Bypassing a single push

When you have reviewed a finding and want to push anyway:

```sh
PNPM_AUDIT_DISABLE=1 git push      # skips the auditor only
git push --no-verify               # skips the WHOLE chain, leak scan included
```

Prefer `PNPM_AUDIT_DISABLE=1` -- it skips only the audit and still runs any
repo-local pre-push hook and the push-time leak scan. `--no-verify` skips
everything, including the leak scan, which is the last look before a commit
leaves the machine. Inside a Claude Code session, `git push --no-verify` and
`git commit --no-verify` are refused (`validate-bash.sh`, W-20260929-A32).

---

## Turning it off

```sh
git config --file ~/.gitconfig.private --unset core.hooksPath
```

Git immediately falls back to per-repo `.git/hooks` everywhere. That also turns
off the leak scans and the session lines, not just the audit. To stop only the
audit, set `PNPM_AUDIT_DISABLE=1` in your shell instead. The chainer files
remain stowed (harmless) and can be re-enabled anytime.

---

## Verifying it is active

```sh
# 1. Is the global hooks path pointed at the chainer?
git config --get core.hooksPath          # expect: ~/.config/git/hooks

# 2. Does the chainer resolve?
ls -l ~/.config/git/hooks/pre-push                 # -> _audit-chain
command -v pnpm-audit-hook                          # on PATH?

# 3. Dry test in a throwaway repo with an exotic (file:) dependency:
#    a full audit should block the pre-push with a non-zero exit.
```

---

## Troubleshooting

**Pushes are not being audited.**
Check `git config --get core.hooksPath` is `~/.config/git/hooks`. If the
repo sets its own `core.hooksPath` (husky/lefthook), the global hook is bypassed
by design -- audit that repo manually with `pnpm-audit-tree .` or add the per-repo
hook from [`PNPM_AUDIT_TREE.md`](./PNPM_AUDIT_TREE.md).

**`pre-push` not found / nothing happens after enabling.**
The chainer is not stowed. Re-run `./install.sh` (re-stows `home/` -> `~/`), then
confirm `ls -l ~/.config/git/hooks/pre-push`.

**A repo's own hooks stopped running.**
They should not -- the chainer delegates to `.git/hooks/<name>` first. If a hook
is missing, confirm it is executable (`chmod +x .git/hooks/<name>`); git ignores
non-executable hooks.

**Push is slow.**
`full` mode does network checks (cooldown + advisories). For a quick, offline
push, bypass once with `PNPM_AUDIT_DISABLE=1 git push`, or lower the scope by
auditing manually beforehand.

**`pnpm-audit-hook` not installed.**
The hook fails open (never blocks). Re-stow so `~/.local/bin/pnpm-audit-hook`
exists, and ensure `~/.local/bin` is on `PATH`.

---

## See also

- [`PNPM_AUDIT_TREE.md`](./PNPM_AUDIT_TREE.md) -- the auditor engine, all checks,
  per-repo hook and direnv triggers, exit codes, and CLI flags.
