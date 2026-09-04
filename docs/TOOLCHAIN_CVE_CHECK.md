# toolchain-cve-check — are our pinned floors (and installed versions) CVE-exposed?

A read-only monitor that answers one question on a schedule: **is a version we
depend on sitting inside a published vulnerable range right now?** It watches both
the security _floors_ this repo pins (`PNPM_MIN_VERSION`, `NVM_MIN_VERSION`) and the
pnpm/nvm versions _actually installed_ on the machine — plus, since 2026-07-30, the
installed **Claude Code** version, which is not pinned at all but is the most privileged
tool here.

## Why it exists

A pinned floor that was clean the day it was set can **silently** become vulnerable
later, when a new advisory is catalogued against it. That is not hypothetical: this
repo's `PNPM_MIN_VERSION` sat at `11.7.0` for nine days before `GHSA-qrv3-253h-g69c`
(High, CVSS 8.2) was published affecting `>=11.0.0 <11.8.0` — i.e. the floor itself.
It was caught only because a human noticed a version in a banner. The same failure
mode had also left the README recommending a CVE-vulnerable nvm (`v0.40.3`).

`toolchain-cve-check` closes that gap: the day a pin (or an installed version) lands
in a published vulnerable range, it says so, and nudges the maintainer to bump.

## What it checks (7 core subjects, plus Homebrew on demand)

| #   | Subject             | Version source                       | Advisory source                   |
| --- | ------------------- | ------------------------------------ | --------------------------------- |
| 1   | pnpm floor          | `--pnpm-floor` / `$PNPM_MIN_VERSION` | OSV                               |
| 2   | pnpm installed      | `pnpm -v`                            | OSV                               |
| 3   | nvm floor           | `--nvm-floor` / `$NVM_MIN_VERSION`   | GitHub nvm-repo advisories        |
| 4   | nvm installed       | `git -C ~/.nvm describe --tags`      | GitHub nvm-repo advisories        |
| 5   | bun floor           | `--bun-floor` / `$BUN_MIN_VERSION`   | OSV                               |
| 6   | bun installed       | `bun --version`                      | OSV                               |
| 7   | Claude Code         | `claude --version`                   | OSV (`@anthropic-ai/claude-code`) |
| 8   | Homebrew (`--brew`) | `brew list --versions`               | **NVD by CPE**                    |

Each subject is reported independently as **OK** (clean), **EXPOSED** (in a vulnerable
range — actionable), **UNKNOWN** (could not be determined — _not_ clean), or
**SKIPPED** (data unavailable; never a false positive).

### Subjects 1–7 vs subject 8: use the right tool

Subjects 1–7 are a handful of API calls and belong in the SessionStart path.
Subject 8 is a ~230-formula sweep taking roughly **15 minutes**, so it is opt-in
behind `--brew` and never runs inline in a hook.

**For day-to-day Homebrew coverage, use [`vuln-scan`](VULN_SCAN.md) instead.** It
is the incremental, SQLite-backed version of subject 8: it only checks what has
changed since last time, understands Homebrew revision bumps, and filters out
CVEs that Homebrew has already backported a fix for. `toolchain-cve-check --brew`
remains useful as a stateless one-shot audit.

> **Duplication warning.** `toolchain-cve-check` currently carries its own copy of
> the NVD/CPE/brew logic rather than importing `home/.local/bin/vulnlib.py`. A fix
> applied to one will **not** reach the other until they are collapsed. See the
> header of `vulnlib.py`.

## The data-source asymmetry (why pnpm and nvm differ)

This is the crux of the design, and it was verified against the live APIs, not assumed:

