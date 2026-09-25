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
```

A zsh function takes precedence over `PATH`, so an interactive `rm` uses the function (which
prints what it trashed) and a script's `rm` uses the shim (quiet, so it does not corrupt stdout
that a caller may be parsing). Verified: `zsh -ic 'type rm'` reports the function while
`/bin/sh -c 'command -v rm'` reports `~/.local/bin/rm`.

`safe-rm` fails closed. If no trash tool is installed it exits 1 and deletes nothing; it never
falls back to `rm`, because a silent downgrade from "recoverable" to "permanent" is the one
behaviour a safety command must not have.

## Coverage

Measured 2026-09-04 on macOS 25.6 (Darwin), SIP enabled. Every row was run, not inferred.

| Call path                                    | Covered?          | Evidence                                                                                                                                                                                     |
| -------------------------------------------- | ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interactive zsh, `rm -rf dir`                | yes               | trashed to `~/.Trash/rmtest-victim`; `test -e` confirmed                                                                                                                                     |
| Claude Code Bash tool                        | yes               | `type rm` -> shell function from the session's shell snapshot                                                                                                                                |
| `sudo rm` / `sudo rmdir`                     | yes               | 13-case behaviour test, below                                                                                                                                                                |
| `sudo -u root rm -rf x`                      | yes               | option scanner finds the command past sudo's own flags                                                                                                                                       |
| `#!/bin/bash` script, bare `rm`              | yes               | live: script's `rm -rf` landed in `~/.Trash/victim`                                                                                                                                          |
| `#!/bin/zsh` script, bare `rm`               | yes               | dummy-shim test hit the shim                                                                                                                                                                 |
| `xargs rm`                                   | yes               | live: `~/.Trash/xtarget.txt`                                                                                                                                                                 |
| `make clean`                                 | yes               | live: `~/.Trash/junk.o`, and a missing target did not break the rule                                                                                                                         |
| `find -exec rm`                              | yes               | same PATH lookup as `xargs`                                                                                                                                                                  |
| `command rm`, `\rm`                          | yes               | these bypass functions and aliases, not `PATH`                                                                                                                                               |
| `env -i rm`, `PATH=/bin rm`, `command -p rm` | **no**            | a PATH without `~/.local/bin` finds `/bin/rm` (measured 2026-09-25 for `env -i` and `command -p`; `PATH=/bin` is the same lookup, not run). The agent guard denies them (`rm-lookup`, below) |
| Homebrew formula post-install                | yes               | `formula.rb:1662` restores the user's PATH for that phase                                                                                                                                    |
| cron / launchd / CI                          | **no**            | minimal PATH; `~/.local/bin` absent                                                                                                                                                          |
| Homebrew internals                           | **no**            | `bin/brew:308` hardcodes `PATH=/usr/bin:/bin:/usr/sbin:/sbin`                                                                                                                                |
| Docker `RUN rm -rf`                          | **no**            | runs inside the image with its own `/bin/rm`                                                                                                                                                 |
| `/bin/rm`                                    | **no, cannot be** | absolute path never consults PATH; SIP `restricted`, see below                                                                                                                               |
| `SAFE_RM_OFF=1 rm ...`                       | **no, by design** | the deliberate "I really mean it" door                                                                                                                                                       |

## The PATH shim

[`home/.local/bin/rm`](../home/.local/bin/rm) is the piece that reaches scripts. `~/.local/bin`
is `$path[1]`, ahead of `/usr/bin` and `/bin`, so a bare `rm` resolves there first. It does three
things and then hands off to `safe-rm`:

1. Honours `SAFE_RM_OFF=1` by exec'ing `/bin/rm`, checked first so it works even if `safe-rm` is
   broken.
2. **Preserves rm's own directory rule.** Real `rm dir` refuses without `-r`; `trash` has no such
   rule and takes a directory happily. Without this check the shim would quietly REMOVE a safety
   net while claiming to add one, so a typo'd `rm build` would take the tree. Long options are
   matched exactly, so `--preserve-root` is not mistaken for recursive because it contains an `r`.
3. Refuses, rather than deleting, when `safe-rm` is not on PATH.

Everything else is delegated deliberately. `safe-rm` already skips targets that do not exist
(`trash` itself exits 5 on a missing path, which would break every `rm -f *.aux` in every
Makefile), strips `--` (which `trash` mistakes for a filename), and ignores rm-style flags.

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
- `SAFE_RM_OFF=1` before a big build if you do not want the churn.

### Environment variables

