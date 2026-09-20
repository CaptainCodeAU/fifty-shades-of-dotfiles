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
#
# Quoted strings, $(...) and heredoc BODIES are stripped before matching, the same
# way the enforce-* guards do it. Measured 2026-09-21 before the fix: a commit
# message saying "git clean -fd is banned" and an echo mentioning a force push were
# both denied, and the probe that found it was itself denied by this hook.
#
# `--selftest` proves every arm, positive and negative. Exit 0 = all arms pass.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG_FILE="$STATE_DIR/hooks-security.log"

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
  if echo "$s" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f[a-zA-Z]*d' \
     || echo "$s" | grep -qE 'git\s+clean\s+.*-f.*-d|git\s+clean\s+.*-d.*-f'; then
    echo "git clean -fd would remove untracked files and directories"; return
  fi
}

# ---------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  fails=0
  _must() { # $1 = expect-hit(1)/expect-miss(0), $2 = label, $3 = command
    local got hit=0; got="$(_classify "$3")"; [ -n "$got" ] && hit=1
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
  echo "=== NEGATIVE arms: these MUST be allowed ==="
  _must 0 'rm of a subdir'                  'rm -rf ./build'
  _must 0 'plain push'                      'git push origin master'
  _must 0 'reset --hard with a ref'         'git reset --hard HEAD~1'
  _must 0 'git clean dry run'               'git clean -n'
  _must 0 'prose in an echo'                'echo "never git push --force to master"'
  _must 0 'prose in a commit message'       'git commit -m "note: git clean -fd is banned"'
  _must 0 'prose in a heredoc'              $'cat <<EOF\ngit reset --hard is dangerous\nEOF'
  _must 0 'control: harmless'               'echo control-ok'
  echo
  [ "$fails" -eq 0 ] && { echo "ALL ARMS PASS"; exit 0; } || { echo "$fails ARM(S) FAILED"; exit 1; }
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
