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
#   py313 x.py           -> uv run --python 3.13 python x.py   (py310 to py313)
#   pipx install|uninstall|upgrade X -> uv tool ...; pipx run X -> uvx X;
#   pipx list -> uv tool list --show-paths; pipx upgrade-all -> uv tool upgrade --all
# (the py31x and pipx mappings are the .zshrc wrappers' own advice, 2026-09-23)
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
# ADVISORY on an unreadable payload (D-20260925-A03): when the raw text mentions
# python or pip, it WARNS that the rewrite could not run, and lets the command run.
# Never a deny: a broken jq must not halt all work.
CONV_TRIGGER_ERE='(^|[^A-Za-z0-9_.-])(python[0-9.]*|pip[0-9x]*|pytest|ruff|py3[0-9]+)([^A-Za-z0-9_-]|$)'
CONV_TRIGGER_WHAT='python or pip, so the uv rewrite could not run'
CONV_UNREADABLE=warn

if [ ! -r "$CONV_LIB_DIR/conv-hooklib.sh" ]; then
  # Not even the plumbing is here: deny a likely slip by name, allow the rest.
  COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
  if printf '%s' "$COMMAND" | command grep -qE "$CONV_FALLBACK_ERE"; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"enforce-uv: conv-hooklib.sh is missing beside the hook, so it cannot check this command; restow the dotfiles (home/.claude/hooks). Use uv run python / uv add meanwhile."}}'
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
  conv_arm rewrite 'py313 (wrapper advice)'       'py313 x.py'                           'uv run --python 3.13 python x.py'
  conv_arm rewrite 'py310 -c'                     'py310 -c "print(1)"'                  'uv run --python 3.10 python -c "print(1)"'
  conv_arm rewrite 'pipx install'                 'pipx install ruff'                    'uv tool install ruff'
  conv_arm rewrite 'pipx uninstall'               'pipx uninstall ruff'                  'uv tool uninstall ruff'
  conv_arm rewrite 'pipx upgrade'                 'pipx upgrade ruff'                    'uv tool upgrade ruff'
  conv_arm rewrite 'pipx run'                     'pipx run cowsay hi'                   'uvx cowsay hi'
  conv_arm rewrite 'pipx list'                    'pipx list'                            'uv tool list --show-paths'
  conv_arm rewrite 'pipx upgrade-all'             'pipx upgrade-all'                     'uv tool upgrade --all'
  echo "=== DENY arms: a slip whose fix is not clear-cut ==="
  conv_arm deny 'pip install --upgrade'           'pip install --upgrade requests'
  conv_arm deny 'pip install -e .'                'pip install -e .'
  conv_arm deny 'pip install, no package'         'pip install'
  conv_arm deny 'pip download'                    'pip download x'
  conv_arm deny 'pipx install with an option'     'pipx install --python 3.12 ruff'
  conv_arm deny 'pipx inject'                     'pipx inject ruff rich'
  conv_arm deny 'pipx run with an option'         'pipx run --spec x y'
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
  conv_arm allow 'bare py313, unchanged'          'py313'
  conv_arm allow 'uv tool install'                'uv tool install ruff && uvx cowsay hi'
  conv_arm allow 'a path argument'                'ls python3-stuff/ && grep -r pytest .'
  conv_arm allow 'inside $(...), unchanged'       'v=$(python3 -c "print(1)")'
  conv_arm allow 'prose in an echo'               'echo "python3 is banned here"'
  conv_arm allow 'prose in single quotes'         "echo 'pip install x; python3 y'"
  conv_arm allow 'here-string'                    'cat <<< "pip install x"'
  conv_arm allow 'prose in a heredoc'             $'git commit -F - <<EOF\nuse uv, not python3\nEOF'
  conv_arm allow 'commit message via $(heredoc)'  $'git commit -m "$(cat <<\'EOF\'\nrun python3 (not pip) here; it\'s fine\nEOF\n)"'
  conv_arm allow 'quoted ) inside $(...) (2026-09-23 false positive)' 'o=$(open-items add "title (no-cd, uv, pnpm) more" --done-when "... (cd into a subshell with builtin cd, python/pip to uv) ...");'
  conv_arm allow 'git -C'                         'git -C /x log --oneline -3'
  conv_arm allow 'multi-line "..." message (2026-09-23 false positive)' $'git commit -m "first line\n; pip install x is prose\nlast"'
  conv_arm allow 'nested quotes inside "$(...)"'  'x="$(echo "a; python3 b")"; echo "$x"'
  conv_arm allow 'control: harmless'              'echo control-ok'
  echo "=== FALLBACK arms: scanner missing, the rule still holds ==="
  export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  conv_arm deny  'scanner missing: slip denied'   'python3 x.py'
  conv_arm allow 'scanner missing: harmless ok'   'echo control-ok'
  unset CONV_SHSCAN
  echo "=== UNREADABLE arms: jq gone, truncated JSON, a moved key (D-20260925-A03) ==="
  conv_unreadable_arms warn 'python3 x.py' 'echo control-ok'
  conv_unreadable_arms warn 'pip install requests' 'ls pipeline-notes'
  echo "=== LOAD-FAILURE arms: conv-hooklib.sh beside the hook does not parse ==="
  # A copy of the hook under test beside a broken library: the error at the top
  # (nothing defined), at the end (functions defined, the source still returns 1),
  # and at the top with no ERE in the hook (must stay quiet, never deny all; a
  # pin, not a check: bash's =~ fails on an empty ERE, so it passes today even
  # without the [ -n "$_ere" ] line, measured 2026-09-25).
  # One fixed folder per shape, refreshed in place, so reruns leave nothing new.
  _lf() { # $1 top|end|noere, $2 deny|warn|allow, $3 label, $4 command
    local d="${TMPDIR:-/tmp}/$CONV_TAG-brokenlib-$1" h out got ok=0
    h="$d/home/.claude/hooks"
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
  _lf top   warn "broken lib (error at the top), the trigger: warn by name" 'python3 x.py'
  _lf top   allow "broken lib (error at the top), no trigger: quiet" 'echo control-ok'
  _lf end   warn "broken lib (error at the end, functions defined), the trigger: warn" 'python3 x.py'
  _lf end   allow "broken lib (error at the end), no trigger: quiet" 'echo control-ok'
  _lf noere allow "broken lib, no ERE in the hook: quiet, not deny-all" 'python3 x.py'
  conv_selftest_end
fi

conv_hook_main
