# Deletion safety — what routes to the Trash, and what does not

Deleting a file on this machine should be recoverable. That is achieved by routing deletion
through [`home/.local/bin/safe-rm`](../home/.local/bin/safe-rm), which moves targets to the
system Trash (`/usr/bin/trash` on macOS, `trash-put` on Linux/WSL) and **never unlinks**.

The hard part is not the trashing. It is COVERAGE: a shell function only exists inside an
interactive zsh, so every guard written that way is invisible to scripts, cron, CI, git hooks
and `xargs`. This document records which call paths are actually covered, which are not, and —
importantly — which ones **cannot** be, with the measurement that proves it.

## The chain

```
rm()  (home/.zshrc)  ->  safe-rm  ->  /usr/bin/trash   ->  ~/.Trash
rmdir()              ->  safe-rm  ->  trash-put        ->  XDG trash   (Linux/WSL)
sudo rm/rmdir        ->  safe-rm  (as the invoking user, NOT as root)
```

`safe-rm` fails closed. If no trash tool is installed it exits 1 and deletes nothing; it never
falls back to `rm`, because a silent downgrade from "recoverable" to "permanent" is the one
behaviour a safety command must not have.

## Coverage

Measured 2026-09-04 on macOS 25.6 (Darwin), SIP enabled. Every row was run, not inferred.

| Call path                       | Covered?          | Evidence                                                      |
| ------------------------------- | ----------------- | ------------------------------------------------------------- |
| Interactive zsh, `rm -rf dir`   | yes               | trashed to `~/.Trash/rmtest-victim`; `test -e` confirmed      |
| Claude Code Bash tool           | yes               | `type rm` -> shell function from the session's shell snapshot |
| `sudo rm` / `sudo rmdir`        | yes               | see below; 13-case behaviour test                             |
| `sudo -u root rm -rf x`         | yes               | option scanner finds the command past sudo's own flags        |
| `#!/bin/bash` script, bare `rm` | **no**            | `bash -c 'type rm'` -> `/bin/rm`                              |
| `#!/bin/zsh` script, bare `rm`  | **no**            | `zsh -c 'type rm'` -> `/bin/rm`                               |
| `xargs rm`, `find -exec rm`     | **no**            | test file was permanently removed                             |
| `make clean`                    | **no**            | Makefile recipes run under `/bin/sh`                          |
| cron / launchd / CI / git hooks | **no**            | none of them load `.zshrc`                                    |
| `command rm`, `\rm`, `/bin/rm`  | **no, by design** | the deliberate "I really mean it" door                        |

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