| Variable            | Effect                                                             |
| ------------------- | ------------------------------------------------------------------ |
| `SAFE_RM_OFF=1`     | Total bypass — exec `/bin/rm`. Permanent. Per command or exported. |
| `SAFE_RM_VERBOSE=1` | Print each trashed path (drops `safe-rm -q`).                      |

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
nothing. Override for a human who means it: `SAFE_RM_OFF=1` (permanent, no Trash). There is no
second knob, on purpose.

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

### The escape hatches are for humans only

`CLAUDE.md` makes it **binding** that no agent, subagent, script or hook invokes the real
deleter in any form — `/bin/rm`, `/bin/rm -P`, `/usr/bin/rm`, `SAFE_RM_OFF=1`, `unlink`,
`find … -delete`, `truncate -s0`, `> file`, `shred`, `git worktree remove`. All of them destroy
data outside the Trash, and `-P` overwrites the bytes first so that no Trash, snapshot or backup
can recover it. An agent that believes it needs a permanent delete must stop and ask; that call
belongs to the operator. Since 2026-09-23 the agent guard below enforces this at the Bash tool.

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

| Shape                                                                                                                                                                                                                                                                                                                                                                                                                     | Guard      | Safe route in the denial                                         |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------- |
| `git worktree remove`                                                                                                                                                                                                                                                                                                                                                                                                     | **denied** | `rm -r <dir>` (Trash), then `git worktree prune`                 |
| `git clean` without `-n` / `--dry-run`                                                                                                                                                                                                                                                                                                                                                                                    | **denied** | `git clean -n` to list, then bare `rm`                           |
| `git reset --hard` (any ref)                                                                                                                                                                                                                                                                                                                                                                                              | **denied** | `git stash push -u`, or ask Gavin                                |
| `git checkout -- <p>`, `.`, a glob, `<ref> <path>`, a path on disk, `-f`                                                                                                                                                                                                                                                                                                                                                  | **denied** | `git stash push -u`; `git switch` for branches                   |
| `git restore` without `--staged`, or with `--worktree`                                                                                                                                                                                                                                                                                                                                                                    | **denied** | `git stash push -u`, or ask Gavin                                |
| `git switch -f` / `--discard-changes`                                                                                                                                                                                                                                                                                                                                                                                     | **denied** | `git stash push -u` first                                        |
| `git branch -D`, `--delete --force`, `-M`, `-C`                                                                                                                                                                                                                                                                                                                                                                           | **denied** | `git branch -d`                                                  |
| `git stash drop` / `clear`                                                                                                                                                                                                                                                                                                                                                                                                | **denied** | ask Gavin                                                        |
| `git reflog expire/delete`, `git gc --prune=now/all`, `git prune`                                                                                                                                                                                                                                                                                                                                                         | **denied** | ask Gavin (they destroy the recovery trail)                      |
| `/bin/rm`, `/usr/bin/rm`, any path to rm, `grm`                                                                                                                                                                                                                                                                                                                                                                           | **denied** | bare `rm`                                                        |
| a bare `rm` whose lookup the same command changed (`rm-lookup`, W-20260925-A25): any `env` (`env rm`, `env -i`, `env -u PATH`, `env PATH=`), a `PATH=`/`path=`/`PATH+=` prefix, `command -p`, `sudo -i`/`--login`, an earlier `unset PATH`, `export`/`typeset PATH=` or bare `PATH=` statement, `hash rm=`. Measured 2026-09-25: `env -i` still finds `/bin` tools with PATH wiped, and `command -pv rm` prints `/bin/rm` | **denied** | bare `rm`, with PATH left alone                                  |
| `rm -P` (any cluster), `SAFE_RM_OFF=...` (prefix, `env`, `export`)                                                                                                                                                                                                                                                                                                                                                        | **denied** | bare `rm`, or ask Gavin                                          |
| `unlink`, `shred`, `srm`, `wipe`, `truncate`, `dd of=` (not `/dev/null`)                                                                                                                                                                                                                                                                                                                                                  | **denied** | bare `rm`, or move aside first                                   |
| `> f`, `2> f`, `>! f`, `: > f`, `true >\| f`, `cat /dev/null > f`, `cp /dev/null f`                                                                                                                                                                                                                                                                                                                                       | **denied** | move the file aside first                                        |
| `find -delete`; `find -exec` / `fd -x` with any denied command                                                                                                                                                                                                                                                                                                                                                            | **denied** | `find -print`, then `-exec rm {} +`                              |
| `rsync --delete*`, `--del`, `--remove-source-files`                                                                                                                                                                                                                                                                                                                                                                       | **denied** | rsync without them, then bare `rm`                               |
| inline code: `python -c`, `node -e`, `perl -e`, `ruby -e`, `deno eval`, `osascript -e`, and code on stdin (`python3 - <<EOF`, `echo ... \| python3`) calling `os.remove`, `shutil.rmtree`, `Path.unlink`, `rmdir`, `fs.rm*`, `unlink*`, `/bin/rm`, `FileUtils.rm*`                                                                                                                                                        | **denied** | bare `rm` in the shell                                           |
| `docker`/`podman` `... prune`, `volume rm`, `compose down -v`; `brew cleanup`, `--zap`; `pnpm store prune`; `uv cache clean/prune`; `bun pm cache rm`; `rimraf`                                                                                                                                                                                                                                                           | **denied** | ask Gavin (`rimraf`: bare `rm -r`)                               |
| `diskutil erase*`/`partitionDisk`/..., `mkfs*`, `newfs*`, `wipefs`, `tmutil delete*`, `trash-empty`, Finder "empty trash"                                                                                                                                                                                                                                                                                                 | **denied** | ask Gavin                                                        |
| an alias from the shell snapshot whose expansion is any of the above                                                                                                                                                                                                                                                                                                                                                      | **denied** | (as the expansion)                                               |
| a wrapper's value flag given LAST with no value (`time -o`, `nice -n`, `exec -a`, `xargs -n`, `sudo -u`, `env -S`, `git -C`, `perl -e`, `uv run --with`, ...), then a denied command (`time -o; unlink f`)                                                                                                                                                                                                                | **denied** | (as the later command)                                           |
| the guard itself gives no verdict within 3 s (`guard-timeout`), or its child exits without one (`guard-no-verdict`); the denial says it is NOT a match                                                                                                                                                                                                                                                                    | **denied** | split the command, or ask Gavin                                  |
| bare `rm`, `command rm`, `\rm`, `rm *(.)`, `find -exec rm`, `git clean -n`, `git branch -d`, `git restore --staged`, `cmd > out`                                                                                                                                                                                                                                                                                          | allowed    |                                                                  |
| a script or Makefile target that deletes internally, a compiled program                                                                                                                                                                                                                                                                                                                                                   | invisible  | the rm shim still covers a bare `rm` inside it                   |
| a command name in a variable (`$RM x`, zsh `$=x`), git aliases, `ssh host 'rm ...'`                                                                                                                                                                                                                                                                                                                                       | invisible  |                                                                  |
| `mv` / `cp` over an existing file, `sed -i`, `open(f, 'w')`                                                                                                                                                                                                                                                                                                                                                               | invisible  | cp/mv wrappers: prompt at a terminal, decline for agents (below) |
| code piped from a file (`cat x.py \| python3`), heredoc `$( )` expansions                                                                                                                                                                                                                                                                                                                                                 | invisible  |                                                                  |
| snapshot FUNCTIONS (their bodies are not expanded; `rm()` itself contains `/bin/rm` on its `SAFE_RM_OFF` branch)                                                                                                                                                                                                                                                                                                          | invisible  |                                                                  |

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

