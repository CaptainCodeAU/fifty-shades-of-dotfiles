#!/bin/bash
# No bare cd: REWRITE a leading `cd DIR && rest` into a subshell, DENY the rest.
# Runs on PreToolUse for Bash. PROJECT-ONLY: registered in this repo's
# .claude/settings.json and nowhere else (ruled 2026-09-21, P5.6).
#
# WHY. The Bash tool's working directory persists between calls, so a bare cd
# silently moves every later command. The rule is: absolute paths, git -C, or
# `builtin cd` when a change is truly needed.
#
# REWRITE, NOT DENY (ruled by Gavin 2026-09-23). A LEADING cd followed by more
# commands is rewritten so the change cannot outlive the call:
#   cd DIR && rest   ->   (builtin cd DIR && rest
#                         )
#   cd DIR; rest     ->   (builtin cd DIR; rest
#                         )                        (also a newline after cd DIR)
# The closing ) goes on its own line so a trailing comment or a here-document at
# the end cannot swallow it. Measured in zsh 5.9: same output, same exit status
# (0, 1, 7, a failed cd), same globbing, and the session's PWD is unchanged.
# The .zshrc aliases that expand to cd (.. ... .... ..... ~) are the same shape and
# are rewritten the same way; the hook sees the typed text, before alias expansion.
# The live aliases that also change directory but cannot be rewritten safely are
# DENIED: - (cd -), 1..9 (cd -N, oh-my-zsh), grt (cd to the git top level).
#
# STILL DENIED, as before: a cd that is not the first command, more than one cd,
# `cd` alone, `cd -`, `cd` with options or two arguments, `cd DIR || ...`,
# `cd DIR | ...`, a command with a background & anywhere, a quoted or escaped cd,
# a cd inside a { } group (it runs in the CURRENT shell: measured in zsh 5.9,
# `{ cd /tmp; }; pwd` prints /tmp), a command the scanner is unsure of, and a
# command that ALSO trips the uv or pnpm rule (two rewriting hooks would race;
# conv-hooklib.sh has the two rules).
# Allowed untouched: `builtin cd`, cd inside $(...), cd written as prose in
# quotes, heredocs and commit messages, and (since 2026-09-23, Gavin's proposal E)
# any cd inside an explicit ( ) subshell such as `(cd /x && make)`: a subshell's cd
# cannot outlive it (measured: `( cd /tmp ); pwd` prints the old directory). A cd
# OUTSIDE the subshell in the same command is still judged as above.
#
# The scanning is home/.claude/hooks/conv-shscan.awk and the plumbing
# home/.claude/hooks/conv-hooklib.sh, reached through THIS REPO's path (the hook is
# project-only, so the repo is always there). Audit lines go to security.log
# beside this file, BLOCKED for denials and REWROTE for rewrites.
#
# `--selftest` proves every arm, positive and negative. Exit 0 = all arms pass.
# CONV_HOOK_UNDER_TEST=<path> runs the same arms against another copy.

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
CONV_TAG=enforce-no-cd
CONV_MODE_NAME=nocd
CONV_LIB_DIR="$HOOKS_DIR/../../home/.claude/hooks"
CONV_LOG_FILE="$HOOKS_DIR/security.log"
CONV_FALLBACK_ERE='(^|[;&|(][[:space:]]*)cd[[:space:]]'
# An unreadable payload (jq gone, truncated JSON, a moved key) cannot be rewritten
# safely, so a raw text with cd as a word is DENIED by name (D-20260925-A03).
CONV_TRIGGER_ERE='(^|[^A-Za-z0-9_.-])cd([^A-Za-z0-9_-]|$)'
CONV_TRIGGER_WHAT='a cd'
CONV_UNREADABLE=deny

if [ ! -r "$CONV_LIB_DIR/conv-hooklib.sh" ]; then
  COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
  if printf '%s' "$COMMAND" | command grep -qE "$CONV_FALLBACK_ERE"; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"enforce-no-cd: home/.claude/hooks/conv-hooklib.sh is missing from this repo, so it cannot check this command. Do not use cd: use absolute paths, git -C <path>, or builtin cd."}}'
  fi
  exit 0
