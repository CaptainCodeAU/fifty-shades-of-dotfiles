# GitHub credentials in this estate: what exists, what each can do, and what is still open

Written 2026-09-17 at the close of a long two-session investigation, so that
nobody has to rediscover any of it.

**The other half of the record lives in LifeOS**, at
`LIFEOS/MEMORY/LEARNING/INCIDENTS/INC-20260917-gh-credential-fallback-escalation.md`
(commit 62dd38a). It holds that side's internals: its fetcher's four fail-closed
sources, which of its five consumers uses which credential lane, and the
read/write asymmetry reasoning. Read both; neither is complete alone.

*A correction worth keeping, because the first version of this line got it
wrong in exactly the way this estate keeps getting things wrong.* This document
is here because it is this repo's tooling and this repo's operators read it --
NOT, as first written, because "LifeOS memory is not backed up". `~/.claude/MEMORY`
is gitignored and backed up nowhere; `~/.claude/LIFEOS/MEMORY` is a symlink into
the `lifeos-private` repo and IS version controlled and pushed. Two paths one
segment apart, different stores, different durability, and reading one as the
other is the same mistake as every other confident zero in section 7. Everything below marked MEASURED was run on
this machine on that date, most of it against a throwaway private repo with no
GitHub App installed. Everything not marked as measured is flagged as such.

The short version: **there are four GitHub credentials here, they are not
interchangeable, and until tonight most tools took whichever one happened to be
lying around.**

---

## 1. The four credentials

| # | Credential | Where it lives | Reached by |
|---|---|---|---|
| 1 | **GitHub App installation token** | Infisical (`/github-agent-apps/{high,medium,low}-value`, `GITHUB_APP_PRIVATE_KEY`) | `github-agent-token token`, minted per repo, ~1 hour |
| 2 | **Narrow read-only PAT** | macOS Keychain, item `github-api-readonly` | `github-api-token`, and `_claude_launch` exports it as `$GH_TOKEN` |
| 3 | **Public-browsing PATs** | Infisical (`/github-agent-apps/public-read`, `public-write`, `PAT_VALUE`) | `github-agent-token pat public-read`; public-write has no print mode by design |
| 4 | **gh's own keyring token** | gh's internal keyring, a classic `gho_` OAuth token | nothing asks for it; gh uses it when nothing else is supplied |

Number 4 is the problem. Nobody chose it, nothing names it, and it is what every
unsupplied `gh` call silently lands on.

### What each can actually do (MEASURED, 38 cells)

Run `gh-cred-matrix` to reproduce. Against a private repo:

| Operation | narrow PAT (2) | keyring token (4) |
|---|---|---|
| identity `/user` | OK | OK |
| read public repo | OK | OK |
| read private repo metadata | OK | OK |
| **read private repo SOURCE** | **FAIL** | **OK** |
| Actions runs (what `ci-watch` needs) | OK | OK |
| list issues | OK | OK |
| **create issue** | **FAIL** | **OK** (it created one) |

**They differ in exactly two places, and both are the dangerous ones.** The
keyring token's scopes are `gist`, `read:org`, `repo`; `repo` is read AND write,
which the naming gives away since GitHub prefixes its read-only variants with
`read:`.

The public-read PAT (3) cannot see a private repo at all: `Not Found`, while
reading `cli/cli` fine in the same breath. It is not a substitute for (2).

The App token (1) can create issues where the App is installed (MEASURED by the
peer session against `dot-claude`), which is what gives write-capable tools a
home that is not the keyring token.

---

## 2. The two lanes that never meet

**This is the single most useful fact in the document.**

| Lane | Used by | Credential | Mechanism |
|---|---|---|---|
| `git push` / `fetch` over HTTPS | git | App (1) | git credential helper, `!$HOME/.local/bin/github-agent-token` |
| `gh` API calls | every status/CI/issue tool | `$GH_TOKEN`, else gh's keyring (4) | gh's own auth, which **ignores git credential helpers entirely** |

So "every repo has a GitHub App" is true and does not help: the App is a git
credential, and none of the escalation happens in git's lane.

---

## 3. The structural bug, found twice

`_claude_launch` in `home/.zshrc` reads the Keychain and passes `GH_TOKEN` as a
per-command prefix. It is reachable ONLY through the zsh aliases `c`, `ct`, `cb`,
`cr`, `ci`, `cpr`, `cd_`, `cskip` (12 references in that file: the definition,
ten aliases, two comments). **No spawned process inherits an alias.**

The `gh()` wrapper in the same file is the second instance: inside a flipped repo
it MINTS an App token and OVERRIDES a caller-supplied `GH_TOKEN` with an
assignment prefix. Also a shell construct, also not inherited.