| What goes wrong                                                              | Result                                                          | Evidence                                          |
| ---------------------------------------------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------- |
| the classifier runs past 3 s                                                 | **denied** (`guard-timeout`)                                    | selftest DEADLINE arm, test seam                  |
| the classifier exits before its verdict (an `exit`, a fatal shell error)     | **denied** (`guard-no-verdict`, via an EXIT trap)               | selftest DEADLINE arm, test seam                  |
| the classifier is killed by a signal                                         | **denied** (`guard-no-verdict`)                                 | one manual run in a scratch copy, not in selftest |
| `DEL_GUARD_DEADLINE` set above 2                                             | ignored; the 3 s deadline holds                                 | selftest arm (99: denied under 4.5 s)             |
| the lexer (awk) fails                                                        | allowed, `additionalContext` warning                            | unchanged                                         |
| `jq` missing                                                                 | **denied** if the raw text names a trigger, else a warning      | selftest UNREADABLE arms (D-20260925-A03)         |
| malformed JSON, or `tool_input.command` under another key                    | **denied** if the raw text names a trigger, else allowed        | selftest UNREADABLE arms                          |
| empty stdin, empty command                                                   | allowed, no decision (a crash here would block every Bash call) | selftest HOOK arms                                |
| a stall BEFORE the deadline starts: stdin never closing, `jq` itself hanging | allowed at the harness's 5 s timeout                            | not covered                                       |
| a spinning `awk` child of a killed classifier                                | keeps running as an orphan (the verdict is already a deny)      | not covered; no awk loop is known to spin         |

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
