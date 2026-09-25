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
# An unreadable payload whose raw text has builtin as a word is DENIED by name
# (D-20260925-A03).
CONV_TRIGGER_ERE='(^|[^A-Za-z0-9_.-])builtin([^A-Za-z0-9_-]|$)'
CONV_TRIGGER_WHAT='builtin'
CONV_UNREADABLE=deny

if [ ! -r "$CONV_LIB_DIR/conv-hooklib.sh" ]; then
  COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
  if printf '%s' "$COMMAND" | command grep -qE "$CONV_FALLBACK_ERE"; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"enforce-builtin: home/.claude/hooks/conv-hooklib.sh is missing from this repo, so it cannot check this builtin. builtin only works with zsh builtins (cd, echo, printf, etc.)."}}'
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
  conv_arm deny 'after env VAR="a b" (quoted value)' 'env FOO="a b" builtin foo'
  conv_arm deny 'after VAR="a b" (quoted value)'  'FOO="a b" builtin foo'
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
  echo "=== UNREADABLE arms: jq gone, truncated JSON, a moved key (D-20260925-A03) ==="
  conv_unreadable_arms deny 'builtin foo' 'echo mybuiltin builtins'
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
  _lf top   deny "broken lib (error at the top), the trigger: deny by name" 'builtin foo'
  _lf top   allow "broken lib (error at the top), no trigger: quiet" 'echo mybuiltin builtins'
  _lf end   deny "broken lib (error at the end, functions defined), the trigger: deny" 'builtin foo'
  _lf end   allow "broken lib (error at the end), no trigger: quiet" 'echo mybuiltin builtins'
  _lf noere allow "broken lib, no ERE in the hook: quiet, not deny-all" 'builtin foo'
  conv_selftest_end
fi

conv_hook_main
