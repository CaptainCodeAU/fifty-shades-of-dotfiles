# toolchain-cve-check — are our pinned floors (and installed versions) CVE-exposed?

A read-only monitor that answers one question on a schedule: **is a version we
depend on sitting inside a published vulnerable range right now?** It watches both
the security _floors_ this repo pins (`PNPM_MIN_VERSION`, `NVM_MIN_VERSION`) and the
pnpm/nvm versions _actually installed_ on the machine.

## Why it exists

A pinned floor that was clean the day it was set can **silently** become vulnerable
later, when a new advisory is catalogued against it. That is not hypothetical: this
repo's `PNPM_MIN_VERSION` sat at `11.7.0` for nine days before `GHSA-qrv3-253h-g69c`
(High, CVSS 8.2) was published affecting `>=11.0.0 <11.8.0` — i.e. the floor itself.
It was caught only because a human noticed a version in a banner. The same failure
mode had also left the README recommending a CVE-vulnerable nvm (`v0.40.3`).

`toolchain-cve-check` closes that gap: the day a pin (or an installed version) lands
in a published vulnerable range, it says so, and nudges the maintainer to bump.

## What it checks (4 subjects)

| #   | Subject        | Version source                       | Advisory source            |
| --- | -------------- | ------------------------------------ | -------------------------- |
| 1   | pnpm floor     | `--pnpm-floor` / `$PNPM_MIN_VERSION` | OSV                        |
| 2   | pnpm installed | `pnpm -v`                            | OSV                        |
| 3   | nvm floor      | `--nvm-floor` / `$NVM_MIN_VERSION`   | GitHub nvm-repo advisories |
| 4   | nvm installed  | `git -C ~/.nvm describe --tags`      | GitHub nvm-repo advisories |

Each subject is reported independently as **OK** (clean), **EXPOSED** (in a vulnerable
range — actionable), or **SKIPPED** (data unavailable; never a false positive).

## The data-source asymmetry (why pnpm and nvm differ)

This is the crux of the design, and it was verified against the live APIs, not assumed:

- **pnpm is an npm package**, so [OSV](https://osv.dev) answers "is `pnpm@X` vulnerable?"
  by exact version, **unauthenticated, from any shell**. OSV performs the semver-range
  match server-side, so there is **no client-side range parser** for pnpm.

  ```
  POST https://api.osv.dev/v1/query
  {"package":{"name":"pnpm","ecosystem":"npm"},"version":"11.7.0"}  ->  GHSA-qrv3-253h-g69c
  {"package":{"name":"pnpm","ecosystem":"npm"},"version":"11.9.0"}  ->  (clean)
  ```

- **nvm is a bash script, not a registry package.** Its advisories are **absent from
  OSV and from GitHub's _global_ advisory database**. They live **only** at the repo
  endpoint, which requires `gh` + a token:

  ```
  gh api repos/nvm-sh/nvm/security-advisories
  ```

  So the nvm half needs `gh`, and a small client-side membership test over each
  advisory's `vulnerable_version_range` (e.g. `>= 0.40.0, <= 0.40.3`). The two nvm
  advisories on record:
  - `GHSA-3c52-35h2-gfmm` / CVE-2026-10796 (High): `<= 0.40.4`, fixed `0.40.5`
  - `GHSA-4fc5-r4vr-8rp7` / CVE-2026-1665 (Medium): `>= 0.40.0, <= 0.40.3`, fixed `0.40.4`

### The `$GH_TOKEN` consequence

`$GH_TOKEN` is present **only inside Claude Code sessions** (see
`.claude/hooks/enforce-gh-ssh-only.sh`), not in plain interactive shells. So:

- **pnpm checks run anywhere** (OSV needs no auth).
- **nvm checks need a token** — inside a Claude session they run; elsewhere they report
  `SKIPPED (needs gh + GH_TOKEN)`. A skip is **never** an EXPOSED — the tool fails safe.

## How it runs

1. **Standalone CLI** — `home/.local/bin/toolchain-cve-check` (Python, PEP 723, zero
   dependencies, run via `uv`). Run it anytime:

   ```bash
   toolchain-cve-check                       # uses $PNPM_MIN_VERSION / $NVM_MIN_VERSION
   toolchain-cve-check --pnpm-floor 11.7.0    # ad-hoc: prove a version is exposed
   toolchain-cve-check --quiet                # only print exposures + a summary (hooks)
   toolchain-cve-check --json                 # machine-readable
   ```

2. **SessionStart hook** — `.claude/hooks/toolchain-cve-check.sh` runs the tool at the
   start of every Claude session in this repo (wired in `.claude/settings.json`,
   alongside the Zed changelog check). It reads the floors from `install.sh`, caches the
   verdict for 6h in `$TMPDIR`, prints a one-line "all clean" or — on exposure — the full
   table plus an explicit nudge to bump the floor. It is read-only and **always exits 0**
   (never blocks a session).

## Exit codes

| Code | Meaning                                                                 |
| ---- | ----------------------------------------------------------------------- |
| `0`  | every subject is CLEAN or SKIPPED (nothing actionable)                  |
| `1`  | at least one subject is EXPOSED (a pin/installed version is vulnerable) |

The non-zero exit makes the tool usable as a CI / pre-push gate too, not just a hook.

## Negative self-test (proves detection works)

Because everything is clean today, prove the detector actually fires by feeding it the
historical bad pins:

```bash
toolchain-cve-check --pnpm-floor 11.7.0   # -> pnpm floor EXPOSED: GHSA-qrv3-253h-g69c (HIGH; fixed 11.8.0), exit 1
toolchain-cve-check --nvm-floor 0.40.3    # -> nvm floor EXPOSED: CVE-2026-10796 + CVE-2026-1665, exit 1
```

## Scope (and deliberate non-scope)

- **In scope:** the `pnpm` and `nvm` floors + their installed versions. These are the
  only two version floors the repo pins.
- **Out of scope, on purpose:**
  - `NODE_MIN_MAJOR` — an end-of-life _major_ guard, not a single CVE-pinnable version.
  - Hard-coded version pins inside docs/README (e.g. an install URL) — too noisy to
    CVE-scan reliably.
  - `bun` / `uv` — no floor constants exist to check.
  - **Auto-bumping** — this is a monitor and a nudge. Bumping a floor stays a deliberate,
    reviewed edit (in both `install.sh` and `home/.zsh_onboarding`), then a commit.

## Related

- [`docs/PNPM_AUDIT_TREE.md`](PNPM_AUDIT_TREE.md) — per-project pnpm dependency auditor (a
  different job: it audits a project's _dependencies_, not the pnpm/nvm tool versions).
- [`docs/NVM_SECURITY.md`](NVM_SECURITY.md) — the layered nvm/Node hardening this complements.
- [`docs/CI_WATCH.md`](CI_WATCH.md) — sibling session-start watcher: an escalating,
  dismiss-only-by-fixing CI-status line for repos you flag.
