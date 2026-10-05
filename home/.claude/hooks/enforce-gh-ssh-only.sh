#!/bin/bash
# Block what breaks SSH-only GitHub auth, in the Claude Bash tool:
#   gh auth login|setup-git|refresh     re-add HTTPS credential helpers
#   gh auth switch|logout|git-credential change or print gh's credential
#   gh config set git_protocol https    makes gh clone and push over HTTPS
#   git credential.*.helper writes      (config, git -c, clone --config)
#   git url.*.insteadOf writes          rewrite every SSH remote machine-wide
#   a credential inside a git URL       persisted in .git/config
# ~/.gitconfig is a symlink into the dotfiles repo, so a --global write is also
# a write into another repo. Mirrors the interactive gh() wrapper in .zshrc,
# which does NOT apply to the non-interactive Bash tool. PreToolUse for Bash.
#
# ONE SOURCE (D-20260929-A06, 2026-09-29): this file, in the dotfiles repo at
# home/.claude/hooks/, stow-linked into ~/.claude/hooks. Until then there were
# two real files (dot-claude's and .claude/hooks/ here) and they had drifted by
# 98 diff lines; the one every session ran lacked the A76 arms below.
#
# 2026-09-17, defect 1 -- THE ANCHOR. The original pattern anchored `gh` to
# start-of-string or a [;&|] separator only, so every ordinary prefixed form
# walked straight past it. Measured, with the bare form blocking correctly as
# the positive control in the same run:
#
#     <bare form>                            -> BLOCKED  (control)
#     env -u GH_TOKEN <form>                 -> ALLOWED  <- bypass
#     /opt/homebrew/bin/<form>               -> ALLOWED  <- bypass
#     sudo <form>                            -> ALLOWED  <- bypass
#     GH_TOKEN= <form>                       -> ALLOWED  <- bypass
#
# An `env` prefix also bypasses the interactive gh() wrapper, because `env`
# execs the binary and never consults shell functions. So both layers of this
# guard failed on the same one-word prefix, and the authorised keyring token
# swap that found this was allowed through without a single log line.
#
# 2026-09-17, defect 2 -- THE FALSE POSITIVE the fix for defect 1 introduced.
# Widening the anchor made the pattern match the command name written as PROSE
# inside a heredoc, so writing documentation about this very guard was blocked
# on the first attempt. That matters more than it looks: a guard that blocks
# people from documenting it is a guard that gets switched off. Heredoc bodies
# are therefore stripped before matching, alongside the existing quoted-string
# and subshell stripping.
#
# 2026-09-25, D-20260925-A03 (W-20260924-A76) -- AN UNREADABLE PAYLOAD. With jq
# missing, invalid JSON, or tool_input.command moved, this hook exited 0 in
# silence. Now, when the RAW payload mentions a trigger anywhere (it cannot
# tell prose from a command unread), it DENIES by name, JSON built without jq.
# Without that text: exit 0, as before.
#
# 2026-09-29, H3 (W-20260929-A33, A44) -- THE STRIPPING HID REAL COMMANDS. The
# quote stripping that fixed defect 2 also threw away every `bash -c '...'`,
# `sh -c`, `zsh -c` and `eval "..."` body, and every $(...), so the trio ran
# unseen inside any of them (red-team G06-G08, G21). And the half of the rule
# that says "or a credential helper" had no check at all (G09, G10, G14, G17,
# G18, G20). So the command is now READ, not stripped: a small lexer (awk,
# below) splits it into simple commands the way the shell would, quotes
# removed and their contents kept inside one word, and the rules look at argv
# after seeing through prefixes (VAR=1, env, sudo, command, nohup, time, exec,
# nice, timeout, xargs, ...). A shell body (`-c`, eval, env -S, watch, a
# heredoc or here-string fed to a shell, echo piped into a shell, $(...),
# backticks, <(...)) is lexed again as a command of its own, up to 4 deep.
# That is the approach enforce-no-permanent-delete.sh takes (its _shell_text /
# _shell_cmd / eval branch and MAX_DEPTH=4); this is a smaller lexer written for
# this hook, not a copy of that one, and it expands no aliases. A word that is
# data (a commit message, an rg pattern, heredoc prose fed to cat) stays data.
# Copy B's regex scan is KEPT and runs first, as a floor: every command it
# denied is still denied, whatever the lexer makes of it.
#
# KNOWN LIMITS, stated rather than papered over. This hook raises the cost of an
# accidental bypass; it is not a sandbox.
#   - An ARGUMENT held in a variable: `a=auth; gh $a login`. (A command WORD
#     is covered: `NAME=value; $NAME ...` in the same command is resolved (G16),
#     and any other $-word, `${x}h` or `$(printf gh)`, followed by `auth login`
#     is denied.) Also `xargs gh auth < file`, where the verb comes from stdin.
#   - Writing ~/.gitconfig as a FILE: `cat >> ~/.gitconfig <<EOF`, sed -i, the
#     Edit/Write tools, or `git config include.path <file with a helper>`.
#   - A script file, a Makefile, an alias from the shell snapshot, `source`.
#   - Anything the interactive gh() wrapper or git itself does internally.
#
# `--selftest` proves every arm, deny and allow, readable and unreadable, on
# stdin payloads through this entrypoint; GH_SSH_ONLY_UNDER_TEST=<path> runs the
# same arms on another copy, judged on the decision alone.

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
# The same log every other guard uses, OUTSIDE the hooks dir. It used to be
# $HOOKS_DIR/security.log: run from the repo (a test, a selftest), that wrote a
# file into home/.claude/hooks, which stow then tried to link over the live log,
# and the 2026-10-05 restow stopped on it.
LOG_FILE="${GH_SSH_ONLY_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/hooks-security.log}"
[ -n "${GH_SSH_ONLY_LOG:-}" ] || [ -d "${LOG_FILE%/*}" ] || mkdir -p "${LOG_FILE%/*}" 2>/dev/null

# The crude match on the RAW payload, used only when it cannot be read.
RAW_TRIGGER='(^|[^A-Za-z0-9_-])gh[[:space:]]+auth[[:space:]]+(login|setup-git|refresh|switch|logout|git-credential)([^A-Za-z0-9_-]|$)'
RAW_TRIGGER_CI='credential\.([^[:space:]"]*\.)?helper|insteadof|git_protocol|://[^/@[:space:]"]*:[^/@[:space:]"]*@|://(gh[pousr]_|github_pat_)'

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Token-shaped strings and URL passwords out, then cap: a guard must not become
# the leak it guards against.
redact() {
  printf '%s' "$1" | tr '\n' ' ' \
    | sed -E 's/(gh[pousr]_|github_pat_)[A-Za-z0-9_]+/\1<redacted>/g; s#(://)[^/@[:space:]]*:[^/@[:space:]]*@#\1<redacted>@#g' \
    | cut -c1-400
}

# The payload cannot be read. $1 = why. DENY by name when the raw text mentions
# a trigger (JSON escapes \n \r \t and \" undone first); return otherwise.
unreadable() {
  local raw hit=0
  raw=$(printf '%s' "$INPUT" | sed -e 's/\\[nrt]/ /g' -e 's/\\"/"/g')
  [[ $raw =~ $RAW_TRIGGER ]] && hit=1
  shopt -s nocasematch
  [[ $raw =~ $RAW_TRIGGER_CI ]] && hit=1
  shopt -u nocasematch
  [ "$hit" -eq 1 ] || return 0
  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-gh-ssh-only unreadable payload ($1)" >> "$LOG_FILE"; } 2>/dev/null
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"enforce-gh-ssh-only: cannot read the tool payload (%s); denying because it mentions gh auth, a git credential helper, insteadOf, git_protocol or a credential in a URL. Install jq or check the payload shape, then run ~/.claude/hooks/enforce-gh-ssh-only.sh --selftest."}}\n' "$1"
  exit 0
}

