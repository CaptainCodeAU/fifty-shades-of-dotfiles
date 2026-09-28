#!/bin/bash
# Block `gh auth login|setup-git|refresh` in the Claude Bash tool.
# These re-add HTTPS credential helpers to ~/.gitconfig and undermine the
# SSH-only GitHub auth model. Mirrors the interactive gh() wrapper in .zshrc,
# which does NOT apply to the non-interactive Bash tool.
# Runs on PreToolUse for Bash.
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
# KNOWN LIMIT, stated rather than papered over: a path assembled in a variable
# ("$GHBIN" auth login) cannot be matched by any regex here, because the quote
# stripping removes it and the literal command name never appears. This hook
# raises the cost of an accidental bypass; it is not a sandbox.
#
# 2026-09-25, D-20260925-A03 (W-20260924-A76) -- AN UNREADABLE PAYLOAD. With jq
# missing, invalid JSON, or tool_input.command moved, this hook exited 0 in
# silence. Now, when the RAW payload mentions `gh auth login|setup-git|refresh`
# anywhere (it cannot tell prose from a command unread), it DENIES by name,
# JSON built without jq. Without that text: exit 0, as before.
#
# `--selftest` proves the arms, readable and unreadable, on stdin payloads;
# GH_SSH_ONLY_UNDER_TEST=<path> runs them on another copy. It had none before.

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
LOG_FILE="${GH_SSH_ONLY_LOG:-$HOOKS_DIR/security.log}"

# The crude match on the RAW payload, used only when it cannot be read.
RAW_TRIGGER='(^|[^A-Za-z0-9_-])gh[[:space:]]+auth[[:space:]]+(login|setup-git|refresh)([^A-Za-z0-9_-]|$)'

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# The payload cannot be read. $1 = why. DENY by name when the raw text mentions
# the trigger (JSON escapes \n \r \t and \" undone first); return otherwise.
unreadable() {
  local raw
  raw=$(printf '%s' "$INPUT" | sed -e 's/\\[nrt]/ /g' -e 's/\\"/"/g')
  [[ $raw =~ $RAW_TRIGGER ]] || return 0
  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-gh-ssh-only unreadable payload ($1)" >> "$LOG_FILE"; } 2>/dev/null
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"enforce-gh-ssh-only: cannot read the tool payload (%s); denying because it mentions gh auth login, setup-git or refresh. Install jq or check the payload shape, then run .claude/hooks/enforce-gh-ssh-only.sh --selftest."}}\n' "$1"
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
    out=$(printf '%s' "$3" | PATH="$path" GH_SSH_ONLY_LOG=/dev/null "$_hook" 2>/dev/null); rc=$?
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
  _d gh-auth 'inside ( )'                            '(gh auth login)'
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
  _d gh-auth     'G06 bash -c'                       "bash -c 'gh auth login'"
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

  echo
  echo "arms: $((passes + fails)), passed $passes, failed $fails, wall $(( $(date +%s) - _t0 ))s"
  [ "$fails" -eq 0 ] && { echo "ALL ARMS PASS"; exit 0; }
  echo "$fails ARM(S) FAILED"; exit 1
fi

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

# Strip heredoc BODIES, keeping the line that opens them (that line is a real
# command and must still be scanned). Handles <<WORD, <<-WORD, <<'WORD', <<"WORD".
# \047 is a single quote, written as an escape so the awk program needs none.
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

# Strip subshells and quoted strings to avoid further false positives.
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
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-gh-ssh-only \"$COMMAND\"" >> "$LOG_FILE"
  deny "Blocked: 'gh auth login/setup-git/refresh' re-add HTTPS credential helpers and break SSH-only GitHub auth. For API reads, fetch the narrow credential yourself: GH_TOKEN=\"\$(github-api-token)\" gh api ... . As of 2026-09-18 the launcher no longer exports \$GH_TOKEN into sessions, so there is nothing ambient to rely on."
fi

exit 0
