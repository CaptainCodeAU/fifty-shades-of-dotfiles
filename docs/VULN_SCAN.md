# vuln-scan — are the packages actually installed carrying known CVEs?

A read-only, incremental scanner over **installed Homebrew formulae**, checked
against NVD by CPE. Sibling to [`toolchain-cve-check`](TOOLCHAIN_CVE_CHECK.md),
which watches a handful of pinned floors; this one watches all ~230 things
Homebrew has put on the machine.

## Why a second tool rather than a flag

`toolchain-cve-check` answers from scratch every run. For 230 formulae that is
roughly **15 minutes** — fine for an ad-hoc audit, impossible for a shell prompt.
`vuln-scan` remembers what it has already checked in SQLite, so the ordinary case
(nothing installed or upgraded since last login) costs **one `brew list` and one
local read, with no network at all**.

The cache key is `(name, version, revision)`. The **revision matters**: Homebrew
ships backported security patches as a revision bump while keeping the upstream
version, so `libssh2 1.11.1_3` and `1.11.1_4` are genuinely different things and
a bump must force a rescan. Keying on version alone would mean a security update
is never re-examined.

## Three doors, one engine

| Invocation | Where it runs             | Behaviour                                                                                  |
| ---------- | ------------------------- | ------------------------------------------------------------------------------------------ |
| `--fast`   | every new terminal tab    | Silent when nothing changed. Checks up to 12 packages inline; **detaches anything larger** |
| (hook)     | Claude `SessionStart`     | `.claude/hooks/vuln-scan-check.sh` — same engine, turns findings into session tasks        |
| `--report` | on demand / automatically | Writes a self-contained briefing for a context-free assistant                              |

The 12-package inline cap is what keeps this out of the "why is my terminal
frozen" category. A cold database has ~230 packages to check; a login shell that
blocks for a quarter of an hour is a tool people delete. Anything over the cap is
handed to a detached process behind an atomic lock, and the shell says so rather
than pausing silently.

## What it will not do

**Report "clean" when it could not tell.** Every uncertain path — unresolvable
CPE, rate limit, empty response body, namesake collision — lands on `UNVERIFIED`,
which is printed even under `--quiet`. See
the header of `home/.local/bin/vulnlib.py` for the four separate ways an NVD
answer can silently look like a zero:

1. an unknown CPE returns 0 CVEs, byte-identical to a clean package;
2. past the rate limit NVD returns an **empty body**, which parses as 0;
3. `vulnerable: false` context matches count as hits if you trust `totalResults`
   — gnutls 3.8.13 once "matched" a 2009 **Mutt** bug that merely names it;
4. Homebrew version suffixes (`1.11.1_3`, `openssl@3`) match no CPE at all.

## Reading the output

| Bucket                            | Meaning                                                                |
| --------------------------------- | ---------------------------------------------------------------------- |
| `ACTION NEEDED`                   | CVSS >= 7.0, or unscored. These are in the briefing                    |
| `EXPOSED, BELOW ACTION THRESHOLD` | Live and unfixed, just under 7.0. **Quieter, not safe**                |
| `PATCHED BY HOMEBREW`             | NVD still flags it; the fix is backported into the installed revision  |
| `ALL-VERSION, no fixed release`   | Real, but no upgrade can clear it — excluded from the alarm on purpose |
| `UNVERIFIED`                      | No resolvable CPE. **Not** clean — just unanswerable                   |

### The Homebrew-patch subtlety, which is the whole reason this is trustworthy

NVD knows nothing about Homebrew revisions, so a formula whose fix has already
been backported keeps reporting as vulnerable. Where a CVE description names its
fix commit and that commit appears in the formula's patch list (`brew cat`), the
finding is downgraded to `PATCHED BY HOMEBREW` and kept out of the alarm.

Measured on `libssh2 1.11.1_4`: 6 of 9 CVEs matched to backported patches,
including the CRITICAL CVE-2026-55200. Matching is deliberately substring-tolerant
in both directions because NVD's prose is hand-written and sometimes wrong — that
CVE says _"fixed in commit 7acf3df"_ when the real hash is `97acf3df`.

