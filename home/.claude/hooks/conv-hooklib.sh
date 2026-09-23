# conv-hooklib.sh -- the shared body of the convention hooks. SOURCED, never run.
#
# Sourced by enforce-uv.sh and enforce-pnpm.sh (beside this file, stowed to
# ~/.claude/hooks/) and by this repo's project-only .claude/hooks/enforce-no-cd.sh.
# The scanning and deciding happen in conv-shscan.awk; this file only moves JSON
# in and out, logs, and runs the selftest arms. bash 3.2 compatible (/bin/bash on
# macOS): no associative arrays, no mapfile.
#
# THE CALLER SETS, before sourcing:
#   CONV_TAG          hook name for messages and the log, e.g. enforce-uv
#   CONV_MODE_NAME    uv | pnpm | nocd (conv-shscan.awk's CONV_MODE)
#   CONV_LIB_DIR      the directory holding conv-shscan.awk
#   CONV_LOG_FILE     the audit log (CONV_HOOK_LOG in the environment overrides it)
#   CONV_FALLBACK_ERE a crude word match, used ONLY when the scanner is unusable
#
# REWRITING A TOOL CALL: the two rules, both measured live on 2.1.280 (2026-09-23,
# docs/CLAUDE_HOOKS.md "Rewriting a tool call" has the arms):
#   1. A rewrite carries updatedInput and additionalContext and NO
#      permissionDecision. With "allow" the rewritten command runs even when nothing
#      permits it (escalation); with no decision the normal permission check runs on
#      the REWRITTEN command, settings deny rules included.
#   2. Two hooks that rewrite the same call race; the last to finish wins. So a
#      command that trips two conventions is DENIED with one combined message by
#      every hook involved; a deny from any hook beats a rewrite.

conv_log() { # $1 BLOCKED|REWROTE, $2 reason, $3 command, [$4 new command]
  local f="${CONV_HOOK_LOG:-$CONV_LOG_FILE}"
  mkdir -p "$(dirname "$f")" 2>/dev/null
  # The braces matter: a failed >> is the SHELL's error, raised before the
  # command's own 2>/dev/null applies (docs/CLAUDE_HOOKS.md, "Two traps").
  if [ "$1" = REWROTE ]; then
    { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] REWROTE $CONV_TAG \"$2\" \"$3\" -> \"$4\"" >> "$f"; } 2>/dev/null
  else
    { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BLOCKED $CONV_TAG \"$2\" \"$3\"" >> "$f"; } 2>/dev/null
  fi
  return 0
}

conv_deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Command on stdin, cwd as $1. Prints the scanner protocol. rc 3 = scanner missing.
conv_scan() {
  local awkf="${CONV_SHSCAN:-$CONV_LIB_DIR/conv-shscan.awk}"
  [ -r "$awkf" ] || return 3
  CONV_MODE="$CONV_MODE_NAME" CONV_CWD="$1" LC_ALL=C awk -f "$awkf"
}

conv_hook_main() {
  local input cmd cwd out rc verdict rest msg new json
  input=$(cat)
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$cmd" ] && exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
  out=$(printf '%s' "$cmd" | conv_scan "$cwd"); rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    # The scanner is missing or broke. Say so by name, and fall back to the
    # crude word match so the rule still holds (deny only, never rewrite).
    if printf '%s' "$cmd" | command grep -qE "$CONV_FALLBACK_ERE"; then
      conv_log BLOCKED "scanner unusable rc=$rc" "$cmd"
      conv_deny "$CONV_TAG: its scanner conv-shscan.awk is missing or failed (rc=$rc), so it cannot tell a real slip from prose, and this command mentions one. Restow the dotfiles (home/.claude/hooks) or fix the scanner."
    fi
    exit 0
  fi
  verdict=${out%%$'\n'*}; rest=${out#*$'\n'}; msg=${rest%%$'\n'*}
  case "$verdict" in
    ALLOW) exit 0 ;;
    DENY)  conv_log BLOCKED "$msg" "$cmd"; conv_deny "$msg" ;;
    REWRITE)
      case "$rest" in *$'\n'*) new=${rest#*$'\n'} ;; *) new="" ;; esac
      if [ -z "$new" ]; then
        conv_log BLOCKED "empty rewrite" "$cmd"
        conv_deny "$CONV_TAG: the rewrite came out empty, so nothing ran; resend the command in the allowed form"
      fi
      # NO permissionDecision here, deliberately: see rule 1 in the header.
      if ! json=$(printf '%s' "$input" | jq -c --arg new "$new" --arg ctx "$msg" \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:(.tool_input + {command:$new}),additionalContext:$ctx}}'); then
        conv_log BLOCKED "jq failed building the rewrite" "$cmd"
        conv_deny "$CONV_TAG: could not build the rewrite, so nothing ran; resend the command in the allowed form"
      fi
      conv_log REWROTE "$msg" "$cmd" "$new"
      printf '%s\n' "$json"
      exit 0 ;;
    *) conv_log BLOCKED "scanner said '$verdict'" "$cmd"
       conv_deny "$CONV_TAG: its scanner returned '$verdict'; denying rather than guessing" ;;
  esac
}