if [ "${1:-}" = "--selftest" ]; then
  fails=0; passes=0; _t0=$(date +%s)
  _hook="${GH_SSH_ONLY_UNDER_TEST:-$0}"
  # Another copy (GH_SSH_ONLY_UNDER_TEST) is judged on the DECISION only: its
  # reason text is its own, and the question asked of it is "does it deny".
  _foreign=0
  [ -n "${GH_SSH_ONLY_UNDER_TEST:-}" ] && ! [ "$GH_SSH_ONLY_UNDER_TEST" -ef "$0" ] && _foreign=1
  echo "hook under test: $_hook"
  [ "$_foreign" -eq 1 ] && echo "(another copy: deny arms are judged on the decision alone)"
  _pl() { jq -nc --arg c "$1" '{session_id:"selftest", transcript_path:"/dev/null", cwd:"/tmp",
    permission_mode:"default", hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:$c, description:"selftest arm", timeout:120000}, tool_use_id:"toolu_selftest"}'; }
  _mv() { printf '%s' "$1" | jq -c '.tool_input.cmd = .tool_input.command | del(.tool_input.command)'; }
  # A PATH with every tool in /bin and /usr/bin EXCEPT jq (macOS ships /usr/bin/jq).
  _nojq="$(mktemp -d "${TMPDIR:-/tmp}/gh-ssh-only-nojq.XXXXXX")"
  for f in /bin/* /usr/bin/*; do
    case "${f##*/}" in jq) continue ;; esac
    [ -e "$_nojq/${f##*/}" ] || ln -s "$f" "$_nojq/${f##*/}"
  done
  _hk() { # $1 deny:<id>|unreadable|quiet, $2 label, $3 raw payload, [$4 nojq]
    local out rc got ok=0 path="$PATH" id
    if [ "${4:-}" = nojq ]; then
      if PATH="$_nojq" command -v jq >/dev/null 2>&1 || ! PATH="$_nojq" command -v grep >/dev/null 2>&1; then
        printf 'FAIL  %s  (the no-jq PATH is not one: invalid trial)\n' "$2"; fails=$((fails+1)); return
      fi
      path="$_nojq"
    fi
    local seams="GH_SSH_ONLY_LOG=/dev/null"   # $4 may add test seams, VAR=value words
    case "${4:-}" in nojq|'') ;; *) seams="$seams $4" ;; esac
    out=$(printf '%s' "$3" | env $seams PATH="$path" "$_hook" 2>/dev/null); rc=$?
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput | "\(.permissionDecision) \(.permissionDecisionReason)"' 2>/dev/null)
    case "$1" in
      deny:*)
        id="${1#deny:}"
        if [ "$_foreign" -eq 1 ]; then case "$got" in "deny "*) ok=1 ;; esac
        elif [ "$id" = gh-auth ]; then case "$got" in "deny Blocked: 'gh auth login/setup-git/refresh'"*) ok=1 ;; esac
        else case "$got" in "deny Blocked: "*"(enforce-gh-ssh-only: $id)"*) ok=1 ;; esac
        fi ;;
      unreadable)
        if [ "$_foreign" -eq 1 ]; then case "$got" in "deny "*) ok=1 ;; esac
        else case "$got" in "deny enforce-gh-ssh-only: cannot read the tool payload"*) ok=1 ;; esac
        fi ;;
      quiet) [ -z "$out" ] && ok=1 ;;
    esac
    [ "$rc" -eq 0 ] || ok=0
    if [ "$ok" -eq 1 ]; then printf 'ok    %-22s %s\n' "$1" "$2"; passes=$((passes+1))
    else printf 'FAIL  %-22s %s  (rc=%s, got: %s)\n' "$1" "$2" "$rc" "$(printf '%s' "${got:-$out}" | head -c 200)"; fails=$((fails+1)); fi
  }
  _d() { _hk "deny:$1" "$2" "$(_pl "$3")"; }   # $1 id, $2 label, $3 command
  _a() { _hk quiet "$1" "$(_pl "$2")"; }        # $1 label, $2 command
  W_T='gh auth login'
  W_O='gh auth status'

  echo "=== 1. unreadable payload (D-20260925-A03, A76): first, before anything new ==="
  p=$(_pl "$W_T"); _hk unreadable 'truncated JSON, with the trigger'    "${p%??????????}"
  p=$(_pl "$W_O"); _hk quiet      'truncated JSON, without the trigger' "${p%??????????}"
  _hk unreadable 'command under another key, with the trigger'          "$(_mv "$(_pl "$W_T")")"
  _hk quiet      'command under another key, without the trigger'       "$(_mv "$(_pl "$W_O")")"
  _hk unreadable 'PATH without jq, with the trigger'                    "$(_pl "$W_T")" nojq
  _hk quiet      'PATH without jq, without the trigger'                 "$(_pl "$W_O")" nojq
  p=$(_pl $'cd /tmp\ngh auth refresh'); _hk unreadable 'truncated, the trigger after an escaped newline' "${p%??????????}"
  _hk unreadable 'PATH without jq, prose is denied too: unread, it cannot be told apart' \
    "$(_pl 'git commit -m "never run gh auth login here"')" nojq
  _hk quiet      'a real, EMPTY command stays quiet, trigger in the description' \
    "$(_pl '' | jq -c '.tool_input.description = "gh auth login"')"
  p=$(_pl 'git config --global credential.helper store'); _hk unreadable 'truncated, a credential helper write' "${p%??????????}"
  p=$(_pl 'git config --global user.name x');              _hk quiet      'truncated, an unrelated git config'   "${p%??????????}"

  echo "=== 2. existing deny arms (copy B's, red-team G01-G05, G13, G22) ==="
  _d gh-auth 'G01 bare form'                         'gh auth login'
  _d gh-auth 'G02 setup-git'                         'gh auth setup-git'
  _d gh-auth 'G03 refresh -s repo'                   'gh auth refresh -s repo'
  _d gh-auth 'G04 absolute path'                     '/opt/homebrew/bin/gh auth login'
  _d gh-auth 'G05 env -u prefix (defect 1)'          'env -u GH_TOKEN gh auth login'
  _d gh-auth 'env prefix, setup-git (defect 1)'      'env -u GH_TOKEN gh auth setup-git'
  _d gh-auth 'sudo and a path (defect 1)'            'sudo /opt/homebrew/bin/gh auth refresh -s repo'
  _d gh-auth 'assignment prefix (defect 1)'          'GH_TOKEN= gh auth login'
  _d gh-auth 'G13 token piped in'                    'echo tok | gh auth login --with-token'
  _d gh-auth 'G22 refresh, bare'                     'gh auth refresh'
  _d gh-auth 'after &&'                              'true && gh auth login'
  _d gh-auth 'after ;'                               'ls; gh auth setup-git'
  _d gh-auth 'command prefix'                        'command gh auth login'
  _d gh-auth 'nohup prefix'                          'nohup gh auth login'
  _d gh-auth 'heredoc feeding a real invocation'     $'gh auth login --with-token <<EOF\ntok\nEOF'

  echo "=== 3. existing allow arms ==="
  _a 'gh auth status is allowed'                     "$W_O"
  _a 'the name as an rg argument (defect 3)'         'rg -n "gh auth login" docs/X.md'
  _a 'the name in a commit message'                  'git commit -m "never run gh auth login here"'
  _a 'the name as heredoc prose (defect 2)'          $'cat > notes.md <<EOF\ngh auth login breaks SSH\nEOF'
  _a 'gh run list'                                   'gh run list'
  _a 'gh api user'                                   'gh api user'

  echo "=== 4. new deny arms (H3: red-team G06-G21, W-20260929-A33) ==="
  _d gh-auth     'inside ( ): B wants a space after the verb' '(gh auth login)'
  _d gh-auth     'G06 bash -c'                     "bash -c 'gh auth login'"
  _d gh-auth     'G07 zsh -c, token redirected'      'zsh -c "gh auth login --with-token < t"'
  _d gh-auth     'G08 eval'                          'eval "gh auth login"'
  _d gh-auth     'G21 sh -c setup-git'               "sh -c 'gh auth setup-git'"
  _d cred-helper 'G09 global credential.helper'      'git config --global credential.helper osxkeychain'
  _d cred-helper 'G10 --unset-all credential.helper' 'git config --global --unset-all credential.helper'
  _d insteadof   'G14 url.*.insteadOf'               'git config --global url.https://github.com/.insteadOf git@github.com:'
  _d token-url   'G17 token in a remote URL'         'git remote set-url origin https://ghp_example@github.com/x/y.git'
  _d cred-helper 'G18 git -c credential.helper'      'git -c credential.helper= -c credential.helper=store push'
  _d gh-auth     'nested: bash -c "sh -c ..."'       "bash -c \"sh -c 'gh auth login'\""
  _d gh-auth     'bash -lc'                          "bash -lc 'gh auth login'"
  _d gh-auth     'sudo bash -c'                      "sudo bash -c 'gh auth refresh'"
  _d gh-auth     'env -S string'                     "env -S 'gh auth login'"
  _d gh-auth     'eval inside bash -c'               "bash -c 'eval \"gh auth login\"'"
  _d gh-auth     '$( ) inside double quotes'         'echo "$(gh auth login)"'
  _d gh-auth     'backticks'                         'echo `gh auth login`'
  _d gh-auth     'heredoc fed to bash'               $'bash <<EOF\ngh auth login\nEOF'
  # W-20260929-A118: four shapes that ran a command no guard saw (S47 S54 S55 S57)
  _d gh-auth     'A118 script -q /dev/null CMD (S47)' 'script -q /dev/null gh auth login'
  _d gh-auth     'A118 script -q -c CMD file'        'script -q -c "gh auth login" /dev/null'
  _d gh-auth     'A118 source <(echo ...) (S54)'     "source <(echo 'gh auth login')"
  _d gh-auth     'A118 . <(printf ...)'              ". <(printf 'gh auth login')"
  _d gh-auth     'A118 . /dev/stdin <<< (S55)'       ". /dev/stdin <<< 'gh auth login'"
  _d gh-auth     'A118 $(...) in unquoted heredoc (S57)' $'cat <<EOF\n$(gh auth login)\nEOF'
  _a 'A118 script -q /dev/null gh auth status'       'script -q /dev/null gh auth status'
  _a 'A118 source <(a generator)'                    'source <(kubectl completion zsh)'
  _a 'A118 $(...) in QUOTED heredoc stays data'      $'cat <<\'EOF\'\n$(gh auth login)\nEOF'
  _a 'A118 . /dev/stdin <<< gh auth status'          ". /dev/stdin <<< 'gh auth status'"
  # W-20260929-A134: the gh guard's last misses (lexer comparison S21 S46 S50 S69)
  _d gh-auth     'A134 function f { ...; }; f (S21)' 'function f { gh auth login; }; f'
  _d gh-auth     'A134 /usr/bin/env bash -c (S46)'   "/usr/bin/env bash -c 'gh auth login'"
  _d gh-auth     'A134 cat <<EOF | bash (S50)'       $'cat <<\'EOF\' | bash\ngh auth login\nEOF'
  _d gh-auth     'A134 eval "$(echo ...)" (S69)'     'eval "$(echo gh auth login)"'
  _a 'A134 function f { gh auth status; }; f'        'function f { gh auth status; }; f'
  _a 'A134 cat <<EOF | bash, gh auth status'         $'cat <<\'EOF\' | bash\ngh auth status\nEOF'
  _a 'A134 eval "$(echo gh auth status)"'            'eval "$(echo gh auth status)"'
  _d gh-auth     'here-string fed to bash'           "bash <<< 'gh auth login'"
  _d gh-auth     'echo piped into sh'                "echo 'gh auth login' | sh"
  _d gh-auth     'quoted command word'               '"gh" auth login'
  _d gh-auth     'backslash inside the name'         'g\h auth login'
  _d gh-auth     'ANSI-C quoted name'                "\$'\\x67h' auth login"
  _d gh-auth     'G16 name held in a variable'       'GH=gh; $GH auth login'
  _d gh-auth     'unresolved variable name'          '"$GHBIN" auth login'
  _d gh-auth-state 'G11 gh auth switch'              'gh auth switch'
  _d gh-auth-state 'G12 gh auth logout'              'gh auth logout -h github.com'
  _d gh-auth-state 'G19 gh auth git-credential'      'gh auth git-credential get'
  _d gh-protocol 'G15 git_protocol https'            'gh config set git_protocol https'
  _d gh-protocol 'git_protocol https with -h host'   'gh config set -h github.com git_protocol https'
  _d cred-helper 'G20 gh repo clone -- --config'     'gh repo clone other/repo -- --config credential.helper=store'
  _d cred-helper 'url-scoped credential helper'      'git config --global credential.https://github.com.helper store'
  _d cred-helper 'new syntax: git config set'        'git config set --global credential.helper store'
  _d cred-helper '--add an empty helper'             "git config --global --add credential.helper ''"
  _d cred-helper '--remove-section credential'       'git config --global --remove-section credential'
  _d cred-helper 'key case does not matter'          'git config --global CREDENTIAL.Helper store'
  _d insteadof   'git -c url.*.insteadOf'            'git -c url.https://github.com/.insteadOf=git@github.com: fetch'
  _d insteadof   'pushInsteadOf'                     'git config --global url.https://github.com/.pushInsteadOf git@github.com:'
  _d token-url   'clone with user:token'             'git clone https://x-access-token:ghs_abc@github.com/x/y.git'
  _d cred-helper 'clone -c credential.helper'        'git clone -c credential.helper=store https://github.com/x/y.git'
  _d token-url   'remote add with user:pass'         'git remote add up https://user:pass@github.com/x/y.git'
  _d token-url   'push to a token URL'               'git push https://ghp_abc@github.com/x/y.git HEAD'
  _d token-url   'remote.origin.url with a token'    'git config remote.origin.url https://ghp_x@github.com/x/y.git'

  echo "=== 5. new allow arms ==="
  _a 'bash -c with a harmless gh call'               "bash -c 'gh api user'"
  _a 'read: --get-all the url-scoped helper'         'git config --get-all credential.https://github.com.helper'
  _a 'read: --global --get credential.helper'        'git config --global --get credential.helper'
  _a 'read: key alone is a get'                      'git config credential.helper'
  _a 'read: insteadOf key alone'                     'git config --global url.https://github.com/.insteadOf'
  _a 'read: --list --show-origin'                    'git config --list --show-origin'
  _a 'unrelated global config write'                 'git config --global user.name Gavin'
  _a 'set-url to an SSH alias'                       'git remote set-url origin git-cc:owner/repo'
  _a 'flip: set-url to x-access-token (no secret)'   'git -C /tmp/r remote set-url origin https://x-access-token@github.com/owner/repo.git'
  _a 'flip: githubagent.tier write'                  'git -C /tmp/r config --local githubagent.tier write'
  _a 'flip: remote get-url'                          'git -C /tmp/r remote get-url origin'
  _a 'flip: --get-regexp appid'                      "git -C /tmp/r config --get-regexp '^githubagent\\..+\\.appid\$'"
  _a 'github-agent-flip itself'                      'github-agent-flip --tier write /tmp/r'
  _a 'git_protocol ssh'                              'gh config set git_protocol ssh'
  _a 'gh repo clone with plain git flags'            'gh repo clone owner/repo -- --depth 1'
  _a 'clone over SSH'                                'git clone git@github.com:x/y.git'
  _a 'clone over ssh://git@'                         'git clone ssh://git@github.com/x/y.git'
  _a 'curl with a token URL is not a git remote'     'curl -s https://ghp_x@api.github.com/user'
  _a 'credential.helper in a commit message'         'git commit -m "git config --global credential.helper store is banned"'
  _a 'credential.helper as an rg pattern'            "rg -n 'credential.helper' docs/"
  _a 'bash -c prose in a heredoc'                    $'cat > n.md <<EOF\nbash -c \'gh auth login\'\nEOF'
  _a 'echo to a file, not to a shell'                "echo 'gh auth login' > notes.md"
  _a 'printf, not piped to a shell'                  "printf '%s\\n' 'gh auth login'"
  _a 'sh -c harmless'                                "sh -c 'ls -la'"
  _a 'eval of a harmless substitution'               'eval "$(direnv export zsh)"'
  _a 'command -v gh is a lookup'                     'command -v gh'
  _a 'gh auth token is not this hook'\''s job'        'gh auth token'
  _a 'plain push'                                    'git push origin HEAD'
  _a '$( ) harmless'                                 'echo "$(git rev-parse HEAD)"'

  echo "=== 6. depth, scale and failing closed ==="
  _n5="bash -c \"sh -c 'zsh -c \\\"eval gh auth login\\\"'\""
  _d gh-auth     '5 levels deep is read'             "$_n5"
  _deep='gh auth login'; _deep_ok='gh api user'
  for _i in 1 2 3 4 5 6 7 8 9; do _deep="eval $(printf '%q' "$_deep")"; _deep_ok="eval $(printf '%q' "$_deep_ok")"; done
  _hk deny:too-deep '10 levels deep, with the trigger: denied'        "$(_pl "$_deep")"
  _hk deny:too-deep '10 levels deep, without it: denied too (fail closed)' "$(_pl "$_deep_ok")"
  _big="git commit -m \"$(head -c 30000 /dev/zero | tr '\0' 'x' | fold -w 80 | sed 's/^/line (gh) "q" /')\""
  _s=$(date +%s); _a '35 KB commit message is allowed' "$_big"
  _e=$(( $(date +%s) - _s ))
  if [ "$_e" -le 1 ]; then printf 'ok    %-22s %s\n' scale "35 KB command in ${_e}s (<= 1 s; was 25 s before records ended in RSC)"; passes=$((passes+1))
  else printf 'FAIL  %-22s %s\n' scale "35 KB command took ${_e}s (> 1 s)"; fails=$((fails+1)); fi
  _script="bash <<'EOF'"$'\n'"$(for _i in $(seq 1 400); do echo "git status; echo \"\$(git rev-parse HEAD)\" | cat"; done)"$'\n'"gh auth login"$'\n'"EOF"
  _d gh-auth     'a 400-line script fed to bash: its last line' "$_script"
  if [ "$_foreign" -eq 0 ]; then
    _s=$(date +%s)
    _hk deny:guard-timeout 'a stall past the deadline is DENIED' "$(_pl 'git status')" 'GH_SSH_ONLY_TEST_STALL=3 GH_SSH_ONLY_DEADLINE=1'
    _e=$(( $(date +%s) - _s ))
    if [ "$_e" -le 2 ]; then printf 'ok    %-22s %s\n' deadline "the stall was cut at ${_e}s (<= 2 s, deadline 1 s)"; passes=$((passes+1))
    else printf 'FAIL  %-22s %s\n' deadline "the stall took ${_e}s (> 2 s)"; fails=$((fails+1)); fi
    _s=$(date +%s)
    _hk deny:guard-timeout 'GH_SSH_ONLY_DEADLINE=99 is ignored' "$(_pl 'git status')" 'GH_SSH_ONLY_TEST_STALL=6 GH_SSH_ONLY_DEADLINE=99'
    _e=$(( $(date +%s) - _s ))
    if [ "$_e" -le 4 ]; then printf 'ok    %-22s %s\n' deadline "cut at the built-in 3 s deadline: ${_e}s (<= 4 s; the harness gives 5)"; passes=$((passes+1))
    else printf 'FAIL  %-22s %s\n' deadline "took ${_e}s (> 4 s)"; fails=$((fails+1)); fi
    _hk deny:guard-no-verdict 'a child that dies is DENIED' "$(_pl 'git status')" 'GH_SSH_ONLY_TEST_CRASH=1'
    _hk quiet      'the seams are inert without a stall or crash' "$(_pl 'git status')" 'GH_SSH_ONLY_DEADLINE=1'
  fi

  echo
  echo "arms: $((passes + fails)), passed $passes, failed $fails, wall $(( $(date +%s) - _t0 ))s"
  [ "$fails" -eq 0 ] && { echo "ALL ARMS PASS"; exit 0; }
  echo "$fails ARM(S) FAILED"; exit 1
