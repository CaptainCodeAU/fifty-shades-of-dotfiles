# Deletion safety — what routes to the Trash, and what does not

Deleting a file on this machine should be recoverable. That is achieved by routing deletion
through [`home/.local/bin/safe-rm`](../home/.local/bin/safe-rm), which moves targets to the
system Trash (`/usr/bin/trash` on macOS, `trash-put` on Linux/WSL) and **never unlinks**.

The hard part is not the trashing. It is COVERAGE: a shell function only exists inside an
interactive zsh, so every guard written that way is invisible to scripts, cron, CI, git hooks
and `xargs`. This document records which call paths are actually covered, which are not, and —
importantly — which ones **cannot** be, with the measurement that proves it.

## The chain

There are two entry points, and which one runs depends only on whether a shell function is in
scope. Both end at the same place.

```
interactive zsh   rm() / rmdir()  (home/.zshrc)   ->  safe-rm      ->  /usr/bin/trash  ->  ~/.Trash
everything else   ~/.local/bin/rm  (PATH shim)    ->  safe-rm -q   ->  trash-put       ->  XDG trash (Linux/WSL)
sudo rm / rmdir   sudo() (home/.zshrc)            ->  safe-rm      (as the invoking user, NOT as root)
bare trash        ~/.local/bin/trash  (PATH shim)  ->  trash-guard  ->  /usr/bin/trash  (since 2026-09-29)
```

Since 2026-09-29 `safe-rm` and the `trash` shim both ask
[`trash-guard`](../home/.local/bin/trash-guard) before anything moves; see
[The trash guard](#the-trash-guard) below.

A zsh function takes precedence over `PATH`, so an interactive `rm` uses the function (which
prints what it trashed) and a script's `rm` uses the shim (quiet, so it does not corrupt stdout
that a caller may be parsing). Verified: `zsh -ic 'type rm'` reports the function while
`/bin/sh -c 'command -v rm'` reports `~/.local/bin/rm`.

`safe-rm` fails closed. If no trash tool is installed it exits 1 and deletes nothing; it never
falls back to `rm`, because a silent downgrade from "recoverable" to "permanent" is the one
behaviour a safety command must not have.

## Coverage

Measured 2026-09-04 on macOS 25.6 (Darwin), SIP enabled. Every row was run, not inferred.

| Call path                                                                                                                                   | Covered?               | Evidence                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interactive zsh, `rm -rf dir`                                                                                                               | yes                    | trashed to `~/.Trash/rmtest-victim`; `test -e` confirmed                                                                                                                                                                                                                                                                                    |
| Claude Code Bash tool                                                                                                                       | yes                    | `type rm` -> shell function from the session's shell snapshot                                                                                                                                                                                                                                                                               |
| `sudo rm` / `sudo rmdir`                                                                                                                    | yes                    | 13-case behaviour test, below                                                                                                                                                                                                                                                                                                               |
| `sudo -u root rm -rf x`                                                                                                                     | yes                    | option scanner finds the command past sudo's own flags                                                                                                                                                                                                                                                                                      |
| `#!/bin/bash` script, bare `rm`                                                                                                             | yes                    | live: script's `rm -rf` landed in `~/.Trash/victim`                                                                                                                                                                                                                                                                                         |
| `#!/bin/zsh` script, bare `rm`                                                                                                              | yes                    | dummy-shim test hit the shim                                                                                                                                                                                                                                                                                                                |
| `xargs rm`                                                                                                                                  | yes                    | live: `~/.Trash/xtarget.txt`                                                                                                                                                                                                                                                                                                                |
| `make clean`                                                                                                                                | yes                    | live: `~/.Trash/junk.o`, and a missing target did not break the rule                                                                                                                                                                                                                                                                        |
| `find -exec rm`                                                                                                                             | yes                    | 2026-10-01, both finds (an agent shell's `find` is Claude Code's built-in `bfs`; scripts get `/usr/bin/find`): sandboxed, each printed `safe-rm: these paths still exist after the trash call` (the shim; `/bin/rm` cannot print it), file stayed; `bfs` unsandboxed, in `~/.Trash`, `keeper` untouched                                     |
| `command rm`, `\rm`                                                                                                                         | yes                    | these bypass functions and aliases, not `PATH`                                                                                                                                                                                                                                                                                              |
| `env -i rm`, `PATH=/bin rm`, `command -p rm`                                                                                                | **no**                 | a PATH without `~/.local/bin` finds `/bin/rm` (measured 2026-09-25 for `env -i` and `command -p`; `PATH=/bin` is the same lookup, not run). The agent guard denies them (`rm-lookup`, below)                                                                                                                                                |
| Homebrew formula post-install                                                                                                               | yes                    | `formula.rb:1662` restores the user's PATH for that phase                                                                                                                                                                                                                                                                                   |
| cron / launchd / CI                                                                                                                         | **no**                 | minimal PATH; `~/.local/bin` absent                                                                                                                                                                                                                                                                                                         |
| Homebrew internals                                                                                                                          | **no**                 | `bin/brew:308` hardcodes `PATH=/usr/bin:/bin:/usr/sbin:/sbin`                                                                                                                                                                                                                                                                               |
| Docker `RUN rm -rf`                                                                                                                         | **no**                 | runs inside the image with its own `/bin/rm`                                                                                                                                                                                                                                                                                                |
| `/bin/rm`                                                                                                                                   | **no, cannot be**      | absolute path never consults PATH; SIP `restricted`, see below                                                                                                                                                                                                                                                                              |
| `SAFE_RM_OFF=1 rm ...`                                                                                                                      | yes, guarded           | REMOVED 2026-09-29 (Gavin, W-20260929-A164): the shim ignores it, says so, and still goes to the Trash                                                                                                                                                                                                                                      |
| bare `trash X` (agent, script, terminal)                                                                                                    | yes, guarded           | `~/.local/bin/trash` shim runs `trash-guard` first (2026-09-29); `trash-guard-selftest`. Needs the shim stowed; until then a bare `trash` is `/usr/bin/trash`                                                                                                                                                                               |
| `/usr/bin/trash`, `command trash`, `env trash` typed by an agent                                                                            | denied                 | hook rule `trash-path` (2026-09-29), below                                                                                                                                                                                                                                                                                                  |
| a PATH change before a bare `trash` (`PATH=... trash`, `export`/`unset PATH`, `path=()`, `hash trash=`, `sudo -i trash`), typed by an agent | denied                 | `trash-path`, mirroring `rm-lookup` (W-20260929-A158). Before it, the incident's own shape `PATH=/usr/bin trash ''` passed                                                                                                                                                                                                                  |
| a `trash` or `rm` by path in any `.local/bin` but this account's `~/.local/bin`, or after `HOME=` / `export HOME` / `unset HOME`            | denied                 | `trash-path` / `rm-path` (W-20260929-A171). `~`, `$HOME`, `${HOME}` and the home written out stay allowed; a `HOME=x` PREFIX is left alone (the `~` there is still the old home)                                                                                                                                                            |
| `/usr/bin/trash X` in Gavin's own terminal                                                                                                  | **no, by design**      | the human's deliberate route around the shim                                                                                                                                                                                                                                                                                                |
| bare `trash` in a zsh opened BEFORE the shim was stowed                                                                                     | **no**, until `rehash` | zsh remembers where it first found `trash` (measured 2026-09-29: the old one ran until `rehash`). `install.sh` says so after it stows; `rm-reach-check` cannot see another shell's memory (W-20260929-A184). Agent Bash calls start a fresh shell each time                                                                                 |
| `/usr/bin/trash X` inside a script, cron, launchd, brew internals                                                                           | **no**                 | an absolute path, or a PATH without `~/.local/bin`; the hook sees only an agent's typed command                                                                                                                                                                                                                                             |
| Claude Code's `ExitWorktree` remove (not Bash: the delete guard never sees it)                                                              | discard denied         | measured 2026-10-05: remove deletes the worktree and its branch outright, nothing in `~/.Trash`; it refuses unsaved work unless `discard_changes: true`, which `enforce-no-worktree-discard.sh` denies (W-20261005-A42). A clean remove still runs (it loses nothing); subagent worktree auto-cleanup is not a tool call and is not covered |

