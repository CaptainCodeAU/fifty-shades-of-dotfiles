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
| 4 | ~~**gh's own keyring token**~~ **RESOLVED 2026-09-17, see section 9.** The keyring now holds credential 2, the narrow read-only PAT. The classic `gho_` OAuth token was replaced and then REVOKED at GitHub. | gh's internal keyring | nothing asks for it; gh uses it when nothing else is supplied -- which is now harmless, because what it lands on is the credential it should have had |

Number 4 WAS the problem. Nobody chose it, nothing named it, and it was what every
unsupplied `gh` call silently landed on. Closed 2026-09-17: the keyring was repointed
at credential 2 and the old OAuth grant revoked. **The sentence is kept rather than
rewritten** because it states the failure shape this whole document exists to record,
and a shape does not stop being true just because one instance of it was fixed. The
unsupplied call still happens; it simply no longer gains anything by happening.

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

1. ~~**The keyring token still exists and is still write-capable.**~~
   **CLOSED 2026-09-17 evening, see section 9.** It was REPLACED with the narrow
   read-only PAT rather than deleted, on Gavin's explicit pick. The token now in
   the keyring cannot read private file contents and cannot write. Logging out
   remains available as the stricter endpoint later. What this item got wrong:
   it assumed deletion was the only mechanism, and replacement is strictly
   better for the reason section 9 gives.
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

---

## 8. Second pass, 2026-09-17 evening: the shell-layer fix, attacked and dropped

A later session re-opened the spawn gap without reading this document first, and
proposed the one thing section 4 had already rejected in a different costume: an
`alias claude='_claude_launch claude ...'` in `home/.zshrc`. Two read-only audits
(one cross-vendor) and eight measurements later it was dropped. **The re-derivation
is itself the finding** — the ruling in section 4 lived here while a commit message
from the same day (`69de6c9`) said the alias route had been picked. When the record
disagrees with itself, the later, fuller document wins, and this section is the tie
being broken in writing so it is not broken again by guesswork.

### What was measured that section 4 did not know

All in throwaway herdr panes, since closed. Each has its control named.

| # | Finding | Basis |
|---|---|---|
| 1 | A shell-layer fix WOULD work. A sentinel alias fired on herdr's typed line: herdr echoed bare `claude`, the pane printed `ALIASFIRED_7f3q`. Sentinel assembled at runtime so it could not match the echoed definition. | MEASURED |
| 2 | `agent start` reports `argv: ["claude"]` with NO arguments, so an alias would supply every flag. | MEASURED |
| 3 | The `LastCommitFiles.sh` banner is a NON-ISSUE for agent detection. Control arm (no alias) detected Claude in 4s; banner arm detected in 4s, with both the banner text and `Claude Code v2.1.274` in the pane read. | MEASURED |
| 4 | `_claude_launch` BLOCKS in a pty. With the alias in place, `agent start` timed out at 45s and the pane sat at `Enter passphrase for ~/.ssh/captaincodeau`, banner above it proving the wrapper had run. | MEASURED |
| 5 | herdr then reports `timed out waiting for agent startup`. Nothing in that error names ssh. Same family as the auth-error rule: the symptom names the surface, never the layer. | MEASURED |
| 6 | zsh BAKES an alias into every function defined after it, permanently, at parse time. `myfunc_before` kept `claude bar`; `myfunc_after` became `_wrap claude --SKIP-PERMS foo`. The source file still reads `claude`; only `functions <name>` shows the truth. Baseline scan of the live shell: `baked=1 scanned=2031`, the single hit being `_claude_launch`'s own body. | MEASURED |
| 7 | The Claude Code Bash tool sources `~/.claude/shell-snapshots/snapshot-zsh-*.sh`, so **310 aliases are live inside every Bash call**. `whence -w c` returns `c: alias`; control `whence -w notanalias_zz` returns `none`, rc=1. An alias would therefore fire estate-wide, not just in herdr panes. | MEASURED |
| 8 | A plain `zsh -c` sources neither `.zshrc` nor the snapshot, so it has NO aliases: `whence -w claude` returns `command`, and `GH=0 NVD=0 HOME=17` (the 17 is the control). A `claude -p` spawned from there reported its own env as `GH_TOKEN` 0 bytes, `NVD_API_KEY` 0 bytes, `HOME` 18 bytes. | MEASURED |

Rows 7 and 8 look contradictory and are not. **The difference is who sourced what**,
not whether zsh expands aliases non-interactively. Record both together or the next
reader will think one of them is wrong.

Row 7 is the strongest argument against any shell-layer fix, and it is stronger than
the inheritance argument in section 4: an alias does not merely fail to reach other
launch paths, it silently reaches a path nobody intended. Had the alias mirrored `c`,
every herdr-spawned agent would have gained `--dangerously-skip-permissions`, turning
a broad READ token into an agent that can WRITE without prompting. That is a bigger
privilege change than the one being fixed, in the opposite direction.

### Sizing what deleting the keyring token would cost (section 7, item 1)

Census of every git repo under `~/CODE` and `~/.claude`, `find -maxdepth 4`:

