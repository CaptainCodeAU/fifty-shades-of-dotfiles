#!/bin/bash
# Enforce uv for Python commands: REWRITE a clear slip, DENY an unclear one.
# Runs on PreToolUse for Bash.
#
# TRAVELS WITH pj (P5.6, 2026-09-21). Stowed to ~/.claude/hooks/ and declared once
# in settings/claude/hooks.json with targets ["project"]. The rule it enforces is
# machine-wide (OPERATIONAL_RULES.md Environment: `uv run python3`, never bare
# python3; the same sentence sits in every project CLAUDE.md). Audit line goes to
#   ${XDG_STATE_HOME:-~/.local/state}/dotfiles/hooks-security.log
# (BLOCKED lines for denials, REWROTE lines for rewrites).
#
# REWRITE, NOT DENY (ruled by Gavin 2026-09-23): a denial cost a whole round trip
# for a slip whose fix was never in doubt. Now the clear shapes are rewritten
# before they run and the session is told in one line (additionalContext):
#   python3 x.py         -> uv run python3 x.py      (also python, pytest, ruff)
#   pip install a b      -> uv add a b               (-r FILE kept)
#   pip uninstall -y a   -> uv remove a              (-y dropped: uv never prompts)
#   pip list|show|freeze|check -> uv pip ...
# at command position, after VAR=val, env VAR=val, time, nohup, noglob, nocorrect.
# Everything else that trips the rule is still DENIED with the old message: any
# other pip option, a path-prefixed or quoted binary, sudo/doas/exec/xargs/command
# in front, a command the scanner is unsure of, and a command that ALSO trips the
# pnpm rule (two rewriting hooks would race; conv-hooklib.sh has the two rules).
# A rewrite never touches text inside quotes, $(...), backticks or heredocs.
#
# The scanning is conv-shscan.awk and the plumbing conv-hooklib.sh, both beside
# this file. If the scanner is missing the hook still denies, by name.
#
# Measured before travelling (last 20 transcripts each): 0 of 51 Network_Plan and
# 1 of 245 win_go_app_test commands would have been denied, and that one was a
# bare `python3 -c`, which is the rule violation.
#
# The 'uv pip' exemption is NOT decoration. Before 2026-09-17 this rule anchored to
# start-of-line, so 'uv pip install' never reached it and the missing exemption was
# invisible. Widening the anchor exposed it by blocking a correct command. Any rule
# that widens must re-check its own exemptions. (The scanner now sees `pip` there as
# an ARGUMENT of uv, not a command, so the exemption is structural.)
#
# `--selftest` proves every arm, positive and negative. Exit 0 = all arms pass.
# CONV_HOOK_UNDER_TEST=<path> runs the same arms against another copy.

CONV_TAG=enforce-uv
CONV_MODE_NAME=uv
CONV_LIB_DIR="$(dirname "$0")"
CONV_LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/hooks-security.log"
CONV_FALLBACK_ERE='(^|[^A-Za-z0-9_./-])(python3?|pip3?|pytest|ruff)([^A-Za-z0-9_-]|$)'

if [ ! -r "$CONV_LIB_DIR/conv-hooklib.sh" ]; then
  # Not even the plumbing is here: deny a likely slip by name, allow the rest.
  COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
  if printf '%s' "$COMMAND" | command grep -qE "$CONV_FALLBACK_ERE"; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"enforce-uv: conv-hooklib.sh is missing beside the hook, so it cannot check this command; restow the dotfiles (home/.claude/hooks). Use uv run python / uv add meanwhile."}}'
  fi
  exit 0
fi
. "$CONV_LIB_DIR/conv-hooklib.sh"

