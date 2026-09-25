#!/bin/bash
# Block the shell probe that prints a secret while looking like it hides one.
# PreToolUse on Bash. Sibling of enforce-census.sh: same payload contract, same
# jq-must-shout rule, but this one DENIES instead of reminding.
#
# WHY IT EXISTS -- measured, not felt
#   Audited ~/.claude/projects on 2026-09-17. Two real credentials were sitting in
#   local transcripts, one for three months. Neither was written there by a tool.
#   Agents typed them, in commands written to be CAREFUL:
#
#     echo "GH_TOKEN set? ${GH_TOKEN:+yes}${GH_TOKEN:-no}"   -> yes<the whole token>
#     echo "interactive-shell sees it: ${V:+SET}${V:-unset}" -> SET<the whole token>
#     env | grep -i git                                      -> GH_TOKEN=<the whole token>
#
#   `${V:-word}` does NOT mean "print word instead of the value". It means "use word
#   ONLY if V is empty", so when V IS set it expands to the value. The author wanted
#   yes/no and got yes-plus-secret. It reads as a redaction and is an expansion, which
#   is why nobody reviewing those commands looked twice.
#
#   Prose alone does not stop this: the rule now lives in OPERATIONAL_RULES.md, but the
#   two leaks were written by sessions that had every count-and-absence rule loaded and
#   still typed the probe. This fires at the only moment that helps.
#
# 🔴 WHY IT BLOCKS RATHER THAN WARNS
#   A warning arrives in the same breath as the output. By then the secret is in the
#   transcript and the transcript is append-only. There is no "undo" for a printed key,
#   so the only useful intervention is BEFORE the command runs.
#
# 🔴 AND WHY A MISSING jq MUST SHOUT
#   `command -v jq || exit 0` would make this hook silent in every project forever, and
#   silence here is indistinguishable from a clean bill of health. Same reasoning as
#   enforce-census.sh, same remedy: say so, loudly, every time.
#
# WHAT IT DELIBERATELY DOES NOT CATCH
#   A probe hidden inside a quoted argument (`bash -c "echo \$GH_TOKEN"`) and one inside
#   a heredoc body. Both spans are stripped before matching, because leaving them in
#   makes prose in a commit message trip the block -- the expensive error. Same accepted
#   trade as the sibling hook.
#
#   `--selftest` proves every arm, positive AND negative. A block rule with no negative
#   arm cannot tell "correctly silent" from "broken and silent".

set -uo pipefail

# A variable whose NAME says it holds a credential. Kept deliberately narrow: this must
# not fire on TMPDIR, EDITOR or PATH, or the block becomes something to route around.
SECRETY='[A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY|_KEY|CREDENTIAL|PRIVKEY|PAT)[A-Za-z0-9_]*'

# The crude match on the RAW payload, used ONLY when the payload cannot be read
# (jq missing, invalid JSON, no tool_input.command; D-20260925-A03). Any
# expansion of a credential-named variable, ${#V} included (it cannot be told
# apart here), or an env/printenv piped anywhere. A hit DENIES by name.
RAW_TRIGGER='\$\{?#?'"$SECRETY"'|(^|[^A-Za-z0-9_.-])(env|printenv)([[:space:]]+-[A-Za-z0-9]+)*[[:space:]]*\|'

