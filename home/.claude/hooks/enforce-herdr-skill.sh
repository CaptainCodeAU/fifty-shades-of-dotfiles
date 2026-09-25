#!/bin/bash
# Block a `herdr` Bash command until the herdr skill has been read this session.
# Runs on PreToolUse for Bash. Sibling of enforce-gh-ssh-only / enforce-census.
#
# WHY IT EXISTS
#   The herdr skill (~/.agents/skills/herdr/SKILL.md, symlinked from
#   ~/.claude/skills/herdr) already documents hard-won gotchas -- a reserved
#   zsh variable name that silently breaks scripts, a wrong JSON field path
#   that wastes a debugging session, sandbox requirements, busy-pane races.
#   The skill's own description already matches ad-hoc herdr scripting, but
#   nothing forces it to actually be read before the first `herdr` call --
#   confirmed 2026-08-28: an entire session ran many herdr commands and hit
#   two of those exact documented gotchas before ever reading the skill.
#
# HOW THE "ONCE PER SESSION" PART IS VERIFIED, NOT JUST CLAIMED
#   This hook denies every `herdr` Bash command until a marker file exists
#   for this session_id. The marker is written by the SIBLING hook
#   mark-herdr-skill-read.sh, which fires on PostToolUse for the Skill tool
#   and only touches the marker when the skill actually invoked was "herdr".
#   So the block does not lift just because it fired once -- it lifts only
#   after the herdr skill was genuinely invoked.
#
# FAILS CLOSED ON A PAYLOAD IT CANNOT READ (W-20260924-A76, ruling D-20260925-A03).
#   Until 2026-09-25 a missing jq, truncated JSON or a moved key all made this
#   hook exit 0 in silence (redteam-3 H4 measured the same on a sibling). Now,
#   when the RAW payload mentions herdr as a word, it denies by name; with no
#   herdr in the raw text it exits 0 as before. A payload with no session_id is
#   the same kind of drift: the marker cannot be checked, so a herdr command is
#   denied rather than let through. Every deny is permissionDecision "deny" with
#   exit 0, so a `test -x ... || true` registration wrapper cannot swallow it.
#
# `--selftest` proves every arm. CONV_HOOK_UNDER_TEST=<path> runs the same arms
# on another copy (master's, to show which arms are new).

HSK_RAW_ERE='(^|[^A-Za-z0-9_.-])herdr([^A-Za-z0-9_-]|$)'

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Deny without jq: a fixed string, so it cannot fail to build.
deny_unreadable() { # $1 reason (no double quotes, no backslashes)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"enforce-herdr-skill: cannot read the tool payload (%s); denying because it mentions herdr. Fix what reads the payload (jq, or a payload shape a Claude Code update changed), then retry."}}\n' "$1"
  exit 0
}

