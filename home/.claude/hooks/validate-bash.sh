#!/bin/bash
# Block destructive Bash commands. Runs on PreToolUse for Bash.
#
# TRAVELS WITH pj (P5.6, 2026-09-21). Stowed to ~/.claude/hooks/ and declared once
# in settings/claude/hooks.json with targets ["project"], so it fires in every
# folder a pj session opens, not only in the dotfiles repo. It therefore writes its
# audit line to the machine-wide state home, never beside the script:
#   ${XDG_STATE_HOME:-~/.local/state}/dotfiles/hooks-security.log
#
# Denies:
#   rm -rf / (or ~, $HOME)            root or home deletion
#   git push --force|-f ... main|master
#   git reset --hard                  with no ref
#   git clean -fd / -f -d             untracked files and directories
# and, through the shared scanner (conv-shscan.awk, mode guard), three rules Gavin
# approved 2026-09-23 from the conv-hooks survey of live aliases:
#   ci cr ct cpr cd_ cskip            .zshrc aliases launching a NESTED Claude with
#                                     --dangerously-skip-permissions (cb does not
#                                     skip permissions and is allowed)
#   gpf!                              oh-my-zsh alias for git push --force; the
#                                     lease forms gpf and gpsupf stay allowed
#   brew install|instal|reinstall|upgrade   ask Gavin; list/info/search/outdated
#                                     stay allowed. The .zshrc brew() guard is
#                                     interactive-only, measured inert here.
# A hook sees the TYPED text, never the alias expansion, which is why the first
# four rules (on the expansions) never saw these names.
#
# Quoted strings, $(...) and heredoc BODIES are stripped before matching, the same
# way the enforce-* guards do it. Measured 2026-09-21 before the fix: a commit
# message saying "git clean -fd is banned" and an echo mentioning a force push were
# both denied, and the probe that found it was itself denied by this hook. The three
# guard rules do not use that strip: the scanner reads the command the way zsh
# tokenises it (quotes, $(...), heredocs, groups), so they deny the alias at command
# position only, including inside $(...), backticks and eval, where zsh expands it.
# conv-shscan.awk and conv-hooklib.sh must be stowed beside this file; without them
# the three rules fall back to a crude word match, deny only, and say so by name.
#
# `--selftest` proves every arm, positive and negative. Exit 0 = all arms pass.
# VB_HOOK_UNDER_TEST=<path> runs the payload arms against another copy, and
# CONV_PAYLOAD_FILE=<captured payload> runs them on a real payload envelope.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG_FILE="$STATE_DIR/hooks-security.log"
HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
SHSCAN="${CONV_SHSCAN:-$HOOKS_DIR/conv-shscan.awk}"
GUARD_FALLBACK_ERE='(^|[;&|({`][[:space:]]*)(ci|cr|ct|cpr|cd_|cskip|gpf!)([[:space:];&|)]|$)|(^|[;&|({`][[:space:]]*)([^[:space:]]*/)?brew[[:space:]]+(install|instal|reinstall|upgrade)'