## The PATH shim

[`home/.local/bin/rm`](../home/.local/bin/rm) is the piece that reaches scripts. `~/.local/bin`
is `$path[1]`, ahead of `/usr/bin` and `/bin`, so a bare `rm` resolves there first. It does three
things and then hands off to `safe-rm`:

1. Ignores `SAFE_RM_OFF` (it used to exec `/bin/rm`; Gavin removed that on 2026-09-29,
   W-20260929-A164) and prints one line saying the delete still goes to the Trash.
2. **Preserves rm's own directory rule.** Real `rm dir` refuses without `-r`; `trash` has no such
   rule and takes a directory happily. Without this check the shim would quietly REMOVE a safety
   net while claiming to add one, so a typo'd `rm build` would take the tree. Long options are
   matched exactly, so `--preserve-root` is not mistaken for recursive because it contains an `r`.
3. Refuses, rather than deleting, when `safe-rm` is not on PATH.

Everything else is delegated deliberately. `safe-rm` already skips targets that do not exist
(`trash` itself exits 5 on a missing path, which would break every `rm -f *.aux` in every
Makefile), strips `--` (which `trash` mistakes for a filename), and ignores rm-style flags.

### The shim is a stow link, so it vanishes with the links (2026-10-05)

`~/.local/bin/rm`, `safe-rm` and `trash-guard` are stow links into this repo, like everything
else in `~/.local/bin`. On 2026-10-05 a failed restow removed every link for 6.5 minutes. In that
window, a script's or a fresh terminal's `rm` fell through to `/bin/rm`, a PERMANENT delete. That
included the terminal Gavin used to repair it (measured by the outage investigation; record in
the drawer `WORK/outage-2026-10-05/`).

What now covers that window:

- the restow is all-or-nothing: `install.sh` refuses a conflict with nothing removed, and puts
  back any link it removed if stow then fails (W-20261005-A48 and its follow-ups);
- a new terminal says so: the `~/.zshenv` warning block prints "plain rm is the PERMANENT
  /bin/rm here" when the links are gone;
- one command puts them back from any terminal, with no hooks and no `rm`:
  `sh ~/.local/state/dotfiles/links/restore` (it moves blocking files aside and deletes nothing);
- `dotlinks-watch` notices a missing link within seconds.