fi

set -f   # lexer words are split on US below and must never glob
# Byte-wise matching. In a UTF-8 locale bash 3.2 matched a 35 KB command 10x slower.
export LC_ALL=C

INPUT=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  unreadable "jq is not on PATH"
  exit 0
fi
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); rc=$?

if [ -z "$COMMAND" ]; then
  if [ "$rc" -ne 0 ]; then
    unreadable "jq could not parse it, rc=$rc"
  elif ! echo "$INPUT" | jq -e '.tool_input | has("command")' >/dev/null 2>&1; then
    unreadable "it has no tool_input.command"
  fi
  exit 0   # a real, empty command: nothing to check, as before
fi

MSG_GH_AUTH="Blocked: 'gh auth login/setup-git/refresh' re-add HTTPS credential helpers and break SSH-only GitHub auth. For API reads, fetch the narrow credential yourself: GH_TOKEN=\"\$(github-api-token)\" gh api ... . As of 2026-09-18 the launcher no longer exports \$GH_TOKEN into sessions, so there is nothing ambient to rely on."

# $1 = reason id, $2 = where it was found (0 = the command itself).
block() {
  local id="$1" msg
  case "$id" in
    gh-auth)       msg="$MSG_GH_AUTH" ;;
    gh-auth-state) msg="Blocked: 'gh auth switch/logout/git-credential' changes which GitHub credential gh holds, or prints one. Under SSH-only auth that is Gavin's call, and an agent cannot undo it (gh auth login is blocked too). Ask him." ;;
    gh-protocol)   msg="Blocked: 'gh config set git_protocol' to anything but ssh makes gh clone and push over HTTPS, which needs the credential helper SSH-only auth keeps out. Keep git_protocol ssh." ;;
    cred-helper)   msg="Blocked: this sets, clears or overrides a git credential helper (credential.*.helper, by git config, git -c, or clone --config). GitHub auth here is SSH-only; the App helper joins a repo only through github-agent-flip, and ~/.gitconfig is the dotfiles repo's file. Reads (--get, --get-all, --list) are allowed. Ask Gavin for a change." ;;
    insteadof)     msg="Blocked: url.*.insteadOf / pushInsteadOf rewrites remotes machine-wide (for example every SSH remote to HTTPS). GitHub auth here is SSH-only. Reads are allowed; ask Gavin for a change." ;;
    guard-timeout) msg="Blocked: the gh SSH-only guard gave NO VERDICT within ${DEADLINE:-3} s, so it refuses (fail closed). This is NOT a match: nothing was found. Split the command into smaller pieces, or ask Gavin." ;;
    too-deep)      msg="Blocked: shell bodies (sh -c, eval, \$(...), heredocs into a shell) nest deeper than $MAX_DEPTH levels, past what the gh SSH-only guard reads, so it refuses (fail closed). This is NOT a match. Flatten the command." ;;
    guard-no-verdict) msg="Blocked: the gh SSH-only guard exited without a verdict (a crash, not a match), so it refuses (fail closed). Run ~/.claude/hooks/enforce-gh-ssh-only.sh --selftest, or ask Gavin." ;;
    token-url)     msg="Blocked: a git URL with a credential in it (user:password@, or a token before the @) persists that secret in .git/config and in this transcript. Use SSH (git-cc:owner/repo), or github-agent-flip, whose https://x-access-token@github.com/... carries no secret." ;;
  esac
  [ "${2:-0}" -gt 0 ] && msg="$msg Found inside a nested shell body (sh/bash/zsh -c, eval, env -S, a heredoc, here-string or pipe into a shell, or a \$(...) substitution)."
  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-gh-ssh-only $id \"$(redact "$COMMAND")\"" >> "$LOG_FILE"; } 2>/dev/null
  deny "$msg (enforce-gh-ssh-only: $id)"
}