Two instances of "credential logic in the shell layer", both found by accident
while looking for something else. Treat that as a category, not a pair.

### herdr, specifically (MEASURED, and it closed a two-day-old open item)

`herdr agent start --kind claude` reports `argv: ["claude"]` and echoes the bare
command into the pane. The spawned process's parent is `-zsh`, so herdr TYPES
into a live interactive shell rather than exec'ing into the pty. The alias `c`
IS defined in that shell, but herdr types `claude`, so `_claude_launch` never
runs. That session came up with `GH_TOKEN` of length 0 and no `NVD_API_KEY`
(control: `${#HOME}` was 17 in the same command), and `gh auth status` inside it
reported the keyring token with `repo` scope.

Not a herdr bug. cron, launchd, a CI runner or an MCP server all land identically.

---

## 4. What was decided, and what was built

Gavin's ruling, after four options were costed: **fix the consumers, not the
launcher.** A tool that fetches its own credential is correct no matter who
spawns it; every launcher-side fix only covers the launchers it knows about.

Rejected, and why, so nobody re-proposes them cold:

- **A `claude()` shell function.** Would work, since herdr types into a live
  shell. Rejected: a function is no more inherited than an alias, so it fixes
  herdr and nothing else.
- **A PATH shim in front of `claude`.** Written, never shipped, parked. `PATH`
  IS inherited, so it covers everything a shell started. Rejected once the
  consumer fix made it redundant. Its own limits: boot-time launchd and cron
  keep their own `PATH`, and `~/.local/bin/claude` is a symlink the Claude Code
  installer rewrites (observed rewritten 2026-09-17 10:39), so a shim placed
  there would be silently clobbered.
- **Swapping gh's stored token** via `gh auth login --with-token`. Not done.
  It needs a guard lift (`CLAUDE.md` line 345 and
  `.claude/hooks/enforce-gh-ssh-only.sh` block it) and it touches
  `git_protocol = ssh`, which **21 of the 94 repos on this machine still use**.
- **Deleting the keyring token.** Not done, not authorised, and it would break
  every consumer until they self-fetch.
- **`gh auth refresh` to narrow the existing token's scopes.** MEASURED by the
  peer session: two attempts both COMPLETED and changed nothing. The scopes were
  unchanged afterwards. So the CLI route to narrowing what gh already holds is
  closed, and a success exit code there means nothing. Recorded because it is an
  obvious thing to try and it looks like it worked.

### Shipped in this repo

| Thing | What it does |
|---|---|
| `home/.local/bin/github-api-token` | prints the narrow PAT, or fails with EMPTY stdout |
| `home/.local/bin/gh-cred-matrix` | the measurement tool that produced section 1 |
| `ci-watch` | fetches its own credential, fails CLOSED, names which credential answered |
| `toolchain-cve-check` | same, plus the summary fix in section 6 |
| `.claude/hooks/zed-version-check.sh` | same |

LifeOS (`dot-claude`) owns its five consumers and grew its own fetcher
(`bd9547f`), deliberately duplicating the READ lane (71 lines) and borrowing the
WRITE lane (513 lines, JWT signing plus Infisical bootstrap). Two
implementations of credential-minting would be a worse bug than the dependency.

---

## 5. The trap that will catch the next person

**An empty or unset `GH_TOKEN` is not "no credential" to gh. It falls through to
the keyring token.** MEASURED, three arms, on a source read only the broad token
can serve:

```
GH_TOKEN=''                       -> 612c950bddd...   a real commit SHA
GH_TOKEN=<narrow PAT>             -> 403 not accessible by personal access token
GH_CONFIG_DIR=<empty> GH_TOKEN='' -> please run gh auth login
```

The third arm is what makes the first trustworthy.

So the obvious consumer shape is a trap:

```bash
GH_TOKEN="$(github-api-token)" gh api ...     # WRONG: a failed fetch gives GH_TOKEN=""
```

Use both guards, never either alone, because exit status and emptiness diverge:

```bash
tok="$(github-api-token)" || { echo "cannot authenticate" >&2; exit 1; }
[ -n "$tok" ]             || { echo "cannot authenticate" >&2; exit 1; }
GH_TOKEN="$tok" gh api ...
```

A tool that must keep running sets a deliberately INVALID token so gh fails
closed. **Do not make the sentinel token-shaped** — the leak scanner will block
it, correctly, because a fake secret matching the secret pattern trains people
to wave the scanner through.

### Measuring gh at all

