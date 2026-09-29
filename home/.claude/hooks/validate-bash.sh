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
#   git push that FORCES main or master  in any spelling git accepts: -f in a
#                                     cluster, +refspec, --mirror, lease, the flag
#                                     after the branch, or no refspec while main is
#                                     checked out in the payload's cwd (fails closed
#                                     when that cannot be read). Parsed by the
#                                     scanner, rule D; W-20260929-A31.
#   git reset --hard                  with no ref
#   git clean -fd / -f -d             untracked files and directories
# and, through the shared scanner (conv-shscan.awk, mode guard), the force-push
# rule above and three rules Gavin
# approved 2026-09-23 from the conv-hooks survey of live aliases:
#   ci cr ct cpr cd_ cskip            .zshrc aliases launching a NESTED Claude with
#                                     --dangerously-skip-permissions (cb does not
#                                     skip permissions and is allowed)
#   gpf!                              oh-my-zsh alias for git push --force. The
#                                     lease forms gpf and gpsupf were allowed
#                                     everywhere until 2026-09-29; now the
#                                     force-push rule reads them (deny on main,
#                                     allow on a feature branch, D-20260929-A08)
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
GUARD_FALLBACK_ERE='(^|[;&|({`][[:space:]]*)(ci|cr|ct|cpr|cd_|cskip|gpf!|gpf|gpsupf)([[:space:];&|)]|$)|(^|[;&|({`][[:space:]]*)([^[:space:]]*/)?brew[[:space:]]+(install|instal|reinstall|upgrade)'
# Scanner missing: a push word plus anything that looks like a force denies, crudely.
PUSH_FALLBACK_ERE='(^|[^A-Za-z0-9_.-])(push|gp|gpu|gpv|gpsup|ggpush)([[:space:];&|)]|$)'
FORCE_FALLBACK_ERE='(^|[[:space:]])(-[A-Za-z0-9]*f[A-Za-z0-9]*|--f[a-z-]*|--m[a-z]*|\+[^[:space:]]+)([[:space:]=;&|)]|$)'

log_blocked() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED validate-bash \"$1\" \"$2\"" >> "$LOG_FILE"
}

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# FAILS CLOSED ON A PAYLOAD IT CANNOT READ (W-20260924-A76, D-20260925-A03). A
# missing jq, truncated JSON or a moved tool_input.command made this guard exit 0
# in silence (measured 2026-09-25 on `ci x` and `git reset --hard`). Now, when the
# RAW payload mentions any word a rule above denies on, it denies by name; with none
# it exits 0 as before. The raw text is tested twice, as is and with every quote
# character removed, so `r""m -rf /` (which _strip turns into rm) is still seen.
# Words, one per rule: rm (root/home rm), git push|reset|clean and the bare words
# push|reset|clean (force push, reset --hard, git clean -fd, also after a quoted
# span is spliced out), brew (install|instal|reinstall|upgrade, or a subcommand in
# a variable), ci cr ct cpr cd_ cskip (nested Claude), gpf (gpf!), and the push
# aliases gp gpu gpv gpsup ggpush (force push, 2026-09-29).
VB_RAW_ERE='rm[[:space:]]|git[[:space:]]+(push|reset|clean)|(^|[^A-Za-z0-9_.-])(push|reset|clean|brew|ci|cr|ct|cpr|cd_|cskip|gpf|gp|gpu|gpv|gpsup|ggpush)([^A-Za-z0-9_-]|$)'

