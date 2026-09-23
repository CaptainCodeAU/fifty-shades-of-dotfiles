#!/bin/bash
# Block builtin with non-builtins: only allow it with actual zsh builtins.
# Runs on PreToolUse for Bash. PROJECT-ONLY: registered in this repo's
# .claude/settings.json, like enforce-no-cd.sh beside it.
#
# `builtin <word>` fails in zsh unless <word> is a builtin, and an agent that
# learns "use builtin cd" tends to generalise it. The hook DENIES `builtin X` at
# command position when X is not on the list below.
#
# ON THE SHARED SCANNER SINCE 2026-09-23 (Gavin's proposal F). Until then it
# stripped "$(...)", "..." and '...' with sed and grepped the rest, which has the
# flaw the other convention hooks had: `s/\$\([^)]*\)//` stops at the first ")"
# even inside a quoted string, so `o=$(tool "a (b)" "(builtin foo)")` put the prose
# "(builtin foo" at command position and was DENIED. The sed strip also worked line
# by line, so a multi-line "..." commit message could do the same. The scanner is
# home/.claude/hooks/conv-shscan.awk (mode builtin), the plumbing conv-hooklib.sh,
# both reached through THIS REPO's path, as enforce-no-cd.sh does.
#
# Behaviour kept from the sed version: the allowed list, the prefixes it looks
# through (assignments; env sudo command nohup time exec doas xargs followed by
# options, assignments or plain words), a path-prefixed builtin, a quoted
# "builtin" ignored, nothing inside $(...) checked, a bare `builtin` allowed.
# Changed, all toward correctness: every builtin in the command is checked (the
# old one read only the first), `{ builtin x; }`, `if builtin x` and `! builtin x`
# are seen, and `builtin "echo"` is read as echo (the strip left the NEXT word).
#
# `--selftest` proves every arm, positive and negative. Exit 0 = all arms pass.
# CONV_HOOK_UNDER_TEST=<path> runs the same arms against another copy.

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
CONV_TAG=enforce-builtin
CONV_MODE_NAME=builtin
CONV_LIB_DIR="$HOOKS_DIR/../../home/.claude/hooks"
CONV_LOG_FILE="$HOOKS_DIR/security.log"
CONV_FALLBACK_ERE='(^|[;&|(][[:space:]]*)builtin[[:space:]]'

if [ ! -r "$CONV_LIB_DIR/conv-hooklib.sh" ]; then
  COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
  if printf '%s' "$COMMAND" | command grep -qE "$CONV_FALLBACK_ERE"; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"enforce-builtin: home/.claude/hooks/conv-hooklib.sh is missing from this repo, so it cannot check this builtin. builtin only works with zsh builtins (cd, echo, printf, etc.)."}}'
  fi
  exit 0
fi
. "$CONV_LIB_DIR/conv-hooklib.sh"

# ---------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  conv_selftest_begin "$0"
  echo "=== DENY arms (the sed version denied these too) ==="
  conv_arm deny 'builtin foo'                     'builtin foo'
  conv_arm deny 'builtin ls with args'            'builtin ls -la /tmp'
  conv_arm deny 'after &&'                        'git status && builtin grep x f'
  conv_arm deny 'after ;'                         'echo a; builtin make'
  conv_arm deny 'after |'                         'echo a | builtin cat'
  conv_arm deny 'after ('                         '(builtin git status)'
  conv_arm deny 'on a second line'                $'echo a\nbuiltin rg x'
  conv_arm deny 'after an assignment'             'FOO=1 builtin foo'
  conv_arm deny 'after env VAR=1'                 'env FOO=1 builtin foo'
  conv_arm deny 'after sudo -n'                   'sudo -n builtin foo'
  conv_arm deny 'after nohup'                     'nohup builtin foo'
  conv_arm deny 'after time'                      'time builtin foo'
  conv_arm deny 'after xargs -n1'                 'xargs -n1 builtin foo'
  conv_arm deny 'path-prefixed builtin'           '/usr/bin/builtin foo'
  conv_arm deny 'argument in a variable'          'builtin $cmd x'
  echo "=== ALLOW arms (the sed version allowed these too) ==="
  conv_arm allow 'builtin cd'                     'builtin cd /x && ls'
  conv_arm allow 'builtin echo'                   'builtin echo hi'
  conv_arm allow 'builtin print'                  'builtin print -r -- x'
  conv_arm allow 'builtin whence'                 'builtin whence -p gh'
  conv_arm allow 'builtin :'                      'builtin : noop'
  conv_arm allow 'builtin .'                      'builtin . ./env.sh'
  conv_arm allow '(builtin cd) subshell'          '(builtin cd /x && make)'
  conv_arm allow 'bare builtin, no argument'      'builtin'
  conv_arm allow 'the word in prose'              'echo builtin foo'
  conv_arm allow 'prose in double quotes'         'echo "use builtin foo"'
  conv_arm allow 'prose in single quotes'         "echo 'builtin foo'"
  conv_arm allow 'inside $(...)'                  'x=$(builtin foo); echo "$x"'
  conv_arm allow 'prose in a heredoc'             $'cat <<EOF\nbuiltin foo is wrong\nEOF'
  conv_arm allow 'quoted "builtin"'               '"builtin" foo'
  conv_arm allow 'a word containing builtin'      'mybuiltin foo; builtins x'
  conv_arm allow 'nested quotes inside "$(...)"'  'x="$(echo "a; builtin foo")"; echo "$x"'
  conv_arm allow 'heredoc inside $(...)'          $'git commit -m "$(cat <<\'EOF\'\nwe (builtin foo) here\nEOF\n)"'
  conv_arm allow 'control: harmless'              'echo control-ok'
  echo "=== FALSE-POSITIVE arms: the sed version DENIED these (fixed by the scanner) ==="
  conv_arm allow 'quoted ) inside $(...)'         'o=$(open-items add "title (a, b)" --done-when "x (builtin foo) y")'
  conv_arm allow 'multi-line "..." message'       $'git commit -m "first line\n; builtin foo is prose\nlast"'
  conv_arm allow 'builtin "echo" (quoted builtin)' 'builtin "echo" hi'
  echo "=== FALSE-NEGATIVE arms: the sed version ALLOWED these ==="
  conv_arm deny 'second builtin is the bad one'   'builtin cd /x; builtin foo'
  conv_arm deny 'inside { }'                      '{ builtin foo; }'
  conv_arm deny 'after if'                        'if builtin foo; then :; fi'
  conv_arm deny 'after !'                         '! builtin foo'
  echo "=== FALLBACK arms: scanner missing, the rule still holds ==="
  export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  conv_arm deny  'scanner missing: builtin denied' 'builtin foo'
  conv_arm allow 'scanner missing: harmless ok'   'echo control-ok'
  unset CONV_SHSCAN
  conv_selftest_end
fi

conv_hook_main
