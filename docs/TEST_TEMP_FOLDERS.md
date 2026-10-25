# Test temp folders

Gavin asked for one rule for tests in every project (25 Oct 2026, record #3989):

1. make temp folders with `mktemp`, under `TMPDIR`;
2. remove them on exit with a trap that runs on success, on failure and on Ctrl-C;
3. end each run with a check that nothing is left behind.

Sessions of another project had left 31 test folders, 8.8 GB, in the shared
`/tmp/claude-501`. Two files do the work, both in `home/.local/bin`:

- `test-temp.sh` is sourced by a test. It makes the folder and sets the traps (1 and 2).
- `test-temp` runs a suite and checks it (3). It also lints test files for the traps below.

Removal goes to the Trash only. Nothing here deletes anything for good.

## In a test

The same lines work in bash (3.2 and later) and in zsh.

```sh
. "$HOME/.local/bin/test-temp.sh" new mytest || exit 2   # TT is the new folder
mkdir "$TT/work"                                          # use it
```

That is all. When the test ends, its folder goes to the Trash.

Keep the `|| exit 2`. When the file is missing (not stowed, or a typo in the path), `.` fails,
and both bash and zsh carry on with the next line. `TT` is then empty, so `"$TT/work"` would
be `/work`. Measured 25 Oct 2026 in bash 3.2 and zsh 5.9. With the guard, the test stops
there instead.

| Call                                                  | What it does                                                   |
| ----------------------------------------------------- | -------------------------------------------------------------- |
| `. test-temp.sh new NAME [keep-on-fail] \|\| exit 2`  | Makes `NAME.XXXXXX` in the temp folder. `TT` is its real path. |
| `. test-temp.sh adopt DIR [keep-on-fail] \|\| exit 2` | Takes a folder the test made itself. `TT` is its real path.    |
| `tt_also PATH [keep-on-fail]`                         | One more path of the test's own, removed with `TT`.            |
| `tt_on_end 'COMMAND'`                                 | Runs COMMAND at the end, before anything moves.                |

- The temp folder is `TMPDIR`. With `TMPDIR` unset (Gavin, 25 Oct 2026) it is the macOS user
  temp folder (`getconf DARWIN_USER_TEMP_DIR`), or `/tmp` off macOS. It is never the shared
  `/tmp/claude-<uid>`.
- `keep-on-fail` keeps that folder when the test exits non-zero, and says where.
- `adopt` and `tt_also` take a mktemp-shaped name (`NAME.XXXXXX`). Its real folder must be
  inside the temp folder, `/tmp` or the macOS user temp folder. It must not be inside the
  shared `/tmp/claude-<uid>` unless it is inside the temp folder too. `adopt` refuses a link,
  with or without a trailing slash.
- Source it at the test's top level, before any trap of your own.
- It owns the EXIT, INT, TERM, HUP and PIPE traps. Put your own cleanup in `tt_on_end`.
  A `trap ... EXIT` set later replaces the helper's. Then `test-temp check` fails the run
  ("end never ran").
- An `exit` inside a `tt_on_end` command does not end the shell. It is noted, the removal
  still runs, and the test keeps its own exit status. The rest of that command still runs.
  A `return` ends just that command.
- Never `exec` from a `tt_on_end` command: the process is replaced, and nothing more runs.
- In zsh, after a signal, `tt_on_end` commands run inside the signal trap. Keep them to
  shell builtins such as `kill`. A program started there can hang (see the trap table).
- A second `. test-temp.sh new OTHER` in the same shell adds a second folder. `TT` is then
  the second one. A subshell that sources it again gets folders of its own, and removes
  only those, at its own end.

### What the end does

- It runs once, and only in the test's own process. A subshell, `$(...)` or `&` child that
  ends is not the test ending.
- The test's exit status stays its own: 0 stays 0, 1 stays 1.
- After a signal (Ctrl-C, TERM, HUP, a broken pipe), the removal runs, and then the test
  raises the same signal again with its default action. So the caller sees the test die of
  that signal. A bash loop that runs tests then stops, as it does for a test with no trap.
  A test that only exited 130 would let the loop run the next test (measured: a loop of three
  tests ran tests 2 and 3, and exited 0). Exit 130, 143, 129 or 141 is the fallback only if
  the re-raise comes back.
- It sends each path through the dotfiles Trash shim, the account's `~/.local/bin/rm`. It
  checks the shim for its marker when sourced. It runs the removal from `/`, because the
  trash guard refuses a folder that holds the current folder.
- Then it checks each path with `test -e`.

### Refusals

The helper refuses with exit 2, before it makes anything, when:

- it is sourced at an interactive prompt (it returns 2 there: its Ctrl-C trap would close the shell);
- it is sourced inside a zsh function;
- a trap of the test's own is already set on EXIT, INT, TERM, HUP or PIPE (it would be
  replaced). The message names each one;
