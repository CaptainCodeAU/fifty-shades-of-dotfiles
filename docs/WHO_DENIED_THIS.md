# Who denied this? A field guide to the five layers that can refuse a command

A refused command on this Mac can come from five different layers, and the message rarely says
which one. CLAUDE.md names the trap ("nothing in a denial message says which layer issued it");
this page is the answer to it: read the message, find the layer, take that layer's route.

Written 2026-10-05 after one session (dotfiles-main, 4555711b) hit four of the five layers in an
afternoon and none of them was caused by that day's changes (the guards logged 0 denials after the
15:29 install). Every example below is real, from that session.

## The five layers at a glance

| #   | Layer                                          | Who owns it                      | What the message starts with                                                                                                    | Can you change it?                      |
| --- | ---------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| 1   | Our PreToolUse guards (dotfiles, all projects) | this repo, `home/.claude/hooks/` | `PreToolUse:Bash hook error: BLOCKED (<rule>)`, or `HOOK MISSING, DENYING` / `HOOK CRASHED, DENYING`                            | yes, in this repo                       |
| 2   | This repo's own project hooks                  | this repo, `.claude/hooks/`      | `Don't use 'cd' -- use absolute paths ...` and similar                                                                          | yes, project-only                       |
| 3   | Claude Code's built-in safety checks           | Anthropic (Claude Code itself)   | `Permission for this command was denied by a built-in Claude Code safety check`                                                 | no                                      |
| 4   | Permission rules and the permission gate       | settings files, and Gavin        | `File is in a directory that is denied by your permission settings` / `Permission to use Bash with command ... has been denied` | rules yes (settings), the gate is Gavin |
| 5   | The OS Bash sandbox                            | the session's sandbox config     | `Operation not permitted`, `afpAccessDenied`, `[Errno 1]`                                                                       | per command, with a reason              |

Plus refusals that are not denials at all: the cp/mv wrappers and safe-rm decline and say so
(section 6).

## 1. Our PreToolUse guards (every Claude session, every project)

Registered by `claude-hooks-sync` into `~/.claude/settings.json` (user) and
`~/.claude/settings.project.json` (pj project scope), and by engage's own manifest for engage
sessions. Each guard runs on Bash, and since 2026-10-05 on Monitor too (W-20260924-A71).

| Guard                              | What it stops                                                                    | Detail                                                                                                                                                                                                                                                                                                                                                                       |
| ---------------------------------- | -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enforce-no-permanent-delete.sh`   | any delete that skips the Trash                                                  | rule name in the message: `rm-path`, `redir-trunc` (`> f` or `: > f` on its own empties a file), `git-worktree-remove`, `git-clean`, `git-reset-hard`, `git-checkout-discard`, `inline-code`, `find-delete`, `dd-of`, `rsync-delete`, `safe-rm-off`, `trash-empty` and more (29 rules). Coverage and safe routes: [DELETION_SAFETY.md](DELETION_SAFETY.md) "The agent guard" |
| `enforce-no-reset-by-name.sh`      | remove a dir, then reuse its name (a failed remove would merge into stale files) | [CLAUDE_HOOKS.md](CLAUDE_HOOKS.md)                                                                                                                                                                                                                                                                                                                                           |
| `enforce-secret-probe.sh`          | printing a credential into the transcript                                        | CLAUDE.md "Printing a secret is BLOCKED"                                                                                                                                                                                                                                                                                                                                     |
| `enforce-gh-ssh-only.sh`           | `gh auth login/setup-git/...` and HTTPS credential helpers                       | [GH_AUTH_GUARD_USER_LEVEL.md](GH_AUTH_GUARD_USER_LEVEL.md)                                                                                                                                                                                                                                                                                                                   |
| `enforce-pj-workers.sh`            | a conductor starting a plain Claude worker                                       | [CLAUDE_HOOKS.md](CLAUDE_HOOKS.md)                                                                                                                                                                                                                                                                                                                                           |
| `validate-bash.sh` (project scope) | destructive patterns, protected paths                                            | [CLAUDE_HOOKS.md](CLAUDE_HOOKS.md)                                                                                                                                                                                                                                                                                                                                           |
| `enforce-no-worktree-discard.sh`   | `ExitWorktree` with discard                                                      | [CLAUDE_HOOKS.md](CLAUDE_HOOKS.md)                                                                                                                                                                                                                                                                                                                                           |

Two special messages come from the wrapper around every guard, not the guard:

- `HOOK MISSING, DENYING`: the guard's file is gone (on 2026-10-05: every link removed by a failed
  restow). Since that day the wrapper first looks again after 5 ms, and the message leads with the
  fix: `sh ~/.local/state/dotfiles/links/restore` from any terminal.
- `HOOK CRASHED, DENYING`: the guard ran and exited with something other than 0 or 2. Run it by
  hand with `--selftest` to see why (D-20261002-A01).

