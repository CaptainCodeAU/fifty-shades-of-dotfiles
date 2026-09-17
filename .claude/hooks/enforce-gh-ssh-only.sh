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

HOOKS_DIR="$(builtin cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOOKS_DIR/security.log"

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
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