- **pnpm is an npm package**, so [OSV](https://osv.dev) answers "is `pnpm@X` vulnerable?"
  by exact version, **unauthenticated, from any shell**. OSV performs the semver-range
  match server-side, so there is **no client-side range parser** for pnpm.

  ```text
  POST https://api.osv.dev/v1/query
  {"package":{"name":"pnpm","ecosystem":"npm"},"version":"11.7.0"}  ->  GHSA-qrv3-253h-g69c
  {"package":{"name":"pnpm","ecosystem":"npm"},"version":"11.9.0"}  ->  (clean)
  ```

- **nvm is a bash script, not a registry package.** Its advisories are **absent from
  OSV and from GitHub's _global_ advisory database**. They live **only** at the repo
  endpoint, which requires `gh` + a token:

  ```text
  gh api repos/nvm-sh/nvm/security-advisories
  ```

  So the nvm half needs `gh`, and a small client-side membership test over each
  advisory's `vulnerable_version_range` (e.g. `>= 0.40.0, <= 0.40.3`). The nvm
  advisories on record:
  - `GHSA-4ghp-wxpw-rhpg` / CVE-2026-15921 (Low): `>= 0.32.1, <= 0.40.5`, fixed `0.40.6`
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
   toolchain-cve-check                       # floors from env + installed pnpm/nvm/claude
   toolchain-cve-check --pnpm-floor 11.7.0    # ad-hoc: prove a version is exposed
   toolchain-cve-check --claude-version 2.1.100  # ditto for Claude Code
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

## Regression suites

Two committed suites, both hermetic and offline. Run them after touching anything
they cover -- neither is wired into CI, because there is no CI here.

```bash
vulnlib-selftest                            # 58 checks: the shared library
.claude/hooks/toolchain-cve-check-selftest  # 28 checks: the SessionStart banner
```

[`vulnlib-selftest`](../home/.local/bin/vulnlib-selftest) covers the backport-detection
path in `vulnlib.py` -- whether an UNDETERMINED answer can ever read as "nothing was
backported", which `resolves` entries may silence a CVE, and whether a cached verdict
expires. Fixtures are injected through the module's own caches, so it never runs `brew`
or touches a database.

[`toolchain-cve-check-selftest`](../.claude/hooks/toolchain-cve-check-selftest) covers the
banner itself, and exists because the shell script deciding what you READ at login had no
controls at all while the Python behind it had 58. Three defects lived there in one
sitting on 2026-09-04, every one making the alert quieter: a count that included the
tool's own footer line (so every "N formulae UNVERIFIED" ever printed was one too high,
and a gate written to suppress wrong advice could never fire), a `grep -c` idiom that
printed `[: 0\n0: integer expected` into a security banner, and one piece of advice for
two causes that need opposite actions. It feeds the hook fixtures via `TMPDIR` and
`XDG_CACHE_HOME`, so your real caches are untouched.

Both open with a harness control that refuses to run if fixture injection is not working,
and both are mutation-tested: re-introduce any defect they claim to cover and they fail,
naming the check that caught it.

## Scope (and deliberate non-scope)

- **In scope:** the `pnpm` and `nvm` floors + their installed versions (the only two
  version floors the repo pins), **plus the installed Claude Code version** (added
  2026-07-30).
- **Claude Code is checked differently, and deliberately so.** It ships as the npm package
  `@anthropic-ai/claude-code`, so OSV covers it exactly like pnpm — but nothing _pins_ it,
  so there is no floor to check and only the installed version is examined. It earns a
  slot because it is the most privileged tool in the estate: 28 recorded advisories as of
  2026-07-30, several of them sandbox escapes. Before this, the daily monitor watched two
  package managers while the agent with filesystem and shell access was checked only when
  somebody thought to look. Remediation also differs — there is no floor to bump, so an
  exposure says `claude update`, and the tool prints that instead of the floor advice.
  Ad-hoc: `toolchain-cve-check --claude-version 2.1.100` (a known-exposed version, useful
  as a negative control).
- **Out of scope, on purpose:**
  - `NODE_MIN_MAJOR` — an end-of-life _major_ guard, not a single CVE-pinnable version.
  - Hard-coded version pins inside docs/README (e.g. an install URL) — too noisy to
    CVE-scan reliably.
  - `uv` — no floor constant exists to check.
  - `bun` — `BUN_MIN_VERSION` is checked, floor and installed, via OSV (wired
    2026-08-01). Confirmed real coverage rather than an empty shelf: bun@1.0.0
    returns GHSA-4j66-8f4r-3pjx and GHSA-v9mx-4pqq-h232.
  - **Auto-bumping** — this is a monitor and a nudge. Bumping a floor stays a deliberate,
    reviewed edit (in both `install.sh` and `home/.zsh_onboarding`), then a commit.

## Related

- [`docs/PNPM_AUDIT_TREE.md`](PNPM_AUDIT_TREE.md) — per-project pnpm dependency auditor (a
  different job: it audits a project's _dependencies_, not the pnpm/nvm tool versions).
- [`docs/NVM_SECURITY.md`](NVM_SECURITY.md) — the layered nvm/Node hardening this complements.
- [`docs/CI_WATCH.md`](CI_WATCH.md) — sibling session-start watcher: an escalating,
  dismiss-only-by-fixing CI-status line for repos you flag.
