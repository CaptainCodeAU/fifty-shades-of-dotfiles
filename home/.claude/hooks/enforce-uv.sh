#!/bin/bash
# Block bare Python tooling: enforce uv for all Python commands.
# Runs on PreToolUse for Bash.
#
# TRAVELS WITH pj (P5.6, 2026-09-21). Stowed to ~/.claude/hooks/ and declared once
# in settings/claude/hooks.json with targets ["project"]. The rule it enforces is
# machine-wide (OPERATIONAL_RULES.md Environment: `uv run python3`, never bare
# python3; the same sentence sits in every project CLAUDE.md). Audit line goes to
#   ${XDG_STATE_HOME:-~/.local/state}/dotfiles/hooks-security.log
#
# Measured before travelling (last 20 transcripts each): 0 of 51 Network_Plan and
# 1 of 245 win_go_app_test commands would have been denied, and that one was a
# bare `python3 -c`, which is the rule violation.
#
# The 'uv pip' exemption is NOT decoration. Before 2026-09-17 this rule anchored to
# start-of-line, so 'uv pip install' never reached it and the missing exemption was
# invisible. Widening the anchor exposed it by blocking a correct command. Any rule
# that widens must re-check its own exemptions.
#
# `--selftest` proves every arm, positive and negative. Exit 0 = all arms pass.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG_FILE="$STATE_DIR/hooks-security.log"

log_blocked() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED enforce-uv \"$1\" \"$2\"" >> "$LOG_FILE"
}

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Command position: start, or after ; & | (, with optional VAR=val and
# env/sudo/command/... prefixes, and an optional path prefix on the binary.
PFX='(^|[;&|(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(env|sudo|command|nohup|time|exec|doas|xargs)([[:space:]]+(-[^[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|[A-Za-z_][A-Za-z0-9_]*))*[[:space:]]+)*([A-Za-z0-9_./-]*/)?'

# Strip heredoc bodies (keep the opening line), then $(...), "..." and '...'.
# Without this the command name written as PROSE inside a heredoc matches, and
# writing documentation about this guard gets blocked (measured 2026-09-17: that
# exact false positive refused a commit message).
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
  if _has "$s" 'pip3?\s+install\b' && ! _has "$s" 'uv\s+pip\s+'; then
    echo "Use 'uv add <package>' instead of pip install"; return
  fi
  if _has "$s" 'pip3?\s+uninstall\b' && ! _has "$s" 'uv\s+pip\s+'; then
    echo "Use 'uv remove <package>' instead of pip uninstall"; return
  fi
  if _has "$s" 'pip3?\s+' && ! _has "$s" 'uv\s+pip\s+'; then
    echo "Use 'uv run pip' or 'uv pip' instead of bare pip"; return
  fi
  if _has "$s" 'python3?\s+' && ! _has "$s" 'uv\s+run\s+python3?\s+'; then
    echo "Use 'uv run python' instead of bare python"; return
  fi
  if _has "$s" 'pytest\b' && ! _has "$s" 'uv\s+run\s+pytest\b'; then
    echo "Use 'uv run pytest' instead of bare pytest"; return
  fi
  if _has "$s" 'ruff\b' && ! _has "$s" 'uv\s+run\s+ruff\b'; then
    echo "Use 'uv run ruff' instead of bare ruff"; return
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
  _must 1 'pip install'                     'pip install requests'
  _must 1 'pip3 uninstall'                  'pip3 uninstall requests'
  _must 1 'bare pip list'                   'pip list'
  _must 1 'bare python3 script'             'python3 script.py'
  _must 1 'bare python3 -c, chained'        'git status && python3 -c "print(1)"'
  _must 1 'env-prefixed python3'            'env FOO=1 python3 x.py'
  _must 1 'bare pytest'                     'pytest -q'
  _must 1 'bare ruff'                       'ruff check .'
  echo "=== NEGATIVE arms: these MUST be allowed ==="
  _must 0 'uv run python3'                  'uv run python3 x.py'
  _must 0 'uv pip install'                  'uv pip install x'
  _must 0 'uv run pytest'                   'uv run pytest -q'
  _must 0 'uv run ruff'                     'uv run ruff check .'
  _must 0 'command -v probe'                'command -v python3'
  _must 0 'which probe'                     'which python3'
  _must 0 'prose in an echo'                'echo "python3 is banned here"'
  _must 0 'prose in a heredoc'              $'git commit -F - <<EOF\nuse uv, not python3\nEOF'
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