# ---------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  conv_selftest_begin "$0"
  echo "=== REWRITE arms: the exact command that must run ==="
  conv_arm rewrite 'bare python3 script'          'python3 script.py'                    'uv run python3 script.py'
  conv_arm rewrite 'bare python'                  'python x.py'                          'uv run python x.py'
  conv_arm rewrite 'python3 -c, chained'          'git status && python3 -c "print(1)"'  'git status && uv run python3 -c "print(1)"'
  conv_arm rewrite 'env-prefixed python3'         'env FOO=1 python3 x.py'               'env FOO=1 uv run python3 x.py'
  conv_arm rewrite 'assignment-prefixed'          'FOO=1 python x.py'                    'FOO=1 uv run python x.py'
  conv_arm rewrite 'time python3'                 'time python3 x.py'                    'time uv run python3 x.py'
  conv_arm rewrite 'zsh noglob python3'           'noglob python3 x.py *.txt'            'noglob uv run python3 x.py *.txt'
  conv_arm rewrite 'python3 in a pipeline'        'ls | python3 -m json.tool'            'ls | uv run python3 -m json.tool'
  conv_arm rewrite 'zsh |& pipeline'              'python3 x.py |& tee log'              'uv run python3 x.py |& tee log'
  conv_arm rewrite 'zsh &! background'            'python3 x.py &!'                      'uv run python3 x.py &!'
  conv_arm rewrite 'two python3, both rewritten'  'python3 a.py; python3 b.py'           'uv run python3 a.py; uv run python3 b.py'
  conv_arm rewrite 'python3 in a subshell'        '(python3 x.py)'                       '(uv run python3 x.py)'
  conv_arm rewrite 'pytest inside if/then'        'if true; then pytest -q; fi'          'if true; then uv run pytest -q; fi'
  conv_arm rewrite 'fd redirection kept'          'python3 x.py 2>&1 | tee log'          'uv run python3 x.py 2>&1 | tee log'
  conv_arm rewrite 'heredoc body untouched'       $'python3 - <<EOF\nimport os; print("python3 pip")\nEOF'  $'uv run python3 - <<EOF\nimport os; print("python3 pip")\nEOF'
  conv_arm rewrite 'after a comment line'         $'# run it\npython3 x.py'              $'# run it\nuv run python3 x.py'
  conv_arm rewrite 'pip install'                  'pip install requests'                 'uv add requests'
  conv_arm rewrite 'pip3 install two packages'    'pip3 install requests "rich>=13"'     'uv add requests "rich>=13"'
  conv_arm rewrite 'pip install -r file'          'pip install -r requirements.txt'      'uv add -r requirements.txt'
  conv_arm rewrite 'pip uninstall -y'             'pip uninstall -y requests'            'uv remove requests'
  conv_arm rewrite 'pip3 list'                    'pip3 list'                            'uv pip list'
  conv_arm rewrite 'pip freeze'                   'pip freeze > req.txt'                 'uv pip freeze > req.txt'
  conv_arm rewrite 'bare pytest'                  'pytest'                               'uv run pytest'
  conv_arm rewrite 'pytest -q'                    'pytest -q'                            'uv run pytest -q'
  conv_arm rewrite 'bare ruff'                    'ruff check .'                         'uv run ruff check .'
  echo "=== DENY arms: a slip whose fix is not clear-cut ==="
  conv_arm deny 'pip install --upgrade'           'pip install --upgrade requests'
  conv_arm deny 'pip install -e .'                'pip install -e .'
  conv_arm deny 'pip install, no package'         'pip install'
  conv_arm deny 'pip download'                    'pip download x'
  conv_arm deny 'pip uninstall, no package'       'pip3 uninstall -y'
  conv_arm deny 'path-prefixed python3'           '/usr/bin/python3 x.py'
  conv_arm deny 'venv python'                     '.venv/bin/python -m pytest'
  conv_arm deny 'sudo python3'                    'sudo python3 x.py'
  conv_arm deny 'sudo -u root python3'            'sudo -u root python3 x.py'
  conv_arm deny 'xargs python3'                   'xargs python3 < files.txt'
  conv_arm deny 'command python3 (bypass)'        'command python3 x.py'
  conv_arm deny 'exec python3'                    'exec python3 x.py'
  conv_arm deny 'env -i python3'                  'env -i python3 x.py'
  conv_arm deny 'quoted "python3"'                '"python3" x.py'
  conv_arm deny 'escaped \python3'                '\python3 x.py'
  conv_arm deny 'unsure: case clause'             'case $x in a) python3 x.py ;; esac'
  conv_arm deny 'unsure: unterminated quote'      'python3 x.py "oops'
  conv_arm deny 'two conventions: + npm'          'python3 x.py && npm test'
  echo "=== ALLOW arms: look-alikes that must pass untouched ==="
  conv_arm allow 'uv run python3'                 'uv run python3 x.py'
  conv_arm allow 'uv pip install'                 'uv pip install x'
  conv_arm allow 'uv run pytest'                  'uv run pytest -q'
  conv_arm allow 'uv run ruff'                    'uv run ruff check .'
  conv_arm allow 'command -v probe'               'command -v python3'
  conv_arm allow 'which probe'                    'which python3'
  conv_arm allow 'bare interpreter, unchanged'    'python3'
  conv_arm allow 'python3.12, unchanged'          'python3.12 x.py'
  conv_arm allow 'a path argument'                'ls python3-stuff/ && grep -r pytest .'
  conv_arm allow 'inside $(...), unchanged'       'v=$(python3 -c "print(1)")'
  conv_arm allow 'prose in an echo'               'echo "python3 is banned here"'
  conv_arm allow 'prose in single quotes'         "echo 'pip install x; python3 y'"
  conv_arm allow 'here-string'                    'cat <<< "pip install x"'
  conv_arm allow 'prose in a heredoc'             $'git commit -F - <<EOF\nuse uv, not python3\nEOF'
  conv_arm allow 'commit message via $(heredoc)'  $'git commit -m "$(cat <<\'EOF\'\nrun python3 (not pip) here; it\'s fine\nEOF\n)"'
  conv_arm allow 'quoted ) inside $(...) (2026-09-23 false positive)' 'o=$(open-items add "title (no-cd, uv, pnpm) more" --done-when "... (cd into a subshell with builtin cd, python/pip to uv) ...");'
  conv_arm allow 'git -C'                         'git -C /x log --oneline -3'
  conv_arm allow 'control: harmless'              'echo control-ok'
  echo "=== FALLBACK arms: scanner missing, the rule still holds ==="
  export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  conv_arm deny  'scanner missing: slip denied'   'python3 x.py'
  conv_arm allow 'scanner missing: harmless ok'   'echo control-ok'
  unset CONV_SHSCAN
  conv_selftest_end
fi

conv_hook_main
