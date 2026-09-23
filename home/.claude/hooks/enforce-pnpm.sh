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

if [ ! -r "$CONV_LIB_DIR/conv-hooklib.sh" ]; then
  COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
  if printf '%s' "$COMMAND" | command grep -qE "$CONV_FALLBACK_ERE"; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"enforce-pnpm: conv-hooklib.sh is missing beside the hook, so it cannot check this command; restow the dotfiles (home/.claude/hooks). Use pnpm / pnpm dlx meanwhile."}}'
  fi
  exit 0
fi
. "$CONV_LIB_DIR/conv-hooklib.sh"

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
  conv_selftest_end
fi

conv_hook_main