Every denial is logged to `~/.local/state/dotfiles/hooks-security.log` (D-20261005-A04), which is
how "did today's change cause this?" gets a measured answer instead of a guess.

The right response: change the command's shape to the safe route the message names, or ask Gavin.
Never reword the command to slip past the guard (CLAUDE.md, "Deletion safety").

## 2. This repo's own project hooks (only when the session's folder is this repo)

Registered in this repo's `.claude/settings.json`, so they fire HERE and nowhere else:

- `enforce-no-cd.sh`: denies a leading `cd` (rewrites `cd DIR && x` into a subshell; allows `cd`
  inside an explicit `( )`, but not when the same command also defines a function). Use
  `git -C <path>`, absolute paths, or `builtin cd`.
- `enforce-builtin.sh` (Bash) and `protect-files.sh` (Edit|Write).

The trap is the one CLAUDE.md names: a rule you only ever meet inside one repo gets mistaken for a
property of the tool. If a command works in another project and not here, check this layer first.

## 3. Claude Code's built-in safety checks (not ours, not configurable)

Message: `Permission for this command was denied by a built-in Claude Code safety check, not by the
user.` It stops removals that could delete far more than intended: `rm -r` on a home or workspace
directory, or on a path built from a variable it cannot resolve, or a `sh -c` / `zsh -c` script
it cannot read for removals.

On 2026-10-05 it fired twice on test code: `rm -r "$WT"` (a variable), and a `zsh -c '...'` test
script that contained no `rm` at all; it still could not read the script, so it refused.

The right response: never work around it. Use a literal path; put a test script in a visible file
and run the file; or leave the removal to Gavin. A removal inside the Trash route (`rm` = safe-rm)
still goes through this check first.

## 4. Permission rules and the permission gate

Two different things that read alike:

- A deny RULE in a settings file. Example: `File is in a directory that is denied by your
permission settings` on an Edit under `~/.claude/projects/*/memory/`, from the rule
  `Edit(~/.claude/projects/*/memory/*)` in `~/.claude/settings.project.json`. Drawer files are
  written by the tools (open-items, decided, pj-wrap) or by `cp` of a NEW file, never edited in place.
- The permission GATE: `Permission to use Bash with command ... has been denied`. Either Gavin
  said no at the prompt, or the auto-mode classifier refused it. On 2026-10-05 a `cp -f`
  overwrite of a drawer file was refused this way. Do not retry the same command; change the
  approach (write a new file) or ask.

## 5. The OS Bash sandbox (per command)

Messages: `Operation not permitted`, `afpAccessDenied` (the Trash), `[Errno 1] Operation not
permitted: '/dev/fd/3'`, a `<sandbox_violations>` block. The sandbox is on in exactly one project
on this Mac, this repo (`.claude/settings.local.json`; measured 2026-10-05: 1 of 66 projects).
It denies writes outside the working folder and `$TMPDIR`, reads under any `.ssh`, the Keychain,
pty allocation, and `/dev/fd/N`. Details: [CLAUDE_CODE_SECURITY.md](CLAUDE_CODE_SECURITY.md)
section 3 and CLAUDE.md "Sandbox".

The right response: if the task needs it, run that ONE command with the sandbox off and say why;
a denial on something the task does not involve is the boundary working.

Its quiet failure: a sandboxed command can PRINT a plausible result built on a skipped read (a
`find` that silently skipped `.ssh`; a `yt` pipe that printed no path). Read the exit code.

## 6. Refusals that are not denials

- `cp: ... NOT overwritten: no one can answer an overwrite prompt here` (and the same for `mv`):
  the cp/mv wrappers decline every overwrite in an agent shell (DELETION_SAFETY.md "Agent shells
  never wait on a prompt"). `cp -f` overwrites; prefer writing a new file.
- `safe-rm: these paths still exist after the trash call`: the Trash refused (usually the sandbox,
  layer 5); the file is neither gone nor in the Trash.
- `git-leak-scan` exit 2: it scanned nothing; that is not a pass.

## Real examples, 2026-10-05

| Message seen                                                                | Layer             |
| --------------------------------------------------------------------------- | ----------------- |
| `BLOCKED (git-worktree-remove)`                                             | 1, deletion guard |
| `BLOCKED (redir-trunc)` on `: > $S/STATE` and on `( ... ) > file`           | 1, deletion guard |
| `HOOK MISSING, DENYING: enforce-gh-ssh-only.sh` (the outage)                | 1, wrapper        |
| `Don't use 'cd' ... this command has a function definition`                 | 2, project hook   |
| `built-in Claude Code safety check` on `rm -r "$WT"` and on a `zsh -c` test | 3                 |
| `File is in a directory that is denied by your permission settings`         | 4, deny rule      |
| `Permission to use Bash with command ... cp -f ... has been denied`         | 4, gate           |
| `Operation not permitted` writing `~/.local/share/uv/tools`                 | 5, sandbox        |
| `cp: ... NOT overwritten: no one can answer an overwrite prompt`            | 6, wrapper        |
