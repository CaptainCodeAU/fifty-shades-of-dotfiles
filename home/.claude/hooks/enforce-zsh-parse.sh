#!/bin/bash
# enforce-zsh-parse.sh -- turn away a Bash-tool command whose zsh-only syntax Claude Code cannot read.
#
# Gavin, dotfiles-main Q1 (v2): 2, 28 Oct 2026, with "the few prompts that still come as well as
# the ones that get caught, everything should be logged. So from time to time we can review it".
# Built test-first (his ask, the same day): the selftest's slices are the specification.
#
# WHY. Claude Code reads every Bash-tool command with a bash parser (tree-sitter-bash). zsh-only
# syntax makes that parse fail; then Claude Code cannot rule out a hidden rm and stops for Gavin:
# "Dangerous rm operation not ruled out -- the shell may read this command differently than it
# was parsed". Bypass mode, allow rules and a PreToolUse allow cannot pass it (2.1.312 code and
# the permission-modes docs). On 28 Oct 2026 it held an e-conductor helper 13 minutes on a probe
# with no rm in it: print -rl -- ${(s.:.)PATH} | grep -n local; BP="${(j.:.)...:#...}"; ...
# Turning the command away with a reason lets the agent rewrite it at once: no prompt, no wait
# (the deny-with-reason route reported working in claude-code #104925 and #93392).
#
# HOW, in two steps so ordinary commands stay fast (measured 28 Oct: about 40 ms, and about 90 ms
# when the parser runs, warm):
#   1. FORMS, a quick text test for a zsh-only form. No match: allow at once, parser not started.
#   2. zsh-parse-check.py parses the command with tree-sitter-bash, and the script of any
#      `sh|bash|zsh|dash -c` (also behind env, sudo, nohup and the like), because Claude Code reads
#      -c scripts too (claude-code #99249). A parse error: deny, naming the form, where it was, and
#      the routes that work. No error (the form sat inside quotes): allow.
# The measured list (24 forms that break the parse, 9 neighbours that do not) is slice 7.
#
# FAILS OPEN on its own trouble: no uv, or a parser that will not run, lets the command through;
# a first run that must fetch the parser may pass the hook's 5 s limit, which Claude Code also
# treats as allow. Never blocks work because of itself.
#
# LOG: each catch goes to the permission-prompt log as kind "caught", each unchecked command as
# kind "unchecked", through notify-permission-prompt.sh (no ping: nothing waits on Gavin). The
# prompts that still come are there as kind "prompt". Review: permission-prompts (~/.local/bin).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [ "${1-}" = --selftest ]; then
  self="$HERE/$(basename "${BASH_SOURCE[0]}")"
  . "$HOME/.local/bin/test-temp.sh" new zsh-parse-selftest || exit 2
  fails=0
  ok()  { printf 'ok    %s\n' "$1"; }
  bad() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
  log="$TT/log.jsonl"
  # run <command>: send it the way Claude Code does, print what the guard answers
  run() { jq -cn --arg c "$1" '{session_id:"st",cwd:"/tmp",tool_name:"Bash",tool_input:{command:$c}}' \
    | PERMISSION_PROMPT_LOG="$log" "$self"; }
  denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

  # slice 1: the command that held e-conductor's helper on 28 Oct is turned away
  c='print -rl -- ${(s.:.)PATH} | grep -n local'
  denied "$(run "$c")" && ok "denied: $c" || bad "NOT denied: $c"

  # slice 2: a plain command passes, silently, and never starts the parser (a fake uv records it)
  fakeuv="$TT/uv"; printf '#!/bin/sh\ntouch "%s/uv-ran"\nexit 1\n' "$TT" > "$fakeuv"; chmod +x "$fakeuv"
  out="$(jq -cn '{session_id:"st",cwd:"/tmp",tool_name:"Bash",tool_input:{command:"git -C /tmp log --format=%h -n 3"}}' \
    | PERMISSION_PROMPT_LOG="$log" ZSH_PARSE_CHECK_UV="$fakeuv" "$self")"
  [ -z "$out" ] && [ ! -e "$TT/uv-ran" ] && ok "plain command: allowed, parser not started" \
    || bad "plain command: out '$out', parser started: $([ -e "$TT/uv-ran" ] && echo yes || echo no)"
  # its control: a zsh form DOES reach the parser through the same fake
  printf '%s' '{"tool_input":{"command":"echo ${(f)x}"}}' | ZSH_PARSE_CHECK_UV="$fakeuv" "$self" >/dev/null
  [ -e "$TT/uv-ran" ] && ok "control: a zsh form starts the parser" || bad "control: the fake parser never ran"

  # slice 3: Claude Code reads the script of sh|bash|zsh|dash -c too (claude-code #99249), so zsh
  # inside one is turned away; a zsh form inside plain quotes is only text, and passes
  for c in "env PATH=/x zsh -c 'print -r -- \${(s.:.)PATH}'" 'bash -c "echo \${(f)x}"'; do
    denied "$(run "$c")" && ok "denied: $c" || bad "NOT denied: $c"
  done
  # slice 4: the reason names the form, where it sat, and the route that works
  why() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""'; }
  r="$(why "$(run 'print -rl -- ${(s.:.)PATH}')")"
  case "$r" in *"'\${(s.:.)'"*"(in the command)"*'zsh "$TMPDIR/'*) ok "reason: form, place and route" ;;
    *) bad "reason lacks form, place or route: ${r:0:120}" ;; esac
  r="$(why "$(run "zsh -c 'print \${(f)x}'")")"
  case "$r" in *"(in the -c script)"*"no way round"*) ok "reason: says -c is no way round" ;;
    *) bad "reason for -c: ${r:0:120}" ;; esac
  for c in "grep -n '\${(s.:.)PATH}' notes.txt" "zsh -c 'echo \"*(.N)\" is text'"; do
    out="$(run "$c")"; [ -z "$out" ] && ok "allowed: $c" || bad "NOT allowed: $c"
  done

  # slice 5: each catch is logged (kind caught, the form, where, no ping); an allowed command is not
  : > "$log"
  run 'echo ${(f)x}' >/dev/null
  run "zsh -c 'print \${(f)x}'" >/dev/null
  run 'ls -la /tmp' >/dev/null
  run "grep -n '\${(s.:.)PATH}' notes.txt" >/dev/null
  got="$(jq -r '[.kind, .form, .found_in, .ping, .session_id] | join("|")' "$log" 2>/dev/null)"
  want='caught|${(f)|command|not sent: caught before the prompt|st