# ---------------------------------------------------------------- the floor
# Copy B's scan, kept verbatim in effect: strip heredoc bodies, $(...) and
# quoted strings, then match the trio in command position. Whatever it denied
# stays denied. The lexer below is what sees INSIDE the stripped parts.
#
# Heredoc BODIES are stripped, keeping the line that opens them (that line is a
# real command and must still be scanned). Handles <<WORD, <<-WORD, <<'WORD',
# <<"WORD". \047 is a single quote, written as an escape so the awk program
# needs none.
NOHEREDOC=$(printf '%s\n' "$COMMAND" | awk '
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
  }')
STRIPPED=$(echo "$NOHEREDOC" | sed -E 's/\$\([^)]*\)//g; s/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g')

# Match the blocked subcommands only in COMMAND POSITION: at the start, after a
# separator, or after a bounded set of command prefixes (env/sudo/command/time/
# ... with their own flags, and VAR=value assignments), plus an optional path.
#
# 2026-09-17, defect 3 -- NOT "after any whitespace", which is what the first fix
# for defect 1 used. That matched the command name as an ARGUMENT or as prose:
# `rg -n <name> docs/X.md` and a commit message merely mentioning the tool were
# both refused. A peer session lost a commit attempt to it. Command position is
# the property that was always meant; whitespace was a lazy proxy for it.
GH_AUTH_RE='(^|[;&|(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(env|sudo|command|nohup|time|exec|doas|xargs)([[:space:]]+(-[^[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|[A-Za-z_][A-Za-z0-9_]*))*[[:space:]]+)*([A-Za-z0-9_./-]*/)?gh[[:space:]]+auth[[:space:]]+(login|setup-git|refresh)([[:space:]]|$)'

