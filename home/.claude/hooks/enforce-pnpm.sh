#!/bin/bash
# Enforce pnpm for Node.js commands: REWRITE a clear slip, DENY an unclear one.
# Runs on PreToolUse for Bash.
#
# TRAVELS WITH pj (P5.6, 2026-09-21). Stowed to ~/.claude/hooks/ and declared once
# in settings/claude/hooks.json with targets ["project"]. The rule is the dotfiles
# package-manager policy (npm and yarn are also blocked by .zshrc wrappers in every
# interactive shell; this hook is the Bash-tool half). Audit line goes to
#   ${XDG_STATE_HOME:-~/.local/state}/dotfiles/hooks-security.log
# (BLOCKED lines for denials, REWROTE lines for rewrites).
#
# REWRITE, NOT DENY (ruled by Gavin 2026-09-23). Only shapes where pnpm is a
# drop-in are rewritten, and the session is told in one line:
#   npm install | npm i          -> pnpm install | pnpm i
#   npm install|i|add <pkgs>     -> pnpm add <pkgs>      (-D -E -g and long forms)
#   npm uninstall|remove|rm <p>  -> pnpm remove <p>      (-g)
#   npm run <script>             -> pnpm run <script>    (no extra arguments)
#   npm test|t|start             -> pnpm test|start      (no extra arguments)
#   yarn | yarn install          -> pnpm install
#   yarn add|remove|run|dlx|test|start ... -> pnpm ...   (same limits)
#   npx [-y] <pkg> [args]        -> pnpm dlx <pkg> [args]
# Everything else is still DENIED: npm ci (pnpm has no ci; the message names
# `pnpm install --frozen-lockfile`), other subcommands and options, extra script
# arguments, a quoted or path-prefixed binary, sudo/xargs/exec/command in front,
# pnpm link --global (unchanged), a command the scanner is unsure of, and a
# command that ALSO trips the uv rule (two rewriting hooks would race).
#
# NPX IS DENIED WHEN IT MAY MEAN A LOCAL BINARY. `npx tsc` in a project runs the
# local node_modules/.bin/tsc; `pnpm dlx tsc` always fetches from the registry,
# where "tsc" is an unrelated package. So an npx target found in
# node_modules/.bin of the payload's cwd or any parent, or any npx after a cd in
# the same command, is denied with both forms named (pnpm exec / pnpm dlx).
#
# The scanning is conv-shscan.awk and the plumbing conv-hooklib.sh, both beside
# this file. If the scanner is missing the hook still denies, by name.
#
# Measured before travelling (last 20 transcripts each): 0 of 51 Network_Plan and
# 0 of 245 win_go_app_test commands would have been denied.
#
# `--selftest` proves every arm, positive and negative. Exit 0 = all arms pass.
# CONV_HOOK_UNDER_TEST=<path> runs the same arms against another copy.

CONV_TAG=enforce-pnpm
CONV_MODE_NAME=pnpm
CONV_LIB_DIR="$(dirname "$0")"
CONV_LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/hooks-security.log"
CONV_FALLBACK_ERE='(^|[^A-Za-z0-9_./-])(npm|yarn|npx)([^A-Za-z0-9_-]|$)'
# ADVISORY on an unreadable payload (D-20260925-A03): when the raw text mentions
# npm, npx or yarn, it WARNS that the rewrite could not run, and lets the command
# run. Never a deny: a broken jq must not halt all work.
CONV_TRIGGER_ERE='(^|[^A-Za-z0-9_.-])(npm|npx|yarn)([^A-Za-z0-9_-]|$)'
CONV_TRIGGER_WHAT='npm, npx or yarn, so the pnpm rewrite could not run'
CONV_UNREADABLE=warn