- `gh` is a **shell function** here. `whence -p gh` (zsh) or `type -P gh` (bash).
  `command -v gh` returns the function name and is not safe.
- A measurement taken **inside a flipped repo** measures the App token, because
  the wrapper overrides yours. App failures say *"not accessible by
  integration"*; PAT failures say *"not accessible by personal access token"*.
  Reading the first while believing you passed a PAT sends you after the wrong
  credential family; it cost the peer session a wrong conclusion.
- `GH_CONFIG_DIR=/tmp/empty-dir` simulates the deleted-token world reversibly.
  Nothing is deleted and nothing needs recovering. Best single technique of the
  investigation.

---

## 6. The other defect this turned up

`toolchain-cve-check` printed **`All 5 checked subject(s) clean. (2 skipped)`**
in green, exit 0, when two of seven subjects could not be checked at all. Every
word true, the impression false: the denominator moved from 7 to 5 and the
headline did not say so. Now it leads with
`2 of 7 subject(s) NOT CHECKED`, the healthy case says `All 7` (it was quietly
wrong there too), and the SessionStart hook surfaces `NOT CHECKED` alongside
`EXPOSED`.

The novel part, which the peer named better than I did: the excess authority was
invisible because the QUERY was innocuous. A security checker was reading a
PUBLIC advisory list while holding a credential that can read all private
source, and it succeeded exactly as intended. Every other instance that day
announced itself through a failure that looked like success. This one announced
nothing at all.

---

## 7. STILL OPEN

Nothing here is blocked on this repo.

1. **The keyring token still exists and is still write-capable.** It becomes
   deletable once LifeOS's five consumers are done. **No ruling has been made on
   deleting it, and "all consumers fixed" is not implicit permission.** When it
   is time, `gh auth logout` is the mechanism, and everything in section 4 about
   the guard applies.
2. **`gh-cred-testbed` can be deleted from 2026-09-18.** Keep-for-a-day was the
   peer's request, for an arm they may not need. The property that made it
   useful is preserved in `gh-cred-matrix`'s header, so the repo is disposable
   once that is read.
3. **Untracked files were never swept.** The peer's census ran in git mode:
   2 untracked in `dot-claude`, 4 in `lifeos-private`, 1 here. An untracked
   script calling `gh` would not have appeared and would still run.
4. **Pulse is a LATENT instance.** `com.lifeos.pulse` is a live launchd daemon
   whose work module spawns bare `gh issue list`, but `WORK.REPO` is unset so it
   returns before reaching that line. **The day a work repo is configured, an
   unattended daemon starts calling bare `gh`.** Fix it before configuring it.
5. **Boot-time contexts remain uncovered by anything.** launchd and cron have
   their own `PATH` and cannot reach the login Keychain. Every fetch here fails
   CLOSED there rather than escalating, which is correct but means those
   contexts have no GitHub access at all. The only route that would change this
   is the file-based Infisical bootstrap at
   `~/.config/github-agent/<service>.secret`, which **does not exist on this
   machine**. Creating it means a long-lived client secret on disk: a real trade,
   not a free win.
6. **`GH_TOKEN` is still leaking into transcripts** — 12 files, oldest 14 June,
   token rotated but the cause unfixed. Pre-existing, `OPEN.md` item 4, and
   directly relevant: it is the argument against passing tokens on command
   lines, and the reason tools fetching internally is the better shape.

### Not explored at all

- Whether any **other** tool on this machine, outside these two repos, calls
  `gh` unsupplied. Only `dot-claude`, `lifeos-private` and this repo were swept.
- Whether the App can serve `ci-watch`'s Actions reads across **several** repos,
  which would remove the PAT from the read lane entirely. App tokens are
  per-installation and `ci-watch` watches repos that may not all have it.
- What `gh auth login --with-token` actually does to `git_protocol` and
  `~/.gitconfig`. The guard exists because it "re-adds HTTPS credential helpers";
  that claim has never been re-verified, and 21 SSH repos depend on the answer.
- Whether the sandboxed-agent Keychain denial has any route around it that is
  not a standing grant. Two were already rejected: a keychain allow-list and an
  App-only keychain.

### A method note worth keeping

Five separate times in one evening, across two sessions, the same shape: **a
property that is true in both worlds cannot decide between them.** A count that
reads 0 whether the mechanism worked or never ran. A `head -8` that hid the
answer. A search of the wrong region. An empty directory that was empty for the
live plugin too. A source file containing a call that is never reached. In every
case the defence was not care, it was a CONTROL run in the same command.

That rule is now in this repo's `CLAUDE.md` as the general form of its four
worked traps, with `peek` as the tool for the truncation variant.
