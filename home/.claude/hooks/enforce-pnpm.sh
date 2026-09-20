#!/bin/bash
# Block npm/yarn/npx: enforce pnpm or bun for all Node.js commands.
# Runs on PreToolUse for Bash.
#
# TRAVELS WITH pj (P5.6, 2026-09-21). Stowed to ~/.claude/hooks/ and declared once
# in settings/claude/hooks.json with targets ["project"]. The rule is the dotfiles
# package-manager policy (npm and yarn are also blocked by .zshrc wrappers in every
# interactive shell; this hook is the Bash-tool half). Audit line goes to
#   ${XDG_STATE_HOME:-~/.local/state}/dotfiles/hooks-security.log
#
# Measured before travelling (last 20 transcripts each): 0 of 51 Network_Plan and
# 0 of 245 win_go_app_test commands would have been denied.
#
# `--selftest` proves every arm, positive and negative. Exit 0 = all arms pass.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG_FILE="$STATE_DIR/hooks-security.log"

log_blocked() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-pnpm \"$1\" \"$2\"" >> "$LOG_FILE"
}

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

PFX='(^|[;&|(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(env|sudo|command|nohup|time|exec|doas|xargs)([[:space:]]+(-[^[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|[A-Za-z_][A-Za-z0-9_]*))*[[:space:]]+)*([A-Za-z0-9_./-]*/)?'

# Strip heredoc bodies (keep the opening line), then $(...), "..." and '...'.
# Measured 2026-09-17: without this, prose about the guard refused a commit message.
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

_has() { echo "$1" | grep -qE "${PFX}$2"; }

# Prints the deny reason, or nothing when the command is allowed.
_classify() {
  local s
  s=$(_strip "$1")
  if _has "$s" 'npm\s+'; then echo "Use 'pnpm' or 'bun' instead of npm"; return; fi
  if _has "$s" 'yarn\s+'; then echo "Use 'pnpm' or 'bun' instead of yarn"; return; fi
  if _has "$s" 'yarn\s*$'; then echo "Use 'pnpm install' or 'bun install' instead of yarn"; return; fi
  if _has "$s" 'npx\s+'; then echo "Use 'pnpm dlx' or 'bunx' instead of npx"; return; fi
  if _has "$s" 'pnpm\s+(link|ln)\s+.*(-g|--global)'; then
    echo "Use 'pnpm install -g .' instead of 'pnpm link --global' (v11 shim layout bug)"; return
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
  _must 1 'npm install'                     'npm install'
  _must 1 'npm, chained'                    'git pull && npm ci'
  _must 1 'yarn with args'                  'yarn add left-pad'
  _must 1 'bare yarn'                       'yarn'
  _must 1 'npx'                             'npx create-thing'
  _must 1 'env-prefixed npm'                'env CI=1 npm test'
  _must 1 'pnpm link --global'              'pnpm link --global'
  echo "=== NEGATIVE arms: these MUST be allowed ==="
  _must 0 'pnpm install'                    'pnpm install'
  _must 0 'pnpm dlx'                        'pnpm dlx prettier --check .'
  _must 0 'bun add'                         'bun add x'
  _must 0 'bunx'                            'bunx foo'
  _must 0 'npm as a word inside a path'     'cat ~/.npmrc'
  _must 0 'prose in an echo'                'echo "npm install is banned"'
  _must 0 'prose in a heredoc'              $'git commit -F - <<EOF\nnever npm install\nEOF'
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
