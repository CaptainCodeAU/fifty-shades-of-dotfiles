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

| Call path                       | Covered?          | Evidence                                                             |
| ------------------------------- | ----------------- | -------------------------------------------------------------------- |
| Interactive zsh, `rm -rf dir`   | yes               | trashed to `~/.Trash/rmtest-victim`; `test -e` confirmed             |
| Claude Code Bash tool           | yes               | `type rm` -> shell function from the session's shell snapshot        |
| `sudo rm` / `sudo rmdir`        | yes               | 13-case behaviour test, below                                        |
| `sudo -u root rm -rf x`         | yes               | option scanner finds the command past sudo's own flags               |
| `#!/bin/bash` script, bare `rm` | yes               | live: script's `rm -rf` landed in `~/.Trash/victim`                  |
| `#!/bin/zsh` script, bare `rm`  | yes               | dummy-shim test hit the shim                                         |
| `xargs rm`                      | yes               | live: `~/.Trash/xtarget.txt`                                         |
| `make clean`                    | yes               | live: `~/.Trash/junk.o`, and a missing target did not break the rule |
| `find -exec rm`                 | yes               | same PATH lookup as `xargs`                                          |
| `command rm`, `\rm`             | yes               | these bypass functions and aliases, not `PATH`                       |
| Homebrew formula post-install   | yes               | `formula.rb:1662` restores the user's PATH for that phase            |
| cron / launchd / CI             | **no**            | minimal PATH; `~/.local/bin` absent                                  |
| Homebrew internals              | **no**            | `bin/brew:308` hardcodes `PATH=/usr/bin:/bin:/usr/sbin:/sbin`        |
| Docker `RUN rm -rf`             | **no**            | runs inside the image with its own `/bin/rm`                         |
| `/bin/rm`                       | **no, cannot be** | absolute path never consults PATH; SIP `restricted`, see below       |
| `SAFE_RM_OFF=1 rm ...`          | **no, by design** | the deliberate "I really mean it" door                               |

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

## What this does NOT protect against

None of the above involves `rm`, and no `rm` wrapper can see any of it:

- Shell truncation: `> file`, `: > file`, `truncate -s0`
- `find -delete`, `unlink`, `mv` over an existing file, `install`, `rsync --delete`
- `git clean -fdx`, `git checkout` discarding changes, `git reset --hard`
- `docker system prune`, `brew cleanup`, `pnpm store prune`
- Language-level deletes: Python `os.remove`, Node `fs.unlinkSync`
- Finder Shift-Delete, or emptying the Trash
- Disk failure

A recoverable-delete wrapper is one door. It is not a backup, and it must not be mistaken for
one.

## Related

- [`home/.local/bin/safe-rm`](../home/.local/bin/safe-rm) — the single owner of "move to Trash"
- [`SECURITY.md`](SECURITY.md) — overall posture
