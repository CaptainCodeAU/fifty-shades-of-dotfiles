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
# a command the scanner is unsure of, and a command that ALSO trips the uv or pnpm
# rule (two rewriting hooks would race; conv-hooklib.sh has the two rules).
# Allowed untouched: `builtin cd`, cd inside $(...), and cd written as prose in
# quotes, heredocs and commit messages.
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

if [ ! -r "$CONV_LIB_DIR/conv-hooklib.sh" ]; then
  COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
  if printf '%s' "$COMMAND" | command grep -qE "$CONV_FALLBACK_ERE"; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"enforce-no-cd: home/.claude/hooks/conv-hooklib.sh is missing from this repo, so it cannot check this command. Do not use cd: use absolute paths, git -C <path>, or builtin cd."}}'
  fi
  exit 0
fi
. "$CONV_LIB_DIR/conv-hooklib.sh"

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
  conv_arm deny 'cd inside a subshell (as before)' '(cd /x && make)'
  conv_arm deny 'cd inside { } (as before)'       '{ cd /x; make; }'
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
  echo "=== FALLBACK arms: scanner missing, the rule still holds ==="
  export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  conv_arm deny  'scanner missing: slip denied'   'cd /x && ls'
  conv_arm allow 'scanner missing: harmless ok'   'echo control-ok'
  unset CONV_SHSCAN
  conv_selftest_end
fi

conv_hook_main
