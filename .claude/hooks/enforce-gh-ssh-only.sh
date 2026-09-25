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
  fails=0
  _hook="${GH_SSH_ONLY_UNDER_TEST:-$0}"
  echo "hook under test: $_hook"
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
  _hk() { # $1 blocked|unreadable|quiet, $2 label, $3 raw payload, [$4 nojq]
    local out rc got ok=0 path="$PATH"
    if [ "${4:-}" = nojq ]; then
      if PATH="$_nojq" command -v jq >/dev/null 2>&1 || ! PATH="$_nojq" command -v grep >/dev/null 2>&1; then
        printf 'FAIL  %s  (the no-jq PATH is not one: invalid trial)\n' "$2"; fails=$((fails+1)); return
      fi
      path="$_nojq"
    fi
    out=$(printf '%s' "$3" | PATH="$path" GH_SSH_ONLY_LOG=/dev/null "$_hook" 2>/dev/null); rc=$?
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput | "\(.permissionDecision) \(.permissionDecisionReason)"' 2>/dev/null)
    case "$1" in
      blocked)    case "$got" in "deny Blocked: 'gh auth login/setup-git/refresh'"*) ok=1 ;; esac ;;
      unreadable) case "$got" in "deny enforce-gh-ssh-only: cannot read the tool payload"*) ok=1 ;; esac ;;
      quiet)      [ -z "$out" ] && ok=1 ;;
    esac
    [ "$rc" -eq 0 ] || ok=0
    if [ "$ok" -eq 1 ]; then printf 'ok    %-10s %s\n' "$1" "$2"
    else printf 'FAIL  %-10s %s  (rc=%s, got: %s)\n' "$1" "$2" "$rc" "$(printf '%s' "${got:-$out}" | head -c 200)"; fails=$((fails+1)); fi
  }
  W_T='gh auth login'
  W_O='gh auth status'
  echo "=== controls: a readable payload behaves as before ==="
  _hk blocked 'bare form'                              "$(_pl "$W_T")"
  _hk blocked 'env prefix (defect 1)'                  "$(_pl 'env -u GH_TOKEN gh auth setup-git')"
  _hk blocked 'sudo and an absolute path (defect 1)'   "$(_pl 'sudo /opt/homebrew/bin/gh auth refresh -s repo')"
  _hk quiet   'gh auth status is allowed'              "$(_pl "$W_O")"
  _hk quiet   'the name as an rg argument (defect 3)'  "$(_pl 'rg -n "gh auth login" docs/X.md')"
  _hk quiet   'the name in a commit message'           "$(_pl 'git commit -m "never run gh auth login here"')"
  _hk quiet   'the name as heredoc prose (defect 2)'   "$(_pl $'cat > notes.md <<EOF\ngh auth login breaks SSH\nEOF')"
  echo "=== unreadable payload (D-20260925-A03) ==="
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
  echo
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