if echo "$STRIPPED" | grep -qE "$GH_AUTH_RE"; then
  block gh-auth 0
fi

# ---------------------------------------------------------------- prefilter
# Every rule below needs one of these in the raw text, or an escape that could
# spell one. Without any of them the command cannot match: skip the lexer.
case "$COMMAND" in
  *[gG][hH]*|*[gG][iI][tT]*|*[aA][uU][tT][hH]*|*[hH][eE][lL][pP][eE][rR]*|*[iI][nN][sS][tT][eE][aA][dD]*|*\$\'*|*\\*) ;;
  *) exit 0 ;;
esac

# ---------------------------------------------------------------- the lexer
US=$'\037'   # field separator in lexer records
RSC=$'\036'  # record separator: words keep their real newlines
MAX_DEPTH=8  # levels of nested shell bodies (the delete guard uses 4; a level costs one awk run here)
FSEP=$'\034'  # joins the nested bodies of one level
# Input: shell text on stdin. Output, records ended by RSC (not by a newline, so
# a word keeps its newlines and nothing has to be decoded: decoding them with
# ${@//...} took 1.85 s on one 35 KB word), fields split by US:
#   C <cid> <pl> <word>...   a simple command, quotes removed, redirections out
#   H <cid> <text>           stdin data for command <cid>: heredoc / here-string
#   S <text>                 the body of a $(...), `...`, <(...), >(...), =(...)
#   E                        last record, always; its absence means the lexer failed
# <pl> numbers a pipeline: it changes at ; & && || newline ( ), not at |.
read -r -d '' LEXER <<'AWK'
BEGIN { US = sprintf("%c", 31); RSC = sprintf("%c", 30); Q = sprintf("%c", 39); ORS = RSC
        FSEP = sprintf("%c", 28); HX = "0123456789abcdef"; buf = ""; first = 1
        nt = split("gh git eval script source . cat sh bash zsh dash ksh mksh yash fish echo printf env genv sudo doas command exec nohup time nice timeout gtimeout caffeinate stdbuf gstdbuf xargs gxargs watch export typeset declare local readonly integer", TL, " ")
        for (k = 1; k <= nt; k++) TRIG[TL[k]] = 1 }
{ if (first) { buf = $0; first = 0 } else buf = buf "\n" $0 }
function enc(w) { gsub(RSC, "", w); gsub(US, "", w); return w }
function emitS(b) { print "S" US enc(b) }
# A134: a $( ) or backtick body handed to eval runs what it prints
function emitSub(b) { if (nw > 0 && tolower(W[1]) == "eval") b = b " | sh"; emitS(b) }
# A118: a command that runs the output of a <( ) it is given
function runsout(w,   b) { b = tolower(w); sub(/.*\//, "", b); return b == "source" || b == "." || b ~ /^(sh|bash|zsh|dash|ksh|mksh|yash|fish)$/ }
# A118: every $( ) (not $(( ))) and backtick span in t, lexed as a nested body
function xsubs(t,   i, m, c, dd, st) {
  m = length(t); i = 1
  while (i <= m) {
    c = substr(t, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == "$" && substr(t, i + 1, 1) == "(" && substr(t, i + 2, 1) != "(") {
      dd = 1; st = i + 2; i += 2
      while (i <= m && dd > 0) { c = substr(t, i, 1); if (c == "(") dd++; else if (c == ")") dd--; i++ }
      emitS(substr(t, st, i - 1 - st)); continue
    }
    if (c == "`") { st = i + 1; i++; while (i <= m && substr(t, i, 1) != "`") i++; emitS(substr(t, st, i - st)); i++; continue }
    i++
  }
}
function fw() {
  if (!inw) return
  if (expect == "t") expect = ""
  else if (expect == "hs") { HS[++nhs] = cur; expect = "" }
  else if (expect == "hd") { HD[++nh] = cur; HC[nh] = cid; HT[nh] = hstrip; HDQ[nh] = wq; expect = "" }   # A118: HDQ = quoted marker
  else W[++nw] = cur
  cur = ""; inw = 0; wq = 0
}
# Only a command that could matter is emitted: bash 3.2 pays ~0.1 ms for each
# record it reads, and a 2000-line script fed to bash was 20 s before this.
# Kept: any word naming a rule's command or a prefix it sees through, any word
# starting with $, or a leading assignment (G16 resolves $NAME from it).
function keep(   k, b) {
  if (nw > 0 && W[1] ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/) return 1
  for (k = 1; k <= nw; k++) {
    if (substr(W[k], 1, 1) == "$") return 1
    b = tolower(W[k]); sub(/^=/, "", b); sub(/.*\//, "", b)
    if (b in TRIG) return 1
  }
  return 0
}
function ec(   k, line) {
  expect = ""
  if (nw == 0 && nhs == 0 && !hadr) return
  if (!keep()) { nw = 0; nhs = 0; hadr = 0; cid++; return }
  line = "C" US cid US pl
  for (k = 1; k <= nw; k++) line = line US enc(W[k])
  print line
  for (k = 1; k <= nhs; k++) print "H" US cid US enc(HS[k])
  nw = 0; nhs = 0; hadr = 0; cid++
}
function hd(i,   k, b0, b1, line, e, t) {
  for (k = hstart; k <= nh; k++) {
    b0 = i; b1 = i   # the body is s[b0, b1): one substr, not a concat per line
    while (i <= n) {
      e = i; while (e <= n && substr(s, e, 1) != "\n") e++
      line = substr(s, i, e - i)
      t = line; if (HT[k]) sub(/^\t+/, "", t)
      if (t == HD[k]) { i = e + 1; break }
      i = e + 1; b1 = i
    }
    if (i > n && b1 > n) b1 = n + 1
    print "H" US HC[k] US enc(substr(s, b0, b1 - b0))
    if (!HDQ[k]) xsubs(substr(s, b0, b1 - b0))   # A118: an unquoted body runs its substitutions
  }
  hstart = nh + 1
  return i
}
function mparen(k,   d, ch, q) {
  d = 1; q = ""
  while (k <= n) {
    ch = substr(s, k, 1)
    if (q == Q) { if (ch == Q) q = "" }
    else if (ch == "\\") k++
    else if (q == "\"") { if (ch == "\"") q = "" }
    else if (ch == Q || ch == "\"") q = ch
    else if (ch == "(") d++
    else if (ch == ")") { d--; if (d == 0) return k }
    k++
  }
  return n + 1
}
function bq(k,   j) {
  j = k; while (j <= n && substr(s, j, 1) != "`") { if (substr(s, j, 1) == "\\") j++; j++ }
  emitSub(substr(s, k, j - k)); cur = cur "`...`"
  return j + 1
}
function dq(k,   ch, nx, j) {
  while (k <= n) {
    ch = substr(s, k, 1)
    if (ch == "\"") return k + 1
    if (ch == "\\") {
      nx = substr(s, k + 1, 1)
      if (nx == "\n") { k += 2; continue }
      if (nx == "$" || nx == "`" || nx == "\"" || nx == "\\") { cur = cur nx; k += 2; continue }
      cur = cur ch; k++; continue
    }
    if (ch == "$" && substr(s, k + 1, 1) == "(") { j = mparen(k + 2); emitSub(substr(s, k + 2, j - k - 2)); cur = cur "$(...)"; k = j + 1; continue }
    if (ch == "`") { k = bq(k + 1); continue }
    cur = cur ch; k++
  }
  return n + 1
}
function ansic(k,   ch, nx, v, m, d) {
  while (k <= n) {
    ch = substr(s, k, 1)
    if (ch == Q) return k + 1
    if (ch == "\\") {
      nx = substr(s, k + 1, 1); k += 2
      if (nx == "n") cur = cur "\n"
      else if (nx == "t") cur = cur "\t"
      else if (nx == "x") {
        v = 0; m = 0
        while (m < 2 && (d = index(HX, tolower(substr(s, k, 1)))) > 0) { v = v * 16 + d - 1; k++; m++ }
        if (m > 0 && v > 0) cur = cur sprintf("%c", v)
      }
      else if (nx ~ /[0-7]/) {
        v = nx + 0; m = 1
        while (m < 3 && substr(s, k, 1) ~ /[0-7]/) { v = v * 8 + substr(s, k, 1); k++; m++ }
        if (v > 0) cur = cur sprintf("%c", v)
      }
      else cur = cur nx
      continue
    }
    cur = cur ch; k++
  }
  return n + 1
}
function redir(i,   c2) {
  if (inw && cur ~ /^[0-9]+$/) { cur = ""; inw = 0 } else fw()
  hadr = 1
  if (substr(s, i, 3) == "<<<") { expect = "hs"; return i + 3 }
  if (substr(s, i, 2) == "<<") { i += 2; hstrip = 0; if (substr(s, i, 1) == "-") { hstrip = 1; i++ } expect = "hd"; return i }
  if (substr(s, i, 1) == "&") i++
  while (substr(s, i, 1) == "<" || substr(s, i, 1) == ">") i++
  c2 = substr(s, i, 1)
  if (c2 == "|" || c2 == "!") i++
  else if (c2 == "&") {
    i++
    if (substr(s, i, 1) ~ /[0-9-]/) { while (substr(s, i, 1) ~ /[0-9-]/) i++; expect = ""; return i }
  }
  expect = "t"; return i
}
# Several texts may arrive joined by FSEP (every nested body of one level, lexed
# in one awk run); each is lexed from a clean state.
END {
  cid = 1; pl = 1
  nt = split(buf, T, "[" FSEP "]")   # a 1-char separator would split on newlines too (BSD awk)
  for (t = 1; t <= nt; t++) lexone(T[t])
  print "E"
}
function lexone(txt,   i, c, nx, j) {
  s = txt; n = length(s); nw = 0; nh = 0; nhs = 0; hstart = 1
  cur = ""; inw = 0; expect = ""; hadr = 0
  i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") { nx = substr(s, i + 1, 1); if (nx != "\n") { cur = cur nx; inw = 1; wq = 1 } i += 2; continue }
    if (c == Q) {
      j = i + 1; while (j <= n && substr(s, j, 1) != Q) j++
      cur = cur substr(s, i + 1, j - i - 1); inw = 1; wq = 1; i = j + 1; continue
    }
    if (c == "$" && substr(s, i + 1, 1) == Q) { inw = 1; wq = 1; i = ansic(i + 2); continue }
    if (c == "\"") { inw = 1; wq = 1; i = dq(i + 1); continue }
    if (c == "$" && substr(s, i + 1, 1) == "(") {
      j = mparen(i + 2); emitSub(substr(s, i + 2, j - i - 2)); cur = cur "$(...)"; inw = 1; i = j + 1; continue
    }
    if (c == "`") { inw = 1; i = bq(i + 1); continue }
    if ((c == "<" || c == ">" || c == "=") && !inw && substr(s, i + 1, 1) == "(") {
      j = mparen(i + 2); pb = substr(s, i + 2, j - i - 2)
      if (c == "<" && nw > 0 && runsout(W[1])) pb = pb " | sh"   # A118: source <( ) runs what it prints
      emitS(pb); cur = "<(...)"; inw = 1; i = j + 1; continue
    }
    if (c == " " || c == "\t") { fw(); i++; continue }
    if (c == "\n") { fw(); ec(); pl++; i = hd(i + 1); continue }
    if (c == "#" && !inw) { while (i <= n && substr(s, i, 1) != "\n") i++; continue }
    if (c == "<" || c == ">" || (c == "&" && substr(s, i + 1, 1) == ">")) { i = redir(i); continue }
    if (c == ";" || c == "&" || c == "|" || c == "(" || c == ")") {
      fw(); ec(); nx = substr(s, i + 1, 1)
      if (c == "|") { if (nx == "|") { pl++; i += 2 } else if (nx == "&") i += 2; else i++ }
      else if (c == "&") { if (nx == "&" || nx == "!" || nx == "|") i += 2; else i++; pl++ }
      else if (c == ";") { i++; if (nx == ";" || nx == "&" || nx == "|") i++; pl++ }
      else { i++; pl++ }
      continue
    }
    cur = cur c; inw = 1; i++
  }
  fw(); ec(); pl++
}
AWK

# ---------------------------------------------------------------- the rules
RE_NAME='^[A-Za-z_][A-Za-z0-9_]*$'
RE_K_HELPER='^credential\.(.+\.)?helper$'
RE_K_INSTEAD='^url\..+\.(push)?insteadof$'
RE_K_RURL='^remote\..+\.(push)?url$'
RE_SEC_CRED='^credential($|\.)'
RE_SEC_URL='^url\.'
RE_URL_UI='^[A-Za-z][A-Za-z0-9+.-]*://([^/@]*)@'
RE_TOKENISH='^(gh[pousr]_|github_pat_)'
RE_OPAQUE='^[A-Za-z0-9_-]{20,}$'

REASON=""; REASON_DEPTH=0; DEPTH=0; LEXER_FAILED=0; TOO_DEEP=0; NEST=""
STDIN_SHELL=0; DATA=""; LOOKUP=""
VAR_N=(); VAR_V=()

_deny() { [ -n "$REASON" ] && return 0; REASON="$1"; REASON_DEPTH=$((DEPTH - 1)); }

# A key's class, case-insensitively as git reads it: helper|insteadof|remoteurl|"".
_key_class() {
  KC=""
  shopt -s nocasematch
  if [[ $1 =~ $RE_K_HELPER ]]; then KC=helper
  elif [[ $1 =~ $RE_K_INSTEAD ]]; then KC=insteadof
  elif [[ $1 =~ $RE_K_RURL ]]; then KC=remoteurl
  fi
  shopt -u nocasematch
}

# A URL that carries a credential: user:password@, or a token-shaped user.
# https://x-access-token@github.com/... (github-agent-flip's form) carries none.
_cred_url() {
  [[ $1 =~ $RE_URL_UI ]] || return 1
  local ui="${BASH_REMATCH[1]}"
  [ "$ui" = x-access-token ] && return 1
  case "$ui" in *:*) return 0 ;; esac
  [[ $ui =~ $RE_TOKENISH ]] && return 0
  [[ $ui =~ $RE_OPAQUE ]] && return 0
  return 1
}

_urls() { local a; for a in "$@"; do _cred_url "$a" && { _deny token-url; return 0; }; done; return 0; }

# key=value from git -c, --config-env or clone --config.
_kv() {
  local key="${1%%=*}" val=""
  case "$1" in *=*) val="${1#*=}" ;; esac
  _key_class "$key"
  case "$KC" in
    helper) _deny cred-helper ;;
    insteadof) _deny insteadof ;;
    remoteurl) _cred_url "$val" && _deny token-url ;;
  esac
  return 0
}