| Population | Count |
|---|---|
| repos total | 94 |
| flipped to the App (`githubagent.tier` set) | 44 |
| not flipped | 50 |
| ...of those, YOURS with a GitHub origin | **2** (`cc-warehouse`, the `captaincodeau` marketplace, both plugin clones) |
| ...third-party clones | 30 |
| ...no remote at all | 18 |

The three unflipped rows sum to 50, which is the control against the total. So the
browsing cost of losing credential (4) falls on 30 third-party clones and 2 plugin
marketplaces, all read-only work that `github-agent-token pat public-read` already
serves. The 18 local-only repos need no credential. This does not by itself authorise
the deletion — section 7 item 1 still stands — but it sizes it.

Re-verified the same evening, in the non-flipped `cc-warehouse` with `GH_TOKEN` and
`GITHUB_TOKEN` both unset: `gh` answered as `CaptainCodeAU` from `(keyring)`, token
`gho_`, scopes `gist, read:org, repo`, with `HTTP/2.0 200 OK` returned in the same
command as the control. Unchanged from section 1. MEASURED.

### The ordering rule, which is the part that would have bitten

**Delete or replace the keyring token BEFORE you stop exporting `GH_TOKEN`, never
the other way round.** The moment `GH_TOKEN` is unset, `gh` falls through to its
keyring by design. If the broad token is still there, unexporting converts a
launcher gap into an estate-wide default, by the same mechanism as the banned
"retry with `GH_TOKEN` unset" fallback, arriving as a migration step instead of a
retry. REASONED, and it is the reason the two steps are not interchangeable.

### A documentation defect found on the way

`CLAUDE.md` recommends `type -P gh` as the resolver that sees past the shell
wrapper. **`type -P` is a bash builtin flag.** In zsh it fails: `zsh:type:8: bad
option: -P`. The zsh form is `whence -p`. That line exists specifically to stop
someone measuring the wrong credential, so it failing in the estate's default
interactive shell is worth correcting. MEASURED. **Since corrected**: `CLAUDE.md`
now carries both forms and the reason the wrong one fails silently. This sentence
is left in place, amended rather than deleted, because a record that quietly
erases its own open items cannot be trusted about the ones still listed.

### Still open after this pass

- ~~Whether `ssh-add` blocks or fails fast with **no tty at all**.~~ **ANSWERED
  2026-09-17 evening: it FAILS FAST, it does not hang.** The probe returned
  `rc=1`, not `124`, from a context where `tty` reported `not a tty`, with
  `timeout 2 sleep 30` returning `124` in the same run as the control proving the
  instrument detects a real hang. It prints the passphrase prompt, gets EOF, and
  gives up at once. So the blocking behaviour in row 4 is specific to a pty, and
  Bash-tool and cron contexts were never at risk of hanging on this. MEASURED.
- A `SIGKILL` skips `_claude_launch`'s `trap`, leaving a 12-hour `ssh-agent`
  holding an unlocked key. Today that is once per session; under any
  per-invocation wrapper it would be once per call. REASONED.
- Taking ssh out of `_claude_launch` entirely would remove rows 4, 5 and most of
  the process-tree question in one move. Not proposed formally, not costed.

---

## 9. Third pass, 2026-09-17 evening: the swap, executed

Gavin picked **replace, not delete**, from four costed options. Done and verified.

### The argument that decided it, which the first two passes missed

Sections 7 and 8 both framed this as *how much authority do we take away*. That
framing makes deletion look like the ideal and replacement like a compromise. It is
backwards. **After the swap the fallback credential and the intended credential are
the SAME token.** A herdr-spawned agent now has identical authority to a
`_claude_launch` one, so the spawn gap in
`INC-20260915-herdr-spawn-bypasses-credential-path` stops being a privilege
difference at all. Deleting the token makes the gap loud; replacing it makes the gap
harmless. Loud is worth less than harmless in contexts nobody is watching, and the
unattended ones are exactly where section 7 item 4 says the risk lives.

### What was measured, each with a control in the same command

| # | Finding | Basis |
|---|---|---|
| 1 | **`--with-token` does NOT touch `~/.gitconfig`.** sha1 `d38fa65e...` identical before and after a real login. The guard's premise applies to the interactive flow and `setup-git`, not to this. This closes the section 7 "not explored at all" item, and the 21 ssh repos were never at risk from it. | MEASURED |
| 2 | **The broad token really could read private source.** It listed 19 root entries of the private `dot-claude` and read `CLAUDE.md` at 7293 bytes. The narrow PAT returns 403 on that exact path, while both read a public file at 6262 bytes as the control. The incident's central claim is now first-hand, not relayed. | MEASURED |
| 3 | **The PAT works through gh despite gh's own warning.** `gh auth login --help` discourages fine-grained PATs with `--with-token` and asks for classic `repo, read:org, gist`. It was accepted anyway, rc=0. The warning is about confusing behaviour, not refusal. | MEASURED |
| 4 | **`git_protocol: ssh` survived.** `hosts.yml` and `config.yml` both byte-identical after the swap. `--git-protocol ssh --skip-ssh-key` were passed rather than trusted to default. A fresh config shows `https`, so this was a real risk, not a theoretical one. | MEASURED |
| 5 | **Both git lanes still work.** Census of all 94 repos reproduced the record exactly: 21 ssh origins, 55 https, 18 with no remote, summing to 94 as its own control. One repo from each lane returned real refs; a bogus remote returned rc=128 as the negative control. | MEASURED |
| 6 | **Post-swap behaviour of the keyring token:** public read 6262, private contents 403, write 403, `rate_limit` 5000 as the positive arm in the same breath. | MEASURED |

