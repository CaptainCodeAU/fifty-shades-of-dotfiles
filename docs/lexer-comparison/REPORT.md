# Shell lexer comparison: the three lexers in home/.claude/hooks/

Item W-20260929-A50, ruling D-20260929-A19 (compare the three lexers before any
consolidation), then D-20260929-A24 (option B; these shapes become a shared test set).
Read-only research: no hook was changed. Everything here comes from `run.sh` in this
folder, which writes `cases.tsv` beside itself. Produced 2026-09-29 by a subagent of
session dotfiles-doer (a rerun: the first copy was lost to a reboot); written into this
file by that session. Two claims were re-run by hand with controls: `source <(...)`
passes the delete guard, and validate-bash denies harmless text inside `bash -c`.

| Lexer | Where it lives                                | Hook measured here                     | Trigger (denied in plain form) |
| ----- | --------------------------------------------- | -------------------------------------- | ------------------------------ |
| 1     | awk block in `enforce-no-permanent-delete.sh` | `enforce-no-permanent-delete.sh` (del) | `rm -P x`                      |
| 1     | same block, read at run time                  | `enforce-secret-probe.sh` (sec)        | `printenv GH_TOKEN`            |
| 2     | `conv-shscan.awk`                             | `validate-bash.sh` (vb)                | `git push --force origin main` |
| 3     | its own awk lexer                             | `enforce-gh-ssh-only.sh` (gh)          | `gh auth login`                |