- `TMPDIR` is the shared root, `/tmp/claude-<uid>` (with or without a trailing slash, or as
  `/private/tmp/claude-<uid>`). That session has no folder of its own, so the test's folders
  would stay in the shared folder, which is this record's incident. Run it outside the
  sandbox, or give the session its own folder. `run` refuses the same way (exit 3);
- there is no temp folder;
- no Trash shim carrying its marker is found;
- a name or path breaks the rules above.

It also refuses to be run instead of sourced.

An ignore, `trap '' SIG`, is not refused. bash 5 lists a signal its parent ignored in exactly
that form (measured), so refusing it would refuse every test such a parent runs. In bash, a
signal ignored from the start stays ignored: the helper cannot trap it.

### The list

Each event is one line, appended to `${TEST_TEMP_DIR:-<the temp folder>}/.test-temp/list`:

```
made|gone|refused|failed|kept <TAB> path <TAB> pid <TAB> epoch seconds <TAB> detail
```

- `made`: the helper made or took the path.
- `gone`: the path went to the Trash, or was already gone.
- `refused`: the Claude sandbox would not let it go to the Trash. That needs
  `SANDBOX_RUNTIME=1`, which Claude Code sets inside the Bash sandbox and nowhere else, and an
  afpAccessDenied from the Trash. The path is still there.
- `failed`: the Trash would not take it anywhere else. The path is still there.
  `test-temp check` always fails this one.
- `kept`: keep-on-fail kept it, for a test that failed.

## Running a suite

```sh
test-temp run -- ./tests/run-all.sh
```

`run` does this:

1. It makes a private run folder, `test-temp-run.XXXXXX`, in your temp folder.
2. It runs the suite with `TMPDIR` and `TEST_TEMP_DIR` set to that folder.
3. It checks the folder, and prints one summary line.
4. It sends the run folder to the Trash when nothing is left in it. Otherwise it keeps the
   folder and says where.

