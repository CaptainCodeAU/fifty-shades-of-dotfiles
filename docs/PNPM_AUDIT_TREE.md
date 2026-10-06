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
network calls are npm registry metadata, the advisory endpoint and OSV -- no
code from the audited packages is ever executed. The auditor cannot be turned
into an attack surface.

**A scanned project never chooses the pnpm that runs.** Every pnpm the tool starts
gets `PNPM_CONFIG_PM_ON_FAIL=ignore`. Without it, measured on 12.9.0 (W-20261006-A31),
a project pinning pnpm made the tool's `pnpm audit` download and RUN the pinned
version (11.1.2), and a pin equal to the running pnpm, or any
`devEngines.packageManager` pin, made it REWRITE the project's `pnpm-lock.yaml`. A
sweep of `~/CODE` with the fix hashed 147 lockfiles and manifests before and after:
0 changed.

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
  A dry-resolved lockfile is not the project's lockfile: the "no lockfile" finding always
  stands, and the resolve only adds what it finds in the tree (exotic sources, integrity).
- `--offline` -- no network at all: no cooldown, no advisories, no OSV, and the deep
  resolve runs `pnpm install --offline` against the local cache only. A tree that is not
  cached is noted ("not in the local pnpm cache"), never fetched. Before 2026-10-06 the
  deep resolve went to the network even under `--offline`, and its temp lockfile
  suppressed the "no lockfile" finding, so the pre-commit hook and direnv reported a
  project with no lockfile as clean (57 projects flagged against 102 on `~/CODE`) and an
  unreachable registry held a direnv `cd` for 70 s.
- `--min-release-age MIN` -- override `minimumReleaseAge` minutes (default: read from pnpm config).
- `--audit-level low|moderate|high|critical` -- advisory floor (default: low).
- `--fail-on SEVERITY` -- exit non-zero if any finding >= SEVERITY (for hooks).
- `--json PATH` -- also write a JSON report.
- `--md PATH` -- write the markdown report here (default: dated file under
  `${XDG_CACHE_HOME:-~/.cache}/dotfiles/pnpm-audit/`).
- `--no-report` -- skip writing the markdown report (used by hooks/direnv).
- `--quiet` -- minimal output. `--yes` -- skip the default-root prompt.
- `--max-registry N` -- cap unique registry lookups (default 2000; a capped run says so).

Every run prints one summary line on stderr, even under `--quiet`: projects, how many
have a real `pnpm-lock.yaml`, how many ran the network checks, findings and the worst
severity.

Environment: `PNPM_AUDIT_VERBOSE=1` re-enables the "No JS projects (package.json) found"
no-op line under `--quiet` (which hooks and direnv pass), so a push can confirm the guard
fired. Without it that one line is silent, keeping non-JS hook runs clean. Manual runs
(no `--quiet`) always show it. Only that no-op notice is gated -- all findings and the
clean-tree confirmation are unaffected.

`PNPM_MIN_VERSION` -- the floor `pm-pin` compares pins against. Read from the
environment (exported by `~/.zsh_onboarding`), else from that file's export line; never
a third hardcoded copy. When neither is found the run notes "pnpm floor not checked".

`PNPM_AUDIT_OWNERS=a,b` (or `git config --global --add pnpmaudit.owner <name>`) -- your
repo owners. With it set, a stray `package-lock.json` / `yarn.lock` in a repo whose
`origin` belongs to someone else is `info`, not `moderate`: it is repo POLICY, and the
policy is yours. Only those policy findings change; a clone's security findings stand.
There is no default on purpose (a name in this tool would be an identity in a public
file). Measured 2026-10-06: 11 of 16 stray npm lockfiles on `~/CODE` dropped to info;
the 5 left are your own repos and two copies with no `origin`, which an origin check
cannot see.

Workspaces: a lockfile above a project only counts when its `importers:` list that
project. A workspace member is checked once, at the root, when the root is in the same
scan (it used to be checked once per member, so every finding counted N times); scanned
on its own (direnv, `--no-recursive`) it is checked against the root's lockfile. A nested
`package.json` that is NOT an importer (a `tools/` script, a vendored `file:` target) is
its own project: before, it borrowed the parent's lockfile and read as pinned.
`.venv` and `site-packages` are not walked (pyright vendors a `package.json`).

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
| `integrity` | lockfile entries missing an integrity hash (git + `file:` exempt: older lockfiles wrote none)  | high                                  |
| `pm-pin`    | a pnpm pin (`packageManager` or `devEngines.packageManager`) younger than the cooldown          | high                                  |
| `pm-pin`    | a pnpm pin below this box's `PNPM_MIN_VERSION` (exact, `^` and `~` specs; works offline)        | moderate                              |
| `pm-pin`    | a pnpm pin with published advisories (OSV, exact pins, online)                                  | worst advisory                        |
| `pm-pin`    | any of the three above when pnpm will not obey the pin here (`pmOnFail` warn/ignore/error)      | low                                   |
| `hygiene`   | no lockfile (unpinned); stray `package-lock.json` / `yarn.lock` (wrong PM)                     | moderate (stray in a clone: info)     |