**Method (VERIFIED, it is what run.sh does).** Black box through the real hooks, run
from <repo> with `/bin/bash` (GNU bash 3.2.57, the hooks' shebang) and jq 1.8.2.
Each command is sent as a PreToolUse payload on stdin
(`{tool_name:"Bash",tool_input:{command},cwd}`) and only
`.hookSpecificOutput.permissionDecision` (or exit 2) is read back. Logs go to
/dev/null (`DEL_GUARD_LOG`, `CONV_HOOK_LOG`, `GH_SSH_ONLY_LOG`) and `XDG_STATE_HOME`
points into `$TMPDIR`, so nothing lands in the repo. Hooks are never copied. Trigger
text lives only inside run.sh. Every call ran inside the Claude Bash sandbox; none
returned a sandbox refusal (every result was a clean deny or allow with exit 0; the
harness tags anything else `rc<N>` and none appeared).

Three row groups, 164 rows, each sent to all four hooks (656 hook calls + 12 controls):

- **S01-S70** wrap the trigger in an executing shape. Expected: deny.
- **D01-D24** put the trigger where it is data. Expected: allow.
- **N01-N70** repeat S01-S70 with a near-miss command that is allowed in plain form
  (`rm x`, `printenv HOME`, `git push --force origin feature`, `gh auth status`).
  Expected: allow. This separates "read the shape" from "saw scary text and denied".

State measured: repo HEAD `15ae41a`; sha256 prefixes: enforce-no-permanent-delete.sh
`75dc4f116377`, enforce-secret-probe.sh `bdb6eaf8329f`, validate-bash.sh `88eb8699c5cc`,
conv-shscan.awk `0cb6f37e177b`, conv-hooklib.sh `290dd5e96398`,
enforce-gh-ssh-only.sh `9ddf7e9d291c`.

## 1. Controls (VERIFIED)

run.sh refuses to write cases.tsv unless all twelve pass. All twelve passed.

| Hook | plain trigger | `echo ok` | plain near-miss | deny reason names                           |
| ---- | ------------- | --------- | --------------- | ------------------------------------------- |
| del  | deny          | allow     | allow           | `rm-P` (-P overwrites before unlinking)     |
| sec  | deny          | allow     | allow           | `RULE 5: printenv GH_TOKEN`                 |
| vb   | deny          | allow     | allow           | force push: "the refspec main updates main" |
| gh   | deny          | allow     | allow           | `gh-auth` (login/setup-git/refresh)         |

## 2. Shapes by hook

`ok` = expected answer. **MISS** = expected deny, got allow (false negative).
**FP** = expected allow, got deny (false positive). `ok*` (vb only) = denied, but by
validate-bash's fail-closed rule ("a git push that may force ... sits where
validate-bash cannot parse it (inside X)"), not by reading the command.
Exact per-hook commands and deny reasons are in cases.tsv.

| id  | shape                                       | expect | del      | sec      | vb       | gh       |
| --- | ------------------------------------------- | ------ | -------- | -------- | -------- | -------- |
| S01 | plain                                       | deny   | ok       | ok       | ok       | ok       |
| S02 | after ;                                     | deny   | ok       | ok       | ok       | ok       |
| S03 | after &&                                    | deny   | ok       | ok       | ok       | ok       |
| S04 | after \|\|                                  | deny   | ok       | ok       | ok       | ok       |
| S05 | after newline                               | deny   | ok       | ok       | ok       | ok       |
| S06 | backgrounded &                              | deny   | ok       | ok       | ok       | ok       |
| S07 | pipeline, right side                        | deny   | ok       | ok       | ok       | ok       |
| S08 | pipeline, left side                         | deny   | ok       | ok       | ok       | ok       |
| S09 | $(...)                                      | deny   | ok       | ok       | ok       | ok       |
| S10 | "$(...)" in double quotes                   | deny   | ok       | ok       | ok       | ok       |
| S11 | backticks                                   | deny   | ok       | ok       | ok*      | ok       |
| S12 | bash -c '...'                               | deny   | ok       | ok       | ok*      | ok       |
| S13 | sh -c "..."                                 | deny   | ok       | ok       | ok*      | ok       |
| S14 | zsh -c '...'                                | deny   | ok       | ok       | ok*      | ok       |
| S15 | bash -lc (clustered flag)                   | deny   | ok       | ok       | ok*      | ok       |
| S16 | eval "..."                                  | deny   | ok       | ok       | ok*      | ok       |
| S17 | eval unquoted words                         | deny   | ok       | ok       | ok*      | ok       |
| S18 | ( subshell )                                | deny   | ok       | ok       | ok       | ok       |
| S19 | { group; }                                  | deny   | ok       | ok       | ok       | ok       |
| S20 | f() { ...; }; f                             | deny   | **MISS** | **MISS** | ok       | ok       |
| S21 | function f { ...; }; f                      | deny   | **MISS** | **MISS** | ok       | **MISS** |
| S22 | if ...; then BODY; fi                       | deny   | ok       | ok       | ok       | ok       |
| S23 | if CONDITION; then                          | deny   | ok       | ok       | ok       | ok       |
| S24 | for body                                    | deny   | ok       | ok       | ok       | ok       |
| S25 | while body                                  | deny   | ok       | ok       | ok       | ok       |
| S26 | case arm                                    | deny   | ok       | ok       | ok       | ok       |
| S27 | ! negation                                  | deny   | ok       | ok       | ok       | ok       |
| S28 | [[ ]] && cmd                                | deny   | ok       | ok       | ok       | ok       |
| S29 | FOO=1 cmd                                   | deny   | ok       | ok       | ok       | ok       |
| S30 | redirection before the word                 | deny   | ok       | ok       | ok       | ok       |
| S31 | redirection after                           | deny   | ok       | ok       | ok       | ok       |
| S32 | env                                         | deny   | ok       | ok       | ok       | ok       |
| S33 | env -i                                      | deny   | ok       | ok       | ok       | ok       |
| S34 | command                                     | deny   | ok       | ok       | ok       | ok       |
| S35 | exec                                        | deny   | ok       | ok       | ok       | ok       |
| S36 | nohup                                       | deny   | ok       | ok       | ok       | ok       |
| S37 | sudo                                        | deny   | ok       | ok       | ok       | ok       |
| S38 | sudo -u x                                   | deny   | ok       | ok       | ok       | ok       |
| S39 | timeout 5                                   | deny   | ok       | ok       | **MISS** | ok       |
| S40 | nice -n 5                                   | deny   | ok       | ok       | **MISS** | ok       |
| S41 | time -p                                     | deny   | ok       | ok       | **MISS** | ok       |
| S42 | xargs                                       | deny   | ok       | ok       | ok       | ok       |
| S43 | caffeinate -i                               | deny   | ok       | **MISS** | **MISS** | ok       |
| S44 | stdbuf -oL                                  | deny   | ok       | **MISS** | **MISS** | ok       |
| S45 | watch -n 1                                  | deny   | ok       | **MISS** | **MISS** | ok       |
| S46 | /usr/bin/env bash -c                        | deny   | ok       | ok       | ok*      | **MISS** |
| S47 | script -q /dev/null                         | deny   | **MISS** | **MISS** | **MISS** | **MISS** |
| S48 | heredoc fed to bash (quoted marker)         | deny   | ok       | ok       | ok*      | ok       |
| S49 | heredoc fed to sh (unquoted marker)         | deny   | ok       | ok       | ok*      | ok       |
| S50 | cat <<'EOF' \| bash                         | deny   | ok       | ok       | ok*      | **MISS** |
| S51 | here-string bash <<<                        | deny   | ok       | ok       | ok*      | ok       |
| S52 | echo '...' \| bash                          | deny   | ok       | ok       | **MISS** | ok       |
| S53 | printf '...' \| sh                          | deny   | ok       | ok       | **MISS** | ok       |
| S54 | source <(echo ...)                          | deny   | **MISS** | **MISS** | **MISS** | **MISS** |
| S55 | . /dev/stdin <<<                            | deny   | **MISS** | **MISS** | **MISS** | **MISS** |
| S56 | process substitution <(cmd)                 | deny   | ok       | ok       | ok       | ok       |
| S57 | $(...) in unquoted heredoc to cat           | deny   | **MISS** | **MISS** | **MISS** | **MISS** |
| S58 | $'word' command word                        | deny   | ok       | ok       | **MISS** | ok       |
| S59 | 'word' single-quoted command word           | deny   | ok       | ok       | ok       | ok       |
| S60 | "word" double-quoted command word           | deny   | ok       | ok       | ok       | ok       |
| S61 | \word backslashed command word              | deny   | ok       | ok       | ok       | ok       |
| S62 | split word w''ord                           | deny   | ok       | ok       | ok       | ok       |
| S63 | absolute path command word                  | deny   | ok       | ok       | ok       | ok       |
| S64 | line continuation between words             | deny   | ok       | ok       | ok       | ok       |
| S65 | line continuation inside the word           | deny   | ok       | ok       | **MISS** | ok       |
| S66 | comment line before                         | deny   | ok       | ok       | ok       | ok       |
| S67 | $(...) nested twice                         | deny   | ok       | ok       | ok       | ok       |
| S68 | bash -c nested in bash -c                   | deny   | ok       | ok       | ok*      | ok       |
| S69 | eval of $(...) output                       | deny   | **MISS** | **MISS** | ok*      | **MISS** |
| S70 | & inside { group }                          | deny   | ok       | ok       | ok       | ok       |
| D01 | heredoc to cat (quoted marker)              | allow  | ok       | ok       | ok       | ok       |
| D02 | heredoc to cat (unquoted marker)            | allow  | ok       | ok       | ok       | ok       |
| D03 | $(...) text in quoted-marker heredoc to cat | allow  | ok       | ok       | ok       | ok       |
| D04 | double-quoted echo text                     | allow  | ok       | ok       | ok       | ok       |
| D05 | single-quoted echo text                     | allow  | ok       | ok       | ok       | ok       |
| D06 | unquoted echo arguments                     | allow  | ok       | ok       | ok       | ok       |
| D07 | git commit -m "..."                         | allow  | ok       | ok       | ok       | ok       |
| D08 | git commit -m '...'                         | allow  | ok       | ok       | ok       | ok       |
| D09 | git commit -F - with heredoc                | allow  | ok       | ok       | ok       | ok       |
| D10 | grep pattern                                | allow  | ok       | ok       | ok       | ok       |
| D11 | rg pattern                                  | allow  | ok       | ok       | ok       | ok       |
| D12 | sed pattern                                 | allow  | ok       | ok       | ok       | ok       |
| D13 | awk pattern                                 | allow  | ok       | ok       | ok       | ok       |
| D14 | for-list words                              | allow  | ok       | ok       | ok       | ok       |
| D15 | assignment X='...'                          | allow  | ok       | ok       | ok       | ok       |
| D16 | assignment X="..."                          | allow  | ok       | ok       | ok       | ok       |
| D17 | comment only                                | allow  | ok       | ok       | ok       | ok       |
| D18 | printf %s data                              | allow  | ok       | ok       | ok       | ok       |
| D19 | echo text redirected to a file              | allow  | ok       | ok       | ok       | ok       |
| D20 | echo text piped to cat                      | allow  | ok       | ok       | ok       | ok       |
| D21 | git log --grep=                             | allow  | ok       | ok       | ok       | ok       |
| D22 | quoted sh -c text inside echo               | allow  | ok       | ok       | ok       | ok       |
| D23 | jq --arg value                              | allow  | ok       | ok       | ok       | ok       |
| D24 | heredoc to tee a doc file                   | allow  | ok       | ok       | ok       | ok       |

**Near-miss rows N01-N70 (expect allow).** Only non-ok cells listed; every other
N cell was ok:allow (VERIFIED, cases.tsv).

| Hook | FP  | which                                                                                                                                                                                                 |
| ---- | --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| del  | 0   | (4 `pol`: N32 `env rm x`, N33 `env -i rm x`, N46 `/usr/bin/env bash -c 'rm x'`, N63 `/usr/bin/rm x`)                                                                                                  |
| sec  | 0   |                                                                                                                                                                                                       |
| vb   | 17  | N11-N17 (backticks, -c, -lc, eval), N20 N21 (both function forms), N26 (case arm), N46 (/usr/bin/env bash -c), N48-N51 (heredoc, here-string, cat ... \| bash), N68 (nested -c), N69 (eval of $(...)) |
| gh   | 0   |                                                                                                                                                                                                       |

The four del `pol` rows are denied by the named rules `rm-lookup` ("env, then rm")
and `rm-path` ("rm called by path"): plain rm routed past the Trash wrapper, that
hook's stated policy. Counted neither as FP nor as correct reads (reasons VERIFIED;
that this is intended policy is ASSUMED from the reason text).

