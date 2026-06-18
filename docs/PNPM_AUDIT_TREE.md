# pnpm-audit-tree

A recursive, read-only supply-chain auditor for pnpm/JS project trees. Point it
at a folder; it finds every project, walks each one's dependency graph (including
transitive deps), and reports anything that violates the guardrails this dotfiles
repo enforces. It is an **audit report**, not just a gate -- findings are ranked
by severity and rolled up across the whole tree.

Built in response to the 2025-2026 npm/PyPI supply-chain attack wave (Shai-Hulud
worm, chalk/debug, nx/s1ngularity). Operates from a paranoid posture: it flags
aggressively and prefers false positives.

## Safety

Read-only on your projects. It **never** runs dependency lifecycle scripts and
**never** mutates a scanned project. For a project with no lockfile (or a stale
one), the "deep" resolve runs on a **copy in a temp directory** with
`--ignore-scripts --lockfile-only`, so the real project is untouched. The only
network calls are npm registry metadata + the advisory endpoint -- no code from
the audited packages is ever executed. The auditor cannot be turned into an
attack surface.

## Install / deploy

The tools live at `home/.local/bin/pnpm-audit-tree` and `home/.local/bin/pnpm-audit-hook`,
stow-managed onto `~/.local/bin` (already on PATH). Because `~/.local/bin` links
files individually, **re-stow after pulling** so the new files appear:

```sh
# from the dotfiles repo, re-run the installer (or your stow step)
./install.sh        # or: stow ...   (whatever your machine uses)
command -v pnpm-audit-tree   # confirm it resolves
```

Requires `uv` (the script runs under `uv run python3`, zero third-party deps) and
`pnpm` on PATH.

## Usage

```sh
pnpm-audit-tree [FOLDER] [options]
```

- `FOLDER` -- root to scan. If omitted, falls back to the OS code root
  (`~/CODE` on macOS, `~/repos` on Linux/WSL) and **prompts** before scanning
  everything.
- `--no-recursive` -- audit only FOLDER, do not walk subdirectories.
- `--deep` / `--no-deep` -- dry-resolve missing/stale lockfiles on a temp copy (default: on).
- `--offline` -- skip all network checks (no cooldown, no advisories).
- `--min-release-age MIN` -- override `minimumReleaseAge` minutes (default: read from pnpm config).
- `--audit-level low|moderate|high|critical` -- advisory floor (default: low).
- `--fail-on SEVERITY` -- exit non-zero if any finding >= SEVERITY (for hooks).
- `--json PATH` -- also write a JSON report.
- `--md PATH` -- write the markdown report here (default: dated file under `~/.cache/dotfiles/pnpm-audit/`).
- `--no-report` -- skip writing the markdown report (used by hooks/direnv).
- `--quiet` -- minimal output. `--yes` -- skip the default-root prompt. `--max-registry N` -- cap unique registry lookups.

Environment: `PNPM_AUDIT_VERBOSE=1` re-enables the "No JS projects (package.json) found"
no-op line under `--quiet` (which hooks and direnv pass), so a push can confirm the guard
fired. Without it that one line is silent, keeping non-JS hook runs clean. Manual runs
(no `--quiet`) always show it. Only that no-op notice is gated -- all findings and the
clean-tree confirmation are unaffected.

Examples:

```sh
pnpm-audit-tree ~/CODE/CaptainCodeAU/oi-wake-up --no-recursive   # one project, full audit
pnpm-audit-tree ~/CODE                                            # whole tree (prompts)
pnpm-audit-tree . --offline                                       # fast local structural scan
pnpm-audit-tree ~/CODE --json /tmp/audit.json                     # machine-readable
```

## What it checks