A pnpm 12 lockfile can hold two YAML documents: the first pins pnpm itself
(`packageManagerDependencies`, written for any `devEngines.packageManager` pin, which
`pnpm init` adds by default on 12.9), the second is the real dependency graph. Every
document is read. Before 2026-10-06 only the first was, so a fresh `pnpm init`
project's real dependencies were never checked.

Whether a pin bites depends on the `pmOnFail` pnpm applies to that project, measured on
12.9.0 by which version actually ran: `$PNPM_CONFIG_PM_ON_FAIL` beats the project's
`pnpm-workspace.yaml`, which beats the global `config.yaml`, which beats
`devEngines.packageManager.onFail`; the default is `download`, which runs the pinned
version. A low `pm-pin` still matters on a machine or CI without that setting.

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

Exit codes are read, not just tested: scanner `0` passes, `1` blocks ("supply-chain
findings >= high blocked this hook") ONLY when the scanner also printed its
`<n> finding(s); worst=` summary, so a scanner that crashed before its own guard can
never pass for findings. `3` (INCOMPLETE: some lookups failed, nothing at the floor
was found) warns loudly and lets the push through by default; set
`PNPM_AUDIT_ON_INCOMPLETE=block` to refuse instead (Gavin's pick 2026-10-06, ruling
D-20261006-A03). ANY other code -- the scanner not installed, uv unable to start, a
crash -- fails OPEN and says so: "THE SCAN DID NOT RUN ... NOT a finding and NOT a
clean result". An unscanned push is not a pass; read that line.
`pnpm-audit-hook --selftest` proves 8 arms; `pnpm-audit-tree --selftest` proves 9
against a fake registry, including the old false all-clear (an unreachable registry
made a too-young pnpm pin read as clean, W-20261006-A30). When the hook's normal uv cache is
not writable (inside the Claude sandbox) it points `UV_CACHE_DIR` at `$TMPDIR` itself.

### 3. direnv on-cd check (opt-in, non-blocking)

`direnvrc` defines `pnpm_audit_oncd`. Enable it for a project by adding one line
to that project's `.envrc`:

```sh
pnpm_audit_oncd
```

On `cd` into the project it runs a fast offline structural scan and prints a
one-line warning via direnv's status line if anything moderate or worse is found.
It never blocks the shell and never touches the network: the deep resolve reads the
local pnpm cache only (0.1 s measured), so an unreachable registry cannot hold the `cd`.
A project with no lockfile now shows here (it did not before 2026-10-06).

### 4. Global git pre-push hook via install.sh (opt-in, confirm-gated)

`install.sh` offers (confirm-gated) to run the auditor on every `git push` across
ALL repos by pointing global `core.hooksPath` at the stow-managed chainer in
`home/.config/git/hooks` (-> `~/.config/git/hooks`). Because a global
`core.hooksPath` REPLACES each repo's `.git/hooks` (it is not additive), the
chainer (`_audit-chain`, symlinked from every standard client-side hook name)
first delegates to the repo's own `.git/hooks/<name>` so existing hooks still run,
then adds `pnpm-audit-hook full` on `pre-push` only. Repos that set their own
`core.hooksPath` (husky, lefthook) override the global one and are unaffected.

The chainer runs more than this audit, so `git push --no-verify` skips all of it:

| Step | Hook                 | What                                                                                        | Off switch                                    |
| ---- | -------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------------- |
| 1    | every                | the repo's own `.git/hooks/<name>` (main checkout's, in a worktree)                          | --                                            |
| 2    | pre-push             | `pnpm-audit-hook full`                                                                      | `PNPM_AUDIT_DISABLE=1`                         |
| 2d   | pre-push             | `git-leak-scan` of every pushed commit to a public or unknown remote; fails CLOSED          | none (`leakscan.skip` rules still honoured)    |
| 2b   | pre-commit           | `git-leak-scan` of the staged diff                                                          | `leakscan.skip` (prefer), `leakscan.disable`   |
| 2c   | pre-commit           | `shift-lint --staged`, opt-in                                                               | on only with `shiftlint.enable true`          |
| 3    | prepare-commit-msg   | `C-*` session trailers inside a Claude Code session                                         | `trailers.disable true`                       |

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
- `2` -- usage/environment error (no pnpm, bad folder, declined prompt), or an internal
  error: the scan did not finish, which is NOT a finding and NOT a clean result
- `3` -- INCOMPLETE (`--fail-on` only): nothing at/above `--fail-on`, but some lookups
  failed (registry, advisories, the pnpm pin). Each gap is a named `coverage` finding
  of severity `unknown`; unknown is never clean. Cut-off reads are retried up to 3 times
  first. A real finding still wins with exit 1.

## Related

This audits a _project's dependencies_. To check whether the pnpm/nvm **tool
versions** themselves -- the pinned floors (`PNPM_MIN_VERSION`, `NVM_MIN_VERSION`)
and what's actually installed -- are sitting in a published vulnerable range, see
[`toolchain-cve-check`](TOOLCHAIN_CVE_CHECK.md).
