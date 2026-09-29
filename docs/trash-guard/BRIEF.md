# BRIEF: machine-wide trash guard (trash shim + safe-rm + hook)

Date: 2026-09-29 ~19:50 AEST. Conductor: dotfiles-one [661bf1] (fifty-shades-of-dotfiles).
Worktree: ~/CODE/Scaffoldings/fifty-shades-of-dotfiles/.worktree/trash-guard
(branch `trash-guard`, from master edf509f). Records folder (commit it with the work):
`docs/trash-guard/` in the worktree. Progress: append one line per step to
`docs/trash-guard/progress.md`, last line exactly `DONE` when finished. Report:
`docs/trash-guard/REPORT.md`, last line exactly `status: DONE`.

## Why

Tonight (19:25, 19:31, 19:37) the engage repo went to the Trash three times: a cleanup ran
`trash ''` / `trash ""` with an empty variable, and macOS `/usr/bin/trash ''` trashes the
current folder. Gavin recovered it each time with Put Back. Incident:
~/CODE/CaptainCodeAU/CaptainCodeAU-isolinear/workbench/records-system/2026-09-28/INCIDENT-20260929-engage-repo-trashed.md
Lesson: ~/.claude/pj-global/notes/20260929-cleanup-on-an-empty-path-trashes-the-folder.md
The engage session has paused its cleanup work until this guard is live.

## Scope (Gavin confirmed in the conductor's boxes, 2026-09-29; do not widen or narrow)