# Does the raw text mention herdr as a word? Pure bash, no jq and no grep. A JSON
# \n or \t escape counts as a word boundary, so a herdr on line 2 still counts.
raw_mentions_herdr() {
  local r="$1"
  r=${r//\\n/ }; r=${r//\\t/ }
  [[ "$r" =~ $HSK_RAW_ERE ]]
}

# ---------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  _st_hook="${CONV_HOOK_UNDER_TEST:-$0}"
  _st_n=0; _st_fails=0
  echo "hook under test: $_st_hook"
  # A path that is not there makes every deny arm fail as <no output>, which reads
  # like a finding about the hook. Refuse instead (measured 2026-09-25).
  [ -x "$_st_hook" ] || { echo "REFUSED: the hook under test is not an executable file; no arm ran"; exit 2; }
  # The allow arm needs a real marker. A fixed fake session id, touched in place:
  # reruns reuse it and nothing has to be deleted afterwards.
  _st_sid_read=hsk-selftest-read
  _st_sid_unread="hsk-selftest-unread-$$"
  if ! touch "/tmp/.claude-herdr-skill-read-$_st_sid_read" 2>/dev/null; then
    echo "FAIL  setup   cannot write the marker under /tmp (the Bash sandbox?); run the selftest unsandboxed"
    _st_fails=$((_st_fails + 1))
  fi
  # A PATH holding only what the hook needs, jq left out. One fixed folder,
  # refreshed in place (ln -sf), so reruns do not pile up temp dirs.
  _st_nojq="${TMPDIR:-/tmp}/herdr-skill-selftest-nojq"; mkdir -p "$_st_nojq"
  for _t in cat awk sed grep; do _p=$(type -P "$_t" 2>/dev/null) && ln -sf "$_p" "$_st_nojq/$_t"; done
  [ -e "$_st_nojq/jq" ] && { echo "FAIL  setup   $_st_nojq holds a jq; the no-jq arms would test nothing"; _st_fails=$((_st_fails + 1)); }

  st_payload() { # $1 command, $2 session id ("" = key left out)
    if [ -n "$2" ]; then
      jq -nc --arg c "$1" --arg s "$2" '{session_id:$s, cwd:"/tmp/selftest", hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c, description:"selftest arm"}}'
    else
      jq -nc --arg c "$1" '{cwd:"/tmp/selftest", hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c, description:"selftest arm"}}'
    fi
  }
  # $1 deny|deny-unreadable|allow, $2 label, $3 raw stdin, [$4 PATH]
  st_arm() {
    local out ok=0 reason
    _st_n=$((_st_n + 1))
    if [ -n "${4:-}" ]; then
      out=$(printf '%s' "$3" | PATH="$4" "$_st_hook" 2>/dev/null)
    else
      out=$(printf '%s' "$3" | "$_st_hook" 2>/dev/null)
    fi
    reason=$(printf '%s' "$out" | jq -r 'select(.hookSpecificOutput.permissionDecision == "deny") | .hookSpecificOutput.permissionDecisionReason' 2>/dev/null)
    case "$1" in
      deny)            [ -n "$reason" ] && ok=1 ;;
      deny-unreadable) case "$reason" in "enforce-herdr-skill: cannot read the tool payload ("*) ok=1 ;; esac ;;
      allow)           [ -z "$out" ] && ok=1 ;;
    esac
    if [ "$ok" -eq 1 ]; then printf 'ok    %-15s %s\n' "$1" "$2"
    else printf 'FAIL  %-15s %s\n        got: %s\n' "$1" "$2" "$(printf '%s' "${out:-<no output>}" | head -c 300)"; _st_fails=$((_st_fails + 1)); fi
  }

  echo "=== CONTROLS: a readable payload behaves as it always did ==="
  st_arm deny  "herdr before the skill was read"        "$(st_payload 'herdr agent list' "$_st_sid_unread")"
  st_arm allow "herdr after the skill was read"         "$(st_payload 'herdr agent list' "$_st_sid_read")"
  st_arm deny  "VAR=val prefix, then herdr"             "$(st_payload 'FOO=1 herdr pane list' "$_st_sid_unread")"
  st_arm deny  "herdr after &&"                         "$(st_payload 'ls && herdr pane list' "$_st_sid_unread")"
  st_arm allow "herdr as prose in an echo"              "$(st_payload 'echo "run herdr later"' "$_st_sid_unread")"
  st_arm allow "herdr inside a heredoc body"            "$(st_payload $'cat <<EOF\nherdr agent list\nEOF' "$_st_sid_unread")"
  st_arm allow "herdr-quick-task is another command"    "$(st_payload 'herdr-quick-task . "run tests"' "$_st_sid_unread")"
  st_arm allow "an unrelated command"                   "$(st_payload 'ls -la' "$_st_sid_unread")"

  echo "=== FAIL-CLOSED arms: the payload cannot be read (D-20260925-A03) ==="
  GOOD=$(st_payload 'herdr agent list' "$_st_sid_read")
  PLAIN=$(st_payload 'ls -la' "$_st_sid_read")
  st_arm deny-unreadable "truncated JSON that mentions herdr"          "${GOOD:0:$((${#GOOD} - 40))}"
  st_arm allow           "truncated JSON with no herdr in it"          "${PLAIN:0:$((${#PLAIN} - 40))}"
  st_arm deny-unreadable "herdr on line 2, truncated (a JSON newline escape)" "$(L2=$(st_payload $'ls\nherdr pane list' "$_st_sid_read"); printf '%s' "${L2:0:$((${#L2} - 40))}")"
  st_arm deny-unreadable "the command under the wrong key, herdr"      "$(printf '%s' "$GOOD" | jq -c '.tool_input = {cmd: .tool_input.command}')"
  st_arm allow           "the command under the wrong key, no herdr"   "$(printf '%s' "$PLAIN" | jq -c '.tool_input = {cmd: .tool_input.command}')"
  st_arm deny-unreadable "PATH without jq, herdr"                      "$GOOD" "$_st_nojq"
  st_arm allow           "PATH without jq, no herdr"                   "$PLAIN" "$_st_nojq"
  st_arm allow           "PATH without jq, herdr only inside a word"   "$(st_payload 'ls myherdrnotes herdr-quick-task' "$_st_sid_read")" "$_st_nojq"
  st_arm deny            "no session_id, a herdr command"              "$(st_payload 'herdr agent list' '')"
  st_arm allow           "no session_id, an unrelated command"         "$(st_payload 'ls -la' '')"
  # The registration wrapper: `test -x X && X || true` must not swallow a deny.
  _st_n=$((_st_n + 1))
  _wout=$(printf '%s' "${GOOD:0:$((${#GOOD} - 40))}" | bash -c 'test -x "$1" && "$1" || true' _ "$_st_hook" 2>/dev/null)
  if printf '%s' "$_wout" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    printf 'ok    %-15s %s\n' wrapper "test -x ... || true still carries the deny (exit 0 + JSON)"
  else printf 'FAIL  %-15s %s\n' wrapper "the || true wrapper swallowed the deny"; _st_fails=$((_st_fails + 1)); fi

  echo
  echo "$_st_n arms, $((_st_n - _st_fails)) passed, $_st_fails failed"
  [ "$_st_fails" -eq 0 ] && { echo "ALL ARMS PASS"; exit 0; }
  echo "$_st_fails ARM(S) FAILED"; exit 1
fi

INPUT=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  raw_mentions_herdr "$INPUT" && deny_unreadable "jq is not on PATH"
  exit 0
fi
if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  raw_mentions_herdr "$INPUT" && deny_unreadable "the payload is not valid JSON"
  exit 0
fi
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  raw_mentions_herdr "$INPUT" && deny_unreadable "the payload has no tool_input.command"
  exit 0
fi

# Strip subshells and quoted strings to avoid false positives (e.g. a string
# that merely mentions "herdr").
# Strip heredoc BODIES first, keeping the line that opens them (that line is a real
# command and must still be scanned). Without this, the command name written as PROSE
# inside a heredoc matches, and writing documentation about this guard gets blocked.
# Measured 2026-09-17: that exact false positive refused a commit message.
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

# Only fire when `herdr` is the actual command being invoked, at the start
# or right after a chain operator -- not a substring of some other word.
echo "$STRIPPED" | grep -qE '(^|[;&|(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|(env|sudo|command|nohup|time|exec|doas|xargs)([[:space:]]+(-[^[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|[A-Za-z_][A-Za-z0-9_]*))*[[:space:]]+)*([A-Za-z0-9_./-]*/)?herdr(\s|$)' || exit 0

# A herdr command, but no session_id to check the marker against: payload drift,
# so refuse by name rather than let it through unchecked (D-20260925-A03).
[ -n "$SESSION_ID" ] || deny_unreadable "the payload has no session_id, so the skill marker cannot be checked"

MARKER="/tmp/.claude-herdr-skill-read-${SESSION_ID}"
[ -f "$MARKER" ] && exit 0

deny "Read the herdr skill first this session (Skill tool, skill name \"herdr\") -- it documents hard-won gotchas (a reserved zsh variable name that silently breaks scripts, a wrong agent-status JSON path, sandbox requirements, busy-pane races) that will otherwise cost real time. Then retry this herdr command; it will go through once the skill has been read."
