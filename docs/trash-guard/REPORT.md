# REPORT: machine-wide trash guard

Date: 2026-09-29 (AEST). Worker: herdr pane w3X:p7J, session dotfiles-main-trash-guard-tguard
[0c43a0]. Branch `trash-guard` from master edf509f, 7 commits (this report is the 7th).
Not pushed, not merged, not stowed (brief rule 4).

Labels: VERIFIED (command named), AGENT-REPORTED, ASSUMED.

## 1. What I built and where

| File                                                          | What                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `home/.local/bin/trash-guard` (new, POSIX sh)                 | The one place holding the rules. `--check [--] PATH...` judges only and never deletes (exit 0 / 1 refused / 2 usage). `--real-trash` prints the first `trash` on PATH that is not a copy of the shim. `--show-config` prints floors, temp roots, timeout, real trash.                                                                                                                                                                 |
| `home/.local/bin/trash` (new, PATH shim)                      | Options before `--` pass through unchanged; `--` is dropped and later `-x` targets become `./-x` (`/usr/bin/trash` has no `--`); targets go to `trash-guard --check`; then `exec` of `--real-trash`. Refuses when the guard beside it or a real trash is missing. Carries the marker string `--real-trash` skips, so it never execs itself or another copy.                                                                           |
| `home/.local/bin/safe-rm` (changed)                           | Runs the guard BESIDE it (by `readlink -f "$0"`, same reason as the rm shim, W-20260929-A125) on the targets exactly as given, before its own checks, and refuses if the guard is missing. Uses `trash-guard --real-trash` instead of `command -v trash`, so the guard runs once per call and safe-rm cannot land on the shim. Existing container, sweep and survivor checks are untouched.                                           |
| `home/.claude/hooks/enforce-no-permanent-delete.sh` (changed) | New rule `trash-path`: denies `/usr/bin/trash` or any path to trash except `*/.local/bin/trash`, `command trash`, `env trash`, including inside `sh -c`, `eval`, `$( )`, `xargs`, `find -exec`. The denial names plain `trash` as the safe route. `trash` added to the lexer's prefilter word list, a raw trigger for unreadable payloads, a coverage sample, 13 deny arms and 5 allow arms in its own selftest, 3 `#M:` mutant tags. |
| `home/.local/bin/trash-guard-selftest` (new, bash 3.2)        | 161 arms, both routes, a fake trash, `--against DIR` for master, `--mutants`, `--e2e`.                                                                                                                                                                                                                                                                                                                                                |
| `home/.local/bin/safe-rm-selftest` (changed)                  | Section 7 copies safe-rm into a scratch bin; the copy now gets its trash-guard too (see 3.3).                                                                                                                                                                                                                                                                                                                                         |
| `docs/DELETION_SAFETY.md`                                     | New section "The trash guard" (the guard's refusal message points at it), rows in the call-path coverage table and the agent-guard table, and the remaining gaps.                                                                                                                                                                                                                                                                     |
| `docs/trash-guard/`                                           | BRIEF.md (username path scrubbed to `~` because the leak scanner blocked the commit; text otherwise as given), progress.md, this report.                                                                                                                                                                                                                                                                                              |

Commits: c851e08 guard+shim+safe-rm, c190950 hook, 8c8c9dc selftest (plus a bug fix it caught),
c40c48a arm classes, 7891aef safe-rm-selftest fixture, 5acc876 docs. VERIFIED (`git log
edf509f..HEAD`). End-of-stage `git-leak-scan --control` green and `git-leak-scan --since edf509f`
exit 0, 6 commits, 1,408 added lines scanned, before this report. VERIFIED.

The live links: `~/.local/bin/safe-rm`, `~/.local/bin/rm` and `~/.claude/hooks/enforce-no-permanent-delete.sh`
are stow symlinks into the MAIN checkout. VERIFIED (`ls -la`, `readlink -f`). So a merge to
master makes the rm route and the hook live at once. The `trash` shim is a new file and needs a
stow before a bare `trash` reaches it; until then `trash` is still `/usr/bin/trash`.
VERIFIED for the links; the stow need is inferred from how stow links new files (ASSUMED).

## 2. Every arm, with counts

### trash-guard-selftest (branch vs master)

Run sandboxed with the fake trash. VERIFIED (`trash-guard-selftest`, `trash-guard-selftest --against $TMPDIR/tg-master`,
where tg-master holds master's safe-rm, rm and hook from `git show master:...`, no shim, no guard).

|                                                                                         | Branch               | Master                |
| --------------------------------------------------------------------------------------- | -------------------- | --------------------- |
| All arms                                                                                | 161 passed, 0 failed | 32 passed, 126 failed |
| NEW arms (behaviour this change adds)                                                   | 130 passed, 0 failed | 1 passed, 126 failed  |
| CONTROL arms (must hold on both)                                                        | 31 passed, 0 failed  | 31 passed, 0 failed   |
| Refusal arms behaviourally safe (non-zero, nothing trashed, target kept), rule id aside | 104 of 104           | 14 of 104             |
| `trash X` and `rm -r X` gave the same verdict                                           | 68 of 68 cases       | (n/a)                 |

Master's count is 3 arms lower because sections 9 to 11 short-circuit with one FAIL each when
there is no guard or shim to ask.

The 1 NEW arm that passes on master: the rm route of "`--` then a `-name` target goes as ./-name";
master's safe-rm already did that rewrite. Its trash route fails on master.

The 14 master refusals that were already safe by behaviour, all on the rm route, from safe-rm's
existing `.`/`..`, `/` and home-container guards: `.`, `./`, `.//`, `sub/..`, `.` in temp, `..`,
`../..`, `..` in temp, `/`, `~`, `~/`, `~/.`, `~` as `../../home`, `~` through `link/`. They fail
the arm on master only because the rule id is missing. Every trash-route refusal and every
`~/CODE`, `~/CODE/CaptainCodeAU`, repo, worktree, search and blank refusal fails on master by
behaviour: the fake trash was called.

Arms (each runs on the trash route AND the rm route unless marked):

1. Blank: `''`, `""`, `' '`, tab-newline-space outside temp; `''` and `' '` inside a temp root. `[blank]`.
2. Current folder: `.`, `./`, `.//`, `sub/..`, by absolute path, with `/`, through a symlink with `/`,
   `.` and by path inside temp: `[cwd]`. `..`, a parent by absolute path, `../..`, `..` in temp: `[contains-cwd]`.
3. Floors on a fixture HOME: `/`; `~`, `~/`, `~/.`, `../../home`; `~/CODE`, `~/CODE/`, `$HOME/./CODE`,
   `../../home/CODE`; `~/CODE/CaptainCodeAU`, with `/`, `$HOME/CODE/./CaptainCodeAU`, `..` form; each
   of the three through a symlink with `/`. `[floor]`. CONTROL: a symlink to `~/CODE` without `/` is
   the link, goes, `~/CODE` untouched.
4. Outside temp: a repo root `[repo-root]`; a `.git` FILE root `[repo-root]`; a Scaffoldings-shaped
   folder holding `fifty-shades-of-dotfiles` `[nested-repo]`; a repo four levels down `[nested-repo]`.
   Repos made with real `git init`.
5. Worktrees (real `git worktree add`): `.worktree/wt` goes (CONTROL); one holding a nested repo
   `[nested-repo]`; `.git` pointing outside its repo `[repo-root]`; pointing into another repo's
   worktrees `[repo-root]`.
6. Temp: a repo root and a folder holding a repo inside a temp root go (CONTROL).
7. Search: fake delay 3 s refused `[search-timeout]` and answered under 2.9 s; `TRASH_GUARD_TIMEOUT=9`
   cannot raise the limit; `=0.5` lowers it (delay 1 s, under 1.5 s); no delay goes (CONTROL);
   mode-000 subfolder `[search-unreadable]`.
8. Controls and edges: plain temp folder goes with one fake call carrying its path; plain folder
   and file outside temp go; two targets with one repo: `[repo-root]`, nothing trashed; file plus
   blank: `[blank]`, nothing trashed; `-- -dash` goes as `./-dash`; `-- -repo` refused; `-v`
   passes through; missing target; broken symlink; symlink to a repo without `/` goes, with `/`
   refused; a repo named `a b` refused; a temp folder named `a<newline>b` goes with the exact path;
   a folder with a newline holding a repo refused; 20,000 folders searched and allowed in about
   0.8 s (CONTROL, timed).
9. Check mode on the REAL home (judges only): HOME unset, the account's home and `~/CODE` are
   `[floor]`; HOME set to the fixture, the real `~/CODE/CaptainCodeAU` is `[floor]`; `HOME=/nonexistent`,
   the real home is `[floor]`.
10. Seams: `TRASH_GUARD_TEMP_ROOTS=/Users:/:~:<fixture>` keeps only the fixture; `TRASH_GUARD_REAL_TRASH=/usr/bin/true`
    is refused on both routes, target in place.
11. Shim resolution: a symlink to the shim, a copy of it and the shim itself ahead of the fake on
    PATH are all skipped; control that the no-trash PATH has `sh` and no `trash`; with no real
    trash on PATH both routes refuse, target in place.
12. Hook payload arms: denies `/usr/bin/trash x`, `command trash x`, `env trash x`,
    `sh -c '/usr/bin/trash x'`, `eval 'command trash x'`, `echo $(env trash x)`, each naming plain
    `trash`; allows (CONTROL) `trash x`, `trash -v x`, `command -v trash`.
13. Both routes agreed.

### Other suites

| Suite                                                             | Result                                                 | Evidence |
| ----------------------------------------------------------------- | ------------------------------------------------------ | -------- |
| `enforce-no-permanent-delete.sh --selftest`                       | 547 passed, 0 failed                                   | VERIFIED |
| `enforce-no-permanent-delete.sh --mutants trash`                  | 6 caught, 0 missed of 6                                | VERIFIED |
| `enforce-secret-probe.sh --selftest` (shares the lexer)           | ALL ARMS PASS                                          | VERIFIED |
| `safe-rm-selftest` (unsandboxed: it uses the real Trash)          | 53 passed, 0 failed after the fixture fix; 51/2 before | VERIFIED |
| `trash-guard-selftest --e2e` (unsandboxed, real `/usr/bin/trash`) | 4 passed, 0 failed                                     | VERIFIED |

The e2e run: `--real-trash` resolves to `/usr/bin/trash`; the incident shape, `trash ''` from inside
a temp folder with the real trash behind the shim, is refused and the folder stays; a throwaway
temp file goes to the real Trash and `test -e` shows it gone; its folder is still there.

## 3. Mutants

`trash-guard-selftest --mutants` replaces one tagged line in a COPY with `:`, checks the tag
matched exactly one line before and none after (else INVALID), and runs the suite on the copy.
VERIFIED, 5 caught of 5:

| Mutant                                                                | Caught by |
| --------------------------------------------------------------------- | --------- |
| blank check removed                                                   | 14 arms   |
| cwd check removed                                                     | 18 arms   |
| timeout refusal removed (a timeout becomes an allow)                  | 12 arms   |
| temp exemption removed                                                | 4 arms    |
| hook: the `TRASH_VIA="env"` line deleted (env trash no longer denied) | 2 arms    |

The hook's own `--mutants trash` also caught all 6 of its trash-tagged lines (above).

### 3.3 A real bug the suite caught

`trash-guard --real-trash` honoured the seam by setting `_c`, then called `_init_temp`, which
reused `_c` (POSIX sh has no locals), so the seam check tested the wrong path and refused every
call. The first run showed it (every trash-route arm failed with the seam message). Fixed with
names used nowhere else; fixed before the first commit of the selftest. VERIFIED.

## 4. Edge cases

| Case                             | Behaviour                                                                                                                                                                                                                                                                                        | Evidence                                                                                                                                                      |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Multiple targets, one refused    | Nothing trashed, exit 1, every refusal printed                                                                                                                                                                                                                                                   | arms "two targets, one refused", "a file and a blank"; VERIFIED                                                                                               |
| `--` before a `-name`            | Shim drops `--`, passes `./-name`; safe-rm did already                                                                                                                                                                                                                                           | arms "-- then a -name"; VERIFIED                                                                                                                              |
| Target that does not exist       | Allowed (nothing to protect). Refused only when its parent exists but cannot be entered (`[unresolvable]`)                                                                                                                                                                                       | arm "does not exist"; VERIFIED                                                                                                                                |
| Broken symlink                   | Allowed; the link moves                                                                                                                                                                                                                                                                          | arm "a broken symlink goes"; VERIFIED                                                                                                                         |
| Symlink TO a repo root           | Without `/`: the link itself, allowed, repo untouched. With `/`: judged as the repo, refused. Why: trashing a link moves the link (safe-rm-selftest section 9 trashes a link to a fake home with the real trash and the home survives), so refusing it protects nothing and blocks ordinary work | arms in section 8, safe-rm-selftest 53/0; VERIFIED                                                                                                            |
| Path with spaces or a newline    | Judged exactly; the refusal quotes it; a newline name holding a repo is refused (fallback message when the match cannot be mapped to one target)                                                                                                                                                 | arms in section 8; VERIFIED                                                                                                                                   |
| `trash -v`-style options         | Passed through unchanged, in place                                                                                                                                                                                                                                                               | arm "-v passes through"; VERIFIED                                                                                                                             |
| HOME unset                       | The account's home from the user database stays on the floor list, with its CODE and CaptainCodeAU                                                                                                                                                                                               | section 9 (check mode); VERIFIED                                                                                                                              |
| Search hits an unreadable folder | `[search-unreadable]`, refused                                                                                                                                                                                                                                                                   | mode-000 arm; VERIFIED. The sandbox's `.ssh` deny does NOT trigger it: find lists `home/.ssh` with exit 0 (only contents are denied); VERIFIED (`find` on it) |
| Very large folder                | 20,000 folders: about 0.8 s, allowed. A real `node_modules` of 1,081 folders: 112 ms. `~/.nvm`: refused as a repo root in 24 ms. Bigger than the 2 s budget: `[search-timeout]`                                                                                                                  | timed arm, check-mode runs; VERIFIED                                                                                                                          |

## 5. Choices I made on my own

1. **The search seam is a delay, not a replaceable search command.** A settable search command
   would let anyone make "no repo found" the answer. `TRASH_GUARD_TEST_SEARCH_DELAY` can only
   cause a timeout. Same principle for all seams: `TRASH_GUARD_REAL_TRASH` is honoured only inside
   a system temp folder (so it cannot be pointed at `/bin/rm`), `TRASH_GUARD_TEMP_ROOTS` can only
   narrow, `TRASH_GUARD_TIMEOUT` can only lower, and HOME never unprotects the real home.
2. **`$TMPDIR` counts as a temp root only when it resolves under `/private/tmp`, `/tmp` or
   `/private/var/folders/`.** Otherwise `TMPDIR=$HOME` would exempt every repo in the home folder.
3. **A temp root itself is not exempt**, only paths strictly inside it.
4. **An unreadable folder during the search refuses** (`[search-unreadable]`), same reasoning as the
   timeout: unread is not absent.
5. **A symlink without a trailing slash is judged as the link** (rule 1 only), see edge cases. The
   brief says to resolve symlinks; I resolve every symlink on the way and the final one when it is
   named with `/`.
6. **Files skip resolution entirely** (a file cannot be a floor or hold the cwd), so a call with
   thousands of file operands costs no forks. Folders cost one `cd -P` each and ONE `find` per call
   with `-quit`, under one 2 s budget for the whole call.
7. **safe-rm asks `trash-guard --real-trash` instead of `command -v trash`.** With the shim stowed,
   `command -v trash` would find the shim and run the guard twice.
8. **The guard runs before safe-rm's own checks**, on the targets as given, because those checks
   drop missing targets and a blank argument is one. Side effect worth knowing: **`rm -f ""` now
   exits 1 with a refusal**, where it used to exit 0 silently. A script doing `rm -f "$maybe_empty"`
   will now fail. That is rule 1 on both routes as briefed, but it is a behaviour change callers will
   see. safe-rm's own messages for `.` and `..` are now the guard's.
9. **The hook's `trash-path` does not cover a PATH change before a bare `trash`** (`PATH=/usr/bin trash x`),
   although the rm rule does (`rm-lookup`). The brief listed three forms and said not to widen.
   Filed below as a candidate.
10. **Existing `safe-rm-selftest` ran outside the sandbox with the real Trash**, as it is designed
    to; it trashed only files in its own mktemp folder. It also calls `/bin/rm -rf` on its own temp
    folders internally (pre-existing; filing candidate below). I ran it because the brief asked for
    it; I did not call `/bin/rm` myself.
11. **BRIEF.md edited once**: `/Users/<name>/` scrubbed to `~/` because the leak scanner refused the
    commit (option 1 of its three). Meaning unchanged.
12. **Arm classes**: the two temp-folder "may go" cases are CONTROLS (they must pass on master too),
    and a timing arm passes only together with a timeout refusal, so neither passes on master by
    accident.

## 6. Left undone

- Not pushed, merged or stowed (brief rule 4). Needs Gavin: merge, then `stow` for the `trash`
  shim; the rm route and hook go live on merge alone (section 1).
- Linux/mlbox: not run (brief rule 7, filed separately).
- `sudo trash`: not measured.
- Markdown lint: the edit-time formatter ran on DELETION_SAFETY.md (it re-padded tables; a
  whitespace-blind word diff showed 0 words removed, 88 added); markdownlint itself was not run.
- Fixture folders left in `$TMPDIR` for the OS to reap (`trash-guard-selftest.*`, `tg-master`,
  `trash-guard-e2e.*`, `del-guard-selftest.*`).

## 7. Things worth filing (not filed by me)

1. `trash` after a PATH change in the same agent command is not denied (`PATH=/usr/bin trash x`,
   `export PATH=...; trash x`, `command -p` is covered only because every `command trash` is). The
   hook already tracks this for rm (`RM_LOOKUP`, `PATH_TOUCHED`); a one-line reuse would close it.
2. `sudo trash`: unmeasured whether sudo's PATH reaches the shim.
3. `safe-rm-selftest` calls `/bin/rm -rf` itself (`cleanup`, `newdir`, `seed_sweep`, and `/bin/rm -rf
"$FH"`), against the binding CLAUDE.md rule that no script calls the real deleter.
4. The trash route does not get safe-rm's wider container list (system folders, `~/Documents`,
   `~/Downloads` ...) or its sweep guard; only the floor list was briefed. Moving that list into
   trash-guard would make the two routes identical there too.
5. `rm -f "$EMPTY"` now fails where it used to succeed silently (choice 8). Worth a sweep of scripts
   that rely on it, or a note in the engage cleanup.
6. Two live sessions are both named `dotfiles-one` ([661bf1] and [42a009]); I addressed [661bf1]
   per the brief.

## Addendum: the blank ruling (2026-09-29, Gavin via dotfiles-one [661bf1])

**The ruling, in two messages.** On the rm route only (safe-rm, so the rm shim and the zsh `rm()`
too), a blank argument (`''`, `""`, whitespace only) goes back to master's behaviour: nothing is
trashed, the call exits 0 when nothing else is left, and other targets in the same call go ahead.
It prints exactly one stderr line per call, not one per blank:
`safe-rm: ignored a blank argument (empty variable?)`. The `trash` route is unchanged: `trash ''`
is refused with exit 1. The rest of rule 1 stays refused on both routes. This supersedes choice 8
and filing item 5 above.

**What changed.** `safe-rm` drops blanks before it calls the guard and prints the warning once
(two tagged lines, `#M: rm-blank-skip` and `#M: rm-blank-warn`). trash-guard itself is unchanged;
only its header comment now says the blank rule is in practice the trash route's.

A note on one corner: a blank is dropped, never passed on. On master, a file literally named
`' '` in the cwd would have been trashed by `rm ' '`. Now it is skipped with the warning. I took
"nothing trashed" in the ruling literally.

**Selftest changes.** The six blank cases now expect the trash route to refuse `[blank]`, and the
rm route to exit 0 with the cwd and a canary still there, the fake trash not called, and the
warning on stderr exactly once. `a file and a blank` now expects the rm route to trash the file.
New: `rm -r "" <tempdir>` (the rm route trashes the tempdir and ignores the blank; the trash route
refuses both), and `rm -f "" ""` (exit 0, nothing trashed, warning once). The 8 blank cases are
counted apart from the route-agreement check. Each must answer exactly REFUSED[blank] on the trash
route and ALLOWED on the rm route. I first wrote that check as "the routes differ", and master
passed it by accident, so I tightened it.

**Counts after the ruling.** All VERIFIED, commands named.

| Suite                                                  | Result                                                                                                                                               |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `trash-guard-selftest` (branch)                        | 174 passed, 0 failed (new 134/0, controls 40/0); routes agreed on 61 of 61; the 8 blank cases differed as ruled                                      |
| `trash-guard-selftest --against` master                | 41 passed, 130 failed (new 1 passed, 130 failed; controls 40 passed, 0 failed); the 1 is still the rm route's `-- -name`                             |
| `trash-guard-selftest --mutants`                       | 7 caught of 7: trash-guard blank (proves `trash ''` still refused), cwd, timeout, temp; safe-rm rm-blank-skip; safe-rm rm-blank-warn; hook env trash |
| `enforce-no-permanent-delete.sh --selftest`            | 547 passed, 0 failed                                                                                                                                 |
| `safe-rm-selftest` (unsandboxed)                       | 53 passed, 0 failed                                                                                                                                  |
| `trash-guard-selftest --e2e` (unsandboxed, real trash) | 4 passed, 0 failed; `trash ''` still refused with the folder intact                                                                                  |

The ruling's commit is 42a0f3c. The docs and this addendum come in the commit after it.
`docs/DELETION_SAFETY.md` has the blank row changed to "the trash route only", a paragraph on the
route difference, and the new evidence counts.

status: DONE