# ---------------------------------------------------------------- selftest

# A PreToolUse payload with the envelope Claude Code 2.1.280 really sends: keys
# copied from a captured payload (2026-09-23, del-guard capture), values neutral.
# CONV_PAYLOAD_FILE=<a captured payload> runs every arm on THAT envelope instead,
# only command, cwd, description and timeout replaced (the arms check the last two).
conv_payload() { # $1 command, [$2 cwd]
  if [ -n "${CONV_PAYLOAD_FILE:-}" ]; then
    jq --arg c "$1" --arg cwd "${2:-${TMPDIR:-/tmp}}" \
      '.cwd = $cwd | .tool_input.command = $c | .tool_input.description = "selftest arm" | .tool_input.timeout = 120000' \
      "$CONV_PAYLOAD_FILE"
    return
  fi
  jq -n --arg c "$1" --arg cwd "${2:-${TMPDIR:-/tmp}}" '{
    session_id:"selftest", transcript_path:"/dev/null", cwd:$cwd, prompt_id:"selftest",
    permission_mode:"bypassPermissions", effort:{level:"medium"}, hook_event_name:"PreToolUse",
    tool_name:"Bash", tool_input:{command:$c, description:"selftest arm", timeout:120000},
    tool_use_id:"toolu_selftest"}'
}

conv_selftest_begin() { # $1 = this hook's own path
  _st_fails=0; _st_n=0
  _st_hook="${CONV_HOOK_UNDER_TEST:-$1}"
  echo "hook under test: $_st_hook"
  echo "payload envelope: ${CONV_PAYLOAD_FILE:-built in (2.1.280 keys)}"
}

# $1 rewrite|deny|allow, $2 label, $3 command, $4 expected new command (rewrite), [$5 cwd]
conv_arm() {
  local out got ok=0
  _st_n=$((_st_n + 1))
  out=$(conv_payload "$3" "${5:-}" | CONV_HOOK_LOG=/dev/null XDG_STATE_HOME="${TMPDIR:-/tmp}/conv-selftest-state" "$_st_hook" 2>/dev/null)
  case "$1" in
    rewrite)
      got=$(printf '%s' "$out" | jq -r 'if (.hookSpecificOutput.permissionDecision == null)
            and (.hookSpecificOutput.updatedInput.description == "selftest arm")
            and (.hookSpecificOutput.updatedInput.timeout == 120000)
            and ((.hookSpecificOutput.additionalContext // "") | length > 0)
          then .hookSpecificOutput.updatedInput.command else "<not a clean rewrite>" end' 2>/dev/null)
      [ "$got" = "$4" ] && ok=1 ;;
    deny)
      got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null)
      [ "$got" = deny ] && ok=1 ;;
    allow)
      got="${out:-<no output>}"
      [ -z "$out" ] && ok=1 ;;
  esac
  if [ "$ok" -eq 1 ]; then
    printf 'ok    %-7s %s\n' "$1" "$2"
  else
    printf 'FAIL  %-7s %s\n        command:  %s\n' "$1" "$2" "$3"
    [ "$1" = rewrite ] && printf '        expected: %s\n' "$4"
    printf '        got:      %s\n' "$(printf '%s' "${got:-$out}" | head -c 400)"
    _st_fails=$((_st_fails + 1))
  fi
}

conv_selftest_end() {
  echo
  echo "$_st_n arms, $((_st_n - _st_fails)) passed, $_st_fails failed"
  [ "$_st_fails" -eq 0 ] && { echo "ALL ARMS PASS"; exit 0; }
  echo "$_st_fails ARM(S) FAILED"; exit 1
}