_*Deny reasons (VERIFIED, cases.tsv why_* columns)._* No deny came from a crude
text fallback:

- del: `rm-P` in 66 S rows, `rm-lookup` in S32 S33 S46, `rm-path` in S63.
- sec: every one of its 60 S denies names `RULE 5`; 14 say where ("inside bash -c:",
  "inside eval:", "inside a shell reading stdin:").
- gh: every deny names `gh-auth`; 18 say "inside a nested shell body".
- vb: 42 name the refspec rule after reading the push; the 14 `ok*` rows name the
  fail-closed "cannot parse it (inside bash -c / eval / backticks / a here-document
  fed to bash)" rule. The N rows add "the command has a function definition" and
  "the command has a zsh construct case" as fail-closed triggers.

## 3. Per lexer: misses and false positives (VERIFIED counts)

Read correctly = S row denied by reading it (not ok*) and the matching N row allowed.

| Hook (lexer) | MISS of 70 | FP data, of 24 | FP near-miss, of 70 | S read correctly     |
| ------------ | ---------- | -------------- | ------------------- | -------------------- |
| del (1)      | 7          | 0              | 0 (+4 pol)          | 63                   |
| sec (1)      | 10         | 0              | 0                   | 60                   |
| gh (3)       | 8          | 0              | 0                   | 62                   |
| vb (2)       | 14         | 0              | 17                  | 42 (+14 fail-closed) |