raw_mentions_trigger() {
  local r="$1" q
  r=${r//\\n/ }; r=${r//\\t/ }; r=${r//\\r/ }
  [[ "$r" =~ $VB_RAW_ERE ]] && return 0
  q=${r//\\\"/}; q=${q//\"/}; q=${q//\'/}
  [[ "$q" =~ $VB_RAW_ERE ]]
}

# Deny without jq: a fixed string, so it cannot fail to build. The payload itself
# is never logged: it can hold a secret.
deny_unreadable() { # $1 reason (no double quotes, no backslashes), $2 payload size
  log_blocked "unreadable payload: $1" "(payload not read, $2 bytes)" 2>/dev/null
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"validate-bash: cannot read the tool payload (%s); denying because it mentions a command this guard blocks (rm, git push/reset/clean, brew, or a nested-Claude or gpf! alias). Fix what reads the payload (jq, or a payload shape a Claude Code update changed), then retry."}}\n' "$1"
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
# $1 the command, $2 the payload's cwd (the force-push rule reads the branch there).
_classify() {
  local s
  s=$(_strip "$1")
  if echo "$s" | grep -qE 'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?(/|~|\$HOME)\s*$'; then
    echo "Destructive rm command targeting root or home directory"; return
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
  _guard "$1" "${2:-}"
}

# The three scanner rules (nested-Claude aliases, gpf!, brew install). Prints the
# deny reason, or nothing. A missing or failed scanner is named, never silent.
_guard() {
  local out rc=3 r
  if [ -r "$SHSCAN" ]; then
    out=$(printf '%s' "$1" | CONV_MODE=guard CONV_CWD="${2:-}" LC_ALL=C awk -f "$SHSCAN" 2>/dev/null); rc=$?
  fi
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    if printf '%s' "$1" | command grep -qE "$GUARD_FALLBACK_ERE" \
       || { printf '%s' "$1" | command grep -qE "$PUSH_FALLBACK_ERE" \
            && printf '%s' "$1" | command grep -qE "$FORCE_FALLBACK_ERE"; }; then
      echo "validate-bash: its scanner conv-shscan.awk is missing or failed (rc=$rc), so it cannot tell a nested-Claude alias, gpf!, brew install or a force push from prose, and this command mentions one. Restow the dotfiles (home/.claude/hooks) or fix the scanner."
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
  _must() { # $1 = expect-hit(1)/expect-miss(0), $2 = label, $3 = command, [$4 = cwd]
    local got hit=0; _must_n=$((_must_n + 1)); got="$(_classify "$3" "${4:-}")"; [ -n "$got" ] && hit=1
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
  # W-20260929-A31: a bare force push names no branch, so the payload's cwd decides.
  # With no cwd the branch cannot be read, and the rule fails closed.
  _must 1 'bare force push, no cwd (fail closed)' 'git push -f'
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
  # The lease aliases gpf and gpsupf moved to section D on 2026-09-29
  # (D-20260929-A08): they deny on main and pass on a feature branch, which needs
  # the fixture repos built there.
  echo "=== B. gpf! (git push --force): DENY ==="
  conv_arm deny  'gpf!'                            'gpf!'
  conv_arm deny  'gpf! origin main'                'gpf! origin main'
  conv_arm deny  'gpf! after &&'                   'git fetch && gpf!'
  conv_arm deny  'gpf! after an assignment'        'GIT_TRACE=1 gpf!'
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
  # W-20260929-A35 (D-20260929-A14): the live guards, ~/.gitconfig, ~/.claude/CLAUDE.md and
  # the memory folders are locked against write verbs; the repo copies stay editable.
  # W-20260929-A32 (D-20260929-A13): the leak-scan bypass knobs. Until 2026-09-29 the two
  # --no-verify pushes were ALLOW arms (P08); the ruling makes every skip of the scan a deny.
  echo "=== F. leak-scan bypass knobs: DENY; honest forms: ALLOW ==="
  conv_arm deny  'A32 git push --no-verify origin feature (was P08 allow)' 'git push --no-verify origin feature'
  conv_arm deny  'A32 git push --no-verify origin main (was allow)' 'git push --no-verify origin main'
  conv_arm deny  'A32 git commit --no-verify'                  'git commit --no-verify -m x'
  conv_arm deny  'A32 git commit -n'                           'git commit -n -m x'
  conv_arm deny  'A32 git commit -nm (cluster)'                'git commit -nm x'
  conv_arm deny  'A32 LEAK_SCAN_DISABLE=1 on a commit'         'LEAK_SCAN_DISABLE=1 git commit -m x'
  conv_arm deny  'A32 export LEAK_SCAN_DISABLE=1'              'export LEAK_SCAN_DISABLE=1'
  conv_arm deny  'A32 git config leakscan.disable true'        'git config leakscan.disable true'
  conv_arm deny  'A32 git config --local core.hooksPath'       'git config --local core.hooksPath /tmp/h'
  conv_arm deny  'A32 git -c core.hooksPath= on a commit'      'git -c core.hooksPath=/dev/null commit -m x'
  conv_arm deny  'A32 git -c leakscan.disable=true on a push'  'git -c leakscan.disable=true push origin feature'
  conv_arm allow 'A32 git config leakscan.skip (the narrow knob)' 'git config leakscan.skip username-path'
  conv_arm allow 'A32 git config --get core.hooksPath'         'git config --get core.hooksPath'
  conv_arm allow 'A32 git config --unset leakscan.disable'     'git config --unset leakscan.disable'
  conv_arm allow 'A32 git commit -mn (m takes "n" as its value)' 'git commit -mn'
  conv_arm allow 'A32 a commit message naming --no-verify'     'git commit -m "never use --no-verify"'
  conv_arm allow 'A32 git push -n (a dry run)'                 'git push -n origin feature'
  echo "=== E. writes to protected live files: DENY; reads and repo edits: ALLOW ==="
  conv_arm deny  'A35 sed -i on the live validate-bash'        "sed -i '' 's/x/y/' ~/.claude/hooks/validate-bash.sh"
  conv_arm deny  'A35 $HOME spelling, in double quotes'        'sed -i "" s/a/b/ "$HOME/.claude/hooks/validate-bash.sh"'
  conv_arm deny  'A35 perl -pi on a live guard'                "perl -pi -e 's/a/b/' ~/.claude/hooks/validate-bash.sh"
  conv_arm deny  'A35 redirect into ~/.claude/hooks'           'echo x > ~/.claude/hooks/new.sh'
  conv_arm deny  'A35 append to ~/.gitconfig'                  'echo "[x]" >> ~/.gitconfig'
  conv_arm deny  'A35 git config --global user.email'          'git config --global user.email a@b'
  conv_arm deny  'A35 tee -a into ~/.claude/CLAUDE.md'         'echo x | tee -a ~/.claude/CLAUDE.md'
  conv_arm deny  'A35 cp into a memory folder'                 'cp x.md ~/.claude/projects/-Users-x/memory/y.md'
  conv_arm deny  'A35 mv a live guard away'                    'mv ~/.claude/hooks/validate-bash.sh /tmp/x'
  conv_arm allow 'A35 read a live guard'                       'cat ~/.claude/hooks/validate-bash.sh'
  conv_arm allow 'A35 git config --global --get'               'git config --global --get user.email'
  conv_arm allow 'A35 git config --global --list'              'git config --global --list'
  conv_arm allow 'A35 cp FROM a live guard (a read)'           'cp ~/.claude/hooks/validate-bash.sh /tmp/vb.bak'
  conv_arm allow 'A35 sed -i on the repo copy'                 "sed -i '' 's/x/y/' home/.claude/hooks/validate-bash.sh"
  conv_arm allow 'A35 search a memory folder'                  'rg x ~/.claude/projects/k/memory'
  # W-20260929-A31 (red-team H1, rows P01-P28). Until 2026-09-29 the force-push rule
  # was three regexes that needed main or master typed as its own word beside the
  # flag: bare `git push -f` on main, +main, HEAD:main --force, main -f and --mirror
  # all passed, and --no-verify was denied only because -[a-z]*f matched the f in
  # "verify". Each arm runs in a fixture repo whose HEAD is the branch in its label.
  echo "=== D. force push to main or master: DENY ==="
  FX="${TMPDIR:-/tmp}/vb-selftest-repos"
  _vb_repo() { # $1 dir name, $2 branch: a repo with one commit, HEAD on $2
    local d="$FX/$1" t c
    [ -d "$d/.git" ] || git init -q "$d" >/dev/null 2>&1 || return 1
    git -C "$d" config push.default simple || return 1
    t=$(git -C "$d" mktree </dev/null) || return 1
    c=$(GIT_AUTHOR_NAME=vb GIT_AUTHOR_EMAIL=vb@selftest GIT_COMMITTER_NAME=vb GIT_COMMITTER_EMAIL=vb@selftest \
        GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z \
        git -C "$d" commit-tree -m fixture "$t") || return 1
    git -C "$d" update-ref "refs/heads/$2" "$c" && git -C "$d" symbolic-ref HEAD "refs/heads/$2"
  }
  mkdir -p "$FX/nonrepo"
  _vb_repo main main; _vb_repo master master; _vb_repo feature feature
  _vb_repo main-feature main-feature; _vb_repo fix-main fix-main
  _vb_repo detached feature && git -C "$FX/detached" update-ref --no-deref HEAD refs/heads/feature
  _vb_repo matching feature && git -C "$FX/matching" config push.default matching
  _vb_repo rpush feature && git -C "$FX/rpush" config --replace-all remote.origin.push 'refs/heads/*:refs/heads/*'
  _vb_repo upmain feature && git -C "$FX/upmain" config remote.origin.url /nonexistent \
    && git -C "$FX/upmain" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' \
    && git -C "$FX/upmain" config branch.feature.remote origin \
    && git -C "$FX/upmain" config branch.feature.merge refs/heads/main \
    && git -C "$FX/upmain" config push.default upstream
  # The fixtures are the controls: each must BE what its arms assume, or every
  # arm below is void. Read back with the same git the hook uses.
  for _f in main:main master:master feature:feature main-feature:main-feature fix-main:fix-main \
            matching:feature rpush:feature upmain:feature detached: nonrepo:; do
    _got=$(git -C "$FX/${_f%%:*}" symbolic-ref -q --short HEAD 2>/dev/null); _st_n=$((_st_n + 1))
    if [ "$_got" = "${_f#*:}" ]; then printf 'ok    fixture %s has HEAD [%s]\n' "${_f%%:*}" "$_got"
    else printf 'FAIL  fixture %s has HEAD [%s], wanted [%s]: arms below are void\n' "${_f%%:*}" "$_got" "${_f#*:}"; _st_fails=$((_st_fails + 1)); fi
  done
  _st_n=$((_st_n + 1))
  if git -C "$FX/nonrepo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL  fixture nonrepo is inside a git repo: its arm is void"; _st_fails=$((_st_fails + 1))
  else echo "ok    fixture nonrepo is not a git repo"; fi
  _st_n=$((_st_n + 1))
  if git -C "$FX/detached" rev-parse -q --verify HEAD >/dev/null; then echo "ok    fixture detached has a commit at HEAD"
  else echo "FAIL  fixture detached has no commit at HEAD"; _st_fails=$((_st_fails + 1)); fi
  M="$FX/main" F="$FX/feature"
  conv_arm deny  'P01 git push -f, on main'                   'git push -f'                         '' "$M"
  conv_arm deny  'git push --force, on main'                  'git push --force'                    '' "$M"
  conv_arm deny  'git push -f, on master'                     'git push -f'                         '' "$FX/master"
  conv_arm deny  'git push -f origin (remote only), on main'  'git push -f origin'                  '' "$M"
  conv_arm deny  'P04 git push origin +main, on feature'      'git push origin +main'               '' "$F"
  conv_arm deny  'P05 git push origin +HEAD:main'             'git push origin +HEAD:main'          '' "$F"
  conv_arm deny  '+refs/heads/main'                           'git push origin +refs/heads/main'    '' "$F"
  conv_arm deny  '+master'                                    'git push origin +master'             '' "$F"
  conv_arm deny  'quoted +main'                               "git push origin '+main'"             '' "$F"
  conv_arm deny  'P22 git push origin main -f (flag last)'    'git push origin main -f'             '' "$F"
  conv_arm deny  'P26 git push origin HEAD:main --force'      'git push origin HEAD:main --force'   '' "$F"
  conv_arm deny  'P27 git push --force origin feature:main'   'git push --force origin feature:main' '' "$F"
  conv_arm deny  'quoted main after -f'                       'git push -f origin "main"'           '' "$F"
  conv_arm deny  'P06 --force-with-lease, on main'            'git push --force-with-lease'         '' "$M"
  conv_arm deny  '--force-with-lease origin main'             'git push --force-with-lease origin main' '' "$F"
  conv_arm deny  '--force-with-lease=main:<sha> origin main'  'git push --force-with-lease=main:abc123 origin main' '' "$F"
  conv_arm deny  '--force-w (git abbreviation)'               'git push --force-w origin main'      '' "$F"
  conv_arm deny  '--force-if-includes origin main (conservative)' 'git push --force-if-includes origin main' '' "$F"
  conv_arm deny  'P07 git push --mirror'                      'git push --mirror'                   '' "$F"
  conv_arm deny  '--m (abbreviates --mirror)'                 'git push --m origin'                 '' "$F"
  conv_arm deny  '--all -f'                                   'git push --all -f origin'            '' "$F"
  conv_arm deny  '-uf cluster, origin main'                   'git push -uf origin main'            '' "$F"
  conv_arm deny  '-uf cluster, bare, on main'                 'git push -uf'                        '' "$M"
  conv_arm deny  '--no-force then -f (last wins)'             'git push --no-force -f origin main'  '' "$F"
  conv_arm deny  'P21 -u origin HEAD --force, on main'        'git push -u origin HEAD --force'     '' "$M"
  conv_arm deny  'P25 --force origin HEAD, on main'           'git push --force origin HEAD'        '' "$M"
  conv_arm deny  'force origin @, on main'                    'git push -f origin @'                '' "$M"
  conv_arm deny  'refspec in a variable'                      'git push -f origin "$B"'             '' "$F"
  conv_arm deny  'refspec from $(...)'                        'git push -f origin $(git_current_branch)' '' "$F"
  conv_arm deny  'glob refspec'                               "git push -f origin 'refs/heads/*:refs/heads/*'" '' "$F"
  conv_arm deny  '+: (matching branches)'                     'git push origin +:'                  '' "$F"
  conv_arm deny  'git -C <main repo> push -f, cwd feature'    "git -C $M push -f"                   '' "$F"
  conv_arm deny  'git -C relative, cwd is its parent'         'git -C main push -f'                 '' "$FX"
  conv_arm deny  'git -c push.default=... (config unreadable)' 'git -c push.default=matching push -f' '' "$F"
  conv_arm deny  'GIT_DIR= prefix (config unreadable)'        'GIT_DIR=/x/.git git push -f'         '' "$F"
  conv_arm deny  'git --git-dir= (config unreadable)'         'git --git-dir=/x/.git push -f'       '' "$F"
  conv_arm deny  'P28 commit --amend && push -f, on main'     'git commit --amend --no-edit && git push -f' '' "$M"
  conv_arm deny  'cd <main repo> && push -f, cwd feature'     "cd $M && git push -f"                '' "$F"
  conv_arm deny  'non-repo cwd, bare force (fail closed)'     'git push -f'                         '' "$FX/nonrepo"
  conv_arm deny  'detached HEAD, bare force (fail closed)'    'git push -f'                         '' "$FX/detached"
  conv_arm deny  'push.default=matching, on feature'          'git push -f'                         '' "$FX/matching"
  conv_arm deny  'remote.origin.push configured, on feature'  'git push -f'                         '' "$FX/rpush"
  conv_arm deny  'feature tracking main (push.default=upstream)' 'git push -f'                      '' "$FX/upmain"
  conv_arm deny  '/usr/bin/git path'                          '/usr/bin/git push -f origin main'    '' "$F"
  conv_arm deny  'command git'                                'command git push -f origin main'     '' "$F"
  conv_arm deny  'env VAR=1 git'                              'env FOO=1 git push -f origin main'   '' "$F"
  conv_arm deny  'inside $(...)'                              'x=$(git push -f origin main)'        '' "$F"
  conv_arm deny  'inside eval'                                'eval "git push -f origin main"'      '' "$F"
  conv_arm deny  'inside bash -c'                             "bash -c 'git push -f'"               '' "$F"
  conv_arm deny  'alias gp -f, on main'                       'gp -f'                               '' "$M"
  conv_arm deny  'alias gp origin +main'                      'gp origin +main'                     '' "$F"
  conv_arm deny  'alias gpsup --force, on main'               'gpsup --force'                       '' "$M"
  conv_arm deny  'control: the form denied before 2026-09-29' 'git push --force origin main'        '' "$F"
  # W-20260929-A53: a function definition keeps the crude whole-text match only
  # while some command word is a push; these must still deny.
  conv_arm deny  'A53 fn body git push -f origin main'        'p() { git push -f origin main; }; p' '' "$F"
  conv_arm deny  'A53 function kw, body --force, on main'     'function p { git push --force; }; p' '' "$M"
  conv_arm deny  'A53 fn git push "$@", called -f main'       'p() { git push "$@"; }; p -f origin main' '' "$F"
  conv_arm deny  'A53 fn runs "$@", called git push -f main'  'p() { "$@"; }; p git push -f origin main' '' "$F"
  conv_arm deny  'A53 function with two names, body unread'   'function a b { git push -f origin main; }' '' "$F"
  # W-20260929-A47: a force flag held in a variable, and a push inside a here-document
  # or here-string fed to a shell.
  conv_arm deny  'A47 git push $F origin main'                'git push $F origin main'             '' "$F"
  conv_arm deny  'A47 git push "$F" origin main'              'git push "$F" origin main'           '' "$F"
  conv_arm deny  'A47 bare git push $F, on main'              'git push $F'                         '' "$M"
  conv_arm deny  'A47 git push origin main $F (after the refspec)' 'git push origin main $F' '' "$F"
  conv_arm deny  'A47 bash here-document pushes -f main'      $'bash <<\'EOF\'\ngit push -f origin main\nEOF' '' "$F"
  conv_arm deny  'A47 cat here-document piped to sh'          $'cat <<EOF | sh\ngit push --force origin main\nEOF' '' "$F"
  conv_arm deny  'A47 zsh here-string'                        "zsh <<< 'git push -f origin main'"   '' "$F"
  echo "=== D. force push elsewhere, and plain pushes: ALLOW ==="
  conv_arm allow 'A53 fn def, rg pattern naming force push'   "norm() { sed 's/x/y/' \"\$1\"; }; rg 'force push|git push -f' file" '' "$M"
  conv_arm allow 'A53 function kw, rg pattern push --force'   "function norm { tr a b; }; rg -e 'push --force' README.md" '' "$M"
  conv_arm allow 'A47 git push origin "$BRANCH" (a refspec)'  'git push origin "$BRANCH"'           '' "$F"
  conv_arm allow 'A47 git push $F origin feature'             'git push $F origin feature'          '' "$M"
  conv_arm allow 'A47 git push -- "$R" main (-- ends flags)'  'git push -- "$R" main'               '' "$F"
  conv_arm allow 'A47 commit here-document naming force push' $'git commit -F - <<\'EOF\'\nnever git push -f origin main\nEOF' '' "$M"
  conv_arm allow 'A47 bash here-document, plain push'         $'bash <<\'EOF\'\ngit push origin main\nEOF' '' "$F"
  conv_arm allow 'P02 git push -f origin feature, on main'    'git push -f origin feature'          '' "$M"
  conv_arm allow 'git push -f, on feature'                    'git push -f'                         '' "$F"
  conv_arm allow 'git push -f, on main-feature'               'git push -f'                         '' "$FX/main-feature"
  conv_arm allow 'git push -f, on fix-main'                   'git push -f'                         '' "$FX/fix-main"
  conv_arm allow '-f origin main-feature'                     'git push -f origin main-feature'     '' "$M"
  conv_arm allow '-f origin fix-main'                         'git push -f origin fix-main'         '' "$M"
  conv_arm allow '+feature, on main'                          'git push origin +feature'            '' "$M"
  conv_arm allow '-f feature:feature2'                        'git push -f origin feature:feature2' '' "$M"
  conv_arm allow '--force-with-lease origin feature'          'git push --force-with-lease origin feature' '' "$M"
  conv_arm allow 'plain push origin main'                     'git push origin main'                '' "$M"
  conv_arm allow 'plain push HEAD:main'                       'git push origin HEAD:main'           '' "$F"
  conv_arm allow 'plain -u origin HEAD, on main'              'git push -u origin HEAD'             '' "$M"
  conv_arm allow '-f then --no-force (last wins)'             'git push -f --no-force origin main'  '' "$F"
  conv_arm allow '-o f is a push option, not -f'              'git push -o f origin main'           '' "$F"
  conv_arm allow '-of is -o with value f'                     'git push -of origin main'            '' "$F"
  conv_arm allow 'git -C <feature repo> push -f, cwd main'    "git -C $F push -f"                   '' "$M"
  conv_arm allow 'git fetch -f origin main (not a push)'      'git fetch -f origin main'            '' "$M"
  conv_arm allow 'git pull --force origin main (not a push)'  'git pull --force origin main'        '' "$M"
  conv_arm allow 'prose in an echo'                           'echo "git push -f origin main"'      '' "$M"
  conv_arm allow 'prose in a commit message'                  'git commit -m "never git push -f to main"' '' "$M"
  conv_arm allow 'alias gp origin main'                       'gp origin main'                      '' "$M"
  conv_arm allow 'alias gp -f, on feature'                    'gp -f'                               '' "$F"
  # D-20260929-A08: the lease aliases deny on main like the long form, and pass on
  # a feature branch. Until 2026-09-29 both were allowed everywhere (2026-09-23).
  echo "=== D. lease aliases gpf and gpsupf: DENY on main, ALLOW on a feature branch ==="
  conv_arm deny  'gpf, on main'                               'gpf'                                 '' "$M"
  conv_arm deny  'gpf, on master'                             'gpf'                                 '' "$FX/master"
  conv_arm deny  'gpsupf, on main'                            'gpsupf'                              '' "$M"
  conv_arm deny  'gpsupf, on master'                          'gpsupf'                              '' "$FX/master"
  conv_arm deny  'gpf origin main, on feature'                'gpf origin main'                     '' "$F"
  conv_arm deny  'gpf after &&, on main'                      'git fetch && gpf'                    '' "$M"
  conv_arm deny  'gpf inside $(...), on main'                 'x=$(gpf)'                            '' "$M"
  conv_arm deny  'gpf inside eval (crude)'                    'eval "gpf"'                          '' "$F"
  conv_arm deny  'gpf, non-repo cwd (fail closed)'            'gpf'                                 '' "$FX/nonrepo"
  conv_arm deny  'gpf, feature tracking main'                 'gpf'                                 '' "$FX/upmain"
  conv_arm allow 'gpf, on feature'                            'gpf'                                 '' "$F"
  conv_arm allow 'gpsupf, on feature'                         'gpsupf'                              '' "$F"
  conv_arm allow 'gpf, on main-feature'                       'gpf'                                 '' "$FX/main-feature"
  conv_arm allow 'gpf origin feature, on main'                'gpf origin feature'                  '' "$M"
  conv_arm allow 'gpf origin x, on main'                      'gpf origin x'                        '' "$M"
  conv_arm allow 'echo gpf gpsupf'                            'echo gpf gpsupf'                     '' "$M"
  conv_arm allow 'escaped \gpf (no alias expansion)'          '\gpf'                                '' "$M"
  echo "=== FALLBACK arms: scanner missing, the rules still hold ==="
  export CONV_SHSCAN=/nonexistent/conv-shscan.awk
  conv_arm deny  'scanner missing: ci denied'      'ci x'
  conv_arm deny  'scanner missing: brew install'   'brew install jq'
  conv_arm deny  'scanner missing: git push -f, on main' 'git push -f'                    '' "$M"
  conv_arm deny  'scanner missing: +main'          'git push origin +main'                '' "$F"
  conv_arm deny  'scanner missing: gpf, on main'   'gpf'                                  '' "$M"
  conv_arm allow 'scanner missing: plain push ok'  'git push origin feature'              '' "$M"
  conv_arm allow 'scanner missing: harmless ok'    'echo control-ok'
  unset CONV_SHSCAN
  echo "=== UNREADABLE arms: jq gone, truncated JSON, a moved key (D-20260925-A03) ==="
  conv_unreadable_arms deny 'git reset --hard' 'echo control-ok'
  # Every other rule, truncated and with no jq: each must deny by name.
  for _c in 'rm -rf /' 'rm -rf ~' 'git push --force origin main' 'git clean -fd' 'ci x' 'cskip' \
            'gpf! origin main' 'brew install jq' 'brew $sub jq' 'x=$(cd_)'; do
    _p=$(conv_payload "$_c" | jq -c .)
    conv_arm_raw deny "unreadable, truncated JSON: $_c" "${_p%??????????}"
    conv_arm_raw deny "unreadable, PATH without jq: $_c" "$_p" nojq
  done
  # A quoted span spliced out: _strip turns r""m into rm, so the raw test must too.
  _p=$(conv_payload 'r""m -rf /' | jq -c .)
  conv_arm_raw deny  "unreadable, truncated: r\"\"m -rf / (quote splice)" "${_p%??????????}"
  _p=$(conv_payload 'git "x"push -f origin main' | jq -c .)
  conv_arm_raw deny  "unreadable, truncated: git \"x\"push (quote splice)" "${_p%??????????}"
  # The trigger words inside other words stay quiet.
  _p=$(conv_payload 'echo cities pushover resetting cleanly brewery gpfx' | jq -c .)
  conv_arm_raw allow "unreadable, truncated: trigger letters inside words" "${_p%??????????}"
  conv_arm_raw allow "unreadable, PATH without jq: trigger letters inside words" "$_p" nojq
  echo
  echo "function arms: $_must_n, $((_must_n - fails)) passed, $fails failed"
  echo "payload arms:  $_st_n, $((_st_n - _st_fails)) passed, $_st_fails failed"
  echo "$((_must_n + _st_n)) arms, $((_must_n + _st_n - fails - _st_fails)) passed, $((fails + _st_fails)) failed"
  [ $((fails + _st_fails)) -eq 0 ] && { echo "ALL ARMS PASS"; exit 0; } || { echo "$((fails + _st_fails)) ARM(S) FAILED"; exit 1; }
fi

# ---------------------------------------------------------------- hook path
INPUT=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  raw_mentions_trigger "$INPUT" && deny_unreadable "jq is not on PATH" "${#INPUT}"
  exit 0
fi
if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  raw_mentions_trigger "$INPUT" && deny_unreadable "the payload is not valid JSON" "${#INPUT}"
  exit 0
fi
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$COMMAND" ]; then
  if ! printf '%s' "$INPUT" | jq -e '.tool_input | has("command")' >/dev/null 2>&1; then
    raw_mentions_trigger "$INPUT" && deny_unreadable "the payload has no tool_input.command" "${#INPUT}"
  fi
  exit 0   # a real, empty command: nothing to check, as before
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
REASON=$(_classify "$COMMAND" "$CWD")
if [ -n "$REASON" ]; then
  log_blocked "$REASON" "$COMMAND"
  deny "$REASON"
fi
exit 0