| Category    | Flags                                                                                          | Severity                              |
| ----------- | ---------------------------------------------------------------------------------------------- | ------------------------------------- |
| `advisory`  | known vulnerabilities via `pnpm audit --json` (GHSA)                                           | from advisory                         |
| `cooldown`  | dep versions younger than `minimumReleaseAge` (publish-and-grab window)                        | high                                  |
| `exotic`    | git / remote-tarball / `file:` sources -- direct AND transitive                                | high (transitive) / moderate (direct) |
| `integrity` | lockfile entries missing an integrity hash (git-host + `file:` exempt)                         | high                                  |
| `pm-pin`    | `packageManager` pinned to a version younger than the cooldown (the `pnpm self-update` bypass) | high                                  |
| `hygiene`   | no lockfile (unpinned); stray `package-lock.json` / `yarn.lock` (wrong PM)                     | moderate                              |

### Deferred (by design)

Trust-downgrade detection (`trustPolicy: no-downgrade`) and lifecycle-script
approval (`strictDepBuilds` / `allowBuilds`) are **not** reimplemented here --
they fire when pnpm actually installs. This tool does not install, so it cannot
reproduce them faithfully; it defers to pnpm's install-time enforcement and says
so in every report. Your global config already enforces both.

## Triggers

### 1. Manual (the baseline)

Just run `pnpm-audit-tree <folder>`. Everything else wraps this.

### 2. Git pre-commit / pre-push hook

`pnpm-audit-hook [fast|full]` blocks a commit/push when findings reach a severity
floor (`PNPM_AUDIT_FAILON`, default `high`). `fast` = offline structural (quick,
for pre-commit); `full` = adds cooldown + advisories (for pre-push). Per repo:

```sh
ln -s "$(command -v pnpm-audit-hook)" .git/hooks/pre-commit          # fast
printf '#!/usr/bin/env bash\nexec pnpm-audit-hook full\n' > .git/hooks/pre-push
chmod +x .git/hooks/pre-commit .git/hooks/pre-push
```

Bypass once with `PNPM_AUDIT_DISABLE=1 git commit ...` or `git commit --no-verify`.
Fails open (does not block) if the auditor is not installed.

### 3. direnv on-cd check (opt-in, non-blocking)

`direnvrc` defines `pnpm_audit_oncd`. Enable it for a project by adding one line
to that project's `.envrc`:

```sh
pnpm_audit_oncd
```

On `cd` into the project it runs a fast offline structural scan and prints a
one-line warning via direnv's status line if anything moderate or worse is found.
It never blocks the shell.

### 4. Global git pre-push hook via install.sh (opt-in, confirm-gated)

`install.sh` offers (confirm-gated) to run the auditor on every `git push` across
ALL repos by pointing global `core.hooksPath` at the stow-managed chainer in
`home/.config/git/hooks` (-> `~/.config/git/hooks`). Because a global
`core.hooksPath` REPLACES each repo's `.git/hooks` (it is not additive), the
chainer (`_audit-chain`, symlinked from every standard client-side hook name)
first delegates to the repo's own `.git/hooks/<name>` so existing hooks still run,
then adds `pnpm-audit-hook full` on `pre-push` only. Repos that set their own
`core.hooksPath` (husky, lefthook) override the global one and are unaffected.

```sh
./install.sh           # answer yes at the "Enable the pnpm-audit pre-push hook?" prompt
# or set it yourself (machine-local include, NOT --global -- see note below):
git config --file ~/.gitconfig.private core.hooksPath ~/.config/git/hooks
```

The setting goes in `~/.gitconfig.private` (which the stowed `~/.gitconfig`
already `[include]`s), not via `git config --global`: on these dotfiles
`~/.gitconfig` is a stow symlink into the repo, so `--global` would write the
change into the tracked `home/.gitconfig`. install.sh never clobbers an existing
non-matching `core.hooksPath` -- it warns and skips. Disable with
`git config --file ~/.gitconfig.private --unset core.hooksPath`. Bypass once with
`PNPM_AUDIT_DISABLE=1 git push` or `git push --no-verify`.

### Not built (yet)

Scheduled full-tree sweep (launchd/cron) and CI integration -- easy to add later
on top of the manual command + `--json` / `--fail-on`.

## Exit codes

- `0` -- no findings at/above `--fail-on` (or `--fail-on` unset)
- `1` -- findings at/above `--fail-on`
- `2` -- usage/environment error (no pnpm, bad folder, declined prompt)