- **Lexer 1 through del.** Misses: S20 f() {...}; f, S21 function f {...}; f,
  S47 script -q /dev/null, S54 source <(echo ...), S55 . /dev/stdin <<<, S57 $(...)
  in an unquoted heredoc to cat, S69 eval "$(echo '...')". FP: none.
- **Lexer 1 through sec.** del's seven plus S43 caffeinate -i, S44 stdbuf -oL,
  S45 watch -n 1. FP: none. Same lexer, different result: the three extra misses sit
  in the hook's prefix handling, not the lexer (VERIFIED that results differ; ASSUMED
  cause: rg finds no caffeinate or stdbuf in enforce-secret-probe.sh, five each in
  enforce-no-permanent-delete.sh).
- **Lexer 3 (gh).** Misses: S21, S46 /usr/bin/env bash -c, S47, S50 cat <<'EOF' | bash,
  S54, S55, S57, S69. Reads S20 f() {...}; f, which lexer 1 misses. FP: none.
- **Lexer 2 (vb).** Misses: S39 timeout 5, S40 nice -n 5, S41 time -p, S43, S44, S45,
  S47, S52 echo '...' | bash, S53 printf '...' | sh, S54, S55, S57, S58 $'git', S65
  continuation inside the word. FP: none on data shapes, 17 on near-miss shapes.
  Reads both function forms and the case arm when the push names main (S20 S21 S26
  deny with the refspec reason) but fails closed on the same constructs otherwise.
  Reads $(...) (S09 S10 S67 by the refspec reason) but fails closed on backticks (S11).