Telling someone to upgrade a package they have just upgraded is how a security
alert stops being read.

## Commands

```bash
vuln-scan                       # full table
vuln-scan --fast                # shell-startup mode
vuln-scan --full                # ignore the cache, rescan everything
vuln-scan --only libssh2        # re-check one formula (repeatable)
vuln-scan --json                # machine-readable
vuln-scan --report              # (re)write the briefing
vuln-scan --ack ffmpeg CVE-2026-64830 --ack-days 30 --ack-reason "not fed untrusted media"
```

**Acknowledgements expire.** 30 days by default, on purpose: a permanent mute is
how a finding disappears for good, so an accepted risk comes back for a fresh
decision rather than vanishing.

## The briefing file

`~/.local/state/dotfiles/vuln-briefing.md`, rewritten whenever something is
actionable. It is a **self-contained handover**: paste it into a fresh session
with no repo access and it carries the full problem statement — findings, CVSS,
descriptions, and the unmatched Homebrew patch commits with a direct request to
judge whether they already cover the outstanding CVEs.

It deliberately carries **no machine identifiers, usernames or absolute paths**.
It names installed software and versions, which is a target list, so it is
written to be safe to share.

## The NVD API key (optional; a rate limit, not a credential)

It authorises nothing. It only lifts NVD's anonymous limit from 5 to 50 requests
per 30s, which takes a full sweep from ~20 minutes to ~4. Resolved from, in order:

1. `$NVD_API_KEY` — exported by `_claude_launch`, or from `~/.zshrc.private`
2. `~/.config/dotfiles/nvd-api-key` — the portable path (Linux/WSL)
3. macOS Keychain entry `nvd-api-key`

Free and instantly regenerable at
<https://nvd.nist.gov/developers/request-an-api-key>. `install.sh` reports when
it is missing and gives the platform-correct command; it never prompts or stores
anything itself.

## Platform scope

**Homebrew only, deliberately.** On a Debian/Ubuntu box the tool says
_"no Homebrew on this machine, so nothing was scanned"_ and exits 2 — because
"no packages checked" and "no vulnerable packages" must never look the same.

apt is not a second inventory to bolt on. Debian and Ubuntu backport far harder
than Homebrew while keeping the upstream version in the string
(`1.11.1-1ubuntu0.2`), and unlike `brew cat` there is no per-package list of
applied patches to match against — so NVD-by-CPE against a Debian version would
reproduce, at several times the scale, exactly the false-positive class this tool
exists to eliminate. The right source for those boxes is Ubuntu's own USN/OVAL
tracker. Parked, by decision, 2026-08-03.

## Known duplication

`toolchain-cve-check` still carries its own copy of the NVD/CPE/brew code rather
than importing `vulnlib.py`. This is recorded at the top of `vulnlib.py` and is a
deliberate follow-up: that file is load-bearing in an existing SessionStart hook,
and collapsing it needs its own verification pass against the five behavioural
controls. **Until then, a change to one must be mirrored in the other.**

## Files

| Path                                       | Role                                          |
| ------------------------------------------ | --------------------------------------------- |
| `home/.local/bin/vuln-scan`                | the tool                                      |
| `home/.local/bin/vulnlib.py`               | shared NVD/CPE/brew/store library             |
| `.claude/hooks/vuln-scan-check.sh`         | SessionStart hook — turns findings into tasks |
| `home/.zsh_welcome`                        | shell banner block (exception-only)           |
| `~/.local/state/dotfiles/vuln-scan.db`     | scan state (not in the repo)                  |
| `~/.local/state/dotfiles/vuln-briefing.md` | the handover file (not in the repo)           |

Related: [TOOLCHAIN_CVE_CHECK.md](TOOLCHAIN_CVE_CHECK.md),
[PNPM_AUDIT_TREE.md](PNPM_AUDIT_TREE.md), [SECURITY.md](SECURITY.md).