log_blocked() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED validate-bash \"$1\" \"$2\"" >> "$LOG_FILE"
}

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Strip heredoc bodies (keep the opening line), then $(...), "..." and '...'.
_strip() {
  printf '%s\n' "$1" | awk '
    BEGIN { in_h = 0; term = "" }
    {
      if (in_h) {
        stripped = $0
        sub(/^[ \t]+/, "", stripped)
        if ($0 == term || stripped == term) { in_h = 0 }
        next
      }
      if (match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
        t = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", t)
        gsub(/["\047]/, "", t)
        term = t
        in_h = 1
      }
      print
    }' | sed -E 's/\$\([^)]*\)//g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g'
}

# Prints the deny reason, or nothing when the command is allowed.
_classify() {
  local s
  s=$(_strip "$1")
  if echo "$s" | grep -qE 'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?(/|~|\$HOME)\s*$'; then
    echo "Destructive rm command targeting root or home directory"; return
  fi
  if echo "$s" | grep -qE 'git\s+push\s+.*(--force|--force-with-lease).*\s+(main|master)' \
     || echo "$s" | grep -qE 'git\s+push\s+.*\s+(main|master)\s+.*(--force|--force-with-lease)' \
     || echo "$s" | grep -qE 'git\s+push\s+.*-[a-zA-Z]*f[a-zA-Z]*\s+.*(main|master)'; then
    echo "Force push to main/master is not allowed"; return
  fi
  if echo "$s" | grep -qE 'git\s+reset\s+--hard\s*($|[;&|])'; then
    echo "git reset --hard without a ref: specify a commit"; return
  fi
  # git clean. TWO bugs lived in the old form of this rule and both were measured
  # on 2026-09-21 (W-20260921-A10):
  #
  #   FALSE POSITIVE -- `git clean -fdn`, `--dry-run -fd` and `-fd --dry-run` are
  #   DRY RUNS and were all denied, because -n and --dry-run were never looked for.
  #   Both P5.6 probe sessions hit it.
  #
  #   FALSE NEGATIVE -- `git clean -df` and `-dfx` were ALLOWED. The old pattern
  #   `-[a-zA-Z]*f[a-zA-Z]*d` requires f BEFORE d inside one flag group, and the
  #   two-group alternation needed a separate `-f` and `-d`. Neither matched the
  #   d-before-f spelling, so the destructive form the rule exists for got through.
  #   That one was not in the item; it was found by running all six spellings.
  #
  # So the rule now decides on two independent facts: does a dry-run flag appear,
  # and do BOTH f and d appear among the short flags in either order.
  # A regex over the whole command cannot express "f and d appear, in any order,
  # across any number of flag groups, and n does not". Collecting the letters and
  # asking three yes/no questions can, and it reads the same as the rule.
  if printf '%s' "$s" | grep -qE 'git[[:space:]]+clean'; then
    local tail short long dry=0 has_f=0 has_d=0
    tail=$(printf '%s' "$s" | sed -E 's/.*git[[:space:]]+clean//')
    # every LONG option, and every SHORT cluster's letters mashed together.
    # `--dry-run` cannot leak into the short set: the short pattern needs a letter
    # straight after a single leading `-`, and the second `-` is not a letter.
    long=$(printf '%s' "$tail"  | grep -oE -- '--[a-zA-Z-]+' | tr '\n' ' ')
    short=$(printf '%s' "$tail" | grep -oE -- '(^|[[:space:]])-[a-zA-Z]+' | tr -d ' -' | tr -d '\n')
    case " $long " in *' --dry-run '*) dry=1;; esac
    case "$short" in *n*) dry=1;; esac
    case "$short" in *f*) has_f=1;; esac
    case "$short" in *d*) has_d=1;; esac
    if [ "$dry" -eq 0 ] && [ "$has_f" -eq 1 ] && [ "$has_d" -eq 1 ]; then
      echo "git clean with -f and -d would remove untracked files and directories (add -n to dry-run it)"; return
    fi
  fi
  _guard "$1"
}

# The three scanner rules (nested-Claude aliases, gpf!, brew install). Prints the
# deny reason, or nothing. A missing or failed scanner is named, never silent.
_guard() {
  local out rc=3 r
  if [ -r "$SHSCAN" ]; then
    out=$(printf '%s' "$1" | CONV_MODE=guard LC_ALL=C awk -f "$SHSCAN" 2>/dev/null); rc=$?
  fi
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    if printf '%s' "$1" | command grep -qE "$GUARD_FALLBACK_ERE"; then
      echo "validate-bash: its scanner conv-shscan.awk is missing or failed (rc=$rc), so it cannot tell a nested-Claude alias, gpf! or brew install from prose, and this command mentions one. Restow the dotfiles (home/.claude/hooks) or fix the scanner."
    fi
    return
  fi
  case "${out%%$'\n'*}" in
    ALLOW) ;;
    DENY) r=${out#*$'\n'}; echo "${r%%$'\n'*}" ;;
    *) echo "validate-bash: its scanner answered '${out%%$'\n'*}'; denying rather than guessing" ;;
  esac
}