# ---------------------------------------------------------------- matching engine
# Returns the reason on stdout, or nothing. Never echoes the command back, and never
# echoes a value: a guard that quotes the secret in its own refusal is the bug again.
_classify() {
  local cmd="$1" bare reason=""

  # Strip heredoc bodies, then quoted spans, then comments -- identical order to
  # enforce-census.sh, for the identical reason (prose must not fire a gate).
  local hd='BEGIN{inhd=0}
inhd==0{
  if (match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
    tag=substr($0,RSTART,RLENGTH); sub(/^<<-?[ \t]*/,"",tag); gsub(/["\047]/,"",tag)
    inhd=1; hd=tag
  }
  print; next
}
{ t=$0; sub(/^[ \t]+/,"",t); if (t==hd) { inhd=0; hd="" } ; next }'
  bare="$(printf '%s' "$cmd" | awk "$hd" | sed -e 's/#.*$//')"

  # RULE 1 -- the default-substitution leak. `${V:-word}` / `${V-word}` on a secret-named
  # variable, where word is NON-EMPTY. `${V:-}` is excluded on purpose: an empty default
  # is the standard set -u guard and prints nothing extra.
  if [[ "$bare" =~ \$\{$SECRETY:?-[^\}\"\'][^\}]*\} ]]; then
    reason="RULE 1: \${VAR:-word} on a credential variable"
  fi

  # RULE 2 -- dumping the whole environment. `env` or `printenv` with no variable named,
  # piped anywhere. This is how the second real token reached a transcript.
  if [ -z "$reason" ] && [[ "$bare" =~ (^|[|;\&\(]|\&\&)[[:space:]]*(env|printenv)([[:space:]]+-[a-zA-Z0-9]+)*[[:space:]]*\| ]]; then
    # ...unless a VALUE-STRIPPER is in the pipeline. `env | cut -d= -f1 | grep -i token`
    # is the form this hook's own advice recommends, and blocking the recommended fix is
    # how a gate teaches people to route around it. Checked across the whole command
    # rather than strictly the next stage: over-permissive by a hair, and the hair is
    # cheaper than refusing the safe answer.
    if ! [[ "$bare" =~ (cut[[:space:]]+-d[\'\"]?=[\'\"]?[[:space:]]+-f[[:space:]]*1|awk[[:space:]]+-F[[:space:]]*[\'\"]?=|s/=\.\*//) ]]; then
      reason="RULE 2: env/printenv dumped and filtered -- prints every matching VALUE"
    fi
  fi

  # RULE 3 -- a bare secret variable inside echo/printf. `${#V}` (length) is allowed, and
  # so is `${V:+literal}` on its own, because neither can expand to the value.
  if [ -z "$reason" ]; then
    local echoes
    echoes="$(printf '%s' "$bare" | grep -oE '(^|[|;&(]|&&)[[:space:]]*(echo|printf)[^|;&]*' 2>/dev/null || true)"
    if [ -n "$echoes" ]; then
      local stripped
      stripped="$(printf '%s' "$echoes" | sed -E "s/\\\$\{#$SECRETY\}//g; s/\\\$\{$SECRETY:\+[^\}]*\}//g")"
      if [[ "$stripped" =~ \$\{?$SECRETY ]]; then
        reason="RULE 3: a credential variable expanded inside echo/printf"
      fi
    fi
  fi

  printf '%s' "$reason"
}

_advice='Print a FACT ABOUT the secret, never the secret:

    [ -n "${V-}" ] && echo "V: SET len=${#V}" || echo "V: unset"
    printf %s "$V" | shasum -a 256 | cut -c1-8     # a fingerprint you can compare
    env | cut -d= -f1 | grep -i token              # names only, no values

${V:-word} returns the VALUE when V is set -- it is an expansion, not a redaction.
Transcripts under ~/.claude/projects are append-only and gitignored, so git-leak-scan
cannot see them: a secret printed here is a secret with no way back.
Full rule: OPERATIONAL_RULES.md, "A shell probe written to CHECK whether a secret is set".'

# ---------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  fails=0
  _must() { # $1 = expect-hit(1)/expect-miss(0), $2 = label, $3 = command
    local got; got="$(_classify "$3")"
    local hit=0; [ -n "$got" ] && hit=1
    if [ "$hit" -eq "$1" ]; then printf 'ok    %s\n' "$2"
    else printf 'FAIL  %s  (expected hit=%s, got hit=%s)\n' "$2" "$1" "$hit"; fails=$((fails+1)); fi
  }
  echo "=== POSITIVE arms: these MUST be blocked ==="
  _must 1 'the real 2026-09-15 leak'      'echo "GH_TOKEN set? ${GH_TOKEN:+yes}${GH_TOKEN:-no}"'
  _must 1 'the real 2026-06-20 leak'      'echo "shell sees it: ${GITHUB_PERSONAL_ACCESS_TOKEN:+SET}${GITHUB_PERSONAL_ACCESS_TOKEN:-unset}"'
  _must 1 'env dump, the other real leak' 'env | grep -i git'
  _must 1 'printenv dump'                 'printenv | grep -iE "token|pat"'
  _must 1 'bare echo of a secret'         'echo "$ANTHROPIC_API_KEY"'
  _must 1 'no-colon default form'         'echo "${NVD_API_KEY-none}"'
  echo "=== NEGATIVE arms: these MUST NOT be blocked ==="
  _must 0 'length only'                   'echo "GH_TOKEN len=${#GH_TOKEN}"'
  _must 0 'set-test only'                 'echo "GH_TOKEN: ${GH_TOKEN:+SET}"'
  _must 0 'the recommended safe form'     '[ -n "${GH_TOKEN-}" ] && echo "SET len=${#GH_TOKEN}" || echo unset'
  _must 0 'empty default, set -u guard'   'foo="${GH_TOKEN:-}"; [ -n "$foo" ] && echo yes'
  _must 0 'non-secret default'            'echo "${TMPDIR:-/tmp}/x"'
  _must 0 'env names only'                'env | cut -d= -f1 | grep -i token'
  _must 0 'secret passed, not printed'    'GH_TOKEN="$T" gh api user --jq .login'
  _must 0 'prose in a heredoc'            $'git commit -F - <<EOF\necho "${GH_TOKEN:-no}" is the bug\nEOF'

  # The arms above test _classify in THIS file. These run the whole hook, payload
  # on stdin, so SECRET_PROBE_UNDER_TEST=<path> runs them on another copy.
  echo "=== HOOK arms: the payload read, or not (D-20260925-A03) ==="
  _hook="${SECRET_PROBE_UNDER_TEST:-$0}"
  echo "hook under test: $_hook"
  _pl() { jq -nc --arg c "$1" '{session_id:"selftest", transcript_path:"/dev/null", cwd:"/tmp",
    permission_mode:"default", hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:$c, description:"selftest arm", timeout:120000}, tool_use_id:"toolu_selftest"}'; }
  _mv() { printf '%s' "$1" | jq -c '.tool_input.cmd = .tool_input.command | del(.tool_input.command)'; }
  # A PATH with every tool in /bin and /usr/bin EXCEPT jq (macOS ships /usr/bin/jq).
  _nojq="$(mktemp -d "${TMPDIR:-/tmp}/secret-probe-nojq.XXXXXX")"
  for f in /bin/* /usr/bin/*; do
    case "${f##*/}" in jq) continue ;; esac
    [ -e "$_nojq/${f##*/}" ] || ln -s "$f" "$_nojq/${f##*/}"
  done
  _hk() { # $1 blocked|unreadable|shout|quiet, $2 label, $3 raw payload, [$4 nojq]
    local out rc got ok=0 path="$PATH"
    if [ "${4:-}" = nojq ]; then
      if PATH="$_nojq" command -v jq >/dev/null 2>&1 || ! PATH="$_nojq" command -v grep >/dev/null 2>&1; then
        printf 'FAIL  %s  (the no-jq PATH is not one: invalid trial)\n' "$2"; fails=$((fails+1)); return
      fi
      path="$_nojq"
    fi
    out="$(printf '%s' "$3" | PATH="$path" "$_hook" 2>/dev/null)"; rc=$?
    got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput | "\(.permissionDecision) \(.permissionDecisionReason) \(.additionalContext)"' 2>/dev/null || true)"
    case "$1" in
      blocked)    [[ $got == "deny 🔴 BLOCKED"* ]] && ok=1 ;;
      unreadable) [[ $got == "deny enforce-secret-probe: cannot read the tool payload"* ]] && ok=1 ;;
      shout)      [[ $got == "null null 🔴 THE SECRET-PROBE GUARD IS BROKEN"* ]] && ok=1 ;;
      quiet)      [ -z "$out" ] && ok=1 ;;
    esac
    [ "$rc" -eq 0 ] || ok=0
    if [ "$ok" -eq 1 ]; then printf 'ok    %s\n' "$2"
    else printf 'FAIL  %s  (expected %s, rc=%s, got: %s)\n' "$2" "$1" "$rc" "$(printf '%s' "${got:-$out}" | head -c 200)"; fails=$((fails+1)); fi
  }
  W_T='echo "GH_TOKEN set? ${GH_TOKEN:+yes}${GH_TOKEN:-no}"'
  W_O='ls -la'
  _hk blocked    'control: valid payload, the real leak is blocked as before'   "$(_pl "$W_T")"
  _hk quiet      'control: valid payload, harmless, no output as before'        "$(_pl "$W_O")"
  p="$(_pl "$W_T")"; _hk unreadable 'truncated JSON, with the trigger'           "${p%??????????}"
  p="$(_pl "$W_O")"; _hk quiet      'truncated JSON, without the trigger'        "${p%??????????}"
  _hk unreadable 'command under another key, with the trigger'                  "$(_mv "$(_pl "$W_T")")"
  _hk quiet      'command under another key, without the trigger'               "$(_mv "$(_pl "$W_O")")"
  _hk unreadable 'PATH without jq, with the trigger'                            "$(_pl "$W_T")" nojq
  _hk shout      'PATH without jq, without the trigger: the jq warning as before' "$(_pl "$W_O")" nojq
  _hk unreadable 'PATH without jq, an env dump'                                 "$(_pl 'env | grep -i git')" nojq
  _hk unreadable 'PATH without jq, ${#V} too: it cannot be told apart unread'   "$(_pl 'echo "len=${#GH_TOKEN}"')" nojq
  p="$(_pl $'cd /tmp\necho "$ANTHROPIC_API_KEY"')"
  _hk unreadable 'truncated, the variable after an escaped newline'             "${p%??????????}"
  _hk quiet      'a real, EMPTY command stays quiet, trigger in the description' \
    "$(_pl '' | jq -c '.tool_input.description = "echo $GH_TOKEN"')"
  echo
  [ "$fails" -eq 0 ] && { echo "ALL ARMS PASS"; exit 0; } || { echo "$fails ARM(S) FAILED"; exit 1; }
fi

# ---------------------------------------------------------------- hook body
payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# The payload cannot be read. $1 = why. When the RAW text mentions a trigger,
# DENY by name, built without jq; otherwise return and go on as before. The
# common JSON escapes are undone first (\n \r \t to a space, \" to "). Matched
# with [[ =~ ]], not a pipe into grep -q: under pipefail an early grep exit can
# turn a hit into a miss. The matched text is never printed.
_unreadable() {
  local raw
  raw="$(printf '%s' "$payload" | sed -e 's/\\[nrt]/ /g' -e 's/\\"/"/g')"
  [[ $raw =~ $RAW_TRIGGER ]] || return 0
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"enforce-secret-probe: cannot read the tool payload (%s); denying because it mentions a credential-named variable or an env dump. Install jq (brew install jq) or check the payload shape, then run enforce-secret-probe.sh --selftest."}}\n' "$1"
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  _unreadable "jq is not on PATH"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"},"suppressOutput":true}\n' \
    "🔴 THE SECRET-PROBE GUARD IS BROKEN: jq is not on PATH, so this hook cannot read the tool payload. It has been SILENT for every command until now, and silence here is not a clean bill of health. Install jq (brew install jq). Until then, check by hand that nothing prints a credential value."
  exit 0
fi

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)"; rc=$?
if [ -z "$cmd" ]; then
  if [ "$rc" -ne 0 ]; then
    _unreadable "jq could not parse it, rc=$rc"
  elif ! printf '%s' "$payload" | jq -e '.tool_input | has("command")' >/dev/null 2>&1; then
    _unreadable "it has no tool_input.command"
  fi
  exit 0   # a real, empty command: nothing to check, as before
fi

reason="$(_classify "$cmd")"
[ -n "$reason" ] || exit 0

jq -n --arg r "$reason" --arg a "$_advice" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
    permissionDecisionReason: ("🔴 BLOCKED -- this command would print a credential into the transcript.\n\n" + $r + "\n\n" + $a)}}'
exit 0