fi
. "$CONV_LIB_DIR/conv-hooklib.sh"
# conv-hooklib.sh FAILED TO LOAD (W-20260924-A76). One syntax error is enough;
# then the library's functions are "command not found", rc 127, and the hook
# fails open in silence. `.` returns non-zero on any syntax error (measured on
# 3.2.57, even when the functions got defined), and an error at the TOP leaves
# none defined; so check the status AND every function the hook needs at run
# time. No lib function and no jq below. Same rule as an unreadable payload: a
# guard denies, CONV_UNREADABLE=warn warns, and only when the raw text looks like
# the trigger. The EREs are read with ${V-} (an unset one must not crash under
# set -u), and with none set at all the hook stays quiet. bash's =~ already
# refuses an empty ERE (rc 2, measured on 3.2.57 and 5.3.20), but grep -E ''
# matches everything, so the check keeps "no ERE = no deny" true whichever
# matcher this ever uses. (Snippet: a76-guardsa e21de08.)
_conv_rc=$?
if [ "$_conv_rc" -ne 0 ] || ! declare -F conv_hook_main conv_unreadable conv_scan conv_deny conv_log conv_json_str >/dev/null 2>&1; then
  [ "${1:-}" = "--selftest" ] && { echo "FAIL  conv-hooklib.sh failed to load beside $0 (rc=$_conv_rc)"; exit 1; }
  _raw=$(sed -e 's/\\[nrt]/ /g' -e 's/\\"/"/g')
  _ere="${CONV_TRIGGER_ERE-}"; [ -n "$_ere" ] || _ere="${CONV_FALLBACK_ERE-}"
  [ -n "$_ere" ] || exit 0
  [[ $_raw =~ $_ere ]] || exit 0
  _why="$CONV_TAG: conv-hooklib.sh failed to load (rc=$_conv_rc), so this command was not checked, and it mentions its trigger"
  if [ "${CONV_UNREADABLE:-deny}" = warn ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s. It runs unchecked. Run /bin/bash -n on conv-hooklib.sh, then restow the dotfiles."}}\n' "$_why"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s; denying. Run /bin/bash -n on conv-hooklib.sh, then restow the dotfiles."}}\n' "$_why"
  fi
  exit 0
fi