- **All four:** every data shape D01-D24 allowed.

## 4. Which reads most shapes, and what a shared lexer would need

**Most shapes read correctly: lexer 1 as used by enforce-no-permanent-delete.sh**:
63 of 70 executing shapes, 24 of 24 data shapes, 0 near-miss FP. Then lexer 3 (62),
lexer 1 through the secret guard (60), lexer 2 through validate-bash (42 read, 14 more
denied only by failing closed, 17 near-miss FP) (VERIFIED counts).

A shared lexer that loses nothing would need the union of what each gets right
(which hook reads which shape is VERIFIED; that the capability sits in the lexer
rather than the hook around it is ASSUMED, since this was black box):

- From lexer 1 (del): prefixes timeout, nice, time -p (vb misses), caffeinate,
  stdbuf, watch (vb and sec miss); echo '...' | bash and printf '...' | sh (vb misses);
  $'word' and a continuation inside the command word (vb misses); /usr/bin/env bash -c
  and cat <<'EOF' | bash (gh misses); reading backtick, -c, eval, heredoc and
  here-string bodies instead of failing closed (vb's 17 near-miss FP).
- From lexer 2 (vb): the function f { ...; }; f form (del, sec, gh miss) and the
  f() { ...; }; f form (del, sec miss). vb then fails closed on both when nothing
  names main, so the reading is in the scanner and the FP is the hook's policy on top
  (ASSUMED from the two reason texts).
- From lexer 3 (gh): the f() { ...; }; f form (del, sec miss).
- Only vb, and only by failing closed: eval "$(echo '...')" (S69).
- **No hook handles:** S47 script -q /dev/null CMD, S54 source <(echo '...'),
  S55 . /dev/stdin <<< '...', S57 $(...) inside an unquoted heredoc body fed to cat
  (bash runs that substitution; the quoted-marker form D03 correctly stays data).
  Filed as W-20260929-A118.
- Keep what all four already share: all 24 data shapes allowed.

## 5. What could not be tested, or was not

- **The lexers in isolation.** Only whole hooks were measured, so each result includes
  the hook's own prefix and body handling; del and sec share lexer 1 and still differ
  on three rows (VERIFIED). gh keeps a regex floor that runs before its lexer; black
  box cannot split them (ASSUMED from its header).
- **Other consumers of lexer 2** (enforce-uv, enforce-pnpm, enforce-no-reset-by-name,
  enforce-pj-workers, the repo's .claude/hooks/enforce-no-cd.sh and enforce-builtin.sh)
  were not run. vb's fail-closed rule is its own policy (ASSUMED the others share the
  scanner's reading, not that policy).
- **One trigger per hook.** Other rules (rm -rf ~, gh config set, env dumps,
  git reset --hard) may read shapes differently (ASSUMED representative).
- **Expected answers come from shell semantics, not execution**: no trigger was run.
  That watch and script run their arguments, that $'rm' is rm, that source <(...) and
  $(...) in an unquoted heredoc execute, is ASSUMED from bash/zsh behaviour.
- **Shapes not in the set**: a command word in a variable (c=...; $c), find -exec,
  python -c / perl -e calling system, git -c alias.x='!...', ssh host 'cmd', make, trap,
  an alias defined in the same command, zsh-only forms (=cmd, noglob, anonymous
  functions () { }, ${(z)...}), until/select, <<- heredocs, two heredocs on one line,
  nesting deeper than del's MAX_DEPTH=4.
- **Aliases**: del loads aliases from the live shell snapshots; the default snapshot
  directory was used and alias-dependent shapes were not varied.
- **Unreadable payloads** (no jq, bad JSON, moved field) and branch-dependent vb forms
  (a push with no refspec, which reads the cwd's branch) were not tested.
- Speed was not measured.