Moving the shims out of the stowed set, as a tested, copy-installed release, is phase 2 of the
outage plan (W-20261005-A72, Gavin's decision).

### The cost, accepted knowingly

`safe-rm`'s header says not to route a script's own `mktemp` scratch to the Trash, because a
Trash full of machine noise is one nobody reads. **A PATH shim cannot tell scratch from user
data.** Installing it therefore overrides that scope decision in exchange for total coverage.
Measured before the choice was made: `install.sh` trashes its own temp dirs in 7 places (1564,
1575, 1625, 1632, 1651, 1659, 2025); node/pnpm/bun lifecycle scripts get the full user PATH, so
every `"prebuild": "rm -rf dist"` lands in the Trash; `git-filter-branch`, `git-subtree` and
`git-mergetool` all use shell `rm` on temp checkouts.

Consequences to live with:

- **Empty the Trash regularly.** Space is not reclaimed until you do.
- Repeated `dist`/`build`/`coverage` deletes become `dist 2`, `dist 3`, … in the Trash.
- There is no switch to turn the Trash off for a build (`SAFE_RM_OFF` was removed 2026-09-29).

### Environment variables

| Variable            | Effect                                                                |
| ------------------- | --------------------------------------------------------------------- |
| `SAFE_RM_OFF`       | REMOVED 2026-09-29 (W-20260929-A164). Ignored, with one warning line. |
| `SAFE_RM_VERBOSE=1` | Print each trashed path (drops `safe-rm -q`).                         |

## Catastrophic targets are refused outright

Stock macOS refuses `rm -rf /` in some shells but happily accepts **`rm -rf ~`**, and `/bin/rm`
has no objection at all. On a nearly-full disk that is worse than it sounds: the move cannot
complete, leaving a half-moved home directory and no free space.

`safe-rm` refuses these before the trash tool is invoked at all (verified with a stub `trash`
that logs instead of deleting: it was never called):

| Class                 | Members                                                                                                                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Your home             | `$HOME`, plus anything resolving to it                                                                                                                                                      |
| Its top-level folders | `Library` `Documents` `Desktop` `Downloads` `Pictures` `Movies` `Music` `Public` `.ssh` `.gnupg`                                                                                            |
| Anyone's home         | `/Users/*`, `/home/*`                                                                                                                                                                       |
| System directories    | `/` `/Applications` `/Library` `/System` `/Users` `/Volumes` `/bin` `/cores` `/dev` `/etc` `/home` `/media` `/mnt` `/Network` `/opt` `/private` `/root` `/sbin` `/srv` `/tmp` `/usr` `/var` |
| Whole mounted volumes | `/Volumes/*`, `/media/*`, `/mnt/*`                                                                                                                                                          |
| `.` and `..`          | `.` `./` `..` `../` `sub/..` `.//`                                                                                                                                                          |

**Containers, not contents** — with four named exceptions. For everything in the table above,
the directory itself is refused while `dir/*` is not, because each child is a separate target.
A guard that blocks ordinary work gets routed around, and a routed-around guard protects
nothing. There is no override (`SAFE_RM_OFF=1` was one until 2026-09-29, when Gavin removed it);
a person who means it trashes the folder in Finder.

### The sweep guard

`~/Downloads`, `~/Desktop`, `~/Documents` and `~/CODE` are additionally protected against being
emptied: `rm -rf ~/Downloads/*` is refused, not just `rm -rf ~/Downloads`. Same loss, different
route.

**The glob never reaches this script.** The shell expands `~/Downloads/*` before `safe-rm` is
executed, so what arrives is a plain list of children with no `*` anywhere. The sweep is
therefore recognised from its _shape_: **two or more direct children of a guarded folder named
in one call**. A side effect worth having — `rm -rf ~/CODE/one ~/CODE/two` typed by hand is
caught too, which pattern-matching the glob would have missed.

Two is the threshold because one is how you delete something deliberately.
`rm ~/Downloads/installer.dmg` and `rm -rf ~/CODE/oldproject` are untouched. Deleting several
one at a time still works; what is removed is the single stroke.

Parents are compared as literal strings, not resolved per operand — this runs on every call,
including `rm -rf node_modules` with tens of thousands of operands, and a fork per operand is
not affordable. **Both spellings of `$HOME` are therefore on the list** (the raw value and the
`pwd -P` resolution). That is a bug fix, not caution: with a home under `$TMPDIR`, `$HOME` is
`/var/folders/…` while the resolved form is `/private/var/folders/…` because `/var` is a
symlink, and every sweep slipped through until both were compared. Same class of mistake as the
`/etc` one above, found the same way — by testing rather than by reasoning.

Two implementation details, each of which cost a bug:

1. **Two paths are classified, not one.** `rp` is the fully resolved directory, which catches a
   relative path landing on `$HOME` and a directory symlink followed with a trailing slash.
   `ap` is the literal target made absolute _without_ resolving symlinks — needed because on
   macOS `/etc`, `/var` and `/tmp` **are symlinks**. An earlier version skipped the guard
   entirely for symlinks, on the reasoning that removing a link is harmless. True for a link you
   made; catastrophically false for `/etc`. Caught by this repo's own selftest, which saw the
   stub trash being called while the summary claimed nothing had been refused.
2. **A symlink you created is still removable.** Its own absolute path is not on the list and it
   is not resolved, so `rm mylink` still just removes the link.

### The escape hatch is for a human only

`CLAUDE.md` makes it **binding** that no agent, subagent, script or hook invokes the real
deleter in any form — `/bin/rm`, `/bin/rm -P`, `/usr/bin/rm`, `unlink`,
`find … -delete`, `truncate -s0`, `> file`, `shred`, `git worktree remove`. All of them destroy
data outside the Trash, and `-P` overwrites the bytes first so that no Trash, snapshot or backup
can recover it. An agent that believes it needs a permanent delete must stop and ask; that call
belongs to the operator. Since 2026-09-23 the agent guard below enforces this at the Bash tool.

## The trash guard

Added 2026-09-29. That evening (19:25, 19:31, 19:37) the engage repo went to the Trash three
times: a cleanup ran `trash ''` with an empty variable, and **macOS `/usr/bin/trash ''` trashes
the current folder**. Gavin recovered it each time with Put Back. The rm route already had
`safe-rm`; a bare `trash` had nothing in front of it. Incident:
`CaptainCodeAU-isolinear/workbench/records-system/2026-09-28/INCIDENT-20260929-engage-repo-trashed.md`;
lesson: `~/.claude/pj-global/notes/20260929-cleanup-on-an-empty-path-trashes-the-folder.md`;
brief with Gavin's rulings: [`docs/trash-guard/BRIEF.md`](trash-guard/BRIEF.md).

One file holds the rules, [`home/.local/bin/trash-guard`](../home/.local/bin/trash-guard)
(POSIX sh), and both routes ask it before anything moves, so `trash X` and `rm -r X` get the
same verdict (the selftest compares them on every case). The one ruled exception is a blank
argument, below.

```
bare trash X        ~/.local/bin/trash (shim)       ->  trash-guard --check  ->  real trash (--real-trash)
rm X, any route     zsh rm() / rm shim -> safe-rm   ->  trash-guard --check  ->  real trash (--real-trash)
```

Every target is RESOLVED first (trailing slashes, `./`, `..`, relative paths, symlinks on the
way) and the resolved path is judged. One refusal refuses the whole call; nothing is trashed.
The refusal names the argument, the resolved path and the rule id.

| Rule id             | Refused                                                                            | Where                     |
| ------------------- | ---------------------------------------------------------------------------------- | ------------------------- |
| `blank`             | an empty or whitespace-only argument                                               | the `trash` route only    |
| `cwd`               | `.`, or the current folder by any spelling                                         | everywhere, temp included |
| `contains-cwd`      | a folder that contains the current folder (`..`, a parent by path)                 | everywhere, temp included |
| `floor`             | `/`, `~`, `~/CODE`, `~/CODE/CaptainCodeAU` (one constant, `FLOOR_TAILS`)           | everywhere, temp included |
| `repo-root`         | a folder holding `.git` (a directory or a file)                                    | outside the temp folders  |
| `nested-repo`       | a folder with a git repo anywhere inside it (`~/CODE/Scaffoldings` is the example) | outside the temp folders  |
| `search-timeout`    | the nested-repo search did not finish within 2 s. A timeout is never an allow      | outside the temp folders  |
| `search-unreadable` | the search could not read everything inside. Unread is not absent                  | outside the temp folders  |
| `unresolvable`      | a folder on the path cannot be entered, so the target cannot be judged             | everywhere                |

**"By any spelling" means file identity, not text** (W-20260929-A182). This Mac's disk ignores
case and Unicode form, `pwd -P` keeps the spelling as typed, and `/System/Volumes/Data/...` is a
firmlink to the same folder. Before 2026-09-29 these rules compared strings, so `trash ../SUB`
from inside `.../sub`, `../../PLAIN` above it and an NFD `café` all went through (measured with a
logging stand-in). `cwd`, `contains-cwd` and `floor` now also compare with `-ef` (same device
and inode) on folder targets. A symlink target is still judged as the link itself, so deleting
a link that points at the current folder stays allowed (a control arm).

**A blank argument differs by route** (Gavin, 2026-09-29, on the first report). `trash ''` is
refused, because `/usr/bin/trash ''` moves the current folder. On the rm route (`safe-rm`, so
the rm shim and the zsh `rm()` too) a blank is skipped as it was before the guard: nothing is
trashed, the call exits 0 when nothing else is left, and other targets in the same call go ahead.
It is not silent: exactly one line per call on stderr, however many blanks,
`safe-rm: ignored a blank argument (empty variable?)`. `rm -f "$EMPTY"` in a script keeps
working and still leaves a trace. The rest of rule 1 is refused on both routes.

**Allowed although it holds a `.git` file:** a linked worktree at `<repo>/.worktree/<name>`, or at
`<repo>/.claude/worktrees/<name>` where Claude Code's `EnterWorktree` puts its own (W-20261005-A49),
whose `.git` file points into `<repo>/.git/worktrees/`. That keeps the removal route the agent guards
name for `git worktree remove` and for an `ExitWorktree` discard (`rm -r <dir>`, then
`git worktree prune`). A look-alike parent (`other/worktrees/<name>`) is refused. A worktree holding a
nested repo is still refused, and so is a `.worktree/<name>` whose `.git` points anywhere else.

**Temp folders** (rule 2 only): `$TMPDIR`, `/tmp` (`/private/tmp`) and
`getconf DARWIN_USER_TEMP_DIR`, each resolved. Only a path strictly INSIDE one is exempt, never
the root itself. `$TMPDIR` counts only when it resolves under `/private/tmp`, `/tmp` or
`/private/var/folders/`, so `TMPDIR=$HOME` exempts nothing.

**Files** are judged by rule 1 alone (a file cannot be a floor or hold the current folder).

**A symlink named WITHOUT a trailing slash is the link itself**, and trashing it moves the link,
not its target: `safe-rm-selftest` section 9 trashes a link to a fake home with the real trash and
the home survives. So `rm link-to-repo` is allowed and `rm link-to-repo/` is refused as the repo.

**The search** is one `find <every folder target> -mindepth 2 -name .git -print -quit` per call
(depth 1 was judged already), under a 2 s watchdog that kills it. Measured 2026-09-29: 20,000
folders in about 0.8 s; a real `node_modules` of 1,081 folders in 112 ms; `~/.nvm` refused as a
repo root in 24 ms. The Claude sandbox's `.ssh` read deny does not trip `search-unreadable`:
listing `home/.ssh` is allowed, only file contents are denied (find exit 0).

**The real trash** is `trash-guard --real-trash`. **On macOS it is exactly `/usr/bin/trash`,
never a PATH search** (W-20260929-A169, 2026-09-29, after both Macs were measured: A on 26.6.2, B
on 15.7.4; macOS 15 and later ship it). The search it replaced took the first unmarked `trash` on
PATH, so a link to `/bin/rm`, or a wrapper that calls `trash` again (a loop, measured at 15,686
hops), placed ahead of `/usr/bin` was run by both routes. The OS is read with `uname` by absolute
path, because a PATH without `uname` switched the pin off (caught while building it). Missing
`/usr/bin/trash`: every `trash` and `rm` refuses, loudly. `safe-rm` uses the same answer, so the
guard runs once per call, and on macOS it has no second answer: its `trash-put` PATH fallback is
off there, because a planted `trash-put` was run whenever `--real-trash` failed (measured
2026-09-29 with a logging stand-in). **On Linux** it is still the first `trash` on PATH that is
not a copy of the shim (the shim carries a marker string; any file holding it is skipped), and
`safe-rm` keeps the `trash-put` fallback, until the Linux rule is settled (W-20260929-A157).

**Test seams** (every one can only make the guard more careful, or is fenced to a temp folder,
because an agent can set an environment variable as easily as a test can):

| Variable                        | Effect                                                                                                                                                                                                                                                                             |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TRASH_GUARD_REAL_TRASH`        | REMOVED 2026-09-29 (W-20260929-A185, Gavin's ruling): its folder-only fence let a temp link to `/bin/rm` through, and both routes ran it. Set at all, it now makes `--real-trash` REFUSE. Tests set the real trash by editing the `#P: real-trash` line in a COPY of `trash-guard` |
| `TRASH_GUARD_TEMP_ROOTS`        | replaces the temp list; an entry is kept only when it is inside a real temp root                                                                                                                                                                                                   |
| `TRASH_GUARD_TIMEOUT`           | search timeout; can only LOWER the 2 s                                                                                                                                                                                                                                             |
| `TRASH_GUARD_TEST_SEARCH_DELAY` | sleep before the search (a fake slow search); can only cause a timeout                                                                                                                                                                                                             |
| `HOME`                          | the floor list's home; the account's home from the user database stays on the list anyway                                                                                                                                                                                          |

`trash-guard --show-config` prints the floors, the temp roots in force and the real trash.

**`rm-reach-check` asks two questions about trash** (W-20260929-A168). Row 3a: does a bare `trash`
reach the shim beside the tool (so trash-guard runs first), or does something sit ahead of it on
PATH? Row 3b: what will `safe-rm` actually run, asked of `trash-guard --real-trash` exactly as
`safe-rm` asks it? Before 2026-09-29 one row asked "is `command -v trash` Apple's?", which the
shim made false on every run, and its advice told Gavin to remove the shim. The tool now never
advises removing a file that resolves inside this repo; it says the finding is its own bug. A zsh
that hashed `trash` before the shim was stowed is invisible to it (W-20260929-A184).

**Evidence, batch one** (2026-09-29, branch `trash-batch1`): trash-guard-selftest 178/0 (master's
code with the new arms: 6 failed, 40 controls passed); `--mutants` 9 caught, 0 missed, including
`noseam` and `mac-no-trash-put`. rm-reach-check --selftest 17/0 (master with only the new
selftest grafted in: 7 failed). safe-rm-selftest 52/0 unsandboxed, with no `/bin/rm` left in it
(W-20260929-A160); its `SAFE_RM_OFF=1` arm now runs only from a terminal and says NOT RUN from an
agent, because it is a permanent delete.

**Evidence** (2026-09-29, branch `trash-guard`):
[`trash-guard-selftest`](../home/.local/bin/trash-guard-selftest) 174 passed, 0 failed (134 new
arms, 40 controls; after the blank ruling). Against master's code: controls 40 passed, new arms
130 failed and 1 passed (the rm route's `-- -name`, which safe-rm already handled). `--mutants`:
removing the blank check, the cwd check, the timeout refusal, the temp exemption, safe-rm's
blank skip, safe-rm's blank warning, or the hook's `env trash` line is each caught (7 of 7). `--e2e` with the real `/usr/bin/trash`: the incident shape (`trash ''` from inside a temp
folder) is refused with the folder intact, and a throwaway temp file goes to the Trash.

**Timing arms calibrate themselves** (W-20260929-A188, W-20261002-A04; Gavin's ruling,
2026-10-02). Fixed limits failed on load alone: `trash-guard-selftest` at load 60-97 (2966 ms
against 2900), and the hook's selftest under 60 CPU burners (48 arms, the 1 s shift arms
included). In both suites every timed arm now first times 3 TRIVIAL calls through the same
route, and its limit is its budget plus **3 x their median** for a best-of-3 arm and **4 x** for a
single-shot hook arm, printed on the arm's line with the samples. The budget is only what the
trivial call does not do: a cut or deadline on the wall clock (2 s, 0.5 s, the hook's 1-3 s)
plus 200 ms for the watchdog, or the 5 KB parse. Rules that keep the arms honest:

- A fake slow search or stall is set PAST the computed limit, so a guard that waits for it fails
  at any load. The cut's value is read without a clock: `trash-guard --show-config`, and the
  hook's deny text ("no verdict within 3 s"), which also proves the 3 s is under the harness's 5.
- Lateness is its own arm. A right answer given late fails its timing arm only, and the trash
  suite's route comparison counts verdicts; a timeout refusal and an allow on the 20,000-folder
  tree are both right, so they compare as one.
- An overhead above 5 s is an **INVALID TRIAL**: the run says so and exits **3**, never 0. Both
  `--mutants` modes count exit 3 (and the hook's alarm-ended exit 142) as not caught.
- Calibration would hide a guard that got slower to START, so start-up arms hold a trivial call
  to 40 bare `/bin/sh` (or `/bin/bash`) starts timed in the same breath. `--mutants` forces the
  overhead to 99999 ms (must be exit 3) and 4000 ms (must fail a start-up arm), and the trash
  suite adds `late`: a one-line fault whose refusal is right but waits for the whole search.

Why 3 and 4 (measured 2026-10-02, 10 cores, load 6 to 103): in the trash suite the non-search
part of a timed call ran up to 1.44 x the median trivial call, and one call up to 1.45 x its own
median (1.44 x 1.45 = 2.1); the hook's best-of-3 5 KB arms needed about 1.9 x. A single-shot hook
arm (shift, deadline, crash) carries one more spike: it needed up to 3.12 x at load 99 (1977 ms
against a 3 x limit of 1907), so those take 4, which still sits under the old fixed 1 s at idle.
The median, not the best: the first call of a run measured 1046 ms against 30 after it.

**What it does not cover:**

- `/usr/bin/trash` typed in Gavin's own terminal: by design, the human's route around the shim.
- `/usr/bin/trash` inside a script, and any caller whose PATH lacks `~/.local/bin` (cron,
  launchd, Homebrew internals). The hook sees only an agent's typed command.
- A bare `trash` after a PATH change in the same agent command (`PATH=/usr/bin trash x`,
  `export PATH=...; trash x`): not denied. The rm equivalent is (`rm-lookup`); trash has no
  such rule yet.
- `sudo trash`: not measured.
- Finder "Move to Trash", AppleScript Finder deletes, Python `send2trash`: they never touch
  either route.
- Linux: the guard and shim are POSIX sh but measured on macOS only (mlbox is filed separately).

## sudo rm

`sudo` execs the real `/bin/rm`, so the `rm()` shell function never sees it. The `sudo()`
wrapper in `home/.zshrc` therefore intercepts `rm` and `rmdir` and re-runs the deletion as the
**invoking user** via `safe-rm`.

Running it as you rather than as root is deliberate. Moving a file requires write permission on
its PARENT DIRECTORY, not on the file itself, so an unprivileged trash usually succeeds even on
root-owned targets — and it lands in `~/.Trash`, where Finder's "Put Back" works. `sudo safe-rm`
would instead trash into `/var/root/.Trash`, which is mode 0750 `root:wheel` and invisible to
you. That looks safe and recovers badly.

If the unprivileged attempt genuinely fails, the wrapper returns 1 and prints the explicit
override rather than escalating on your behalf.

The command is located by scanning past sudo's own options, not by reading `$1`. A naive
`[[ "$1" == rm ]]` check is defeated by `sudo -u root rm -rf x` — the same bug class the
`pnpm link --global` guard had to fix.

### Deliberately not caught

| Invocation              | Why not                                                                                |
| ----------------------- | -------------------------------------------------------------------------------------- |
| `sudo /bin/rm ...`      | absolute path; the documented escape hatch                                             |
| `sudo sh -c 'rm -rf x'` | the `rm` is inside a string argument; no wrapper can see it                            |
| `sudo -u other rm x`    | the trash runs as YOU, not as `other`; intent (no permanent delete) is still preserved |

## `/bin/rm` cannot be intercepted, and cannot be locked down

This was asked directly, so it is recorded with evidence rather than left as folklore.

```
$ ls -lO /bin/rm
-rwxr-xr-x  2 root  wheel  restricted,compressed  ...  /bin/rm
$ csrutil status
System Integrity Protection status: enabled.

$ chmod a-x /bin/rm                      -> Operation not permitted
$ chflags uchg /bin/rm                   -> Operation not permitted
$ chmod +a "<user> deny execute" /bin/rm -> Operation not permitted
```

The `restricted` flag is the SIP marker: the file is protected from modification even by root,
so `sudo chmod` fails too. `/bin` is not writable and cannot be shadowed, because an absolute
path does not consult `PATH`.

Measured directly:

```
$ PATH="$shimdir:$PATH" ./script.bash      # script calls: /bin/rm -P file
rm: file: No such file or directory        # went to the REAL binary, shim bypassed
```

Even if SIP allowed it, disabling `/bin/rm` system-wide would break macOS installers, Homebrew
and system scripts that call it by full path.

### What works instead: immunity, not interception

`chflags uchg` defeats every form of `/bin/rm`, including the secure-overwrite one:

```
chflags uchg file.txt
/bin/rm -P  file.txt   -> Operation not permitted, exit 1
/bin/rm -Pf file.txt   -> Operation not permitted, exit 1
/bin/rm -rf parentdir/ -> Operation not permitted, exit 1   (file survives)
```

**Trade-off, measured:** a `uchg` file cannot be trashed either — `/usr/bin/trash` exits 5 with
`afpAccessDenied`. So a protected file is _frozen_, not merely undeletable. It must be
unprotected before it can be removed by any means. That makes `uchg` suitable for archives and
records you never edit, and unsuitable for anything in active use.

## What the rm wrappers do NOT protect against

None of the following involves `rm`, and no `rm` wrapper can see any of it:

- `git worktree remove`: unlinks a whole checkout. The trigger for the guard below: on
  2026-09-23 an agent was one step from running it.
- `herdr worktree remove`: the same, through herdr's own worktree helper (it deletes
  the checkout folder too). Denied since 2026-10-07 (W-20261007-A20).
- Shell truncation: `> file`, `: > file`, `truncate -s0`
- `find -delete`, `unlink`, `mv` over an existing file, `install`, `rsync --delete`
- `git clean -fdx`, `git checkout` / `git restore` discarding changes, `git reset --hard`,
  `git branch -D`, `git stash drop` / `clear`
- `docker system prune`, `brew cleanup`, `pnpm store prune`
- Language-level deletes: Python `os.remove`, Node `fs.unlinkSync`
- Finder Shift-Delete, or emptying the Trash
- Disk failure

A recoverable-delete wrapper is one door. It is not a backup, and it must not be mistaken for
one.

## The agent guard: `enforce-no-permanent-delete.sh`

Ruled by Gavin 2026-09-23 (option A). A PreToolUse hook on the Bash tool
([`home/.claude/hooks/enforce-no-permanent-delete.sh`](../home/.claude/hooks/enforce-no-permanent-delete.sh)),
registered for BOTH targets (user and project) in `settings/claude/hooks.json`. It **denies**
an agent's Bash call that would destroy data outside the Trash, and the denial names the safe
route. It covers agents only: a human's terminal never passes through it.

It does not grep the command text. A small lexer splits the command into simple commands the way
zsh does (the Bash tool runs zsh), so the rules look at the command word of each one. That is
why a banned phrase inside a commit message, an `echo`, an `rg` pattern or a heredoc is allowed,
while the same phrase as a command is denied wherever it sits: after `&&`, `||`, `;`, `|`, `&!`,
inside `( )`, `{ }`, `$( )`, backticks, `<( )`, `=( )`, behind `VAR=1`, `sudo`, `command`,
`env`, `nohup`, `time`, `nice`, `timeout`, `xargs`, `noglob`, `nocorrect`, `exec`, `repeat N`,
`uv run`, `git -C/-c/--git-dir`, inside `sh -c`, `eval`, `env -S`, `find -exec`, `fd -x`,
`git submodule foreach`, and in a heredoc fed to a shell or an interpreter.

### Coverage

| Shape                                                                                                                                                                                                                                                                                                                                                                                                                     | Guard      | Safe route in the denial                                                                                |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------- |
| `git worktree remove`                                                                                                                                                                                                                                                                                                                                                                                                     | **denied** | `rm -r <dir>` (Trash), then `git worktree prune`                                                        |
| `herdr worktree remove` (any flags, after `--session`/`--machine`/`--remote`; `--help` passes). Not seen: the same request sent raw to herdr's socket                                                                                                                                                                                                                                                                     | **denied** | commit, `rm -r <repo>/.worktree/<branch>` (Trash), then `git -C <repo> worktree prune` (W-20261007-A20) |
| `git clean` without `-n` / `--dry-run`                                                                                                                                                                                                                                                                                                                                                                                    | **denied** | `git clean -n` to list, then bare `rm`                                                                  |
| `git reset --hard` (any ref)                                                                                                                                                                                                                                                                                                                                                                                              | **denied** | `git stash push -u`, or ask Gavin                                                                       |
| `git checkout -- <p>`, `.`, a glob, `<ref> <path>`, a path on disk, `-f`                                                                                                                                                                                                                                                                                                                                                  | **denied** | `git stash push -u`; `git switch` for branches                                                          |
| `git restore` without `--staged`, or with `--worktree`                                                                                                                                                                                                                                                                                                                                                                    | **denied** | `git stash push -u`, or ask Gavin                                                                       |
| `git switch -f` / `--discard-changes`                                                                                                                                                                                                                                                                                                                                                                                     | **denied** | `git stash push -u` first                                                                               |
| `git branch -D`, `--delete --force`, `-M`, `-C`                                                                                                                                                                                                                                                                                                                                                                           | **denied** | `git branch -d`                                                                                         |
| `git stash drop` / `clear`                                                                                                                                                                                                                                                                                                                                                                                                | **denied** | ask Gavin                                                                                               |
| `git reflog expire/delete`, `git gc --prune=now/all`, `git prune`                                                                                                                                                                                                                                                                                                                                                         | **denied** | ask Gavin (they destroy the recovery trail)                                                             |
| `/bin/rm`, `/usr/bin/rm`, any path to rm, `grm`                                                                                                                                                                                                                                                                                                                                                                           | **denied** | bare `rm`                                                                                               |
| `trash-path` (2026-09-29): `/usr/bin/trash` or any path to trash except `*/.local/bin/trash`, `command trash`, `env trash` (also inside `sh -c`, `eval`, `$( )`, `xargs`, `find -exec`). They skip the trash guard, which only the PATH shim runs. Allowed: bare `trash`, `trash -v x`, `~/.local/bin/trash x`, `command -v trash`                                                                                        | **denied** | plain `trash`, which goes through the guard                                                             |
| a bare `rm` whose lookup the same command changed (`rm-lookup`, W-20260925-A25): any `env` (`env rm`, `env -i`, `env -u PATH`, `env PATH=`), a `PATH=`/`path=`/`PATH+=` prefix, `command -p`, `sudo -i`/`--login`, an earlier `unset PATH`, `export`/`typeset PATH=` or bare `PATH=` statement, `hash rm=`. Measured 2026-09-25: `env -i` still finds `/bin` tools with PATH wiped, and `command -pv rm` prints `/bin/rm` | **denied** | bare `rm`, with PATH left alone                                                                         |
| `rm -P` (any cluster), `SAFE_RM_OFF=...` (prefix, `env`, `export`)                                                                                                                                                                                                                                                                                                                                                        | **denied** | bare `rm`, or ask Gavin                                                                                 |
| `unlink`, `shred`, `srm`, `wipe`, `truncate`, `dd of=` (not `/dev/null`)                                                                                                                                                                                                                                                                                                                                                  | **denied** | bare `rm`, or move aside first                                                                          |
| `> f`, `2> f`, `>! f`, `: > f`, `true >\| f`, `cat /dev/null > f`, `cp /dev/null f`                                                                                                                                                                                                                                                                                                                                       | **denied** | move the file aside first                                                                               |
| `find -delete`; `find -exec` / `fd -x` with any denied command                                                                                                                                                                                                                                                                                                                                                            | **denied** | `find -print`, then `-exec rm {} +`                                                                     |
| `find -exec rm` (also `-execdir`, `-ok`, `-okdir`; `rmdir`, `trash`, `safe-rm`, `sh -c 'rm ...'`) with no test before it in its AND-chain: first, after `-o`, or after a group true for every file (`find-exec-untested`, W-20261001-A72); or with `-depth`/`-d` and `-prune` in one `find` (`find-depth-prune`). Not tests: `-maxdepth`, leading `-E -x -L`, `-print`, `-prune`, `-true`, an earlier `-exec`             | **denied** | a test such as `-name` first, `-print` dry run; no `-depth`                                             |
| `rsync --delete*`, `--del`, `--remove-source-files`                                                                                                                                                                                                                                                                                                                                                                       | **denied** | rsync without them, then bare `rm`                                                                      |
| inline code: `python -c`, `node -e`, `perl -e`, `ruby -e`, `deno eval`, `osascript -e`, and code on stdin (`python3 - <<EOF`, `python3 - ARG <<EOF` since 2026-09-28, `echo ... \| python3`) calling `os.remove`, `shutil.rmtree`, `Path.unlink`, `rmdir`, `fs.rm*`, `unlink*`, `/bin/rm`, `FileUtils.rm*`                                                                                                                | **denied** | bare `rm` in the shell                                                                                  |
| `docker`/`podman` `... prune`, `volume rm`, `compose down -v`; `brew cleanup`, `--zap`; `pnpm store prune`; `uv cache clean/prune`; `bun pm cache rm`; `rimraf`                                                                                                                                                                                                                                                           | **denied** | ask Gavin (`rimraf`: bare `rm -r`)                                                                      |
| `diskutil erase*`/`partitionDisk`/..., `mkfs*`, `newfs*`, `wipefs`, `tmutil delete*`, `trash-empty`, Finder "empty trash"                                                                                                                                                                                                                                                                                                 | **denied** | ask Gavin                                                                                               |
| an alias from the shell snapshot whose expansion is any of the above                                                                                                                                                                                                                                                                                                                                                      | **denied** | (as the expansion)                                                                                      |
| a wrapper's value flag given LAST with no value (`time -o`, `nice -n`, `exec -a`, `xargs -n`, `sudo -u`, `env -S`, `git -C`, `perl -e`, `uv run --with`, ...), then a denied command (`time -o; unlink f`)                                                                                                                                                                                                                | **denied** | (as the later command)                                                                                  |
| the guard itself gives no verdict within 3 s (`guard-timeout`), or its child exits without one (`guard-no-verdict`); the denial says it is NOT a match                                                                                                                                                                                                                                                                    | **denied** | split the command, or ask Gavin                                                                         |
| bare `rm`, `command rm`, `\rm`, `rm *(.)`, `find . -name x -exec rm {} +`, `find . -path ./keep -prune -o -name x -exec rm {} +`, `git clean -n`, `git branch -d`, `git restore --staged`, `cmd > out`                                                                                                                                                                                                                    | allowed    |                                                                                                         |
| a script or Makefile target that deletes internally, a compiled program                                                                                                                                                                                                                                                                                                                                                   | invisible  | the rm shim still covers a bare `rm` inside it                                                          |
| a command name in a variable (`$RM x`, zsh `$=x`), git aliases, `ssh host 'rm ...'`                                                                                                                                                                                                                                                                                                                                       | invisible  |                                                                                                         |
| `mv` / `cp` over an existing file, `sed -i`, `open(f, 'w')`                                                                                                                                                                                                                                                                                                                                                               | invisible  | cp/mv wrappers: prompt at a terminal, decline for agents (below)                                        |
| code piped from a file (`cat x.py \| python3`), heredoc `$( )` expansions                                                                                                                                                                                                                                                                                                                                                 | invisible  |                                                                                                         |
| snapshot FUNCTIONS (their bodies are not expanded; a wrapper body may name `/bin/rm`)                                                                                                                                                                                                                                                                                                                                     | invisible  |                                                                                                         |

**Aliases.** Agent shells source Claude Code's shell snapshot, and its aliases expand (measured
2026-09-23: 311 aliases, `ll` ran `eza`). A hook sees the text before expansion, so the guard reads
the newest `~/.claude/shell-snapshots/snapshot-*.sh` on every call and classifies an alias's
expansion as zsh would, recursively. On 2026-09-23 **19 of the 311** expanded to a denied shape:
`dcleanbuild dcleanup dcprune dipru dnprune dsprune dvprune gbD gbgD gclean gpristine grhh groh grs
grss gstc gstd gwipe gwtrm`. They are denied by their expansion, not by name, so a new alias is
covered the moment it reaches the snapshot. Three oh-my-zsh aliases that hide a `git reset --hard` (`grhh`, `gwipe`,
`gpristine`) are ALSO denied by name (Gavin, 2026-09-23), so they stay denied if a hook cannot read
the snapshot.

**A stall is a deny, not an allow.** The hook is registered with `"timeout": 5` and `|| true`, so
once it runs past 5 s the harness lets the command through. Until 2026-09-23 a value flag given
last (`time -o`, `nice -n`, or any flag at the 20 unguarded shift sites) spun the option loops forever, and `time -o; unlink f`
ran unchecked (W-20260923-A54). Two fixes: every multi-word `shift` is guarded, and the verdict is
computed in a child the hook waits on for at most **3 s**. What each way of going quiet does now:

| What goes wrong                                                              | Result                                                                                                                                       | Evidence                                             |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| the classifier runs past 3 s                                                 | **denied** (`guard-timeout`)                                                                                                                 | selftest DEADLINE arm, test seam                     |
| the classifier exits before its verdict (an `exit`, a fatal shell error)     | **denied** (`guard-no-verdict`, via an EXIT trap)                                                                                            | selftest DEADLINE arm, test seam                     |
| the classifier is killed by a signal                                         | **denied** (`guard-no-verdict`)                                                                                                              | one manual run in a scratch copy, not in selftest    |
| the classifier parses but no longer recognises anything (a gutted function)  | **denied** (`guard-broken`: a canary `/bin/rm x` must come back `rm-path` first; before 2026-09-29 this was a silent allow, W-20260929-A186) | selftest BROKEN-FILE arms, mutant on the canary line |
| a syntax error anywhere in the hook file                                     | **blocked**: bash stops parsing and exits 2, which Claude Code treats as a block (measured 2026-09-29)                                       | selftest BROKEN-FILE arm (exit 2)                    |
| the hook file loses its exec bit                                             | **allowed** (exit 126 is a non-blocking error to Claude Code; assumed from the hook docs, not measured)                                      | none: open residual in W-20260929-A186               |
| `DEL_GUARD_DEADLINE` set above 2                                             | ignored; the 3 s deadline holds                                                                                                              | selftest arm (99: denied under 4.5 s)                |
| the lexer (awk) fails                                                        | allowed, `additionalContext` warning                                                                                                         | unchanged                                            |
| `jq` missing                                                                 | **denied** if the raw text names a trigger, else a warning                                                                                   | selftest UNREADABLE arms (D-20260925-A03)            |
| malformed JSON, or `tool_input.command` under another key                    | **denied** if the raw text names a trigger, else allowed                                                                                     | selftest UNREADABLE arms                             |
| empty stdin, empty command                                                   | allowed, no decision (a crash here would block every Bash call)                                                                              | selftest HOOK arms                                   |
| a stall BEFORE the deadline starts: stdin never closing, `jq` itself hanging | allowed at the harness's 5 s timeout                                                                                                         | not covered                                          |
| a spinning `awk` child of a killed classifier                                | keeps running as an orphan (the verdict is already a deny)                                                                                   | not covered; no awk loop is known to spin            |

The test seams `DEL_GUARD_TEST_STALL=<1-9>` and `DEL_GUARD_TEST_CRASH=1` only make the child late or
dead, which the hook turns into a deny, so setting them cannot skip the guard. A hook's
environment is the harness's, not the Bash command's: `VAR=1 cmd` in a command reaches `cmd`, never
the hook.

**Every denial is logged** to `${XDG_STATE_HOME:-~/.local/state}/dotfiles/hooks-security.log` in
the sibling hooks' shape, with the command capped at 400 characters and token-shaped strings and
credential-named assignments redacted.

```sh
~/.claude/hooks/enforce-no-permanent-delete.sh --selftest   # every deny and allow arm, twice
~/.claude/hooks/enforce-no-permanent-delete.sh --mutants    # removes each rule line; each must be caught
~/.claude/hooks/enforce-no-permanent-delete.sh --classify 'git clean -fdx'
```

### `find`: order, `-depth`, and the dry run

Added 2026-10-01 (W-20261001-A72; Gavin's box: doc, measure and guard, strictest form). The guard
names `find ... -exec rm {} +` as the safe route for `find -delete`, and its bare `rm` does reach
the Trash shim (Coverage, top). It still has two traps that send a whole tree to the Trash:

1. **find evaluates left to right.** An action placed before the tests runs on every file:
   `find . -exec rm -rf {} + -name '*.tmp'` trashes everything under `.`. Right after a `-o` is
   the same: `find . -name x -o -exec rm {} +` runs on every file NOT named `x`.
2. **`-depth` switches `-prune` off.** `-delete` implies `-depth`, and with `-depth` (BSD `-d`)
   `-prune` does nothing, so `find -d . -path ./keep -prune -o -name '*.o' -exec rm {} +` reaches
   into `keep` too. Measured 2026-10-02 with `-print` on both `bfs` and `/usr/bin/find`: with
   `-depth`, `keep/a.o` was listed; without it, only the file outside `keep`.
3. **Dry run first:** the same command with `-print` in place of the action. Read it, then swap
   the action back.

Sources: the GNU findutils manual, and BSD `man find` on this Mac ("Depth-first traversal
processing is implied by this option" under `-delete`; "the -prune primary has no effect if the
-d option was specified").

The guard denies both (`find-exec-untested`, `find-depth-prune`) when an `-exec`, `-execdir`, `-ok`
or `-okdir` body reaches a deleter it otherwise allows: `rm`, `command rm`, `\rm`, `rmdir`,
`trash`, `safe-rm`, or any of them inside `sh -c`. An AND-chain starts at the front, after `-o`, `-or`
or `,`, and inside `(`. A closed group is a test only when every alternative in it has one:
`\( -name a -o -print \)` is true for every file. An earlier `-exec` is deliberately not a test,
even `-exec grep -q`. The shape that passes:

```sh
find . -name '*.tmp' -print                                  # read the list
find . -name '*.tmp' -exec rm {} +                           # same command, action swapped in
find . -path ./keep -prune -o -name '*.o' -exec rm {} +      # prune idiom, never with -depth
```

An `-exec` body is lexed with the word filter off, so `sh -c 'rmdir "$@"'` is seen too (the lexer
itself is shared with `enforce-secret-probe.sh` and was left alone). Not covered: `fd -x rm` /
`fd -X rm` with no pattern, or the pattern `.`, matches everything and stays allowed.

Which `find` runs: in an agent's Bash call, `find` is a shell function from Claude Code's snapshot
that runs its built-in `bfs` (`type -a find`, measured 2026-10-01), the same way `grep` runs
`ugrep`. Scripts, cron and Gavin's terminal get `/usr/bin/find`. The guard reads the typed text,
so it covers both; a measurement taken in an agent shell measures `bfs` unless it says
`command find`.

## Agent shells never wait on a prompt, and a failed rm stops a reset

Ruled by Gavin 2026-09-24 (W-20260924-A32, Stage 1). Research and red-team reports:
the project drawer, `WORK/agent-shell-prompts/reports/` (cp-hang: why it hangs; bak-redteam: why
automatic backups were NOT built).

**The hang.** A Claude Code Bash call gets stdin `/dev/null`, unless the call contains a `<`
redirect or a heredoc anywhere, and then stdin is a silent open socket. Any prompt then blocks
forever. `cp -i` from the `cp()` wrapper sat for 23 minutes on 2026-09-19; the transcripts hold
about 20 such background hangs and 4 foreground 600 s timeouts since 2026-05 (agent-reported).
`[[ -t 0 ]]` is false in every agent shape, so a terminal check alone cannot tell the cases apart.

**The fix, in `home/.zshrc`.** `__cannot_prompt` is true when `CLAUDECODE` or `AI_AGENT` is set,
or stdin is not a terminal. Every prompting wrapper asks it first:

| Wrapper                | At a terminal (unchanged) | Agent or no terminal                                       |
| ---------------------- | ------------------------- | ---------------------------------------------------------- |
| `cp`, `mv`             | `-i` prompt               | declined at once, each file named on stderr, exit non-zero |
| `cp -f`, `mv -f`       | overwrite                 | overwrite (the explicit choice)                            |
| `rm`, `rmdir` symlink  | confirm prompt            | nothing deleted, exit 1, names the path                    |
| `brew` managed runtime | confirm prompt            | nothing installed, exit 1                                  |

The same change fixed two older bugs: `-*f*` matched operands (`cp -- -file dst` overwrote
silently), and `cp -i` inside `| while read` ate the loop's own lines as answers.
`mv-wrapper-selftest` proves it (57 arms; master's wrapper fails 19). Live proof 2026-09-24 in a
fresh session, stdin a socket: `cp` onto an existing file returned 1 in 0 s, file unchanged.

**The reset.** `rm -rf P 2>/dev/null; mkdir -p P` is common (about 120 distinct strings). In the
sandbox the Trash is refused, so `rm` fails with exit 1 and P survives; `2>/dev/null` and `;` hide
that, and the next step merges into stale files. `rm` keeps failing loudly, with NO fallback (the
rule above stands). Instead [`enforce-no-reset-by-name.sh`](../home/.claude/hooks/enforce-no-reset-by-name.sh)
denies the shape in every project and names the safe routes: a fresh `mktemp -d` per run, or
`rm -rf P && test ! -e P && mkdir -p P`. `rm -rf P && mkdir P` is allowed, because safe-rm exits 1
when anything survives. It sees one Bash call only.

**Known limits.** `CLAUDECODE` is also set in IDE integrated terminals, so a human typing there
gets the decline too (accepted). Overwrites that never reach a wrapper (`>`, `sed -i`, Python
writes, about 15 times more common than cp/mv) are out of scope. Linux (machines C and D, zsh):
GNU `cp -i` decline wording is handled but not measured. Automatic backups: W-20260924-A37.

## Related

- [`home/.local/bin/safe-rm`](../home/.local/bin/safe-rm) — the single owner of "move to Trash"
- [`home/.claude/hooks/enforce-no-permanent-delete.sh`](../home/.claude/hooks/enforce-no-permanent-delete.sh) — the agent guard for everything that never calls `rm`
- [`SECURITY.md`](SECURITY.md) — overall posture
