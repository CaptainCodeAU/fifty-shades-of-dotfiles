# Test temp folders

Gavin asked for one rule for tests in every project (25 Oct 2026, record #3989):

1. make temp folders with `mktemp`, under `TMPDIR`;
2. remove them on exit with a trap that runs on success, on failure and on Ctrl-C;
3. end each run with a check that nothing is left behind.

Sessions of another project had left 31 test folders, 8.8 GB, in the shared
`/tmp/claude-501`. Two files do the work, both in `home/.local/bin`:

- `test-temp.sh` is sourced by a test. It makes the folder and sets the traps (1 and 2).
- `test-temp` runs a suite and checks it (3). It also lints test files for the traps below.
  And it is the after-command hook, which moves to the Trash the folders the Claude sandbox
  would not let a test move there (Gavin's Q1: 2; see [The after-command hook](#the-after-command-hook)).

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
  afpAccessDenied from the Trash. The path is still there. The end also names the list, once,
  to the after-command hook, which moves the path once the Bash command ends where the hook
  runs. The end says so only where the hook has run before, for this Claude (its heartbeat).
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
4. It sends the run folder to the Trash when nothing is left in it but its list and folders
   the sandbox refused. Inside the sandbox that is refused too: the run folder is listed
   `refused` in your list, and the after-command hook, where it runs, moves it after the
   folders inside it (and leaves it if one of them was left).
   Otherwise (a leak, a check not run, a folder kept for a failed test) it keeps the folder and
   says where.

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

- `pass` (the default): they are listed, and the run passes. When the run's `TMPDIR` is a
  session's own folder (`/tmp/claude-<uid>/pj-<id>`) the note says "they go when the session
  ends (no after-command hook has run in this session)", or, once the hook has left this
  Claude its heartbeat, "the after-command hook moves them once this command ends, or they go
  when the session ends". Elsewhere it says they stay there until you trash them. The
  `pj-<id>` shape mirrors engage-temp's session folders; it is kept here as a short mirror on
  purpose, not shared with engage's tool.
- `fail`: they fail the run (exit 4).

Gavin's Q1: 2 (25 Oct 2026): a hook outside the sandbox moves refused folders to the Trash
once each Bash command ends, so `pass` stays the default. Any other value refuses with exit 2.

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
  Where the after-command hook runs, it moves it once the command ends (below).
- The same refusal outside the sandbox (no `SANDBOX_RUNTIME=1`) is listed `failed`, and the
  check fails it.
- Hooks and launchd jobs run outside the sandbox.
- A session with its own `TMPDIR` (`/tmp/claude-<uid>/pj-<id>`) keeps refused folders inside
  its own folder. A session without one would put them in the shared root, so `run` refuses
  there (exit 3).

## The after-command hook

Gavin's Q1: 2 (25 Oct 2026, record #3989): a hook that runs outside the sandbox after each
Bash command moves to the Trash the folders a test listed `refused`. It is
`test-temp after-command`, registered twice on Bash: as PostToolUse, which Claude Code 2.1.310
fires only after a call that succeeded, and as PostToolUseFailure, which it fires after one
that failed (a test that exits non-zero, times out or is stopped). The event's name is the
argument, and the answer names it back.

**How it learns of them.** An end that lists a path `refused` also writes the list's real path
to `/tmp/claude-<uid>/.test-temp-pending/$CLAUDE_PID` (a folder of mode 700): once per test
process, never when the file holds that line already, and never through a link. Claude Code
sets `CLAUDE_PID` to its own pid for Bash calls and for hooks (2.1.310: the same function
builds both environments), so the hook reads only its own Claude's file. With no
`CLAUDE_PID` (not inside Claude Code) nothing is written. A write that fails never fails the
test; it is said once. `run` names your list the same way when the sandbox refuses its run
folder, and the selftest names the session's list for its own folder.

**The heartbeat.** The hook runs only where it is registered: today the dotfiles' user
settings, which engage sessions do not read. So nothing promises a move on the hook's behalf
unless the hook has run for this Claude. Each run as a hook (Claude Code sets
`CLAUDE_PROJECT_DIR` for hooks, never for a Bash call) makes
`<state>/hook/$CLAUDE_PID` once, in the state folder below, which the sandbox cannot write.
Only with that file does a test's end, `check`, `run` or the selftest say "the after-command
hook moves it once this command ends"; without it they say "it goes when the session ends (no
after-command hook has run in this session)". The first Bash call of a session therefore
undersays: the hook may still move its folders once that call ends.

**What it moves.** For each list named there, each path whose last line is `refused`, when all
of these hold:

| Check               | What is asked                                                                                                                |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| the list            | a file named `.test-temp/list`, this account's, no link                                                                      |
| the list's place    | inside a session folder, `/tmp/claude-<uid>/pj-<id>`                                                                         |
| that session folder | its `.pj-temp/owners` (this account's, no link) names this `CLAUDE_PID` (field 2) or the hook input's `session_id` (field 1) |
| the path            | a real folder, no link, this account's                                                                                       |
| its name            | mktemp-shaped, `NAME.XXXXXX`                                                                                                 |
| its place           | inside that same session folder, by its real path; not holding the list that names it                                        |

A folder that holds something left is left too ("it holds ..., which is left"): something
this run left, or a path its own list (a run folder's) has not seen gone and that is still
there. So a run folder never carries to the Trash a folder the checks kept out.

**Against a swap.** Code inside the sandbox can change the session folder at any moment, also
between a check and the move after it: swap a folder on the way for a link to one outside the
session folder, say, and a move by path would take a same-named folder from there. So every
touch of a path in the shared temp folder goes through a small perl walker: from `/`, one
component at a time, never through a link, each folder lstat-ed, entered, and found to be the
same folder (device and inode). The pending file, and each folder to move, is renamed from
inside its verified folder into the staging folder (below), which the sandbox cannot write,
and checked there again (a real folder, this account's, the same inode); the Trash takes it
from there. A rename that fails (another volume, say) leaves the folder where it was, listed
failed. A line for a list is appended the same way (O_NOFOLLOW, and only to an existing file
of this account's), so a swapped list folder gets no line, and that is logged. A moved path
gets a `gone` line ("moved by the after-command hook"), with the same pid as its `made` line,
so `test-temp check` counts it gone. One Trash call per list, in the order the lists were
named, so a run's own folder goes after the folders inside it.

**What it never moves.** Anything that fails a check stays where it is, gets a `failed` line
naming why (so `check` fails it), and a line in the log. A list that fails its checks is not
read for moves and never written to. A list named by a pending file but gone (it went with
its run folder) is logged and skipped. A folder the Trash would not take stays in the staging
folder, and its `failed` line says so. Run by hand inside the sandbox (`SANDBOX_RUNTIME=1`) it
takes nothing at all, and says so: the sandbox reaches neither the Trash nor the staging
folder, so the work waits for the hook.

**The pending file.** It is taken by a rename, through the walk, into the staging folder, as
`<pid>.taken.<epoch>.<pid of the run>`; a test that writes at that moment starts a new file,
which waits for the next Bash call. A line written into the taken file after it was read is
named again (each line once, and not one the new file holds). A pending file that is a link
is taken out of the way the same way, never read or followed, and logged. A run killed part
way leaves its taken file; one whose name says it was taken more than two minutes ago (the
epoch in its name, not its mtime, which a rename keeps from the last write and so can be
days older) is read again, and the no-work test treats such a file as work. Twice is
harmless: only a path whose last line is `refused` moves. Taken files go to the Trash with
the last call.

**What it says.** Nothing, when all went well, and it always exits 0 (the work runs in a
subshell, so not even a fault of its own changes that). When it left something, one
additionalContext line, for the event it ran for, names up to three of them and why, and
points at the log. The rows are `async`, so that line reaches the model a turn later. Once a
run has taken 20 s, the lists it has not moved yet wait for the next Bash call (the row's
timeout is 60 s).

**Its state** is `${XDG_STATE_HOME:-~/.local/state}/dotfiles/test-temp`: `after.log` (one line
per path moved or left, kept to its last 500 lines, disk-watch's way), `staging/` (mode 700;
"Put Back" from the Trash puts a folder there, not back in the session folder), and `hook/`
(the heartbeats, one empty file per Claude that ran the hook).

**Speed**, measured 26 Oct 2026 outside the sandbox on an idle Mac (load average 4 on 10
cores), the command run as Claude Code runs it (`/bin/sh -c`, the input on a pipe):

| Case                                                                | Median     |
| ------------------------------------------------------------------- | ---------- |
| a shell that only reads its input (what any hook pays)              | 4.3 ms     |
| the PostToolUse row, nothing pending (a hook run, heartbeat made)   | 10.1 ms    |
| the same test in the command, input read too (not used, below)      | 4.5 ms     |
| the row, one refused folder pending: the whole run                  | 391 ms     |
| what the session waits for, as async: start it, write the input, go | 0.2-0.3 ms |

50 runs each for the first three, 8 for the others, interleaved. The Trash is most of the
one-folder run, and it swings: the first call after a pause took 6.9 s, and a busy spell
4.8 s (25 Oct, under load). As `async` rows the session waits for none of it: Claude Code
2.1.310 writes the input, backgrounds the process, and delivers its output later as an
`async_hook_response`.

**Why the no-work test is test-temp's first code, not part of the command.** The cheaper
place is the command itself (the third row). But the command shape here is ruled
(`_shape_note` in `settings/claude/hooks.json`, D-20260925-A03): an advisory entry is
`h=...; if [ -x "$h" ]; then "$h" args; else <HOOK MISSING>; fi`, and `claude-hooks-sync`
refuses `||` in one. And `claude-hooks-sync-selftest`'s shape arm (A76) runs every entry from
a Bash call, where `CLAUDE_PID` is set and nothing is pending, and needs the script to run. So
the test is the first code of test-temp, before the whole-read line, and costs one start of
bash. It reads its input to the end before it exits: Claude Code 2.1.310 counts a hook that
closed its stdin before the input was written as failed (EPIPE) and drops its output, and a
write to a pipe whose reader has gone fails at once (measured).

**Where it is registered.** In the dotfiles' user settings, by `claude-hooks-sync`: two rows
in `settings/claude/hooks.json`, PostToolUse and PostToolUseFailure on Bash, class advisory,
`"async": true`, each with a HOOK MISSING line for its own event. The PostToolUse row carries
its first shape (no argument, not async; installed 26 Oct 2026, 1:32 AM) as
`legacy_commands[0]`, so the sync replaces it in place. Gavin runs
`claude-hooks-sync --install`: the sandbox denies an agent's writes to Claude's settings
files. engage sessions read only engage's own settings, so engage's and makeitso's settings
are theirs to add (register it async there too, or the session waits for the moves).

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
  [DELETION_SAFETY.md](DELETION_SAFETY.md)). The hook adds one small taken file per run
  that had something pending.
- A pending file whose Claude has ended stays in `/tmp/claude-<uid>/.test-temp-pending`
  (a few hundred bytes), and so does a taken file in the staging folder whose run was killed
  as its session ended; nothing sweeps them. Their folders still go when their session ends.
- The hook reads lists for what to check, but moves and writes only through the walk; a path a
  list names is checked again at its move. Lists are trusted to hold real paths, as the
  helper writes them.
- The hook acts per list, not per author: every path a session's list holds `refused` moves,
  whichever test in that session made it.
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

The H arms prove the hook against stand-in shims, a session root of the selftest's own and
session folders with their own owners records: end to end in each shell (Ctrl-C included),
nothing pending, each check that leaves a path, a CLAUDE_PID mismatch, malformed input, a
pending file written while it works, `check` after it, the sandbox, and `run`'s own folder.
The N arms (its third review) prove the heartbeat and the words that wait on it, the
PostToolUseFailure answer, a run folder holding what was left, stale taken files by name, a
terminal on stdin (outside the sandbox: it refuses a terminal), a swap after the checks (of
a folder on the way, and of the list's folder), one pending line per list, and a pending
file that is a link, or a taken file with nothing pending. The speed is printed as a figure,
not an arm: on a loaded Mac a wall-clock order can flip, and that nothing pending answers
first is proved by a copy that cannot be parsed past the no-work test.
No arm reads or writes the real `.test-temp-pending`; only the selftest's own end does, to
name its own folder when the sandbox keeps it, as any test's end would.

Its arm S1 checks that neither file names a permanent deleter: `/bin/rm` or `/usr/bin/rm`,
`unlink`, `find -delete`, `rm -P`, `shutil.rmtree`, `os.remove`, or `/usr/bin/trash` (which
skips the trash guard). Each counts as a command or a path of its own. `~/.local/bin/rm`, the
Trash shim the helper names, is not one. Its control plants each of the seven in a copy.