_git_config() {
  local rd=0 wr=0 sec=0
  local -a p=()
  case "${1:-}" in
    get|list|get-urlmatch|get-color|get-colorbool|edit) return 0 ;;
    set|unset) wr=1; shift ;;
    rename-section|remove-section) sec=1; shift ;;
  esac
  while [ $# -gt 0 ]; do
    case "$1" in
      --get|--get-all|--get-regexp|--get-urlmatch|--get-color|--get-colorbool|-l|--list) rd=1; shift ;;
      --add|--replace-all|--unset|--unset-all|--append|--all) wr=1; shift ;;
      --rename-section|--remove-section) sec=1; shift ;;
      -f|--file|--blob|--type|--default|--comment|--value) shift 2 || set -- ;;
      --) shift; while [ $# -gt 0 ]; do p[${#p[@]}]="$1"; shift; done ;;
      -*) shift ;;
      *) p[${#p[@]}]="$1"; shift ;;
    esac
  done
  [ "$rd" -eq 1 ] && return 0
  [ ${#p[@]} -eq 0 ] && return 0
  if [ "$sec" -eq 1 ]; then
    local s
    shopt -s nocasematch
    for s in "${p[@]}"; do
      if [[ $s =~ $RE_SEC_CRED ]]; then REASON_TMP=cred-helper; break; fi
      if [[ $s =~ $RE_SEC_URL ]]; then REASON_TMP=insteadof; break; fi
      REASON_TMP=""
    done
    shopt -u nocasematch
    [ -n "$REASON_TMP" ] && _deny "$REASON_TMP"
    return 0
  fi
  _key_class "${p[0]}"
  case "$KC" in
    helper|insteadof)
      if [ "$wr" -eq 1 ] || [ ${#p[@]} -ge 2 ]; then
        if [ "$KC" = helper ]; then _deny cred-helper; else _deny insteadof; fi
      fi ;;
    remoteurl) [ ${#p[@]} -ge 2 ] && _cred_url "${p[1]}" && _deny token-url ;;
  esac
  return 0
}

_git() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -C|--git-dir|--work-tree|--namespace|--super-prefix|--attr-source) shift 2 || set -- ;;
      -c|--config-env) _kv "${2:-}"; shift 2 || set -- ;;
      --config-env=*) _kv "${1#--config-env=}"; shift ;;
      -*) shift ;;
      *) break ;;
    esac
    [ -n "$REASON" ] && return 0
  done
  [ $# -eq 0 ] && return 0
  local sub="$1"; shift
  case "$sub" in
    config) _git_config "$@" ;;
    remote) case "${1:-}" in add|set-url) _urls "$@" ;; esac ;;
    clone)
      local -a a=("$@")
      while [ $# -gt 0 ]; do
        case "$1" in
          -c|--config) _kv "${2:-}"; shift 2 || set -- ;;
          --config=*) _kv "${1#--config=}"; shift ;;
          *) shift ;;
        esac
      done
      _urls "${a[@]}" ;;
    submodule|fetch|pull|push|ls-remote) _urls "$@" ;;
  esac
  return 0
}