### The defect found by accident, which is the bigger finding

**The guard did not fire.** The authorised swap ran, and `security.log` recorded
nothing. `enforce-gh-ssh-only.sh` anchored the binary name to start-of-string or a
`[;&|]` separator, so an `env` prefix walked straight past it. So did an absolute
path, a `sudo` prefix, and a leading variable assignment. The bare form blocked
correctly as the positive control, which is precisely why nobody noticed: the guard
passed every test anyone thought to run.

Worse, an `env` prefix defeats the interactive shell wrapper too, because `env` execs
the binary and never consults shell functions. **One ordinary word defeated both
layers of the same guard at once**, and neither layer said so.

Fixing the anchor then produced the mirror-image defect, which is worth as much: the
widened pattern began matching the command name written as PROSE inside a heredoc, so
the first attempt to document this section was blocked by the guard it describes. A
guard that blocks people from documenting it is a guard that gets switched off.
Heredoc bodies are now stripped before matching. Proven with 17 cases, 9 must-block
and 8 must-allow, including the fine distinction between a heredoc of prose (allowed)
and a heredoc feeding a real invocation (blocked).

This is the same shape as the method note at the end of section 7, arriving from a new
direction: **a guard that passes its positive control can still be open in every
direction nobody tested.** The control proves the mechanism fires, never that it
covers. Both are needed, and only the first was ever run here.

### Still open after this pass

- ~~**The old `gho_` token is out of the keyring but NOT revoked at GitHub.**~~
  **REVOKED by Gavin, 2026-09-17 evening**, via Authorized OAuth Apps -> GitHub CLI ->
  Revoke. That kills every token that grant ever issued, on every machine, not just
  this one. Verified immediately afterwards with controls in the same commands: gh
  still authenticates from the keyring as the PAT, public and private-metadata reads
  both answer, `rate_limit` returns 5000 as the positive arm, and both git lanes still
  resolve real refs against a bogus remote failing with rc=128. **Nothing on this
  machine depended on it**, which is the point: it had been a standing grant with
  `repo` scope that no tool asked for and every unsupplied call could reach.

  This closes the loop on section 7 item 6 as well, in one direction only. `GH_TOKEN`
  has been leaking into transcripts since June, so any copy of THIS token captured
  there is now inert. The leak itself is untouched, and the PAT that replaced it leaks
  by the same route.
- **Unexporting `GH_TOKEN` is now unblocked** by D-20260917-03's ordering rule, since
  the keyring no longer holds anything broad. Not done, not proposed, not costed.
- **Section 7 items 2 to 6 are untouched by this pass** and all still stand.
- **Taking ssh out of `_claude_launch`** is still uncosted. The no-tty measurement
  above shrinks the case for it slightly: the fast-fail path was never the problem,
  only the pty path is.
- ~~**Whether other guards in this estate share the anchor defect** was not swept.~~
  **SWEPT the same evening. They do, and there were two copies of this guard.**

  First, the guard itself existed TWICE: the repo copy at `.claude/hooks/` and a
  separate real file at `~/.claude/hooks/`, wired globally in `~/.claude/settings.json`
  and therefore live in every project on this machine. Fixing the repo copy fixed the
  narrower of the two. Both now carry the fix and both pass the regression suite. The
  lesson is its own instance of the class: *a fix applied to the copy you happened to
  open is not a fix.*

  Second, five more hooks share the identical `(^|[;&|]\s*)` anchor. Measured, each with
  its bare form blocking as the positive control in the same run:

  | Hook | Bare form | Prefixed form |
  |---|---|---|
  | `enforce-uv.sh` | BLOCKED | `env python3 ...` ALLOWED, `/usr/bin/python3 ...` ALLOWED, `sudo pip install ...` ALLOWED |
  | `enforce-pnpm.sh` | BLOCKED | `env npm install ...` ALLOWED |
  | `enforce-no-cd.sh` | BLOCKED | `time cd /tmp` ALLOWED |
  | `enforce-builtin.sh` | same anchor, not probed | -- |
  | `enforce-herdr-skill.sh` | same anchor, not probed | -- |

  These are style and workflow guards, not security boundaries, so the blast radius is
  nuisance rather than privilege. They are NOT fixed, deliberately: each needs its own
  must-block and must-allow suite before its pattern is widened, because widening is
  exactly what produced the heredoc false positive above. Left as a named open item
  rather than a silent one.

  `enforce-census.sh` is the exception and the reference implementation. It already
  strips heredocs and already carries a comment about anchoring, so somebody met this
  class there first and the knowledge did not travel.