The suite is a child that `run` waits on. Ctrl-C reaches it directly. An INT, TERM or HUP sent
to `run` alone is passed on to it. Either way `run` still checks, prints its line, and then
ends by that same signal, so a loop that runs it stops too. This needs perl, which starts the
suite with INT at its default (a script's background child would ignore INT) and keeps stdin.
perl starts it with `exec { $ARGV[0] }`, never through a shell, so a lone argument stays one
word: a path with a space, a `*` or a `$` runs as given. Without perl, the suite runs in
front, and a TERM sent to `run` alone waits for it to end; `run` says so.

`run` sets its signal traps before it makes anything, so no signal is lost on the way in. One
that comes before the suite starts stops the start: the suite never runs, and the run folder
goes again. One that comes while the suite is starting, before its pid is known, is passed on
as soon as it is. When a signal cuts `run`'s wait short and the suite then ends, one more wait
returns the suite's own status, 127 included (measured on bash 3.2 and 5.3).

The check fails a run when:

- a path is listed `made` with no `gone`, `refused`, `failed` or `kept`: its end never ran
  (the test was killed with SIGKILL, or its EXIT trap was replaced);
- anything is left in the run folder that the list does not explain;
- something new appeared in your own `TMPDIR` while the suite ran;
- a path is listed `failed`.

`refused` and `kept` paths follow `TEST_TEMP_REFUSED`:

- `pass` (the default): they are listed, and the run passes. The note says "they go when the
  session ends" only when the run's `TMPDIR` is a session's own folder
  (`/tmp/claude-<uid>/pj-<id>`). Elsewhere it says they stay there until you trash them. The
  `pj-<id>` shape mirrors engage-temp's session folders; it is kept here as a short mirror on
  purpose, not shared with engage's tool.
- `fail`: they fail the run (exit 4).

Gavin's question Q1 settles the default. Any other value refuses with exit 2.

When `TMPDIR` is the shared root (`/tmp/claude-<uid>`, with or without a trailing slash, or
`/private/tmp/claude-<uid>`), `run` refuses with exit 3. The suite never runs. That session
has no temp folder of its own, so a sandboxed run would leave its folders in the shared
folder. Run it outside the sandbox, or give the session its own folder. The helper itself
refuses the same `TMPDIR` (exit 2), so a test sourced without `run` cannot leave folders there
either.

`test-temp check RUNDIR` checks a run folder that `run` kept. It does not compare your
`TMPDIR` again: by then other work has moved on.

### Exit codes

| Command      | 0                          | 1                          | 2                                                                                      | 3                           | 4                                      |
| ------------ | -------------------------- | -------------------------- | -------------------------------------------------------------------------------------- | --------------------------- | -------------------------------------- |
| `run`        | suite passed, nothing left | suite failed, nothing left | cannot check, or cannot run (usage, no temp folder, no Trash shim, no such command)    | `TMPDIR` is the shared root | something left, suite passed or failed |
| `check`      | nothing left               | -                          | check NOT RUN (no `started` marker, unreadable list)                                   | -                           | something left                         |
| `lint`       | no findings                | findings                   | cannot run (no shell file, an unreadable file or one awk stops on, canary not flagged) | -                           | -                                      |
| `--selftest` | every arm passed           | an arm failed              | could not run                                                                          | -                           | -                                      |

A suite that failed and also left something exits 4. The summary line says both. After a
signal, `run` prints its line and then ends by that signal instead of an exit code.

## Lint

```sh
test-temp lint tests/*.sh tests/*.zsh
```

It reads shell files only: by `#!` line, or by `.sh`, `.bash` or `.zsh`. A file holding a NUL
byte in its first 8 KB is not shell, and is skipped without a word. It reads bytes
(`LC_ALL=C`): in a UTF-8 locale macOS awk stops at the first byte that is not UTF-8 ("towc:
multibyte conversion failure"), and what it found up to there would look like a clean file.
A file awk still stops on counts as unreadable, and lint exits 2. It flags:

- `mktemp` with no template (`mktemp`, `mktemp -d`, `mktemp -t NAME`, the same with a path
  before it, such as `/usr/bin/mktemp -d`, and with a redirection after it, such as
  `mktemp -d 2>/dev/null`: a redirection is no template);
- a literal temp path: `/tmp/...`, `/private/tmp`, `/var/folders` (`${TMPDIR:-/tmp}` is fine);
- in zsh, an EXIT trap with no INT and TERM traps;
- in zsh, a signal trap that does not exit.

A line carrying `# test-temp: allow <reason>` is not flagged. Nor is the line after a comment
line carrying one. The reason is required. Heredoc bodies are data, and are not read
(`<<EOF`, `<<-EOF`, `<<'EOF'`, `<<"EOF"` and `<<\EOF`). A `<<` inside quotes does not start a
heredoc.

Before it reads any file, lint must flag its own canary (three known bad lines). If it does
not, it exits 2. A lint that finds nothing because it is broken never reads as a pass.

## mktemp, measured

Measured 25 Oct 2026 on macOS.

| Form                                      | Where the folder goes                                               | In the Claude sandbox |
| ----------------------------------------- | ------------------------------------------------------------------- | --------------------- |
| `mktemp -d`                               | the user temp folder (`getconf DARWIN_USER_TEMP_DIR`), not `TMPDIR` | fails                 |
| `mktemp -d -t NAME`                       | the same                                                            | fails                 |
| `mktemp -d "${TMPDIR%/}/NAME.XXXXXX"`     | inside `TMPDIR`                                                     | works                 |
| `mktemp -d "${TMPDIR:-/tmp}/NAME.XXXXXX"` | inside `TMPDIR`, but `//` when `TMPDIR` ends in `/`                 | works                 |

Use the third form. Only an explicit template follows `TMPDIR`.

## Traps, measured

Measured 25 Oct 2026. bash 3.2.57 and 5.3; zsh 5.9 and 5.9.2. "Brief" rows were measured
before this build; the others were measured while building it.

| Case                                                                  | bash                                                                                 | zsh                                                                                              | By    |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ | ----- |
| `trap c EXIT` alone, then Ctrl-C or TERM                              | c runs                                                                               | c does not run                                                                                   | brief |
| `trap c EXIT` alone, then a broken pipe                               | c was once skipped                                                                   | -                                                                                                | brief |
| `trap c EXIT INT TERM`, then Ctrl-C                                   | -                                                                                    | c runs, the script carries on and exits 0                                                        | brief |
| `trap c EXIT; trap 'c; exit 130' INT; trap 'c; exit 143' TERM`        | works (c must act once)                                                              | works (c must act once)                                                                          | brief |
| a test that exits 130 on Ctrl-C, run by a bash loop                   | the loop runs the next test                                                          | the loop runs the next test                                                                      | build |
| a test that dies of SIGINT, run by a bash loop                        | the loop stops                                                                       | the loop stops                                                                                   | build |
| `trap - SIG; kill -SIG $$` inside a trap                              | dies of SIG (3.2 runs a line or two first)                                           | INT and TERM: dies of it. HUP: a plain exit 1                                                    | build |
| a signal ignored when the shell started, then `trap - SIG`            | 3.2: stays ignored (5.3 not measured)                                                | reset                                                                                            | build |
| a trap that fired during a builtin                                    | 3.2: runs with that signal blocked, and exec keeps the block. 5.3: not blocked       | -                                                                                                | build |
| EXIT trap, then a `set -u` abort in a script file                     | runs                                                                                 | runs                                                                                             | build |
| EXIT trap, then a `set -u` abort in `zsh -c` / `bash -c` code         | runs                                                                                 | does not run                                                                                     | build |
| EXIT trap, then an ERR_EXIT (`set -e`) exit                           | runs                                                                                 | runs                                                                                             | build |
| `zshexit_functions`, then a `set -u` abort (file or `-c`)             | -                                                                                    | runs                                                                                             | build |
| `zshexit_functions`, then an ERR_EXIT exit                            | -                                                                                    | does not run                                                                                     | build |
| `zshexit_functions`, when a `( ... exit 4 )` subshell ends            | -                                                                                    | runs, in the subshell                                                                            | build |
| the EXIT trap when a `( )`, `$( )` or `&` child ends                  | not run                                                                              | not run                                                                                          | build |
| an EXIT trap set inside a function                                    | fires at shell exit                                                                  | fires when the function returns                                                                  | brief |
| a trap set at the top of a sourced file                               | global                                                                               | global                                                                                           | build |
| a program started from a trap that fired during `printf`              | runs                                                                                 | hangs for good: the forked child never starts. SIGPIPE: every time. INT: 1 of 13 trials (a race) | build |
| the same, from an EXIT trap or `zshexit_functions` reached from there | runs                                                                                 | hangs for good                                                                                   | build |
| `exec` of a fresh shell from that trap                                | -                                                                                    | works: the fresh shell can start programs                                                        | build |
| `exit` inside a plain EXIT trap                                       | ends the shell there, with that status                                               | ends the shell there, with that status                                                           | build |
| a function named `exit`                                               | takes the place of the builtin (measured with POSIX mode off, as the helper sets it) | takes the place of the builtin, with `posix_builtins` too                                        | build |
| `$(trap -p EXIT)`, `$(trap)`                                          | shows the shell's own traps                                                          | shows nothing (a file shows them)                                                                | build |
| `trap` (the listing) inside a function                                | shows the EXIT trap                                                                  | shows no EXIT trap set at the top level                                                          | build |
| a signal the parent ignored, in the listing                           | 5.3: `trap -- '' SIGINT`. 3.2: not listed                                            | not listed                                                                                       | build |
| this process, read in a child                                         | bash 3.2 has no `BASHPID`; `BASH_SUBSHELL` is 1 in a child                           | `$$` stays the parent's; `sysparams[pid]` is the real pid                                        | build |

What the helper does about them:

- Both shells: the EXIT trap, plus INT, TERM, HUP and PIPE. One end, acting once, in the
  test's own process only.
- zsh also: `zshexit_functions`, for a `set -u` abort in `zsh -c` code.
- zsh also: a signal hands the removal to a fresh shell with `exec`. It starts no child in the
  trap. The fresh shell is the same helper file, in an internal mode.
- After a signal, both shells end by `exec perl`, which sets that signal to its default,
  unblocks it, and sends it to itself. That covers the three gaps above: zsh's HUP, bash's
  ignored signal, and bash 3.2's blocked one. The shell's own `kill` is the fallback.
- zsh: to see an EXIT trap set before it, the file's top level writes the trap table into a
  probe file in `.test-temp/`. The probe file is moved into the test's folder at the end, so
  it leaves with the folder.

To test Ctrl-C honestly, the child needs SIGINT at its default and a process group of its own.
Then kill the group: `kill -INT -- -<pgid>`. A plain `&` job ignores SIGINT, so that trial is
invalid. The selftest starts each child under a perl supervisor with the signals at default
and `setpgrp`. The supervisor also tells a child that died of a signal from one that exited
128 + N, which a shell's own `wait` cannot.

## The sandbox

- Inside a sandboxed Claude Bash call the Trash is refused. A folder stays where it is, and
  the list says `refused`. Nothing else is tried: removal is Trash-only (Gavin's ruling A155).
- The same refusal outside the sandbox (no `SANDBOX_RUNTIME=1`) is listed `failed`, and the
  check fails it.
- Hooks and launchd jobs run outside the sandbox.
- A session with its own `TMPDIR` (`/tmp/claude-<uid>/pj-<id>`) keeps refused folders inside
  its own folder. A session without one would put them in the shared root, so `run` refuses
  there (exit 3).

## Limits

- `run` compares only the top level of your `TMPDIR`. Something else writing there at the same
  time shows up as new. Run suites one at a time.
- A tool that ignores `TMPDIR` (bare `mktemp -d`) writes to the user temp folder, which `run`
  does not watch. Lint flags the bare form in test files, not in the tools they run.
- A test killed with SIGKILL leaves its folder. `check` names it ("end never ran").
- `exec` of another program at a test's end skips every trap. `check` names that too.
- When the terminal's Ctrl-C reaches both `run` and the suite, `run` passes the INT on as well,
  so the suite gets it twice. The helper ignores signals while its end runs, so this does no
  harm to it.
- Each folder is its own item in the Trash. Empty the Trash now and then (the accepted cost in
  [DELETION_SAFETY.md](DELETION_SAFETY.md)).
- Outside a run, the list lives in your temp folder and grows by two short lines per folder.
- Lint reads one line at a time. For the mktemp rule it skips quoted text, but reads a `$( )`
  or backtick inside double quotes as code. A template in a variable counts as a template. A
  literal temp path is flagged even inside quotes, since that is how paths are written. Use
  the allow comment where a line is right as it is.

## Proof

```sh
test-temp --selftest
```

It runs every arm in `/bin/bash` (3.2), the PATH bash, `/bin/zsh` and the PATH zsh, under
`set -u`. Each arm is paired with a control. It also measures whether the Trash takes a folder
here, and expects `refused` where it does not (the sandbox). Its fixtures live in one folder of
its own under `TMPDIR`. That folder is listed like any test's, and goes to the Trash at the end.

Its arm S1 checks that neither file names a permanent deleter: `/bin/rm` or `/usr/bin/rm`,
`unlink`, `find -delete`, `rm -P`, `shutil.rmtree`, `os.remove`, or `/usr/bin/trash` (which
skips the trash guard). Each counts as a command or a path of its own. `~/.local/bin/rm`, the
Trash shim the helper names, is not one. Its control plants each of the seven in a copy.