caught|${(f)|-c script|not sent: caught before the prompt|st'
  [ "$got" = "$want" ] && ok "log: 2 catches, nothing for the 2 allowed" || bad "log holds: $got"

  # slice 6: no parser (uv missing, or the parser failing) lets the command through, and says so
  : > "$log"
  for u in /nonexistent/uv "$fakeuv"; do
    out="$(jq -cn '{session_id:"st",cwd:"/tmp",tool_name:"Bash",tool_input:{command:"echo ${(f)x}"}}' \
      | PERMISSION_PROMPT_LOG="$log" ZSH_PARSE_CHECK_UV="$u" "$self")"; rc=$?
    [ "$rc" = 0 ] && [ -z "$out" ] && ok "no parser ($u): allowed" || bad "no parser ($u): rc $rc out '$out'"
  done
  got="$(jq -r '[.kind, .form, .ping] | join("|")' "$log" 2>/dev/null)"
  want='unchecked|${(f)|not sent: parser unavailable, allowed
unchecked|${(f)|not sent: parser unavailable, allowed'
  [ "$got" = "$want" ] && ok "log: both unchecked runs logged" || bad "log holds: $got"

  # slice 7: the measured lists (tree-sitter-bash 0.25, 28 Oct 2026): 24 forms broke the parse,
  # 9 neighbours did not
  n_den=0; n_all=0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if denied "$(run "$c")"; then n_den=$((n_den + 1)); else bad "measured breaking, NOT denied: $c"; fi
  done <<'EOF'
print -rl -- ${(s.:.)PATH} | grep -n local
BP="${(j.:.)${(s.:.)PATH}:#$HOME/.local/bin}"
print -rl -- ${(s.:.)PATH}
echo ${(j.:.)arr}
echo "${(s: :)v}"
echo ${(f)"$(ls)"}
echo ${(@f)"$(ls)"}
echo $=c
echo ${v:#pat}
echo ${${v}}
echo ${${v#a}%b}
ls *(.N)
ls **/*(.om[1,3])
ls (#i)foo*
echo <1-10>
case x in <->) echo n;; esac
diff =(ls a) =(ls b)
() { echo anon }
echo ${(k)assoc}
x=(${(f)"$(cat f)"})
echo ${~pat}
echo ${^arr}x
rm -rf ${(s.:.)PATH}
env PATH=/x zsh -c 'print -r -- ${${(s.:.)PATH}[1]}'
EOF
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    out="$(run "$c")"
    if [ -z "$out" ]; then n_all=$((n_all + 1)); else bad "measured fine, NOT allowed: $c"; fi
  done <<'EOF'
echo plain ${HOME} and "$PATH"
echo ${=c}
for x in ${=v}; do echo $x; done
echo ${f:t} ${f:h} ${f:r}
echo ${f:A}
echo $arr[1]
echo ${arr[1]}
echo ${#arr}
echo $v:t
EOF
  [ "$n_den" = 24 ] && ok "measured list: 24 of 24 breaking forms denied" || bad "measured list: $n_den of 24 denied"
  [ "$n_all" = 9 ] && ok "measured list: 9 of 9 neighbours allowed" || bad "measured list: $n_all of 9 allowed"

  [ "$fails" = 0 ] && echo "selftest: all passed" || echo "selftest: $fails FAILED"
  [ "$fails" = 0 ]; exit $?
fi

CHECK="$HERE/zsh-parse-check.py"

# The zsh-only forms (ERE). A match only sends the command to the parser; the parser decides.
FORMS=(
  '\$\{\([^)]*\)'                 # ${(flags)var}
  '\$\{\$\{'                      # ${${nested}}
  '\$\{[~^]'                      # ${~pat} ${^arr}
  '\$[=~^][A-Za-z_]'              # $=var $~var $^var
  '\$\{[A-Za-z_][A-Za-z0-9_]*:#'  # ${var:#pattern}
  '\(#[a-zA-Z]'                   # (#i) glob flags
  '(^|[[:space:]])=\('            # =(cmd)
  '<[0-9]*-[0-9]*>'               # <-> <1-10>
  '[*?]\([^)]*\)'                 # glob qualifiers *(.N)
  '\(\)[[:space:]]*\{'            # () { anonymous function }
)

form_in() {   # form_in <text>: print the first zsh form found, as the text that matched
  local f m
  for f in "${FORMS[@]}"; do
    m="$(printf '%s' "$1" | LC_ALL=C command grep -o -E -m 1 -e "$f" 2>/dev/null | head -n 1)"
    if [ -n "$m" ]; then printf '%s' "${m# }"; return 0; fi
  done
  return 1
}

in="$(cat)"
cmd="$(printf '%s' "$in" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0
form="$(form_in "$cmd")" || exit 0    # the fast path: no zsh form, nothing to do
LOGGER="$HERE/notify-permission-prompt.sh"
unchecked() {   # no parser: let the command through, and log that it went unchecked
  [ -x "$LOGGER" ] && printf '%s' "$in" | "$LOGGER" --unchecked "$form" >/dev/null 2>&1
  exit 0
}
uv="${ZSH_PARSE_CHECK_UV:-$(command -v uv 2>/dev/null)}"
[ -n "$uv" ] && [ -x "$uv" ] || unchecked
verdict="$(printf '%s' "$cmd" | "$uv" run -q --script "$CHECK" 2>/dev/null)" || unchecked
[ "$(printf '%s' "$verdict" | jq -r '.error' 2>/dev/null)" = true ] || exit 0
where="$(printf '%s' "$verdict" | jq -r '.where // "command"')"
[ -x "$LOGGER" ] && printf '%s' "$in" | "$LOGGER" --caught "$form" "$where" >/dev/null 2>&1
reason="ZSH SYNTAX CLAUDE CODE CANNOT READ, so this command was turned away before it could stop the session. It uses the zsh-only form '$form' (in the $where). Claude Code reads Bash commands with a bash parser; when that fails it asks Gavin to approve ('Dangerous rm operation not ruled out') and the session waits, even in bypass mode. zsh -c '...' is no way round: the inner script is read too. Do this instead: write the zsh to a file with the Write tool (for example \$TMPDIR/probe.zsh) and run: zsh \"\$TMPDIR/probe.zsh\". Or use a form bash also reads: \${=v} to split, \${v//:/ } to replace, \${f:t} and \${f:h} for names. Gavin's choice, dotfiles-main Q1 (v2): 2, 28 Oct 2026; logged for review."
jq -cn --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