# ---------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  conv_selftest_begin "$0"
  echo "=== REWRITE arms: the exact command that must run ==="
  conv_arm rewrite 'cd DIR && rest'               'cd /tmp && ls'                        $'(builtin cd /tmp && ls\n)'
  conv_arm rewrite 'cd DIR; rest'                 'cd /tmp; ls -la'                      $'(builtin cd /tmp; ls -la\n)'
  conv_arm rewrite 'cd DIR, newline, rest'        $'cd /tmp\ngit status'                 $'(builtin cd /tmp\ngit status\n)'
  conv_arm rewrite 'quoted dir with a space'      'cd "/a b" && ls'                      $'(builtin cd "/a b" && ls\n)'
  conv_arm rewrite 'dir from a variable'          'cd "$HOME/x" && make'                 $'(builtin cd "$HOME/x" && make\n)'
  conv_arm rewrite 'rest is a pipeline'           'cd /x && git log | head -5'           $'(builtin cd /x && git log | head -5\n)'
  conv_arm rewrite 'trailing comment kept inside' 'cd /x && ls # look'                   $'(builtin cd /x && ls # look\n)'
  conv_arm rewrite 'rest ends in a heredoc'       $'cd /x && cat <<EOF\ncd is prose here\nEOF'  $'(builtin cd /x && cat <<EOF\ncd is prose here\nEOF\n)'
  conv_arm rewrite 'zsh glob qualifier in rest'   'cd /x && print -l *(.)'               $'(builtin cd /x && print -l *(.)\n)'
  conv_arm rewrite 'alias ..'                     '.. && ls'                             $'(builtin cd .. && ls\n)'
  conv_arm rewrite 'alias ...'                    '...; pwd'                             $'(builtin cd ../..; pwd\n)'
  conv_arm rewrite 'alias ~'                      '~ && ls'                              $'(builtin cd ~ && ls\n)'
  echo "=== DENY arms: a cd whose fix is not clear-cut ==="
  conv_arm deny 'cd alone'                        'cd /tmp'
  conv_arm deny 'cd with nothing after ;'         'cd /tmp;'
  conv_arm deny 'cd -'                            'cd - && ls'
  conv_arm deny 'cd -P'                           'cd -P /x && ls'
  conv_arm deny 'cd with two arguments'           'cd a b && ls'
  conv_arm deny 'cd not first'                    'git status && cd /x && ls'
  conv_arm deny 'two cds'                         'cd /a && cd /b && ls'
  conv_arm deny 'cd ||'                           'cd /x || exit 1'
  conv_arm deny 'cd in a pipeline'                'cd /x | cat'
  conv_arm deny 'background & anywhere'           'cd /x && sleep 5 &'
  conv_arm deny 'zsh &! background'               'cd /x && sleep 5 &!'
  conv_arm deny 'cd inside { } (it persists)'     '{ cd /x; make; }'
  conv_arm deny '{ } cd feeding a pipe'           '{ cd /x; make; } | cat'
  conv_arm deny 'top-level cd after a ( ) cd'     '(cd /x && make) && cd /y && ls'
  conv_arm deny '( ) then a { } cd'               '(cd /x); { cd /y; ls; }'
  conv_arm deny 'unsure: ( ) cd with a case'      '(cd /x && case $a in b) ls ;; esac)'
  conv_arm deny 'quoted "cd"'                     '"cd" /x && ls'
  conv_arm deny 'command cd'                      'command cd /x && ls'
  conv_arm deny 'env-prefixed cd'                 'FOO=1 cd /x && ls'
  conv_arm deny 'alias .. alone'                  '..'
  conv_arm deny 'alias - (cd -)'                  '- && ls'
  conv_arm deny 'alias 2 (cd -2)'                 '2; git status'
  conv_arm deny 'alias grt (cd to top level)'     'grt && ls'
  conv_arm deny 'unsure: case clause'             'cd /x && case $a in b) ls ;; esac'
  conv_arm deny 'two conventions: + python3'      'cd /x && python3 a.py'
  conv_arm deny 'two conventions: + npm'          'cd /x && npm test'
  echo "=== ALLOW arms: look-alikes that must pass untouched ==="
  conv_arm allow 'builtin cd'                     'builtin cd /x && ls'
  conv_arm allow '(builtin cd) subshell'          '(builtin cd /x && make)'
  conv_arm allow 'git -C'                         'git -C /x status'
  conv_arm allow 'cd inside $(...)'               'x=$(cd /x && pwd); echo "$x"'
  conv_arm allow 'prose in an echo'               'echo "cd /x && ls"'
  conv_arm allow 'prose in single quotes'         "echo 'then cd into it'"
  conv_arm allow 'prose in a heredoc'             $'git commit -F - <<EOF\ncd into the repo first\nEOF'
  conv_arm allow 'commit message via $(heredoc)'  $'git commit -m "$(cat <<\'EOF\'\nwe cd (into it) here; don\'t worry\nEOF\n)"'
  conv_arm allow 'quoted ) inside $(...) (2026-09-23 false positive)' 'o=$(open-items add "title (no-cd, uv, pnpm) more" --done-when "... (cd into a subshell with builtin cd, python/pip to uv) ...");'
  conv_arm allow 'multi-line "..." message'       $'git commit -m "first line\n; cd /x && ls is prose\nlast"'
  conv_arm allow 'a word containing cd'           'abcd /x && ls; git add cdrom.txt'
  conv_arm allow 'digits and - as arguments'      'sleep 2 && head -3 f && git diff - <<< x'
  conv_arm allow 'uv run, no cd'                  'uv run python3 x.py'
  conv_arm allow 'nested quotes inside "$(...)"'  'x="$(echo "a; cd /tmp && ls")"; echo "$x"'
  conv_arm allow 'control: harmless'              'echo control-ok'
  echo "=== SUBSHELL arms (proposal E): a cd inside ( ) cannot persist ==="
  conv_arm allow '(cd DIR && make)'               '(cd /x && make)'
  conv_arm allow '(cd DIR; make) into a pipe'     '(cd /x; make) | cat'
  conv_arm allow 'subshell after another command' 'make && (cd /x && ls)'
  conv_arm allow 'subshell in the background'     '(cd /x && make) &'
  conv_arm allow '{ } nested inside ( )'          '( { cd /x; make; } )'
  conv_arm allow 'alias .. inside ( )'            '(.. && ls)'
  conv_arm allow 'alias 2 inside ( )'             '( 2 && ls )'
  conv_arm allow 'zsh glob qualifier inside ( )'  '(cd /x && print -l *(.))'
  conv_arm allow 'multi-line subshell'            $'(\n  cd /x\n  make\n)'
  echo "=== FALLBACK arms: scanner missing, the rule still holds ==="
  export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  conv_arm deny  'scanner missing: slip denied'   'cd /x && ls'
  conv_arm allow 'scanner missing: harmless ok'   'echo control-ok'
  unset CONV_SHSCAN
  echo "=== UNREADABLE arms: jq gone, truncated JSON, a moved key (D-20260925-A03) ==="
  # With cd: deny, never a rewrite built from a payload that was not read.
  # Without: `echo abcd` holds the letters cd inside a word, and stays quiet.
  conv_unreadable_arms deny 'cd /tmp && ls' 'echo abcd'
  echo "=== LOAD-FAILURE arms: conv-hooklib.sh beside the hook does not parse ==="
  # A copy of the hook under test beside a broken library: the error at the top
  # (nothing defined), at the end (functions defined, the source still returns 1),
  # and at the top with no ERE in the hook (must stay quiet, never deny all; a
  # pin, not a check: bash's =~ fails on an empty ERE, so it passes today even
  # without the [ -n "$_ere" ] line, measured 2026-09-25).
  # One fixed folder per shape, refreshed in place, so reruns leave nothing new.
  _lf() { # $1 top|end|noere, $2 deny|warn|allow, $3 label, $4 command
    local d="${TMPDIR:-/tmp}/$CONV_TAG-brokenlib-$1" h out got ok=0
    h="$d/.claude/hooks"
    mkdir -p "$h" "$d/home/.claude/hooks"
    if [ "$1" = noere ]; then
      sed -e '/^CONV_TRIGGER_ERE=/d' -e '/^CONV_FALLBACK_ERE=/d' "$_st_hook" > "$h/hook.sh"
    else
      cp "$_st_hook" "$h/hook.sh"
    fi
    chmod +x "$h/hook.sh"
    cp "$CONV_LIB_DIR/conv-shscan.awk" "$d/home/.claude/hooks/"
    if [ "$1" = end ]; then
      { cat "$CONV_LIB_DIR/conv-hooklib.sh"; echo 'broken() { if then; }'; } > "$d/home/.claude/hooks/conv-hooklib.sh"
    else
      { echo 'broken() { if then; }'; cat "$CONV_LIB_DIR/conv-hooklib.sh"; } > "$d/home/.claude/hooks/conv-hooklib.sh"
    fi
    _st_n=$((_st_n + 1))
    out=$(conv_payload "$4" | jq -c . | CONV_HOOK_LOG=/dev/null "$h/hook.sh" 2>/dev/null)
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput | "\(.permissionDecision) \(.permissionDecisionReason // .additionalContext)"' 2>/dev/null)
    case "$2" in
      deny)  case "$got" in "deny $CONV_TAG: conv-hooklib.sh failed to load (rc="*) ok=1 ;; esac ;;
      warn)  case "$got" in "null $CONV_TAG: conv-hooklib.sh failed to load (rc="*) ok=1 ;; esac ;;
      allow) [ -z "$out" ] && ok=1 ;;
    esac
    if [ "$ok" -eq 1 ]; then printf 'ok    %-7s %s\n' "$2" "$3"
    else printf 'FAIL  %-7s %s\n        got: %s\n' "$2" "$3" "${got:-${out:-<no output>}}"; _st_fails=$((_st_fails + 1)); fi
  }
  _lf top   deny "broken lib (error at the top), the trigger: deny by name" 'cd /tmp && ls'
  _lf top   allow "broken lib (error at the top), no trigger: quiet" 'echo abcd'
  _lf end   deny "broken lib (error at the end, functions defined), the trigger: deny" 'cd /tmp && ls'
  _lf end   allow "broken lib (error at the end), no trigger: quiet" 'echo abcd'
  _lf noere allow "broken lib, no ERE in the hook: quiet, not deny-all" 'cd /tmp && ls'
  conv_selftest_end
fi

conv_hook_main