_gh() {
  while [ $# -gt 0 ]; do case "$1" in -R|--repo|--hostname) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
  case "${1:-}" in
    auth)
      case "${2:-}" in
        login|setup-git|refresh) _deny gh-auth ;;
        switch|logout|git-credential) _deny gh-auth-state ;;
      esac ;;
    config)
      [ "${2:-}" = set ] || return 0
      shift 2 || set --
      local -a p=()
      while [ $# -gt 0 ]; do case "$1" in -h|--host) shift 2 || set -- ;; -*) shift ;; *) p[${#p[@]}]="$1"; shift ;; esac; done
      shopt -s nocasematch
      if [[ ${p[0]:-} == git_protocol && ${p[1]:-} != ssh ]]; then REASON_TMP=gh-protocol; else REASON_TMP=""; fi
      shopt -u nocasematch
      [ -n "$REASON_TMP" ] && _deny gh-protocol ;;
    repo)
      case "${2:-}" in clone|fork) ;; *) return 0 ;; esac
      local -a a=("$@")
      while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done
      while [ $# -gt 0 ]; do
        case "$1" in
          -c|--config) _kv "${2:-}"; shift 2 || set -- ;;
          --config=*) _kv "${1#--config=}"; shift ;;
          *) shift ;;
        esac
      done
      _urls "${a[@]}" ;;
  esac
  return 0
}

# sh/bash/zsh [opts] [-c CODE | script | -s]: -c code is lexed; no script
# means the shell reads stdin, so a heredoc, here-string or pipe into it is.
_shell() {
  local want=0 sflag=0 w
  while [ $# -gt 0 ]; do
    w="$1"
    case "$w" in
      --) shift; break ;;
      -o|+o|-O|+O|--rcfile|--init-file) shift 2 || set -- ;;
      --*) shift ;;
      -*|+*) case "$w" in *c*) want=1 ;; esac; case "$w" in *s*) sflag=1 ;; esac; shift ;;
      *) break ;;
    esac
  done
  if [ "$want" -eq 1 ]; then
    [ $# -gt 0 ] && _nest "$1"
    STDIN_SHELL=0; DATA=""; return 0
  fi
  if [ $# -eq 0 ] || [ "$sflag" -eq 1 ]; then STDIN_SHELL=1; fi
  return 0
}

_remember() { # NAME=value, for a later $NAME command word (G16)
  local nm="${1%%=*}"
  [[ $nm =~ $RE_NAME ]] || return 0
  VAR_N[${#VAR_N[@]}]="$nm"; VAR_V[${#VAR_V[@]}]="${1#*=}"
}
_lookup() { # sets LOOKUP to the latest value of $1; returns 1 when unknown
  local k=${#VAR_N[@]}
  while [ "$k" -gt 0 ]; do
    k=$((k - 1))
    [ "${VAR_N[$k]}" = "$1" ] && { LOOKUP="${VAR_V[$k]}"; return 0; }
  done
  return 1
}

# One simple command's argv.
_argv() {
  [ -n "$REASON" ] && return 0
  [ $# -eq 0 ] && return 0
  local w only=1
  case "$1" in
    export|typeset|declare|local|readonly|integer)
      shift; for w in "$@"; do case "$w" in -*) ;; *=*) _remember "$w" ;; esac; done; return 0 ;;
  esac
  for w in "$@"; do case "$w" in [A-Za-z_]*=*) ;; *) only=0; break ;; esac; done
  if [ "$only" -eq 1 ]; then for w in "$@"; do _remember "$w"; done; return 0; fi
  while [ $# -gt 0 ]; do
    w="$1"
    case "$w" in
      [A-Za-z_]*=*) shift ;;
      '!'|'{'|'}'|if|then|else|elif|fi|do|done|while|until|coproc|noglob|nocorrect|-|builtin|nohup) shift ;;
      function) shift; [ $# -gt 0 ] && shift; [ "${1:-}" = "()" ] && shift ;;   # A134: function NAME [()] { BODY
      time) shift; [ "${1:-}" = -p ] && shift ;;
      command)
        shift
        while [ $# -gt 0 ]; do case "$1" in -v|-V) return 0 ;; --) shift; break ;; -*) shift ;; *) break ;; esac; done ;;
      exec)
        shift
        while [ $# -gt 0 ]; do case "$1" in -a) shift 2 || set -- ;; --) shift; break ;; -*) shift ;; *) break ;; esac; done ;;
      sudo|doas)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -u|-g|-C|-D|-h|-p|-r|-t|-U|-T|-R) shift 2 || set -- ;;
            --) shift; break ;;
            -*) shift ;;
            *) break ;;
          esac
        done ;;
      env|genv|*/env|*/genv)   # A134: /usr/bin/env too
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -u|-C|-P|--unset|--chdir) shift 2 || set -- ;;
            -S|--split-string) _nest "${2:-}"; STDIN_SHELL=0; DATA=""; return 0 ;;
            -S*) _nest "${1#-S}"; STDIN_SHELL=0; DATA=""; return 0 ;;
            --split-string=*) _nest "${1#*=}"; STDIN_SHELL=0; DATA=""; return 0 ;;
            --) shift; break ;;
            -*) shift ;;
            [A-Za-z_]*=*) shift ;;
            *) break ;;
          esac
        done ;;
      script)   # W-20260929-A118: script [opts] [file [cmd ...]] runs cmd; Linux: script -c CMD
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -c|--command) _nest "${2:-}"; STDIN_SHELL=0; DATA=""; return 0 ;;
            -F|-t|-T|-I|-O|-B|-E) shift 2 || set -- ;;
            --) shift; break ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        [ $# -gt 0 ] && shift ;;   # the typescript file
      nice)
        shift
        while [ $# -gt 0 ]; do case "$1" in -n) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done ;;
      timeout|gtimeout)
        shift
        while [ $# -gt 0 ]; do case "$1" in -s|-k) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
        [ $# -gt 0 ] && shift ;;
      caffeinate)
        shift
        while [ $# -gt 0 ]; do case "$1" in -t|-w) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done ;;
      stdbuf|gstdbuf)
        shift
        while [ $# -gt 0 ]; do case "$1" in -i|-o|-e) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done ;;
      xargs|gxargs)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            --) shift; break ;;
            -I|-n|-P|-L|-s|-d|-E|-a|-J|-R|-S) shift 2 || set -- ;;
            -*) shift ;;
            *) break ;;
          esac
        done ;;
      watch)
        shift
        while [ $# -gt 0 ]; do case "$1" in -n|--interval) shift 2 || set -- ;; -*) shift ;; *) break ;; esac; done
        [ $# -gt 0 ] && _nest "$*"
        STDIN_SHELL=0; DATA=""; return 0 ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && return 0
  local c="$1" v nb=""
  shift
  case "$c" in =*) c="${c#=}" ;; esac   # zsh =cmd
  case "$c" in
    '$'*)   # a command word held in a variable
      v="${c#\$}"; v="${v#\{}"; v="${v%\}}"
      if [[ $v =~ $RE_NAME ]] && _lookup "$v"; then
        c="$LOOKUP"
      else
        if [ "${1:-}" = auth ]; then
          case "${2:-}" in login|setup-git|refresh) _deny gh-auth ;; switch|logout|git-credential) _deny gh-auth-state ;; esac
        fi
        return 0
      fi ;;
  esac
  # Command names match case-insensitively: on this APFS volume `GH` runs gh.
  shopt -s nocasematch
  case "${c##*/}" in
    gh) nb=gh ;;
    git) nb=git ;;
    eval) nb=eval ;;
    sh|bash|zsh|dash|ksh|mksh|yash|fish) nb=shell ;;
    echo|printf) nb=data ;;
    source|.) nb=source ;;   # A118
  esac
  shopt -u nocasematch
  case "$nb" in
    gh)    _gh "$@" ;;
    git)   _git "$@" ;;
    eval)  [ $# -gt 0 ] && _nest "$*"; STDIN_SHELL=0; DATA="" ;;
    shell) _shell "$@" ;;
    source)   # W-20260929-A118: sourcing stdin reads it as shell code
      for v in "$@"; do case "$v" in /dev/stdin|/dev/fd/0|-) STDIN_SHELL=1 ;; esac; done ;;
    data)
      while [ $# -gt 0 ]; do case "$1" in -n|-e|-E|-ne|-en) shift ;; *) break ;; esac; done
      DATA="$*" ;;   # printf's \n is turned into a newline only if a shell reads it
  esac
  return 0
}