Applies to BOTH routes: `trash` (a new PATH shim) and the rm shim (`safe-rm`).
Resolve every target first (trailing slashes, `./`, `..`, symlinks, relative paths) and test
the resolved path. A refusal names the argument, the resolved path and the rule, exits
non-zero, and trashes NOTHING in that call (all-or-nothing, like safe-rm's existing guard).

1. ALWAYS refused, anywhere (temp folders included):
   - a blank argument (`''`, `""`, whitespace only)
   - `.`, the current folder, and any folder that CONTAINS the current folder
   - `/`, `~` ($HOME), `~/CODE`, `~/CODE/CaptainCodeAU` (an explicit floor list, one constant)
2. Refused OUTSIDE the system temp folders:
   - any git repo root: a folder holding `.git` (directory or file)
   - any folder that contains a git repo anywhere inside it. The search is bounded: 2 s
     wall clock. When it cannot finish, REFUSE, saying so. Never allow on a timeout.
3. ALLOWED even though it holds a `.git` FILE: a linked worktree whose path is
   `<repo>/.worktree/<name>` (keeps the documented worktree removal route in
   docs/DELETION_SAFETY.md: `rm -r <dir>` then `git worktree prune`). A worktree that itself
   contains a nested repo is still refused.
4. System temp folders for rule 2: `$TMPDIR`, `/private/tmp` (and `/tmp`), and the user temp
   dir `$(getconf DARWIN_USER_TEMP_DIR)` (under `/private/var/folders/`). Resolve these too.
   Selftests clean up throwaway repos there with `rm -r`; they must keep working.
5. Files (not folders) are only subject to rule 1.
6. Close the typed bypass for AGENT sessions: the Bash PreToolUse hook
   `home/.claude/hooks/enforce-no-permanent-delete.sh` (it already denies a typed `/bin/rm`)
   also denies a typed `/usr/bin/trash`, `command trash` and `env trash` (inside `sh -c`,
   `eval`, `$(...)` too, as its lexer already handles for rm). Its denial names the safe route:
   plain `trash`, which goes through the guard. One selftest arm per form in that hook's own
   selftest, plus a control that plain `trash x` is NOT denied by the hook.
7. Mac only. mlbox/Linux is filed separately; keep the guard POSIX sh so it can travel later.

## Build

- One shared guard, e.g. `home/.local/bin/trash-guard` (POSIX sh), used by both routes, with a
  `--check <path>...` mode that only judges and never deletes. One place holds the rules.
- `home/.local/bin/trash`: a PATH shim. It runs the guard, then execs the REAL trash: the next
  `trash` on PATH that is not this file (on this Mac, /usr/bin/trash). If none is found,
  refuse. Never recurse into itself. Pass options through unchanged.
- `home/.local/bin/safe-rm`: call the guard before trashing (keep its existing container and
  sweep guards). safe-rm resolves `trash` with `command -v`, which will now find the shim; make
  sure that neither recurses nor refuses wrongly.
- The hook change in rule 6. If the live-file lock (A35) denies editing a guard file even in
  the worktree, stop and report it; do not work around it.
- Seams for the selftest (env vars), so NO test can ever reach the real Trash or a real
  folder: the real-trash command, the floor list's home, the temp-root list, and the search
  command/timeout (to fake a slow search).
- Docs: add rows to the coverage table in docs/DELETION_SAFETY.md (what is refused, by which
  route, and the typed-path denial). Name any gap that remains (for example Gavin's own
  terminal typing /usr/bin/trash, which is by design).

## Tests (new `home/.local/bin/trash-guard-selftest`, bash 3.2 safe)

Every refusal arm leaves its target in place, checked with `test -e` after the call.
Use a FAKE real-trash via the seam that records calls; assert it was NOT called on refusals.
Arms, each its own line:

- blank `''`, `""`, `' '`; `.`; the current folder by absolute path; a parent of the cwd
- `/`, fixture HOME, fixture HOME/CODE, fixture HOME/CODE/CaptainCodeAU, each also as
  `~/CODE/`, `$HOME/CODE/./CaptainCodeAU`, a relative `..` path, and through a symlink
- a repo root (.git dir) outside temp; a folder with a nested repo outside temp
  (Gavin's example: ~/CODE/Scaffoldings, which holds fifty-shades; use a fixture shaped like it)
- a linked worktree under <repo>/.worktree/<name>: ALLOWED; a worktree holding a nested repo:
  refused
- temp exemption: a repo root inside a fixture temp root: ALLOWED; but blank / cwd inside temp:
  still refused
- slow search (fake): refused, names the timeout
- both routes: `trash X` and `rm -r X` give the same verdicts
- CONTROLS: a plain temp folder with no .git goes (fake trash called once, with the path);
  one end-to-end arm with the REAL /usr/bin/trash on a throwaway temp file you create, then
  `test -e` shows it gone (run unsandboxed; the sandbox denies the Trash).
- Every new arm must FAIL on master's code (no shim / old safe-rm / old hook) and pass on
  yours; report both counts. Add one-fault mutants for: the blank check, the cwd check, the
  timeout-refuses rule, the temp exemption, and one hook form; each must be caught.
- Re-run the existing safe-rm / rm selftests and enforce-no-permanent-delete.sh --selftest;
  report they still pass.

## Rules (binding)

1. Write only inside your worktree and $TMPDIR. Never touch the real ~/.Trash, real repos, or
   real home folders in a test; every destructive arm uses fixtures and the fake trash seam,
   except the one end-to-end control on a temp file you created.
2. Bare tool names on PATH are MASTER copies. Run your worktree copies by absolute path.
3. Never call /bin/rm, `rm -P`, `find -delete`, `unlink` or any permanent delete. Bare `rm` only.
4. Commit small on branch `trash-guard` by explicit path. Never push, never merge, never stow.
5. Never start a Bash command with `cd` in this repo (a hook rewrites or denies it).
6. The Bash tool is zsh: no word-splitting of `$var`, no `type -P`.
7. Label every load-bearing claim VERIFIED (command named), AGENT-REPORTED or ASSUMED.
8. Report sections: what you built and where; every arm with counts (branch vs master);
   mutants; edge cases (below) with behaviour and evidence; choices made on your own;
   left undone; things worth filing (never file them yourself).

## Edge cases to cover in the report

Multiple targets where one is refused (nothing trashed); `--` before a `-name`; a target that
does not exist; a broken symlink; a symlink TO a repo root (say what you do and why); a path
with spaces or a newline; `trash -v`-style options passed through; HOME unset; the search
hitting an unreadable folder (sandbox `.ssh`); a very large folder (timing).

## Report to the conductor

SendMessage `dotfiles-one` on arrival ("I am herdr agent <name>", your session name and
[ref]), then again when REPORT.md is done. Gavin's decisions go through the conductor.