if [ ! -r "$CONV_LIB_DIR/conv-hooklib.sh" ]; then
  COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
  if printf '%s' "$COMMAND" | command grep -qE "$CONV_FALLBACK_ERE"; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"enforce-pnpm: conv-hooklib.sh is missing beside the hook, so it cannot check this command; restow the dotfiles (home/.claude/hooks). Use pnpm / pnpm dlx meanwhile."}}'
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
  # A fixture project whose node_modules/.bin holds a LOCAL binary, for the npx arms.
  _st_proj="${TMPDIR:-/tmp}/conv-selftest-npx-project"
  mkdir -p "$_st_proj/node_modules/.bin" "$_st_proj/sub/dir"
  : > "$_st_proj/node_modules/.bin/localtool"
  echo "=== REWRITE arms: the exact command that must run ==="
  conv_arm rewrite 'npm install'                  'npm install'                    'pnpm install'
  conv_arm rewrite 'npm i'                        'npm i'                          'pnpm i'
  conv_arm rewrite 'npm, chained'                 'git pull && npm install'        'git pull && pnpm install'
  conv_arm rewrite 'npm i <pkg>'                  'npm i left-pad'                 'pnpm add left-pad'
  conv_arm rewrite 'npm install -D <pkg>'         'npm install -D typescript'      'pnpm add -D typescript'
  conv_arm rewrite 'npm install --save-dev'       'npm install --save-dev a b'     'pnpm add --save-dev a b'
  conv_arm rewrite 'npm uninstall'                'npm uninstall left-pad'         'pnpm remove left-pad'
  conv_arm rewrite 'npm run build'                'npm run build'                  'pnpm run build'
  conv_arm rewrite 'npm test'                     'npm test'                       'pnpm test'
  conv_arm rewrite 'npm t'                        'npm t'                          'pnpm test'
  conv_arm rewrite 'env-prefixed npm test'        'env CI=1 npm test'              'env CI=1 pnpm test'
  conv_arm rewrite 'bare yarn'                    'yarn'                           'pnpm install'
  conv_arm rewrite 'yarn install'                 'yarn install'                   'pnpm install'
  conv_arm rewrite 'yarn add'                     'yarn add left-pad'              'pnpm add left-pad'
  conv_arm rewrite 'yarn add -D'                  'yarn add -D vitest'             'pnpm add -D vitest'
  conv_arm rewrite 'yarn run'                     'yarn run lint'                  'pnpm run lint'
  conv_arm rewrite 'npx, registry package'        'npx cowsay hello'               'pnpm dlx cowsay hello'
  conv_arm rewrite 'npx -y dropped'               'npx -y create-vite my-app'      'pnpm dlx create-vite my-app'
  conv_arm rewrite 'npx scoped@version'           'npx @biomejs/biome@1.9.4 check .' 'pnpm dlx @biomejs/biome@1.9.4 check .'
  conv_arm rewrite 'zsh |& after npm'             'npm test |& tee log'            'pnpm test |& tee log'
  echo "=== DENY arms: a slip whose fix is not clear-cut ==="
  conv_arm deny 'npm ci'                          'npm ci'
  conv_arm deny 'npm exec'                        'npm exec foo'
  conv_arm deny 'npm test with arguments'         'npm test -- --watch'
  conv_arm deny 'npm run with arguments'          'npm run build -- --prod'
  conv_arm deny 'npm install unknown option'      'npm install --legacy-peer-deps x'
  conv_arm deny 'bare npm'                        'npm'
  conv_arm deny 'yarn build (script by name)'     'yarn build'
  conv_arm deny 'npx unknown option'              'npx --package=x y'
  conv_arm deny 'npx local binary, cwd'           'npx localtool --version'   ''  "$_st_proj"
  conv_arm deny 'npx local binary, parent dir'    'npx localtool'             ''  "$_st_proj/sub/dir"
  conv_arm deny 'npx after a cd'                  'builtin cd /x && npx cowsay hi'
  conv_arm deny 'sudo npm'                        'sudo npm install -g x'
  conv_arm deny 'path-prefixed npm'               '/usr/local/bin/npm install'
  conv_arm deny 'quoted "npm"'                    '"npm" install'
  conv_arm deny 'pnpm link --global'              'pnpm link --global'
  conv_arm deny 'pnpm ln -g'                      'pnpm ln -g'
  conv_arm deny 'two conventions: + pip'          'npm test && pip install x'
  conv_arm deny 'unsure: function definition'     'f() { npm install; }; f'
  conv_arm deny 'unsure: f () with a space'       'f () { npm install; }; f'
  conv_arm deny 'unsure: function keyword'        'function f { npm install; }; f'
  echo "=== ALLOW arms: look-alikes that must pass untouched ==="
  conv_arm allow 'pnpm install'                   'pnpm install'
  conv_arm allow 'pnpm dlx'                       'pnpm dlx prettier --check .'
  conv_arm allow 'pnpm link (local)'              'pnpm link ../lib'
  conv_arm allow 'bun add'                        'bun add x'
  conv_arm allow 'bunx'                           'bunx foo'
  conv_arm allow 'npm as a word inside a path'    'cat ~/.npmrc'
  conv_arm allow 'command -v probe'               'command -v npm'
  conv_arm allow 'inside $(...), unchanged'       'v=$(npm --version)'
  conv_arm allow 'prose in an echo'               'echo "npm install is banned"'
  conv_arm allow 'prose in a heredoc'             $'git commit -F - <<EOF\nnever npm install\nEOF'
  conv_arm allow 'commit message via $(heredoc)'  $'git commit -m "$(cat <<\'EOF\'\nnpx (not npm) isn\'t used\nEOF\n)"'
  conv_arm allow 'multi-line "..." message (2026-09-23 false positive)' $'git commit -m "first line\n; npm ci is prose\nlast"'
  conv_arm allow 'nested quotes inside "$(...)"'  'x="$(echo "a; npm ci")"; echo "$x"'
  conv_arm allow 'control: harmless'              'echo control-ok'
  echo "=== FALLBACK arms: scanner missing, the rule still holds ==="
  export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  conv_arm deny  'scanner missing: slip denied'   'npm install'
  conv_arm allow 'scanner missing: harmless ok'   'echo control-ok'
  unset CONV_SHSCAN
  echo "=== UNREADABLE arms: jq gone, truncated JSON, a moved key (D-20260925-A03) ==="
  conv_unreadable_arms warn 'npm install' 'pnpm install'
  conv_unreadable_arms warn 'npx cowsay hi' 'cat ~/.npmrc'
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
  _lf top   warn "broken lib (error at the top), the trigger: warn by name" 'npm install'
  _lf top   allow "broken lib (error at the top), no trigger: quiet" 'pnpm install'
  _lf end   warn "broken lib (error at the end, functions defined), the trigger: warn" 'npm install'
  _lf end   allow "broken lib (error at the end), no trigger: quiet" 'pnpm install'
  _lf noere allow "broken lib, no ERE in the hook: quiet, not deny-all" 'npm install'
  conv_selftest_end
fi

conv_hook_main