# A nested body found at this level, lexed with every other one of this level
# in ONE awk run once the level is done.
_nest() {
  [ -n "$1" ] || return 0
  if [ -n "$NEST" ]; then NEST="$NEST$FSEP$1"; else NEST="$1"; fi
}

# Lex and classify shell text: the command itself, then each level of nested
# bodies (FSEP-joined). Deeper than MAX_DEPTH is not skipped in silence: it
# sets TOO_DEEP and the raw text is judged the way an unreadable payload is.
_text() {
  [ -n "$REASON" ] && return 0
  if [ "$DEPTH" -ge "$MAX_DEPTH" ]; then TOO_DEEP=1; return 0; fi
  DEPTH=$((DEPTH + 1))
  local recs line oldifs="$IFS" shells=" " prev_pl="" prev_data="" mine catfeeds=" " prev_cat=""
  local -a lines f
  NEST=""
  recs="$(printf '%s' "$1" | LC_ALL=C awk "$LEXER" 2>/dev/null)"
  if [ "$recs" != "E$RSC" ] && [ "${recs: -3}" != "${RSC}E$RSC" ]; then
    LEXER_FAILED=1; DEPTH=$((DEPTH - 1)); return 0
  fi
  IFS="$RSC"; lines=($recs); IFS="$oldifs"
  for line in "${lines[@]}"; do
    IFS="$US"; f=($line); IFS="$oldifs"
    case "${f[0]}" in
      C)
        STDIN_SHELL=0; DATA=""
        _argv "${f[@]:3}"
        if [ "$STDIN_SHELL" -eq 1 ]; then
          shells="$shells${f[1]} "
          [ "${f[2]}" = "$prev_pl" ] && [ -n "$prev_data" ] && _nest "${prev_data//\\n/$'\n'}"
          # A134: cat <<EOF | sh: the bare cat's heredoc (its H record comes later) is code
          [ "${f[2]}" = "$prev_pl" ] && [ -n "$prev_cat" ] && catfeeds="$catfeeds$prev_cat "
        fi
        prev_cat=""; [ ${#f[@]} -eq 4 ] && [ "${f[3]##*/}" = cat ] && prev_cat="${f[1]}"
        prev_pl="${f[2]}"; prev_data="$DATA" ;;
      H) case "$shells$catfeeds" in *" ${f[1]} "*) _nest "${f[2]:-}" ;; esac ;;
      S) _nest "${f[1]:-}" ;;
    esac
    [ -n "$REASON" ] && break
  done
  mine="$NEST"; NEST=""
  [ -n "$mine" ] && _text "$mine"
  DEPTH=$((DEPTH - 1))
}

# FAIL CLOSED on a stall, as enforce-no-permanent-delete.sh does (its
# _verdict_child / read -t / guard-timeout block, reused in shape): the harness
# ALLOWS a command once a hook passes its 5 s timeout, so a guard that stalls is
# a guard that allows. The verdict is computed in a child; this shell waits at
# most DEADLINE seconds for its one line and denies when none arrives.
# GH_SSH_ONLY_DEADLINE can only LOWER it; the two test seams can only make the
# child late or dead, which is a deny, so a caller who sets them gains nothing.
DEADLINE=3
case "${GH_SSH_ONLY_DEADLINE:-}" in 1|2) DEADLINE="$GH_SSH_ONLY_DEADLINE" ;; esac
_verdict_child() {
  trap 'printf "X\n"' EXIT
  case "${GH_SSH_ONLY_TEST_STALL:-}" in [1-9]) sleep "$GH_SSH_ONLY_TEST_STALL" >/dev/null 2>&1 ;; esac
  [ "${GH_SSH_ONLY_TEST_CRASH:-}" = 1 ] && exit 7
  _text "$COMMAND"
  trap - EXIT
  printf 'V%s%s%s%s%s%s%s%s\n' "$US" "$REASON" "$US" "$REASON_DEPTH" "$US" "$LEXER_FAILED" "$US" "$TOO_DEEP"
}
exec 3< <(_verdict_child 2>/dev/null)
vchild=$!
vline=""; IFS= read -r -t "$DEADLINE" -u 3 vline
exec 3<&-
case "$vline" in
  V"$US"*)
    IFS="$US"; vf=($vline); IFS=$' \t\n'
    REASON="${vf[1]:-}"; REASON_DEPTH="${vf[2]:-0}"; LEXER_FAILED="${vf[3]:-0}"; TOO_DEEP="${vf[4]:-0}" ;;
  X) block guard-no-verdict 0 ;;
  *)
    kill -0 "$vchild" 2>/dev/null && { kill -KILL "$vchild" 2>/dev/null; block guard-timeout 0; }
    block guard-no-verdict 0 ;;
esac

[ -n "$REASON" ] && block "$REASON" "$REASON_DEPTH"
# The lexer failed, or bodies nest deeper than it reads: judge the raw text the
# way an unreadable payload is judged (deny when it mentions a trigger).
INPUT="$COMMAND"
[ "$LEXER_FAILED" = 1 ] && unreadable "the lexer failed on the command"
[ "$TOO_DEEP" = 1 ] && block too-deep 0

exit 0