# ---------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  fails=0; _must_n=0
  _must() { # $1 = expect-hit(1)/expect-miss(0), $2 = label, $3 = command
    local got hit=0; _must_n=$((_must_n + 1)); got="$(_classify "$3")"; [ -n "$got" ] && hit=1
    if [ "$hit" -eq "$1" ]; then printf 'ok    %s\n' "$2"
    else printf 'FAIL  %s  (expected hit=%s, got hit=%s)\n' "$2" "$1" "$hit"; fails=$((fails+1)); fi
  }
  echo "=== POSITIVE arms: these MUST be denied ==="
  _must 1 'rm -rf /'                        'rm -rf /'
  _must 1 'rm -rf ~'                        'rm -rf ~'
  _must 1 'force push, long flag'           'git push --force origin master'
  _must 1 'force push, short flag'          'git push -f origin main'
  _must 1 'force-with-lease'                'git push origin main --force-with-lease'
  _must 1 'bare reset --hard'               'git reset --hard'
  _must 1 'bare reset --hard, chained'      'git fetch && git reset --hard; ls'
  _must 1 'git clean -fd'                   'git clean -fd'
  _must 1 'git clean -f -d'                 'git clean -f -d'
  # W-20260921-A10: every spelling that reaches the same destructive command.
  # -df and -dfx were ALLOWED before 2026-09-21: the old pattern demanded f
  # before d. A guard with a hole in it is worse than no guard, because it is
  # trusted. Order, extra letters and separate groups all mean the same thing.
  _must 1 'git clean -df (d before f)'      'git clean -df'
  _must 1 'git clean -dfx'                  'git clean -dfx'
  _must 1 'git clean -d -f (separate)'      'git clean -d -f'
  _must 1 'git clean -xfd'                  'git clean -xfd'
  _must 1 'git clean -ffd'                  'git clean -ffd'
  echo "=== NEGATIVE arms: these MUST be allowed ==="
  _must 0 'rm of a subdir'                  'rm -rf ./build'
  _must 0 'plain push'                      'git push origin master'
  _must 0 'reset --hard with a ref'         'git reset --hard HEAD~1'
  _must 0 'git clean dry run'               'git clean -n'
  # W-20260921-A10: a dry run is a dry run wherever -n or --dry-run sits.
  # All four of these were DENIED before 2026-09-21 except the -n -fd one, which
  # was allowed only because the old regex happened to miss it.
  _must 0 'git clean -fdn'                  'git clean -fdn'
  _must 0 'git clean -n -fd'                'git clean -n -fd'
  _must 0 'git clean --dry-run -fd'         'git clean --dry-run -fd'
  _must 0 'git clean -fd --dry-run'         'git clean -fd --dry-run'
  _must 0 'git clean -ndfx'                 'git clean -ndfx'
  _must 0 'git clean -f only (no -d)'       'git clean -f'
  _must 0 'git clean -d only (no -f)'       'git clean -d'
  _must 0 'prose in an echo'                'echo "never git push --force to master"'
  _must 0 'prose in a commit message'       'git commit -m "note: git clean -fd is banned"'
  _must 0 'prose in a heredoc'              $'cat <<EOF\ngit reset --hard is dangerous\nEOF'
  _must 0 'control: harmless'               'echo control-ok'
  # The guard rules run end to end: a PreToolUse payload into the hook script, so
  # VB_HOOK_UNDER_TEST=<master's copy> can prove each arm fails where the rule is
  # absent. conv-hooklib.sh supplies the payload and the arm checker.
  if [ ! -r "$HOOKS_DIR/conv-hooklib.sh" ]; then
    echo "FAIL  conv-hooklib.sh missing beside this hook: the guard arms cannot run"
    echo; echo "$((fails + 1)) ARM(S) FAILED"; exit 1
  fi
  . "$HOOKS_DIR/conv-hooklib.sh"
  CONV_HOOK_UNDER_TEST="${VB_HOOK_UNDER_TEST:-}"
  conv_selftest_begin "$0"
  echo "=== A. nested-Claude skip-permissions aliases: DENY ==="
  conv_arm deny 'ci'                               'ci "summarise this"'
  conv_arm deny 'cr'                               'cr'
  conv_arm deny 'ct'                               'ct'
  conv_arm deny 'cpr'                              'cpr 123'
  conv_arm deny 'cd_'                              'cd_'
  conv_arm deny 'cskip'                            'cskip'
  conv_arm deny 'after &&'                         'git status && ci x'
  conv_arm deny 'in a pipeline'                    'echo a | ci -'
  conv_arm deny 'on a second line'                 $'echo a\nci b'
  conv_arm deny 'after an assignment'              'FOO=1 cskip'
  conv_arm deny 'after time'                       'time cr'
  conv_arm deny 'after nocorrect'                  'nocorrect cpr 1'
  conv_arm deny 'after !'                          '! ct'
  conv_arm deny 'after if'                         'if cd_; then :; fi'
  conv_arm deny 'in { }'                           '{ ci x; }'
  conv_arm deny 'in ( )'                           '(ci x)'
  conv_arm deny 'inside $(...)'                    'x=$(cr)'
  conv_arm deny 'inside backticks'                 'y=`ct --x`'
  conv_arm deny 'inside eval'                      'eval "cpr 1"'
  conv_arm deny 'inside <(...)'                    'cat <(ci x)'
  conv_arm deny 'inside zsh =(...)'                'diff =(ci x) f'
  conv_arm deny 'zsh &! background'                'ci x &!'
  conv_arm deny 'after nohup (no expansion; conservative)' 'nohup ci x'
  echo "=== A. look-alikes: ALLOW ==="
  conv_arm allow 'cb (no skip-permissions)'        'cb'
  conv_arm allow 'escaped \ci (no alias expansion)' '\ci x'
  conv_arm allow "quoted 'ci'"                     "'ci' x"
  conv_arm allow 'git ci (a git alias)'            'git ci -m x'
  conv_arm allow 'make ci / pnpm run ci'           'make ci && pnpm run ci'
  conv_arm allow 'echo ci'                         'echo ci'
  conv_arm allow 'alias ci / whence / type'        'alias ci; whence -w cr; type cskip'
  conv_arm allow 'command -v ci'                   'command -v ci'
  conv_arm allow 'prose in quotes'                 'echo "run ci then cr"'
  conv_arm allow 'prose in a heredoc'              $'cat <<EOF\nci is the alias\nEOF'
  conv_arm allow 'prose in a commit message'       $'git commit -m "note\n; ci x is denied\nend"'
  conv_arm allow 'words that start with ci'        'circleci x; cid=1; cd_x y'
  conv_arm allow 'zsh glob qualifier'              'print -l ci*(.)'
  echo "=== B. gpf! (git push --force): DENY, lease forms ALLOW ==="
  conv_arm deny  'gpf!'                            'gpf!'
  conv_arm deny  'gpf! origin main'                'gpf! origin main'
  conv_arm deny  'gpf! after &&'                   'git fetch && gpf!'
  conv_arm deny  'gpf! after an assignment'        'GIT_TRACE=1 gpf!'
  conv_arm allow 'gpf (lease)'                     'gpf'
  conv_arm allow 'gpf origin x (lease)'            'gpf origin x'
  conv_arm allow 'gpsupf (lease)'                  'gpsupf'
  conv_arm allow 'echo gpf!'                       'echo gpf!'
  conv_arm allow 'git push --force-with-lease'     'git push --force-with-lease origin x'
  echo "=== C. brew install/reinstall/upgrade: DENY ==="
  conv_arm deny 'brew install'                     'brew install jq'
  conv_arm deny 'brew instal (brew alias)'         'brew instal jq'
  conv_arm deny 'brew reinstall'                   'brew reinstall jq'
  conv_arm deny 'brew upgrade <formula>'           'brew upgrade jq'
  conv_arm deny 'brew upgrade (everything)'        'brew upgrade'
  conv_arm deny 'brew install --cask'              'brew install --cask foo'
  conv_arm deny 'global option first'              'brew -v install jq'
  conv_arm deny 'after an assignment'              'HOMEBREW_NO_AUTO_UPDATE=1 brew install jq'
  conv_arm deny 'path-prefixed brew'               '/opt/homebrew/bin/brew install jq'
  conv_arm deny 'command brew (skips the wrapper)' 'command brew install jq'
  conv_arm deny 'escaped \brew'                    '\brew install jq'
  conv_arm deny 'quoted "brew"'                    '"brew" install jq'
  conv_arm deny 'sudo -u x brew'                   'sudo -u admin brew install jq'
  conv_arm deny 'env VAR=1 brew'                   'env FOO=1 brew install jq'
  conv_arm deny 'xargs brew install'               'xargs brew install < list.txt'
  conv_arm deny 'after &&'                         'brew update && brew upgrade jq'
  conv_arm deny 'inside $(...)'                    'x=$(brew install jq)'
  conv_arm deny 'inside backticks'                 'x=`brew install jq`'
  conv_arm deny 'inside eval'                      'eval "brew install jq"'
  conv_arm deny 'subcommand in a variable'         'brew $sub jq'
  conv_arm deny 'quoted subcommand'                'brew "install" jq'
  echo "=== C. read-only brew and prose: ALLOW ==="
  conv_arm allow 'brew list'                       'brew list'
  conv_arm allow 'brew info'                       'brew info jq'
  conv_arm allow 'brew search'                     'brew search jq'
  conv_arm allow 'brew outdated'                   'brew outdated'
  conv_arm allow 'brew deps'                       'brew deps --tree jq'
  conv_arm allow 'brew --prefix'                   'brew --prefix'
  conv_arm allow 'brew list | grep'                'brew list --versions | grep jq'
  conv_arm allow 'zsh |& pipe'                     'brew info jq |& cat'
  conv_arm allow 'zsh =(...) around brew list'     'diff =(brew list) f'
  conv_arm allow 'command -v brew'                 'command -v brew; whence -p brew'
  conv_arm allow 'prose in an echo'                'echo "brew install jq"'
  conv_arm allow 'prose in a commit message'       $'git commit -m "why\n; brew install x is denied\nend"'
  conv_arm allow 'rg for the phrase'               "rg 'brew install' docs"
  conv_arm allow 'the word install after brew list' 'brew list install'
  conv_arm allow 'control: harmless'               'echo control-ok'
  echo "=== FALLBACK arms: scanner missing, the rules still hold ==="
  export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  conv_arm deny  'scanner missing: ci denied'      'ci x'
  conv_arm deny  'scanner missing: brew install'   'brew install jq'
  conv_arm allow 'scanner missing: harmless ok'    'echo control-ok'
  unset CONV_SHSCAN
  echo
  echo "function arms: $_must_n, $((_must_n - fails)) passed, $fails failed"
  echo "payload arms:  $_st_n, $((_st_n - _st_fails)) passed, $_st_fails failed"
  echo "$((_must_n + _st_n)) arms, $((_must_n + _st_n - fails - _st_fails)) passed, $((fails + _st_fails)) failed"
  [ $((fails + _st_fails)) -eq 0 ] && { echo "ALL ARMS PASS"; exit 0; } || { echo "$((fails + _st_fails)) ARM(S) FAILED"; exit 1; }
fi

# ---------------------------------------------------------------- hook path
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

REASON=$(_classify "$COMMAND")
if [ -n "$REASON" ]; then
  log_blocked "$REASON" "$COMMAND"
  deny "$REASON"
fi
exit 0
