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

---

## TL;DR

```sh
# Turn ON (either one):
./install.sh                                            # answer yes at the prompt
git config --global core.hooksPath ~/.config/git/hooks  # or set it directly

# Check it's on:
git config --global --get core.hooksPath                # -> ~/.config/git/hooks

# Bypass for ONE push:
PNPM_AUDIT_DISABLE=1 git push        # or:  git push --no-verify

# Turn OFF:
git config --global --unset core.hooksPath
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

Only `pre-push` runs the audit. Commits, merges, checkouts, etc. are **not**
audited by this feature -- they just pass through to your repo's own hooks
unchanged (see "How it works").

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
  Sets global core.hooksPath -> ~/.config/git/hooks ...
Enable the global pnpm-audit pre-push hook? [y/N]
```

Answer `y`. The step is **idempotent** (re-running is safe) and **never
clobbers** an existing global `core.hooksPath` that points somewhere else -- in
that case it warns and skips, leaving your setup alone.

> Note: the prompt only appears on the full `./install.sh` run, not on
> `--stow-only` or `--update`.

### Option B -- manually

```sh
git config --global core.hooksPath ~/.config/git/hooks
```

Identical effect to answering yes in the installer.

---

## How it works

A global `core.hooksPath` tells git to look for **all** hooks in one directory,
for **every** repo -- and it **REPLACES** each repo's `.git/hooks` rather than
adding to it. Pointing it naively at a directory that only contained a `pre-push`
script would therefore silently disable every repo's _other_ hooks (pre-commit,
commit-msg, ...).

To avoid that, `~/.config/git/hooks/` contains a single chainer,
`_audit-chain`, with a symlink for **every standard client-side hook name**
pointing at it. When git runs any hook, the chainer:

1. **Delegates first** to the repo's own `.git/hooks/<name>` if it exists and is
   executable (forwarding arguments and stdin), so existing per-repo hooks still
   run exactly as before.
2. **On `pre-push` only**, additionally runs `pnpm-audit-hook full`.

```
git push
   |
   v
~/.config/git/hooks/pre-push  (symlink -> _audit-chain)
   |
   |-- 1. run <repo>/.git/hooks/pre-push  (if present)   <- your existing hook
   |
   '-- 2. run pnpm-audit-hook full                       <- the supply-chain audit
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

| Variable             | Default | Effect                                                                                                                                |
| -------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `PNPM_AUDIT_FAILON`  | `high`  | Minimum severity that blocks the push: `low`, `moderate`, `high`, `critical`.                                                         |
| `PNPM_AUDIT_DISABLE` | (unset) | Set to `1` to skip the audit entirely for that command.                                                                               |
| `PNPM_AUDIT_VERBOSE` | (unset) | Set to `1` to print the "No JS projects found" no-op confirmation on a push; suppressed by default for non-JS (Python/Rust/Go) repos. |

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
PNPM_AUDIT_DISABLE=1 git push      # skips the auditor
git push --no-verify               # skips ALL pre-push hooks (incl. your own)
```

Prefer `PNPM_AUDIT_DISABLE=1` -- it skips only the audit and still runs any
repo-local pre-push hook. `--no-verify` skips everything.

---

## Turning it off

```sh
git config --global --unset core.hooksPath
```

Git immediately falls back to per-repo `.git/hooks` everywhere. The chainer files
remain stowed (harmless) and can be re-enabled anytime.

---

## Verifying it is active

```sh
# 1. Is the global hooks path pointed at the chainer?
git config --global --get core.hooksPath          # expect: ~/.config/git/hooks

# 2. Does the chainer resolve?
ls -l ~/.config/git/hooks/pre-push                 # -> _audit-chain
command -v pnpm-audit-hook                          # on PATH?

# 3. Dry test in a throwaway repo with an exotic (file:) dependency:
#    a full audit should block the pre-push with a non-zero exit.
```

---

## Troubleshooting

**Pushes are not being audited.**
Check `git config --global --get core.hooksPath` is `~/.config/git/hooks`. If the
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
